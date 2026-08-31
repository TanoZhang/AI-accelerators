// Board self-test: run one 2x2 GEMM through APB/DMA and check C in hardware.
module de25_standard_selftest_top (
  input  logic        CLOCK_50,
  input  logic [3:0]  KEY,
  input  logic [9:0]  SW,
  output logic [9:0]  LEDR,
  output logic [6:0]  HEX0,
  output logic [6:0]  HEX1,
  output logic [6:0]  HEX2,
  output logic [6:0]  HEX3,
  output logic [6:0]  HEX4,
  output logic [6:0]  HEX5
);

  localparam int unsigned APB_ADDR_W  = 12;
  localparam int unsigned SPAD_DEPTH  = 64;
  localparam int unsigned MEMORY_WORDS = 256;
  localparam logic [31:0] A_BASE = 32'h0000_0000;
  localparam logic [31:0] B_BASE = 32'h0000_0040;
  localparam logic [31:0] C_BASE = 32'h0000_0080;
  localparam int unsigned CONFIG_WRITES = 9;

  typedef enum logic [3:0] {
    SELFTEST_BOOT,
    SELFTEST_CONFIG_SETUP,
    SELFTEST_CONFIG_ACCESS,
    SELFTEST_WAIT_IRQ,
    SELFTEST_PERF_SETUP,
    SELFTEST_PERF_ACCESS,
    SELFTEST_CHECK,
    SELFTEST_PASS,
    SELFTEST_FAIL
  } selftest_state_e;

  logic rst_n;
  logic ninit_done;
  logic board_reset_n;
  logic [1:0] reset_sync_q;
  selftest_state_e state_q;
  logic [4:0] boot_count_q;
  logic [3:0] config_index_q;
  logic [1:0] check_index_q;
  logic [23:0] timeout_q;
  logic [31:0] cycle_count_q;
  logic [25:0] heartbeat_q;
  logic [9:0] led_status;

  logic [APB_ADDR_W-1:0] paddr;
  logic psel;
  logic penable;
  logic pwrite;
  logic [31:0] pwdata;
  logic [3:0] pstrb;
  logic [31:0] prdata;
  logic pready;
  logic pslverr;

  logic mem_req_valid;
  logic mem_req_ready;
  logic mem_req_write;
  logic [31:0] mem_req_addr;
  logic [31:0] mem_req_wdata;
  logic [3:0] mem_req_wstrb;
  logic mem_rsp_valid;
  logic mem_rsp_ready;
  logic [31:0] mem_rsp_rdata;
  logic mem_rsp_error;
  logic irq;

  logic [$clog2(MEMORY_WORDS)-1:0] debug_read_addr;
  logic [31:0] debug_read_data;

  function automatic logic [APB_ADDR_W-1:0] config_address(
    input logic [3:0] index
  );
    case (index)
      4'd0: return ai_accel_pkg::CSR_M;
      4'd1: return ai_accel_pkg::CSR_N;
      4'd2: return ai_accel_pkg::CSR_K;
      4'd3: return ai_accel_pkg::CSR_SRC_A_ADDR;
      4'd4: return ai_accel_pkg::CSR_SRC_B_ADDR;
      4'd5: return ai_accel_pkg::CSR_DST_ADDR;
      4'd6: return ai_accel_pkg::CSR_QUANT_CONFIG;
      4'd7: return ai_accel_pkg::CSR_INT_ENABLE;
      default: return ai_accel_pkg::CSR_CONTROL;
    endcase
  endfunction

  function automatic logic [31:0] config_data(input logic [3:0] index);
    case (index)
      4'd0: return 32'd2;
      4'd1: return 32'd2;
      4'd2: return 32'd2;
      4'd3: return A_BASE;
      4'd4: return B_BASE;
      4'd5: return C_BASE;
      4'd6: return 32'd0;
      4'd7: return 32'd1;
      default: return 32'd1;
    endcase
  endfunction

  function automatic logic [31:0] expected_result(input logic [1:0] index);
    case (index)
      2'd0: return 32'd19;
      2'd1: return 32'd22;
      2'd2: return 32'd43;
      default: return 32'd50;
    endcase
  endfunction

  // Hold the FSM in reset until Agilex device initialization is complete.
  // ModelSim uses the inactive value because this IP is synthesis-only.
`ifdef SYNTHESIS
  reset_release u_reset_release (
    .ninit_done (ninit_done)
  );
`else
  assign ninit_done = 1'b0;
`endif

  assign board_reset_n = KEY[0] && !ninit_done;

  // Synchronous release avoids reset recovery/removal problems.
  always_ff @(posedge CLOCK_50 or negedge board_reset_n) begin
    if (!board_reset_n) begin
      reset_sync_q <= 2'b00;
    end else begin
      reset_sync_q <= {reset_sync_q[0], 1'b1};
    end
  end
  assign rst_n = reset_sync_q[1];

  always_comb begin
    paddr   = '0;
    psel    = 1'b0;
    penable = 1'b0;
    pwrite  = 1'b0;
    pwdata  = '0;
    pstrb   = 4'h0;

    if ((state_q == SELFTEST_CONFIG_SETUP)
        || (state_q == SELFTEST_CONFIG_ACCESS)) begin
      paddr   = config_address(config_index_q);
      psel    = 1'b1;
      penable = (state_q == SELFTEST_CONFIG_ACCESS);
      pwrite  = 1'b1;
      pwdata  = config_data(config_index_q);
      pstrb   = 4'hF;
    end else if ((state_q == SELFTEST_PERF_SETUP)
                 || (state_q == SELFTEST_PERF_ACCESS)) begin
      paddr   = ai_accel_pkg::CSR_PERF_CYCLES;
      psel    = 1'b1;
      penable = (state_q == SELFTEST_PERF_ACCESS);
      pwrite  = 1'b0;
    end

    debug_read_addr = (C_BASE >> 2) + check_index_q;

    led_status      = '0;
    led_status[0]   = (state_q == SELFTEST_PASS);
    led_status[1]   = (state_q == SELFTEST_FAIL);
    led_status[2]   = irq;
    led_status[3]   = mem_req_valid || mem_rsp_valid;
    led_status[8:4] = SW[4:0];
    led_status[9]   = heartbeat_q[25];

    // DE25-Standard Rev.D red LEDs are active-low at the FPGA pins.
    LEDR = ~led_status;
  end

  always_ff @(posedge CLOCK_50 or negedge rst_n) begin
    if (!rst_n) begin
      state_q        <= SELFTEST_BOOT;
      boot_count_q   <= '0;
      config_index_q <= '0;
      check_index_q  <= '0;
      timeout_q      <= '0;
      cycle_count_q  <= '0;
      heartbeat_q    <= '0;
    end else begin
      heartbeat_q <= heartbeat_q + 1'b1;

      case (state_q)
        SELFTEST_BOOT: begin
          if (&boot_count_q) begin
            config_index_q <= '0;
            state_q        <= SELFTEST_CONFIG_SETUP;
          end else begin
            boot_count_q <= boot_count_q + 1'b1;
          end
        end

        SELFTEST_CONFIG_SETUP: begin
          state_q <= SELFTEST_CONFIG_ACCESS;
        end

        SELFTEST_CONFIG_ACCESS: begin
          if (pready) begin
            if (pslverr) begin
              state_q <= SELFTEST_FAIL;
            end else if (config_index_q == (CONFIG_WRITES - 1)) begin
              timeout_q <= '0;
              state_q   <= SELFTEST_WAIT_IRQ;
            end else begin
              config_index_q <= config_index_q + 1'b1;
              state_q        <= SELFTEST_CONFIG_SETUP;
            end
          end
        end

        SELFTEST_WAIT_IRQ: begin
          timeout_q <= timeout_q + 1'b1;
          if (irq) begin
            state_q <= SELFTEST_PERF_SETUP;
          end else if (&timeout_q) begin
            state_q <= SELFTEST_FAIL;
          end
        end

        SELFTEST_PERF_SETUP: begin
          state_q <= SELFTEST_PERF_ACCESS;
        end

        SELFTEST_PERF_ACCESS: begin
          if (pready) begin
            if (pslverr) begin
              state_q <= SELFTEST_FAIL;
            end else begin
              cycle_count_q <= prdata;
              check_index_q <= '0;
              state_q       <= SELFTEST_CHECK;
            end
          end
        end

        SELFTEST_CHECK: begin
          if (debug_read_data != expected_result(check_index_q)) begin
            state_q <= SELFTEST_FAIL;
          end else if (check_index_q == 2'd3) begin
            state_q <= SELFTEST_PASS;
          end else begin
            check_index_q <= check_index_q + 1'b1;
          end
        end

        SELFTEST_PASS,
        SELFTEST_FAIL: begin
        end

        default: state_q <= SELFTEST_FAIL;
      endcase
    end
  end

  ai_accelerator_top #(
    .APB_ADDR_W (APB_ADDR_W),
    .SPAD_DEPTH (SPAD_DEPTH)
  ) u_accelerator (
    .clk           (CLOCK_50),
    .rst_n         (rst_n),
    .paddr         (paddr),
    .psel          (psel),
    .penable       (penable),
    .pwrite        (pwrite),
    .pwdata        (pwdata),
    .pstrb         (pstrb),
    .prdata        (prdata),
    .pready        (pready),
    .pslverr       (pslverr),
    .mem_req_valid (mem_req_valid),
    .mem_req_ready (mem_req_ready),
    .mem_req_write (mem_req_write),
    .mem_req_addr  (mem_req_addr),
    .mem_req_wdata (mem_req_wdata),
    .mem_req_wstrb (mem_req_wstrb),
    .mem_rsp_valid (mem_rsp_valid),
    .mem_rsp_ready (mem_rsp_ready),
    .mem_rsp_rdata (mem_rsp_rdata),
    .mem_rsp_error (mem_rsp_error),
    .irq           (irq)
  );

  fpga_selftest_memory #(
    .MEMORY_WORDS (MEMORY_WORDS)
  ) u_memory (
    .clk             (CLOCK_50),
    .rst_n           (rst_n),
    .mem_req_valid   (mem_req_valid),
    .mem_req_ready   (mem_req_ready),
    .mem_req_write   (mem_req_write),
    .mem_req_addr    (mem_req_addr),
    .mem_req_wdata   (mem_req_wdata),
    .mem_req_wstrb   (mem_req_wstrb),
    .mem_rsp_valid   (mem_rsp_valid),
    .mem_rsp_ready   (mem_rsp_ready),
    .mem_rsp_rdata   (mem_rsp_rdata),
    .mem_rsp_error   (mem_rsp_error),
    .debug_read_addr (debug_read_addr),
    .debug_read_data (debug_read_data)
  );

  hex7seg u_hex0 (.value(cycle_count_q[3:0]),   .segments_n(HEX0));
  hex7seg u_hex1 (.value(cycle_count_q[7:4]),   .segments_n(HEX1));
  hex7seg u_hex2 (.value(cycle_count_q[11:8]),  .segments_n(HEX2));
  hex7seg u_hex3 (.value(cycle_count_q[15:12]), .segments_n(HEX3));
  hex7seg u_hex4 (.value(cycle_count_q[19:16]), .segments_n(HEX4));
  hex7seg u_hex5 (.value(cycle_count_q[23:20]), .segments_n(HEX5));

endmodule

module fpga_selftest_memory #(
  parameter int unsigned MEMORY_WORDS = 256,
  parameter int unsigned ADDR_W       = (MEMORY_WORDS > 1)
                                       ? $clog2(MEMORY_WORDS) : 1
) (
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic                 mem_req_valid,
  output logic                 mem_req_ready,
  input  logic                 mem_req_write,
  input  logic [31:0]          mem_req_addr,
  input  logic [31:0]          mem_req_wdata,
  input  logic [3:0]           mem_req_wstrb,
  output logic                 mem_rsp_valid,
  input  logic                 mem_rsp_ready,
  output logic [31:0]          mem_rsp_rdata,
  output logic                 mem_rsp_error,
  input  logic [ADDR_W-1:0]    debug_read_addr,
  output logic [31:0]          debug_read_data
);

  (* ramstyle = "MLAB", ram_style = "distributed" *)
  logic [31:0] memory [0:MEMORY_WORDS-1];
  logic pending_q;
  logic pending_write_q;
  logic pending_error_q;
  logic [ADDR_W-1:0] pending_addr_q;
  logic [31:0] pending_wdata_q;
  logic [3:0] pending_wstrb_q;

  initial begin
    for (int unsigned index = 0; index < MEMORY_WORDS; index++) begin
      memory[index] = 32'd0;
    end

    // A = [[1, 2], [3, 4]] at word address 0.
    memory[0] = 32'd1;
    memory[1] = 32'd2;
    memory[2] = 32'd3;
    memory[3] = 32'd4;

    // B = [[5, 6], [7, 8]] at byte address 0x40.
    memory[16] = 32'd5;
    memory[17] = 32'd6;
    memory[18] = 32'd7;
    memory[19] = 32'd8;
  end

  assign mem_req_ready  = !pending_q && !mem_rsp_valid;
  assign debug_read_data = memory[debug_read_addr];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pending_q        <= 1'b0;
      pending_write_q  <= 1'b0;
      pending_error_q  <= 1'b0;
      pending_addr_q   <= '0;
      pending_wdata_q  <= '0;
      pending_wstrb_q  <= '0;
      mem_rsp_valid    <= 1'b0;
      mem_rsp_rdata    <= '0;
      mem_rsp_error    <= 1'b0;
    end else begin
      if (mem_req_valid && mem_req_ready) begin
        pending_q        <= 1'b1;
        pending_write_q  <= mem_req_write;
        pending_error_q  <= (mem_req_addr[1:0] != 2'b00)
                         || (mem_req_addr[31:2] >= MEMORY_WORDS);
        pending_addr_q   <= mem_req_addr[ADDR_W+1:2];
        pending_wdata_q  <= mem_req_wdata;
        pending_wstrb_q  <= mem_req_wstrb;
      end

      if (pending_q && !mem_rsp_valid) begin
        mem_rsp_valid <= 1'b1;
        mem_rsp_error <= pending_error_q;
        mem_rsp_rdata <= pending_error_q ? 32'd0 : memory[pending_addr_q];

        if (pending_write_q && !pending_error_q) begin
          for (int unsigned byte_index = 0; byte_index < 4; byte_index++) begin
            if (pending_wstrb_q[byte_index]) begin
              memory[pending_addr_q][(byte_index * 8) +: 8]
                <= pending_wdata_q[(byte_index * 8) +: 8];
            end
          end
        end
      end

      if (mem_rsp_valid && mem_rsp_ready) begin
        mem_rsp_valid <= 1'b0;
        mem_rsp_error <= 1'b0;
        pending_q     <= 1'b0;
      end
    end
  end

endmodule

module hex7seg (
  input  logic [3:0] value,
  output logic [6:0] segments_n
);
  always_comb begin
    case (value)
      4'h0: segments_n = 7'b1000000;
      4'h1: segments_n = 7'b1111001;
      4'h2: segments_n = 7'b0100100;
      4'h3: segments_n = 7'b0110000;
      4'h4: segments_n = 7'b0011001;
      4'h5: segments_n = 7'b0010010;
      4'h6: segments_n = 7'b0000010;
      4'h7: segments_n = 7'b1111000;
      4'h8: segments_n = 7'b0000000;
      4'h9: segments_n = 7'b0010000;
      4'hA: segments_n = 7'b0001000;
      4'hB: segments_n = 7'b0000011;
      4'hC: segments_n = 7'b1000110;
      4'hD: segments_n = 7'b0100001;
      4'hE: segments_n = 7'b0000110;
      default: segments_n = 7'b0001110;
    endcase
  end
endmodule
