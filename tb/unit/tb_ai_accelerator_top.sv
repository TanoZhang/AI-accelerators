`timescale 1ns/1ps

module tb_ai_accelerator_top;

  localparam int unsigned APB_ADDR_W = 12;
  localparam int unsigned MEMORY_WORDS = 1024;
  localparam logic [31:0] A_BASE = 32'h0000_0100;
  localparam logic [31:0] B_BASE = 32'h0000_0200;
  localparam logic [31:0] C_BASE = 32'h0000_0300;

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

  logic [31:0] system_memory [0:MEMORY_WORDS-1];
  logic memory_pending_q;
  logic pending_write_q;
  logic [31:0] pending_addr_q;
  logic [31:0] pending_wdata_q;
  int unsigned response_delay_q;
  int unsigned checks;

  ai_accelerator_top #(
    .APB_ADDR_W (APB_ADDR_W),
    .SPAD_DEPTH (64)
  ) dut (
    .clk           (clk),
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

  always #5 clk = ~clk;

  assign mem_req_ready = !memory_pending_q && !mem_rsp_valid;

  task automatic fail(input string label, input string detail);
    begin
      $error("%s: %s", label, detail);
      $fatal(1, "tb_ai_accelerator_top failed");
    end
  endtask

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      memory_pending_q <= 1'b0;
      pending_write_q  <= 1'b0;
      pending_addr_q   <= '0;
      pending_wdata_q  <= '0;
      response_delay_q <= 0;
      mem_rsp_valid    <= 1'b0;
      mem_rsp_rdata    <= '0;
      mem_rsp_error    <= 1'b0;
    end else begin
      if (mem_req_valid && mem_req_ready) begin
        checks++;
        if (mem_req_addr[1:0] != 2'b00
            || (mem_req_addr[31:2] >= MEMORY_WORDS)) begin
          fail("memory request", "address was invalid");
        end
        if (mem_req_write && (mem_req_wstrb != 4'hF)) begin
          fail("memory request", "write did not enable all bytes");
        end
        memory_pending_q <= 1'b1;
        pending_write_q  <= mem_req_write;
        pending_addr_q   <= mem_req_addr;
        pending_wdata_q  <= mem_req_wdata;
        response_delay_q <= 1;
      end

      if (memory_pending_q && !mem_rsp_valid) begin
        if (response_delay_q == 0) begin
          mem_rsp_valid <= 1'b1;
          mem_rsp_error <= 1'b0;
          if (pending_write_q) begin
            system_memory[pending_addr_q[31:2]] <= pending_wdata_q;
            mem_rsp_rdata <= '0;
          end else begin
            mem_rsp_rdata <= system_memory[pending_addr_q[31:2]];
          end
        end else begin
          response_delay_q <= response_delay_q - 1;
        end
      end

      if (mem_rsp_valid && mem_rsp_ready) begin
        mem_rsp_valid    <= 1'b0;
        mem_rsp_error    <= 1'b0;
        memory_pending_q <= 1'b0;
      end
    end
  end

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
    input logic [31:0] data,
    input string label
  );
    begin
      @(negedge clk);
      paddr   = address;
      psel    = 1'b1;
      penable = 1'b0;
      pwrite  = 1'b1;
      pwdata  = data;
      pstrb   = 4'hF;
      @(negedge clk);
      penable = 1'b1;
      @(posedge clk);
      #1;
      checks += 2;
      if (!pready || pslverr) begin
        fail(label, "APB write failed");
      end
      @(negedge clk);
      apb_idle();
    end
  endtask

  task automatic apb_read(
    input logic [APB_ADDR_W-1:0] address,
    output logic [31:0] data,
    input string label
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
      if (!pready || pslverr) begin
        fail(label, "APB read failed");
      end
      @(negedge clk);
      apb_idle();
    end
  endtask

  initial begin
    logic [31:0] status_value;
    logic [31:0] mac_cycles_value;
    int unsigned timeout;

    clk    = 1'b0;
    rst_n  = 1'b1;
    checks = 0;
    apb_idle();

    for (int unsigned index = 0; index < MEMORY_WORDS; index++) begin
      system_memory[index] = '0;
    end

    // One INT8 value occupies the low byte of each 32-bit input word.
    system_memory[A_BASE[31:2] + 0] = 32'd1;
    system_memory[A_BASE[31:2] + 1] = 32'd2;
    system_memory[A_BASE[31:2] + 2] = 32'd3;
    system_memory[A_BASE[31:2] + 3] = 32'd4;
    system_memory[B_BASE[31:2] + 0] = 32'd5;
    system_memory[B_BASE[31:2] + 1] = 32'd6;
    system_memory[B_BASE[31:2] + 2] = 32'd7;
    system_memory[B_BASE[31:2] + 3] = 32'd8;

    #1;
    rst_n = 1'b0;
    #1;
    if (irq || mem_req_valid || mem_rsp_ready) begin
      fail("reset", "top-level outputs were active during reset");
    end
    @(negedge clk);
    rst_n = 1'b1;

    apb_write(ai_accel_pkg::CSR_M, 2, "program M");
    apb_write(ai_accel_pkg::CSR_N, 2, "program N");
    apb_write(ai_accel_pkg::CSR_K, 2, "program K");
    apb_write(ai_accel_pkg::CSR_SRC_A_ADDR, A_BASE, "program A base");
    apb_write(ai_accel_pkg::CSR_SRC_B_ADDR, B_BASE, "program B base");
    apb_write(ai_accel_pkg::CSR_DST_ADDR, C_BASE, "program C base");
    apb_write(ai_accel_pkg::CSR_QUANT_CONFIG, 0, "select INT32 output");
    apb_write(ai_accel_pkg::CSR_INT_ENABLE, 1, "enable DONE interrupt");
    apb_write(ai_accel_pkg::CSR_CONTROL, 1, "start accelerator");

    timeout = 0;
    while (!irq) begin
      @(negedge clk);
      timeout++;
      if (timeout > 5000) begin
        fail("2x2 GEMM", "timeout waiting for completion interrupt");
      end
    end

    checks += 4;
    if (system_memory[C_BASE[31:2] + 0] !== 32'd19
        || system_memory[C_BASE[31:2] + 1] !== 32'd22
        || system_memory[C_BASE[31:2] + 2] !== 32'd43
        || system_memory[C_BASE[31:2] + 3] !== 32'd50) begin
      fail("2x2 GEMM", "output matrix data mismatch");
    end

    apb_read(ai_accel_pkg::CSR_STATUS, status_value, "read final status");
    checks += 2;
    if (status_value[2:0] != 3'b010) begin
      fail("final status", "DONE was not sticky or BUSY/ERROR was set");
    end

    apb_read(ai_accel_pkg::CSR_PERF_MAC_CYCLES, mac_cycles_value,
             "read MAC cycles");
    checks++;
    if (mac_cycles_value != 2) begin
      fail("MAC cycles", "expected exactly K MAC updates for one tile");
    end

    apb_write(ai_accel_pkg::CSR_INT_STATUS, 1, "clear DONE interrupt");
    checks++;
    if (irq) begin
      fail("interrupt clear", "IRQ remained asserted after W1C");
    end

    $display("tb_ai_accelerator_top PASS (%0d self-checks)", checks);
    $finish;
  end

endmodule
