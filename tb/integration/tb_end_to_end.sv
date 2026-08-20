`timescale 1ns/1ps

// Full-system regression using Python-generated expected results.
module tb_end_to_end;

  localparam int unsigned APB_ADDR_W = 12;
  localparam int unsigned MEMORY_WORDS = 8192;
  localparam int unsigned SPAD_DEPTH = 256;
  localparam int unsigned MAX_ELEMENTS = SPAD_DEPTH;
  localparam logic [31:0] A_BASE = 32'h0000_1000;
  localparam logic [31:0] B_BASE = 32'h0000_2000;
  localparam logic [31:0] C_BASE = 32'h0000_3000;
  localparam logic [31:0] CANARY = 32'hA5A5_5A5A;

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
  logic [31:0] expected_memory [0:MAX_ELEMENTS-1];

  logic memory_pending_q;
  logic pending_write_q;
  logic [31:0] pending_addr_q;
  logic [31:0] pending_wdata_q;
  int unsigned response_delay_q;
  int unsigned memory_cycle_q;
  int unsigned active_stall_mode;
  int unsigned active_response_delay;
  int unsigned active_a_words;
  int unsigned active_b_words;
  int unsigned active_c_words;
  int unsigned request_count_q;
  int unsigned request_wait_q;
  int unsigned observed_stall_cycles_q;
  logic request_gate;
  logic case_active;
  string active_case_name;
  int unsigned checks;

  ai_accelerator_top #(
    .APB_ADDR_W (APB_ADDR_W),
    .SPAD_DEPTH (SPAD_DEPTH)
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

  always_comb begin
    request_gate = (active_stall_mode == 0)
                || (request_wait_q >= active_stall_mode);
    mem_req_ready = !memory_pending_q && !mem_rsp_valid && request_gate;
  end

  task automatic fail(input string label, input string detail);
    begin
      $error("%s: %s", label, detail);
      $fatal(1, "tb_end_to_end failed");
    end
  endtask

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      memory_pending_q       <= 1'b0;
      pending_write_q        <= 1'b0;
      pending_addr_q         <= '0;
      pending_wdata_q        <= '0;
      response_delay_q       <= 0;
      memory_cycle_q         <= 0;
      request_count_q        <= 0;
      request_wait_q         <= 0;
      observed_stall_cycles_q <= 0;
      mem_rsp_valid          <= 1'b0;
      mem_rsp_rdata          <= '0;
      mem_rsp_error          <= 1'b0;
    end else begin
      memory_cycle_q <= memory_cycle_q + 1;

      if (!memory_pending_q && !mem_rsp_valid && mem_req_valid) begin
        if (mem_req_ready) begin
          request_wait_q <= 0;
        end else begin
          request_wait_q <= request_wait_q + 1;
        end
      end else if (!mem_req_valid) begin
        request_wait_q <= 0;
      end

      if (case_active && mem_req_valid && !mem_req_ready) begin
        observed_stall_cycles_q <= observed_stall_cycles_q + 1;
      end

      if (mem_req_valid && mem_req_ready) begin
        if (mem_req_addr[1:0] != 2'b00
            || (mem_req_addr[31:2] >= MEMORY_WORDS)) begin
          fail(active_case_name, "DMA issued an unaligned or out-of-range address");
        end
        if (mem_req_write) begin
          if ((mem_req_wstrb != 4'hF)
              || (mem_req_addr < C_BASE)
              || (mem_req_addr >= (C_BASE + (active_c_words * 4)))) begin
            fail(active_case_name, "DMA write crossed the logical C bounds");
          end
        end else if (!(((mem_req_addr >= A_BASE)
                         && (mem_req_addr < (A_BASE + (active_a_words * 4))))
                        || ((mem_req_addr >= B_BASE)
                         && (mem_req_addr < (B_BASE + (active_b_words * 4)))))) begin
          fail(active_case_name, "DMA read crossed the logical A/B bounds");
        end

        request_count_q  <= request_count_q + 1;
        memory_pending_q <= 1'b1;
        pending_write_q  <= mem_req_write;
        pending_addr_q   <= mem_req_addr;
        pending_wdata_q  <= mem_req_wdata;
        response_delay_q <= active_response_delay;
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
      checks++;
      if (!pready || pslverr) begin
        fail(label, "APB read failed");
      end
      @(negedge clk);
      apb_idle();
    end
  endtask

  task automatic run_case(
    input string case_name,
    input int unsigned m,
    input int unsigned n,
    input int unsigned k,
    input int unsigned output_int8,
    input int unsigned relu_enable,
    input int unsigned shift,
    input int unsigned stall_mode,
    input int unsigned response_delay,
    input int unsigned benchmark
  );
    logic [31:0] status_value;
    logic [31:0] total_cycles;
    logic [31:0] mac_cycles;
    logic [31:0] compute_cycles;
    logic [31:0] dma_cycles;
    logic [31:0] stall_cycles;
    logic [31:0] quant_config;
    int unsigned timeout;
    int unsigned expected_requests;
    int unsigned expected_mac_cycles;
    int unsigned useful_macs;
    real mac_utilization;
    real effective_ops_per_cycle;
    time case_start_time;
    time case_end_time;
    begin
      active_case_name      = case_name;
      active_stall_mode     = stall_mode;
      active_response_delay = response_delay;
      active_a_words        = m * k;
      active_b_words        = k * n;
      active_c_words        = m * n;
      request_count_q       = 0;
      request_wait_q        = 0;
      observed_stall_cycles_q = 0;
      memory_cycle_q        = 0;
      case_active           = 1'b1;

      system_memory[(C_BASE >> 2) - 1] = CANARY;
      for (int unsigned index = 0; index <= active_c_words; index++) begin
        system_memory[(C_BASE >> 2) + index] = CANARY;
      end

      if (irq) begin
        apb_write(ai_accel_pkg::CSR_INT_STATUS, 32'h3,
                  {case_name, " clear prior interrupt"});
      end

      quant_config = (output_int8 & 1)
                   | ((relu_enable & 1) << 1)
                   | ((shift & 31) << 2);
      apb_write(ai_accel_pkg::CSR_M, m, {case_name, " M"});
      apb_write(ai_accel_pkg::CSR_N, n, {case_name, " N"});
      apb_write(ai_accel_pkg::CSR_K, k, {case_name, " K"});
      apb_write(ai_accel_pkg::CSR_SRC_A_ADDR, A_BASE, {case_name, " A"});
      apb_write(ai_accel_pkg::CSR_SRC_B_ADDR, B_BASE, {case_name, " B"});
      apb_write(ai_accel_pkg::CSR_DST_ADDR, C_BASE, {case_name, " C"});
      apb_write(ai_accel_pkg::CSR_QUANT_CONFIG, quant_config,
                {case_name, " output config"});
      apb_write(ai_accel_pkg::CSR_INT_ENABLE, 32'h3,
                {case_name, " interrupt enable"});
      case_start_time = $time;
      apb_write(ai_accel_pkg::CSR_CONTROL, 32'h1, {case_name, " start"});

      timeout = 0;
      while (!irq) begin
        @(negedge clk);
        timeout++;
        if (timeout > 100000) begin
          fail(case_name, "timeout waiting for completion/error interrupt");
        end
      end

      apb_read(ai_accel_pkg::CSR_STATUS, status_value,
               {case_name, " final status"});
      if (status_value[2:0] != 3'b010) begin
        fail(case_name, "job ended without DONE-only status");
      end

      for (int unsigned index = 0; index < active_c_words; index++) begin
        checks++;
        if (system_memory[(C_BASE >> 2) + index] !== expected_memory[index]) begin
          $display("MISMATCH,%s,index=%0d,actual=%08h,expected=%08h",
                   case_name, index,
                   system_memory[(C_BASE >> 2) + index], expected_memory[index]);
          fail(case_name, "output differs from Python reference");
        end
      end

      checks += 2;
      if ((system_memory[(C_BASE >> 2) - 1] !== CANARY)
          || (system_memory[(C_BASE >> 2) + active_c_words] !== CANARY)) begin
        fail(case_name, "output write modified a guard word");
      end

      expected_requests = active_a_words + active_b_words + active_c_words;
      checks++;
      if (request_count_q != expected_requests) begin
        fail(case_name, "DMA request count did not match exact matrix bounds");
      end

      apb_read(ai_accel_pkg::CSR_PERF_CYCLES, total_cycles,
               {case_name, " total cycles"});
      apb_read(ai_accel_pkg::CSR_PERF_MAC_CYCLES, mac_cycles,
               {case_name, " MAC cycles"});
      apb_read(ai_accel_pkg::CSR_PERF_COMPUTE_CYCLES, compute_cycles,
               {case_name, " compute cycles"});
      apb_read(ai_accel_pkg::CSR_PERF_DMA_CYCLES, dma_cycles,
               {case_name, " DMA cycles"});
      apb_read(ai_accel_pkg::CSR_PERF_STALL_CYCLES, stall_cycles,
               {case_name, " stall cycles"});

      expected_mac_cycles = ((m + 3) / 4) * ((n + 3) / 4) * k;
      checks += 5;
      if (mac_cycles != expected_mac_cycles) begin
        fail(case_name, "MAC cycles did not equal K times the tile count");
      end
      if ((total_cycles < compute_cycles) || (total_cycles < dma_cycles)
          || (compute_cycles < mac_cycles) || (dma_cycles < expected_requests)) begin
        fail(case_name, "performance counters violated ordering invariants");
      end
      if (stall_cycles != observed_stall_cycles_q) begin
        fail(case_name, "hardware stall counter disagreed with bus observation");
      end
      if ((stall_mode == 0) && (stall_cycles != 0)) begin
        fail(case_name, "zero-wait memory unexpectedly reported request stalls");
      end
      if ((stall_mode != 0) && (stall_cycles == 0)) begin
        fail(case_name, "backpressured memory did not exercise the stall counter");
      end

      useful_macs = m * n * k;
      mac_utilization = (100.0 * useful_macs) / (16.0 * mac_cycles);
      effective_ops_per_cycle = (2.0 * useful_macs) / total_cycles;
      $display(
        "METRIC,%s,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0.3f,%0.6f",
        case_name, m, n, k, output_int8, relu_enable, shift, stall_mode,
        benchmark, total_cycles, mac_cycles, compute_cycles, dma_cycles, stall_cycles,
        mac_utilization, effective_ops_per_cycle
      );
      case_end_time = $time;
      $display("CASE_WINDOW,%s,%0t,%0t", case_name,
               case_start_time, case_end_time);

      apb_write(ai_accel_pkg::CSR_INT_STATUS, 32'h1,
                {case_name, " clear DONE"});
      if (irq) begin
        fail(case_name, "DONE interrupt did not clear");
      end
      case_active = 1'b0;
    end
  endtask

  initial begin
    int vector_file;
    int parsed;
    int case_count;
    string case_name;
    int unsigned m;
    int unsigned n;
    int unsigned k;
    int unsigned output_int8;
    int unsigned relu_enable;
    int unsigned shift;
    int unsigned stall_mode;
    int unsigned response_delay;
    int unsigned benchmark;
    logic [31:0] value;

    clk                   = 1'b0;
    rst_n                 = 1'b1;
    checks                = 0;
    case_active           = 1'b0;
    active_case_name      = "initialization";
    active_stall_mode     = 0;
    active_response_delay = 0;
    active_a_words        = 0;
    active_b_words        = 0;
    active_c_words        = 0;
    apb_idle();

    for (int unsigned index = 0; index < MEMORY_WORDS; index++) begin
      system_memory[index] = '0;
    end

    #1;
    rst_n = 1'b0;
    #1;
    if (irq || mem_req_valid || mem_rsp_ready) begin
      fail("reset", "top-level output was active during reset");
    end
    @(negedge clk);
    rst_n = 1'b1;

    vector_file = $fopen("tb/generated/e2e_vectors.txt", "r");
    if (vector_file == 0) begin
      fail("vectors", "could not open Python-generated vector file");
    end
    parsed = $fscanf(vector_file, "%d", case_count);
    if ((parsed != 1) || (case_count <= 0)) begin
      fail("vectors", "invalid case count");
    end

    for (int case_index = 0; case_index < case_count; case_index++) begin
      parsed = $fscanf(vector_file, "%s %d %d %d %d %d %d %d %d %d",
                       case_name, m, n, k, output_int8, relu_enable, shift,
                       stall_mode, response_delay, benchmark);
      if (parsed != 10) begin
        fail("vectors", "invalid case header");
      end
      if (((m * k) > MAX_ELEMENTS) || ((k * n) > MAX_ELEMENTS)
          || ((m * n) > MAX_ELEMENTS)) begin
        fail(case_name, "case exceeds configured scratchpad depth");
      end

      for (int unsigned index = 0; index < (m * k); index++) begin
        if ($fscanf(vector_file, "%h", value) != 1) begin
          fail(case_name, "truncated A vectors");
        end
        system_memory[(A_BASE >> 2) + index] = value;
      end
      for (int unsigned index = 0; index < (k * n); index++) begin
        if ($fscanf(vector_file, "%h", value) != 1) begin
          fail(case_name, "truncated B vectors");
        end
        system_memory[(B_BASE >> 2) + index] = value;
      end
      for (int unsigned index = 0; index < (m * n); index++) begin
        if ($fscanf(vector_file, "%h", value) != 1) begin
          fail(case_name, "truncated expected vectors");
        end
        expected_memory[index] = value;
      end

      run_case(case_name, m, n, k, output_int8, relu_enable, shift,
               stall_mode, response_delay, benchmark);
    end

    $fclose(vector_file);
    $display("tb_end_to_end PASS (%0d cases, %0d self-checks)",
             case_count, checks);
    $finish;
  end

endmodule
