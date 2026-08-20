`timescale 1ns/1ps

// Full-system error and recovery regression.
module tb_end_to_end_errors;

  localparam int unsigned APB_ADDR_W = 12;
  localparam int unsigned MEMORY_WORDS = 2048;
  localparam logic [31:0] A_BASE = 32'h0000_0100;
  localparam logic [31:0] B_BASE = 32'h0000_0200;
  localparam logic [31:0] C_BASE = 32'h0000_0300;
  localparam logic [31:0] CANARY = 32'hDEAD_BEEF;

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
  int unsigned configured_response_delay;
  int unsigned request_count_q;
  int unsigned write_request_count_q;
  logic inject_read_error;
  logic inject_write_error;
  logic error_injected_q;
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
      $fatal(1, "tb_end_to_end_errors failed");
    end
  endtask

  always @(posedge clk or negedge rst_n) begin
    logic response_has_error;
    if (!rst_n) begin
      memory_pending_q    <= 1'b0;
      pending_write_q     <= 1'b0;
      pending_addr_q      <= '0;
      pending_wdata_q     <= '0;
      response_delay_q    <= 0;
      request_count_q     <= 0;
      write_request_count_q <= 0;
      error_injected_q    <= 1'b0;
      mem_rsp_valid       <= 1'b0;
      mem_rsp_rdata       <= '0;
      mem_rsp_error       <= 1'b0;
    end else begin
      if (mem_req_valid && mem_req_ready) begin
        checks++;
        if (mem_req_addr[1:0] != 0 || mem_req_addr[31:2] >= MEMORY_WORDS) begin
          fail("memory model", "invalid external address");
        end
        if (mem_req_write && mem_req_wstrb != 4'hF) begin
          fail("memory model", "store did not assert all byte strobes");
        end
        request_count_q <= request_count_q + 1;
        if (mem_req_write) begin
          write_request_count_q <= write_request_count_q + 1;
        end
        memory_pending_q <= 1'b1;
        pending_write_q  <= mem_req_write;
        pending_addr_q   <= mem_req_addr;
        pending_wdata_q  <= mem_req_wdata;
        response_delay_q <= configured_response_delay;
      end

      if (memory_pending_q && !mem_rsp_valid) begin
        if (response_delay_q == 0) begin
          response_has_error = !error_injected_q
                            && ((pending_write_q && inject_write_error)
                             || (!pending_write_q && inject_read_error));
          mem_rsp_valid <= 1'b1;
          mem_rsp_error <= response_has_error;
          if (response_has_error) begin
            error_injected_q <= 1'b1;
            mem_rsp_rdata    <= '0;
          end else if (pending_write_q) begin
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
      paddr = address;
      psel = 1'b1;
      penable = 1'b0;
      pwrite = 1'b1;
      pwdata = data;
      pstrb = 4'hF;
      @(negedge clk);
      penable = 1'b1;
      @(posedge clk);
      #1;
      checks++;
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
      paddr = address;
      psel = 1'b1;
      penable = 1'b0;
      pwrite = 1'b0;
      pwdata = '0;
      pstrb = '0;
      @(negedge clk);
      penable = 1'b1;
      @(posedge clk);
      #1;
      data = prdata;
      checks++;
      if (!pready || pslverr) begin
        fail(label, "APB read failed");
      end
      @(negedge clk);
      apb_idle();
    end
  endtask

  task automatic program_job(
    input int unsigned m,
    input int unsigned n,
    input int unsigned k,
    input logic [31:0] a_addr,
    input logic [31:0] b_addr,
    input logic [31:0] c_addr,
    input string label
  );
    begin
      apb_write(ai_accel_pkg::CSR_M, m, {label, " M"});
      apb_write(ai_accel_pkg::CSR_N, n, {label, " N"});
      apb_write(ai_accel_pkg::CSR_K, k, {label, " K"});
      apb_write(ai_accel_pkg::CSR_SRC_A_ADDR, a_addr, {label, " A"});
      apb_write(ai_accel_pkg::CSR_SRC_B_ADDR, b_addr, {label, " B"});
      apb_write(ai_accel_pkg::CSR_DST_ADDR, c_addr, {label, " C"});
      apb_write(ai_accel_pkg::CSR_QUANT_CONFIG, 0, {label, " output"});
    end
  endtask

  task automatic wait_for_irq(input string label);
    int unsigned timeout;
    begin
      timeout = 0;
      while (!irq) begin
        @(negedge clk);
        timeout++;
        if (timeout > 10000) begin
          fail(label, "timeout waiting for interrupt");
        end
      end
    end
  endtask

  task automatic expect_error_status(input string label, input logic expect_busy);
    logic [31:0] status_value;
    begin
      wait_for_irq(label);
      apb_read(ai_accel_pkg::CSR_STATUS, status_value, {label, " status"});
      checks += 3;
      if ((status_value[0] !== expect_busy)
          || status_value[1] || !status_value[2]) begin
        fail(label, "status did not report the expected ERROR state");
      end
    end
  endtask

  task automatic clear_interrupts(input string label);
    begin
      apb_write(ai_accel_pkg::CSR_INT_STATUS, 32'h3, {label, " clear IRQ"});
      checks++;
      if (irq) begin
        fail(label, "interrupt remained asserted after W1C");
      end
    end
  endtask

  initial begin
    logic [31:0] status_value;
    int unsigned requests_before;

    clk = 1'b0;
    rst_n = 1'b1;
    checks = 0;
    configured_response_delay = 1;
    inject_read_error = 1'b0;
    inject_write_error = 1'b0;
    apb_idle();
    for (int unsigned index = 0; index < MEMORY_WORDS; index++) begin
      system_memory[index] = '0;
    end

    #1;
    rst_n = 1'b0;
    #1;
    @(negedge clk);
    rst_n = 1'b1;

    apb_write(ai_accel_pkg::CSR_INT_ENABLE, 32'h3, "enable interrupts");

    // Invalid dimension is rejected before any DMA request.
    requests_before = request_count_q;
    program_job(0, 1, 1, A_BASE, B_BASE, C_BASE, "zero dimension");
    apb_write(ai_accel_pkg::CSR_CONTROL, 1, "zero dimension start");
    expect_error_status("zero dimension", 1'b0);
    if (request_count_q != requests_before) begin
      fail("zero dimension", "invalid job issued a DMA request");
    end
    clear_interrupts("zero dimension");
    $display("ERROR_SCENARIO,zero_dimension,PASS");

    // Misalignment is also rejected before DMA.
    requests_before = request_count_q;
    program_job(1, 1, 1, A_BASE + 1, B_BASE, C_BASE, "misaligned address");
    apb_write(ai_accel_pkg::CSR_CONTROL, 1, "misaligned start");
    expect_error_status("misaligned address", 1'b0);
    if (request_count_q != requests_before) begin
      fail("misaligned address", "misaligned job issued a DMA request");
    end
    clear_interrupts("misaligned address");
    $display("ERROR_SCENARIO,misaligned_address,PASS");

    // Read-response failure aborts the job and never writes C.
    error_injected_q = 1'b0;
    inject_read_error = 1'b1;
    system_memory[C_BASE >> 2] = CANARY;
    requests_before = request_count_q;
    program_job(2, 2, 2, A_BASE, B_BASE, C_BASE, "DMA read error");
    apb_write(ai_accel_pkg::CSR_CONTROL, 1, "DMA read error start");
    expect_error_status("DMA read error", 1'b0);
    checks += 2;
    if ((request_count_q != requests_before + 1)
        || (system_memory[C_BASE >> 2] !== CANARY)) begin
      fail("DMA read error", "job did not abort at the first failed read");
    end
    inject_read_error = 1'b0;
    clear_interrupts("DMA read error");
    $display("ERROR_SCENARIO,dma_read_response_error,PASS");

    // Write-response failure reports ERROR and does not commit the failed word.
    error_injected_q = 1'b0;
    inject_write_error = 1'b1;
    system_memory[A_BASE >> 2] = 3;
    system_memory[B_BASE >> 2] = 4;
    system_memory[C_BASE >> 2] = CANARY;
    requests_before = write_request_count_q;
    program_job(1, 1, 1, A_BASE, B_BASE, C_BASE, "DMA write error");
    apb_write(ai_accel_pkg::CSR_CONTROL, 1, "DMA write error start");
    expect_error_status("DMA write error", 1'b0);
    checks += 2;
    if ((write_request_count_q != requests_before + 1)
        || (system_memory[C_BASE >> 2] !== CANARY)) begin
      fail("DMA write error", "failed store changed C or was not attempted once");
    end
    inject_write_error = 1'b0;
    clear_interrupts("DMA write error");
    $display("ERROR_SCENARIO,dma_write_response_error,PASS");

    // Start-while-busy records ERROR but does not restart/corrupt active work.
    error_injected_q = 1'b0;
    configured_response_delay = 4;
    system_memory[A_BASE >> 2] = 3;
    system_memory[B_BASE >> 2] = 4;
    system_memory[C_BASE >> 2] = CANARY;
    program_job(1, 1, 1, A_BASE, B_BASE, C_BASE, "busy retrigger");
    apb_write(ai_accel_pkg::CSR_CONTROL, 1, "first start");
    @(posedge clk);
    #1;
    if (!dut.accel_busy) begin
      fail("busy retrigger", "first job was not active");
    end
    apb_write(ai_accel_pkg::CSR_CONTROL, 1, "second start");
    expect_error_status("busy retrigger", 1'b1);
    apb_write(ai_accel_pkg::CSR_INT_STATUS, 32'h2, "clear retrigger error");
    apb_write(ai_accel_pkg::CSR_INT_ENABLE, 32'h1, "wait for normal done");
    wait_for_irq("busy retrigger completion");
    apb_read(ai_accel_pkg::CSR_STATUS, status_value, "busy retrigger final status");
    checks += 3;
    if ((status_value[2:0] != 3'b010)
        || (system_memory[C_BASE >> 2] !== 32'd12)) begin
      fail("busy retrigger", "active job did not finish correctly after rejected start");
    end
    clear_interrupts("busy retrigger completion");
    $display("ERROR_SCENARIO,start_while_busy_rejected_without_corruption,PASS");

    // A clean job after all injected failures proves recovery without reset.
    configured_response_delay = 1;
    apb_write(ai_accel_pkg::CSR_INT_ENABLE, 32'h3, "recovery interrupts");
    system_memory[A_BASE >> 2] = 2;
    system_memory[B_BASE >> 2] = -32'sd5;
    system_memory[C_BASE >> 2] = CANARY;
    program_job(1, 1, 1, A_BASE, B_BASE, C_BASE, "recovery job");
    apb_write(ai_accel_pkg::CSR_CONTROL, 1, "recovery start");
    wait_for_irq("recovery job");
    apb_read(ai_accel_pkg::CSR_STATUS, status_value, "recovery status");
    checks += 3;
    if ((status_value[2:0] != 3'b010)
        || (system_memory[C_BASE >> 2] !== -32'sd10)) begin
      fail("recovery job", "clean job failed after prior error cases");
    end
    $display("ERROR_SCENARIO,clean_recovery_without_reset,PASS");

    $display("tb_end_to_end_errors PASS (6 scenarios, %0d self-checks)", checks);
    $finish;
  end

endmodule
