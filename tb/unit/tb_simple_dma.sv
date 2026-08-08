`timescale 1ns/1ps

module tb_simple_dma;

  localparam int unsigned SPAD_DEPTH   = 256;
  localparam int unsigned SPAD_ADDR_W  = $clog2(SPAD_DEPTH);
  localparam int unsigned MEMORY_WORDS = 4096;

  logic clk;
  logic rst_n;
  logic start;
  ai_accel_pkg::dma_transfer_e direction;
  logic [31:0] src_addr;
  logic [31:0] dst_addr;
  logic [31:0] length_words;
  logic busy;
  logic done;
  logic error;

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

  logic activation_write_en;
  logic [SPAD_ADDR_W-1:0] activation_write_addr;
  logic [31:0] activation_write_data;
  logic weight_write_en;
  logic [SPAD_ADDR_W-1:0] weight_write_addr;
  logic [31:0] weight_write_data;
  logic output_read_en;
  logic [SPAD_ADDR_W-1:0] output_read_addr;
  logic output_read_valid;
  logic [31:0] output_read_data;
  logic output_write_en;
  logic [SPAD_ADDR_W-1:0] output_write_addr;
  logic [31:0] output_write_data;

  logic [31:0] system_memory [0:MEMORY_WORDS-1];
  logic [31:0] activation_model [0:SPAD_DEPTH-1];
  logic [31:0] weight_model [0:SPAD_DEPTH-1];
  logic [31:0] output_model [0:SPAD_DEPTH-1];

  logic memory_outstanding_q;
  logic pending_write_q;
  logic [31:0] pending_addr_q;
  logic [31:0] pending_wdata_q;
  logic pending_error_q;
  int unsigned response_delay_q;
  int unsigned forced_request_stalls;
  logic inject_error_next;

  bit scoreboard_active;
  ai_accel_pkg::dma_transfer_e expected_direction;
  logic [31:0] expected_memory_addr;
  int unsigned expected_length;
  int unsigned expected_spad_base;
  int unsigned observed_requests;
  int unsigned observed_scratch_writes;
  int unsigned request_stall_cycles;
  int unsigned response_wait_cycles;
  int unsigned checks;

  simple_dma #(
    .SPAD_DEPTH  (SPAD_DEPTH),
    .SPAD_ADDR_W (SPAD_ADDR_W)
  ) dut (
    .clk                   (clk),
    .rst_n                 (rst_n),
    .start                 (start),
    .direction             (direction),
    .src_addr              (src_addr),
    .dst_addr              (dst_addr),
    .length_words          (length_words),
    .busy                  (busy),
    .done                  (done),
    .error                 (error),
    .mem_req_valid         (mem_req_valid),
    .mem_req_ready         (mem_req_ready),
    .mem_req_write         (mem_req_write),
    .mem_req_addr          (mem_req_addr),
    .mem_req_wdata         (mem_req_wdata),
    .mem_req_wstrb         (mem_req_wstrb),
    .mem_rsp_valid         (mem_rsp_valid),
    .mem_rsp_ready         (mem_rsp_ready),
    .mem_rsp_rdata         (mem_rsp_rdata),
    .mem_rsp_error         (mem_rsp_error),
    .activation_write_en   (activation_write_en),
    .activation_write_addr (activation_write_addr),
    .activation_write_data (activation_write_data),
    .weight_write_en       (weight_write_en),
    .weight_write_addr     (weight_write_addr),
    .weight_write_data     (weight_write_data),
    .output_read_en        (output_read_en),
    .output_read_addr      (output_read_addr),
    .output_read_valid     (output_read_valid),
    .output_read_data      (output_read_data)
  );

  scratchpad_sram #(
    .DATA_W (32),
    .DEPTH  (SPAD_DEPTH),
    .ADDR_W (SPAD_ADDR_W)
  ) output_sram (
    .clk        (clk),
    .rst_n      (rst_n),
    .read_en    (output_read_en),
    .read_addr  (output_read_addr),
    .read_data  (output_read_data),
    .read_valid (output_read_valid),
    .write_en   (output_write_en),
    .write_addr (output_write_addr),
    .write_data (output_write_data)
  );

  always #5 clk = ~clk;

  task automatic fail(input string label, input string detail);
    begin
      $error("%s: %s", label, detail);
      $fatal(1, "tb_simple_dma failed");
    end
  endtask

  always @(negedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mem_req_ready = 1'b0;
    end else if (!memory_outstanding_q && !mem_rsp_valid && mem_req_valid) begin
      if (forced_request_stalls != 0) begin
        mem_req_ready = 1'b0;
        forced_request_stalls = forced_request_stalls - 1;
      end else begin
        mem_req_ready = ($urandom_range(0, 3) != 0);
      end
    end else begin
      mem_req_ready = 1'b0;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      memory_outstanding_q <= 1'b0;
      pending_write_q      <= 1'b0;
      pending_addr_q       <= '0;
      pending_wdata_q      <= '0;
      pending_error_q      <= 1'b0;
      response_delay_q     <= 0;
      mem_rsp_valid        <= 1'b0;
      mem_rsp_rdata        <= '0;
      mem_rsp_error        <= 1'b0;
    end else begin
      if (mem_req_valid && mem_req_ready) begin
        memory_outstanding_q <= 1'b1;
        pending_write_q      <= mem_req_write;
        pending_addr_q       <= mem_req_addr;
        pending_wdata_q      <= mem_req_wdata;
        pending_error_q      <= inject_error_next;
        response_delay_q     <= $urandom_range(1, 6);
        inject_error_next    <= 1'b0;
      end

      if (memory_outstanding_q && !mem_rsp_valid) begin
        response_wait_cycles <= response_wait_cycles + 1;
        if (response_delay_q == 0) begin
          mem_rsp_valid <= 1'b1;
          mem_rsp_error <= pending_error_q;
          if (pending_write_q) begin
            mem_rsp_rdata <= '0;
            if (!pending_error_q) begin
              system_memory[pending_addr_q[31:2]] <= pending_wdata_q;
            end
          end else begin
            mem_rsp_rdata <= system_memory[pending_addr_q[31:2]];
          end
        end else begin
          response_delay_q <= response_delay_q - 1;
        end
      end

      if (mem_rsp_valid && mem_rsp_ready) begin
        mem_rsp_valid        <= 1'b0;
        mem_rsp_error        <= 1'b0;
        memory_outstanding_q <= 1'b0;
      end
    end
  end

  always @(posedge clk) begin
    if (rst_n) begin
      if (mem_req_valid && !mem_req_ready) begin
        request_stall_cycles <= request_stall_cycles + 1;
      end

      if (mem_req_valid && mem_req_ready && scoreboard_active) begin
        checks += 4;
        if (observed_requests >= expected_length) begin
          fail("request scoreboard", "too many memory requests");
        end
        if (mem_req_addr !== expected_memory_addr) begin
          fail("request scoreboard", "memory address did not increment by four");
        end
        if (mem_req_write !==
            (expected_direction == ai_accel_pkg::DMA_OUTPUT_TO_MEM)) begin
          fail("request scoreboard", "request direction is incorrect");
        end
        if (mem_req_write) begin
          if (mem_req_wstrb !== 4'hF) begin
            fail("request scoreboard", "store write strobes are incorrect");
          end
          if (mem_req_wdata !== output_model[expected_spad_base
                                             + observed_requests]) begin
            fail("request scoreboard", "store data is incorrect");
          end
        end else if (mem_req_wstrb !== 4'h0) begin
          fail("request scoreboard", "read request has write strobes");
        end

        observed_requests   <= observed_requests + 1;
        expected_memory_addr <= expected_memory_addr + 32'd4;
      end

      if (activation_write_en) begin
        activation_model[activation_write_addr] <= activation_write_data;
        observed_scratch_writes <= observed_scratch_writes + 1;
      end
      if (weight_write_en) begin
        weight_model[weight_write_addr] <= weight_write_data;
        observed_scratch_writes <= observed_scratch_writes + 1;
      end
    end
  end

  function automatic logic [31:0] pattern_word(input int unsigned index);
    pattern_word = 32'hA500_0000 ^ (index * 32'h0001_1021);
  endfunction

  task automatic preload_output(
    input int unsigned base,
    input int unsigned count
  );
    logic [31:0] data;
    begin
      for (int unsigned index = 0; index < count; index++) begin
        data = pattern_word(index + 100);
        @(negedge clk);
        output_write_en   = 1'b1;
        output_write_addr = SPAD_ADDR_W'(base + index);
        output_write_data = data;
        @(posedge clk);
        output_model[base + index] = data;
        @(negedge clk);
        output_write_en = 1'b0;
      end
    end
  endtask

  task automatic prepare_scoreboard(
    input ai_accel_pkg::dma_transfer_e transfer_direction,
    input logic [31:0] memory_base,
    input int unsigned scratchpad_base,
    input int unsigned count
  );
    begin
      expected_direction   = transfer_direction;
      expected_memory_addr = memory_base;
      expected_spad_base   = scratchpad_base;
      expected_length      = count;
      observed_requests    = 0;
      observed_scratch_writes = 0;
      scoreboard_active    = 1'b1;
      forced_request_stalls = 2;
    end
  endtask

  task automatic launch_command(
    input ai_accel_pkg::dma_transfer_e transfer_direction,
    input logic [31:0] source,
    input logic [31:0] destination,
    input int unsigned count
  );
    begin
      @(negedge clk);
      direction    = transfer_direction;
      src_addr     = source;
      dst_addr     = destination;
      length_words = count;
      start        = 1'b1;
      @(posedge clk);
      #1;
      @(negedge clk);
      start = 1'b0;
    end
  endtask

  task automatic wait_for_completion(
    input bit    expect_error,
    input string label
  );
    int unsigned timeout;
    bit finished;
    begin
      timeout  = 0;
      finished = 1'b0;
      while (!finished) begin
        @(negedge clk);
        timeout++;
        if (timeout > 5000) begin
          fail(label, "timeout");
        end
        if (done) begin
          checks += 2;
          if (expect_error || error) begin
            fail(label, "unexpected successful completion");
          end
          finished = 1'b1;
        end else if (error && !busy) begin
          checks++;
          if (!expect_error) begin
            fail(label, "unexpected DMA error");
          end
          finished = 1'b1;
        end
      end
      scoreboard_active = 1'b0;
    end
  endtask

  task automatic run_load(
    input ai_accel_pkg::dma_transfer_e transfer_direction,
    input int unsigned count,
    input int unsigned scratchpad_base,
    input bit          inject_busy_start,
    input string       label
  );
    int unsigned memory_word_base;
    logic [31:0] memory_byte_base;
    begin
      memory_word_base = $urandom_range(32, MEMORY_WORDS-count-32);
      memory_byte_base = memory_word_base << 2;
      for (int unsigned index = 0; index < count; index++) begin
        system_memory[memory_word_base + index] = pattern_word(index);
      end

      prepare_scoreboard(transfer_direction, memory_byte_base,
                         scratchpad_base, count);
      launch_command(transfer_direction, memory_byte_base,
                     scratchpad_base, count);
      if (!busy) begin
        fail(label, "DMA did not become busy");
      end

      if (inject_busy_start) begin
        @(negedge clk);
        start        = 1'b1;
        src_addr     = 32'hFFFF_FFFC;
        dst_addr     = 32'hFFFF_FFFF;
        length_words = 32'hFFFF_FFFF;
        @(posedge clk);
        #1;
        checks += 2;
        if (!error || !busy) begin
          fail(label, "start while busy was not rejected cleanly");
        end
        @(negedge clk);
        start = 1'b0;
      end

      wait_for_completion(1'b0, label);
      checks += 2;
      if (observed_requests != count || observed_scratch_writes != count) begin
        fail(label, "transfer count is incorrect");
      end
      for (int unsigned index = 0; index < count; index++) begin
        checks++;
        if (transfer_direction == ai_accel_pkg::DMA_MEM_TO_ACTIVATION) begin
          if (activation_model[scratchpad_base + index] !== pattern_word(index)) begin
            fail(label, "activation scratchpad data mismatch");
          end
        end else if (weight_model[scratchpad_base + index]
                     !== pattern_word(index)) begin
          fail(label, "weight scratchpad data mismatch");
        end
      end
    end
  endtask

  task automatic run_store(
    input int unsigned count,
    input int unsigned scratchpad_base,
    input string       label
  );
    int unsigned memory_word_base;
    logic [31:0] memory_byte_base;
    begin
      preload_output(scratchpad_base, count);
      memory_word_base = $urandom_range(32, MEMORY_WORDS-count-32);
      memory_byte_base = memory_word_base << 2;
      for (int unsigned index = 0; index < count; index++) begin
        system_memory[memory_word_base + index] = '0;
      end

      prepare_scoreboard(ai_accel_pkg::DMA_OUTPUT_TO_MEM, memory_byte_base,
                         scratchpad_base, count);
      launch_command(ai_accel_pkg::DMA_OUTPUT_TO_MEM, scratchpad_base,
                     memory_byte_base, count);
      wait_for_completion(1'b0, label);

      checks++;
      if (observed_requests != count) begin
        fail(label, "store request count is incorrect");
      end
      for (int unsigned index = 0; index < count; index++) begin
        checks++;
        if (system_memory[memory_word_base + index]
            !== output_model[scratchpad_base + index]) begin
          fail(label, "system-memory store data mismatch");
        end
      end
    end
  endtask

  task automatic test_zero_length;
    begin
      prepare_scoreboard(ai_accel_pkg::DMA_MEM_TO_ACTIVATION, 32'h100, 0, 0);
      launch_command(ai_accel_pkg::DMA_MEM_TO_ACTIVATION, 32'h100, 0, 0);
      checks += 3;
      if (!done || busy || error) begin
        fail("LENGTH=0", "zero-length command did not finish cleanly");
      end
      @(posedge clk);
      #1;
      if (done || observed_requests != 0) begin
        fail("LENGTH=0", "zero-length command generated work");
      end
      scoreboard_active = 1'b0;
    end
  endtask

  task automatic test_memory_error;
    int unsigned memory_word_base;
    logic [31:0] memory_byte_base;
    begin
      memory_word_base = 200;
      memory_byte_base = memory_word_base << 2;
      system_memory[memory_word_base] = 32'hDEAD_BEEF;
      prepare_scoreboard(ai_accel_pkg::DMA_MEM_TO_ACTIVATION,
                         memory_byte_base, 20, 4);
      inject_error_next = 1'b1;
      launch_command(ai_accel_pkg::DMA_MEM_TO_ACTIVATION,
                     memory_byte_base, 20, 4);
      wait_for_completion(1'b1, "memory response error");
      checks++;
      if (done || observed_scratch_writes != 0) begin
        fail("memory response error", "errored read wrote scratchpad data");
      end
    end
  endtask

  task automatic test_reset_during_transfer;
    int unsigned memory_word_base;
    logic [31:0] memory_byte_base;
    int unsigned timeout;
    begin
      memory_word_base = 500;
      memory_byte_base = memory_word_base << 2;
      for (int unsigned index = 0; index < 20; index++) begin
        system_memory[memory_word_base + index] = pattern_word(index + 50);
      end
      prepare_scoreboard(ai_accel_pkg::DMA_MEM_TO_WEIGHT,
                         memory_byte_base, 40, 20);
      launch_command(ai_accel_pkg::DMA_MEM_TO_WEIGHT,
                     memory_byte_base, 40, 20);

      timeout = 0;
      while ((observed_requests == 0) && (timeout < 200)) begin
        @(negedge clk);
        timeout++;
      end
      if (observed_requests == 0) begin
        fail("reset during transfer", "no request was issued");
      end

      @(negedge clk);
      rst_n = 1'b0;
      #1;
      checks += 3;
      if (busy || done || error) begin
        fail("reset during transfer", "DMA did not reset immediately");
      end
      scoreboard_active = 1'b0;
      @(negedge clk);
      rst_n = 1'b1;
    end
  endtask

  initial begin
    clk                     = 1'b0;
    rst_n                   = 1'b1;
    start                   = 1'b0;
    direction               = ai_accel_pkg::DMA_MEM_TO_ACTIVATION;
    src_addr                = '0;
    dst_addr                = '0;
    length_words            = '0;
    output_write_en         = 1'b0;
    output_write_addr       = '0;
    output_write_data       = '0;
    mem_req_ready           = 1'b0;
    inject_error_next       = 1'b0;
    forced_request_stalls   = 0;
    scoreboard_active       = 1'b0;
    observed_requests       = 0;
    observed_scratch_writes = 0;
    request_stall_cycles    = 0;
    response_wait_cycles    = 0;
    checks                  = 0;

    #1;
    rst_n = 1'b0;
    #1;
    if (busy || done || error || mem_req_valid || mem_rsp_ready) begin
      fail("reset", "DMA outputs did not reset");
    end
    @(negedge clk);
    rst_n = 1'b1;

    test_zero_length();
    run_load(ai_accel_pkg::DMA_MEM_TO_ACTIVATION, 1, 3, 1'b0,
             "activation length 1");
    run_load(ai_accel_pkg::DMA_MEM_TO_WEIGHT, 2, 7, 1'b1,
             "weight length 2 with busy start");
    run_load(ai_accel_pkg::DMA_MEM_TO_ACTIVATION, 37, 50, 1'b0,
             "activation many words");
    run_store(1, 11, "output store length 1");
    run_store(19, 80, "output store many words");
    test_memory_error();
    test_reset_during_transfer();
    run_load(ai_accel_pkg::DMA_MEM_TO_WEIGHT, 6, 120, 1'b0,
             "post-reset recovery");

    checks += 2;
    if (request_stall_cycles == 0 || response_wait_cycles == 0) begin
      fail("latency coverage", "stalls or delayed responses were not exercised");
    end

    $display("tb_simple_dma PASS (%0d self-checks, %0d request stalls, %0d response wait cycles)",
             checks, request_stall_cycles, response_wait_cycles);
    $finish;
  end

endmodule
