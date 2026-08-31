`timescale 1ns/1ps

module tb_apb_accel_regs;

  localparam int unsigned APB_ADDR_W = 12;
  localparam int unsigned DIM_W      = 16;

  logic clk;
  logic rst_n;
  logic [APB_ADDR_W-1:0] paddr;
  logic psel;
  logic penable;
  logic pwrite;
  logic [31:0] pwdata;
  logic [3:0] pstrb;
  logic [31:0] prdata;
  logic pready;
  logic pslverr;
  logic start_pulse;
  logic soft_reset_pulse;
  logic [DIM_W-1:0] cfg_m;
  logic [DIM_W-1:0] cfg_n;
  logic [DIM_W-1:0] cfg_k;
  logic [31:0] src_a_addr;
  logic [31:0] src_b_addr;
  logic [31:0] dst_addr;
  logic quant_enable;
  logic relu_enable;
  logic [4:0] quant_shift;
  logic hw_busy;
  logic hw_done_event;
  logic hw_error_event;
  logic [1:0] int_status;
  logic [1:0] int_enable;
  logic [1:0] int_status_w1c;
  logic done_status;
  logic error_status;
  logic [31:0] perf_cycles;
  logic [31:0] perf_compute_cycles;
  logic [31:0] perf_mac_cycles;
  logic [31:0] perf_dma_cycles;
  logic [31:0] perf_stall_cycles;
  logic irq;
  int unsigned checks;

  apb_accel_regs #(
    .APB_ADDR_W (APB_ADDR_W),
    .DIM_W      (DIM_W)
  ) dut (
    .clk              (clk),
    .rst_n            (rst_n),
    .paddr            (paddr),
    .psel             (psel),
    .penable          (penable),
    .pwrite           (pwrite),
    .pwdata           (pwdata),
    .pstrb            (pstrb),
    .prdata           (prdata),
    .pready           (pready),
    .pslverr          (pslverr),
    .start_pulse      (start_pulse),
    .soft_reset_pulse (soft_reset_pulse),
    .cfg_m            (cfg_m),
    .cfg_n            (cfg_n),
    .cfg_k            (cfg_k),
    .src_a_addr       (src_a_addr),
    .src_b_addr       (src_b_addr),
    .dst_addr         (dst_addr),
    .quant_enable     (quant_enable),
    .relu_enable      (relu_enable),
    .quant_shift      (quant_shift),
    .hw_busy          (hw_busy),
    .int_status       (int_status),
    .int_enable       (int_enable),
    .int_status_w1c   (int_status_w1c),
    .perf_cycles      (perf_cycles),
    .perf_compute_cycles (perf_compute_cycles),
    .perf_mac_cycles  (perf_mac_cycles),
    .perf_dma_cycles  (perf_dma_cycles),
    .perf_stall_cycles (perf_stall_cycles)
  );

  accel_status_irq status_irq (
    .clk                        (clk),
    .rst_n                      (rst_n),
    .done_event                 (hw_done_event),
    .dma_error_event            (hw_error_event),
    .compute_config_error_event (1'b0),
    .int_enable                 (int_enable),
    .w1c_clear                  (int_status_w1c),
    .done_status                (done_status),
    .error_status               (error_status),
    .int_status                 (int_status),
    .irq                        (irq)
  );

  always #5 clk = ~clk;

  task automatic fail(input string label, input string detail);
    begin
      $error("%s: %s", label, detail);
      $fatal(1, "tb_apb_accel_regs failed");
    end
  endtask

  task automatic apb_idle;
    begin
      paddr   = '0;
      psel    = 1'b0;
      penable = 1'b0;
      pwrite  = 1'b0;
      pwdata  = '0;
      pstrb   = '0;
    end
  endtask

  task automatic apb_write(
    input logic [APB_ADDR_W-1:0] address,
    input logic [31:0]           data,
    input logic [3:0]            strobes,
    input bit                    expect_error,
    input string                 label
  );
    begin
      @(negedge clk);
      paddr   = address;
      psel    = 1'b1;
      penable = 1'b0;
      pwrite  = 1'b1;
      pwdata  = data;
      pstrb   = strobes;

      @(negedge clk);
      penable = 1'b1;
      @(posedge clk);
      #1;
      checks += 2;
      if (!pready) begin
        fail(label, "PREADY was low");
      end
      if (pslverr !== expect_error) begin
        fail(label, "unexpected PSLVERR value");
      end

      @(negedge clk);
      apb_idle();
    end
  endtask

  task automatic apb_read(
    input  logic [APB_ADDR_W-1:0] address,
    output logic [31:0]           data,
    input  bit                    expect_error,
    input  string                 label
  );
    begin
      @(negedge clk);
      paddr   = address;
      psel    = 1'b1;
      penable = 1'b0;
      pwrite  = 1'b0;
      pwdata  = '0;
      pstrb   = '0;

      @(negedge clk);
      penable = 1'b1;
      @(posedge clk);
      #1;
      data = prdata;
      checks += 2;
      if (!pready) begin
        fail(label, "PREADY was low");
      end
      if (pslverr !== expect_error) begin
        fail(label, "unexpected PSLVERR value");
      end

      @(negedge clk);
      apb_idle();
    end
  endtask

  task automatic expect_read(
    input logic [APB_ADDR_W-1:0] address,
    input logic [31:0]           expected,
    input string                 label
  );
    logic [31:0] data;
    begin
      apb_read(address, data, 1'b0, label);
      checks++;
      if (data !== expected) begin
        $error("%s: read 0x%08h expected 0x%08h", label, data, expected);
        $fatal(1, "APB read mismatch");
      end
    end
  endtask

  task automatic pulse_done_event;
    begin
      @(negedge clk);
      hw_done_event = 1'b1;
      @(posedge clk);
      #1;
      @(negedge clk);
      hw_done_event = 1'b0;
    end
  endtask

  task automatic pulse_error_event;
    begin
      @(negedge clk);
      hw_error_event = 1'b1;
      @(posedge clk);
      #1;
      @(negedge clk);
      hw_error_event = 1'b0;
    end
  endtask

  task automatic back_to_back_writes;
    begin
      @(negedge clk);
      paddr   = ai_accel_pkg::CSR_M;
      psel    = 1'b1;
      penable = 1'b0;
      pwrite  = 1'b1;
      pwdata  = 32'h0000_1122;
      pstrb   = 4'hF;
      @(negedge clk);
      penable = 1'b1;
      @(posedge clk);
      #1;
      if (pslverr) begin
        fail("back-to-back M", "first transfer failed");
      end

      @(negedge clk);
      paddr   = ai_accel_pkg::CSR_N;
      penable = 1'b0;
      pwdata  = 32'h0000_3344;
      @(negedge clk);
      penable = 1'b1;
      @(posedge clk);
      #1;
      checks += 4;
      if (pslverr || (cfg_m != 16'h1122) || (cfg_n != 16'h3344)) begin
        fail("back-to-back writes", "register values are incorrect");
      end

      @(negedge clk);
      apb_idle();
    end
  endtask

  task automatic clear_with_simultaneous_done_event;
    begin
      @(negedge clk);
      paddr   = ai_accel_pkg::CSR_INT_STATUS;
      psel    = 1'b1;
      penable = 1'b0;
      pwrite  = 1'b1;
      pwdata  = 32'h1;
      pstrb   = 4'h1;
      @(negedge clk);
      penable      = 1'b1;
      hw_done_event = 1'b1;
      @(posedge clk);
      #1;
      checks++;
      if (pslverr) begin
        fail("simultaneous set/clear", "APB transfer failed");
      end
      @(negedge clk);
      hw_done_event = 1'b0;
      apb_idle();
    end
  endtask

  initial begin
    logic [31:0] data;
    logic [DIM_W-1:0] saved_m;
    logic [DIM_W-1:0] saved_n;
    logic [DIM_W-1:0] saved_k;
    logic [31:0] saved_a;
    logic [31:0] saved_b;
    logic [31:0] saved_dst;

    clk             = 1'b0;
    rst_n           = 1'b1;
    hw_busy         = 1'b0;
    hw_done_event   = 1'b0;
    hw_error_event  = 1'b0;
    perf_cycles     = '0;
    perf_compute_cycles = '0;
    perf_mac_cycles = '0;
    perf_dma_cycles = '0;
    perf_stall_cycles = '0;
    checks          = 0;
    apb_idle();

    #1;
    rst_n = 1'b0;
    #1;
    checks += 3;
    if (start_pulse || soft_reset_pulse || irq) begin
      fail("reset", "pulse or interrupt output did not reset");
    end
    @(negedge clk);
    rst_n = 1'b1;

    expect_read(ai_accel_pkg::CSR_CONTROL, 32'h0, "CONTROL reset");
    expect_read(ai_accel_pkg::CSR_STATUS, 32'h0, "STATUS reset");
    expect_read(ai_accel_pkg::CSR_M, 32'h0, "M reset");
    expect_read(ai_accel_pkg::CSR_N, 32'h0, "N reset");
    expect_read(ai_accel_pkg::CSR_K, 32'h0, "K reset");
    expect_read(ai_accel_pkg::CSR_SRC_A_ADDR, 32'h0, "SRC_A reset");
    expect_read(ai_accel_pkg::CSR_SRC_B_ADDR, 32'h0, "SRC_B reset");
    expect_read(ai_accel_pkg::CSR_DST_ADDR, 32'h0, "DST reset");
    expect_read(ai_accel_pkg::CSR_QUANT_CONFIG, 32'h0, "QUANT reset");
    expect_read(ai_accel_pkg::CSR_INT_ENABLE, 32'h0, "INT_ENABLE reset");
    expect_read(ai_accel_pkg::CSR_INT_STATUS, 32'h0, "INT_STATUS reset");
    expect_read(ai_accel_pkg::CSR_PERF_CYCLES, 32'h0, "PERF_CYCLES reset");
    expect_read(ai_accel_pkg::CSR_PERF_MAC_CYCLES, 32'h0,
                "PERF_MAC_CYCLES reset");
    expect_read(ai_accel_pkg::CSR_PERF_COMPUTE_CYCLES, 32'h0,
                "PERF_COMPUTE_CYCLES reset");
    expect_read(ai_accel_pkg::CSR_PERF_DMA_CYCLES, 32'h0,
                "PERF_DMA_CYCLES reset");
    expect_read(ai_accel_pkg::CSR_PERF_STALL_CYCLES, 32'h0,
                "PERF_STALL_CYCLES reset");

    apb_write(ai_accel_pkg::CSR_M, 32'h0000_1234, 4'hF, 1'b0, "write M");
    apb_write(ai_accel_pkg::CSR_N, 32'h0000_5678, 4'hF, 1'b0, "write N");
    apb_write(ai_accel_pkg::CSR_K, 32'h0000_00AB, 4'hF, 1'b0, "write K");
    apb_write(ai_accel_pkg::CSR_SRC_A_ADDR, 32'h1000_0040, 4'hF, 1'b0,
              "write SRC_A");
    apb_write(ai_accel_pkg::CSR_SRC_B_ADDR, 32'h2000_0080, 4'hF, 1'b0,
              "write SRC_B");
    apb_write(ai_accel_pkg::CSR_DST_ADDR, 32'h3000_00C0, 4'hF, 1'b0,
              "write DST");
    apb_write(ai_accel_pkg::CSR_QUANT_CONFIG, 32'h0000_0047, 4'hF, 1'b0,
              "write QUANT_CONFIG");
    apb_write(ai_accel_pkg::CSR_INT_ENABLE, 32'h3, 4'hF, 1'b0,
              "write INT_ENABLE");

    expect_read(ai_accel_pkg::CSR_M, 32'h0000_1234, "read M");
    expect_read(ai_accel_pkg::CSR_N, 32'h0000_5678, "read N");
    expect_read(ai_accel_pkg::CSR_K, 32'h0000_00AB, "read K");
    expect_read(ai_accel_pkg::CSR_SRC_A_ADDR, 32'h1000_0040, "read SRC_A");
    expect_read(ai_accel_pkg::CSR_SRC_B_ADDR, 32'h2000_0080, "read SRC_B");
    expect_read(ai_accel_pkg::CSR_DST_ADDR, 32'h3000_00C0, "read DST");
    expect_read(ai_accel_pkg::CSR_QUANT_CONFIG, 32'h0000_0047,
                "read QUANT_CONFIG");
    expect_read(ai_accel_pkg::CSR_INT_ENABLE, 32'h3, "read INT_ENABLE");

    apb_write(ai_accel_pkg::CSR_M, 32'h0000_EE00, 4'b0010, 1'b0,
              "M byte strobe");
    expect_read(ai_accel_pkg::CSR_M, 32'h0000_EE34, "M byte strobe readback");

    apb_write(ai_accel_pkg::CSR_CONTROL, 32'h1, 4'h1, 1'b0, "START command");
    checks++;
    if (!start_pulse || soft_reset_pulse) begin
      fail("START command", "incorrect command pulses");
    end
    @(posedge clk);
    #1;
    checks++;
    if (start_pulse) begin
      fail("START command", "start_pulse lasted more than one cycle");
    end
    expect_read(ai_accel_pkg::CSR_CONTROL, 32'h0, "CONTROL reads zero");

    saved_m   = cfg_m;
    saved_n   = cfg_n;
    saved_k   = cfg_k;
    saved_a   = src_a_addr;
    saved_b   = src_b_addr;
    saved_dst = dst_addr;
    apb_write(ai_accel_pkg::CSR_CONTROL, 32'h2, 4'h1, 1'b0,
              "SOFT_RESET command");
    checks += 2;
    if (!soft_reset_pulse || start_pulse) begin
      fail("SOFT_RESET command", "incorrect command pulses");
    end
    if ((cfg_m != saved_m) || (cfg_n != saved_n) || (cfg_k != saved_k)
        || (src_a_addr != saved_a) || (src_b_addr != saved_b)
        || (dst_addr != saved_dst)) begin
      fail("SOFT_RESET command", "configuration changed");
    end
    @(posedge clk);
    #1;
    if (soft_reset_pulse) begin
      fail("SOFT_RESET command", "soft_reset_pulse lasted more than one cycle");
    end

    hw_busy = 1'b1;
    expect_read(ai_accel_pkg::CSR_STATUS, 32'h1, "live BUSY status");
    hw_busy = 1'b0;

    pulse_done_event();
    pulse_error_event();
    checks++;
    if (!irq) begin
      fail("interrupt set", "irq did not assert");
    end
    expect_read(ai_accel_pkg::CSR_STATUS, 32'h6, "sticky STATUS");
    expect_read(ai_accel_pkg::CSR_INT_STATUS, 32'h3, "sticky INT_STATUS");

    apb_write(ai_accel_pkg::CSR_STATUS, 32'hFFFF_FFFF, 4'hF, 1'b1,
              "STATUS write protection");
    expect_read(ai_accel_pkg::CSR_STATUS, 32'h6, "STATUS remains read-only");

    apb_write(ai_accel_pkg::CSR_INT_STATUS, 32'h1, 4'h1, 1'b0,
              "clear DONE status");
    expect_read(ai_accel_pkg::CSR_INT_STATUS, 32'h2, "DONE W1C");
    apb_write(ai_accel_pkg::CSR_INT_STATUS, 32'h2, 4'h1, 1'b0,
              "clear ERROR status");
    expect_read(ai_accel_pkg::CSR_INT_STATUS, 32'h0, "ERROR W1C");
    checks++;
    if (irq) begin
      fail("interrupt clear", "irq remained asserted");
    end

    pulse_done_event();
    clear_with_simultaneous_done_event();
    expect_read(ai_accel_pkg::CSR_INT_STATUS, 32'h1,
                "hardware set wins over W1C");
    apb_write(ai_accel_pkg::CSR_INT_STATUS, 32'h1, 4'h1, 1'b0,
              "clear DONE after priority test");

    perf_cycles     = 32'h1234_5678;
    perf_compute_cycles = 32'h1357_2468;
    perf_mac_cycles = 32'h89AB_CDEF;
    perf_dma_cycles = 32'h1020_3040;
    perf_stall_cycles = 32'h5566_7788;
    expect_read(ai_accel_pkg::CSR_PERF_CYCLES, 32'h1234_5678,
                "read PERF_CYCLES");
    expect_read(ai_accel_pkg::CSR_PERF_MAC_CYCLES, 32'h89AB_CDEF,
                "read PERF_MAC_CYCLES");
    expect_read(ai_accel_pkg::CSR_PERF_COMPUTE_CYCLES, 32'h1357_2468,
                "read PERF_COMPUTE_CYCLES");
    expect_read(ai_accel_pkg::CSR_PERF_DMA_CYCLES, 32'h1020_3040,
                "read PERF_DMA_CYCLES");
    expect_read(ai_accel_pkg::CSR_PERF_STALL_CYCLES, 32'h5566_7788,
                "read PERF_STALL_CYCLES");
    apb_write(ai_accel_pkg::CSR_PERF_CYCLES, 32'h0, 4'hF, 1'b1,
              "PERF_CYCLES write protection");
    apb_write(ai_accel_pkg::CSR_PERF_MAC_CYCLES, 32'h0, 4'hF, 1'b1,
              "PERF_MAC_CYCLES write protection");
    apb_write(ai_accel_pkg::CSR_PERF_COMPUTE_CYCLES, 32'h0, 4'hF, 1'b1,
              "PERF_COMPUTE_CYCLES write protection");
    apb_write(ai_accel_pkg::CSR_PERF_DMA_CYCLES, 32'h0, 4'hF, 1'b1,
              "PERF_DMA_CYCLES write protection");
    apb_write(ai_accel_pkg::CSR_PERF_STALL_CYCLES, 32'h0, 4'hF, 1'b1,
              "PERF_STALL_CYCLES write protection");
    expect_read(ai_accel_pkg::CSR_PERF_CYCLES, 32'h1234_5678,
                "PERF_CYCLES unchanged");
    expect_read(ai_accel_pkg::CSR_PERF_MAC_CYCLES, 32'h89AB_CDEF,
                "PERF_MAC_CYCLES unchanged");
    expect_read(ai_accel_pkg::CSR_PERF_COMPUTE_CYCLES, 32'h1357_2468,
                "PERF_COMPUTE_CYCLES unchanged");
    expect_read(ai_accel_pkg::CSR_PERF_DMA_CYCLES, 32'h1020_3040,
                "PERF_DMA_CYCLES unchanged");
    expect_read(ai_accel_pkg::CSR_PERF_STALL_CYCLES, 32'h5566_7788,
                "PERF_STALL_CYCLES unchanged");

    apb_read(12'h040, data, 1'b1, "unmapped read");
    checks++;
    if (data !== 32'h0) begin
      fail("unmapped read", "invalid read did not return zero");
    end
    apb_read(12'h003, data, 1'b1, "unaligned read");
    apb_write(12'h040, 32'hFFFF_FFFF, 4'hF, 1'b1, "unmapped write");
    apb_write(12'h003, 32'hFFFF_FFFF, 4'hF, 1'b1, "unaligned write");

    back_to_back_writes();
    expect_read(ai_accel_pkg::CSR_M, 32'h0000_1122, "back-to-back M read");
    expect_read(ai_accel_pkg::CSR_N, 32'h0000_3344, "back-to-back N read");

    repeat (3) begin
      @(posedge clk);
      #1;
      checks++;
      if (pslverr || start_pulse || soft_reset_pulse) begin
        fail("idle bus", "bus response or command pulse active while idle");
      end
    end

    $display("tb_apb_accel_regs PASS (%0d self-checks)", checks);
    $finish;
  end

endmodule
