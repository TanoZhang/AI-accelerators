`timescale 1ns/1ps

module tb_accel_controller;

  localparam int unsigned DIM_W = 16;

  logic clk;
  logic rst_n;
  logic start;
  logic [DIM_W-1:0] cfg_m;
  logic [DIM_W-1:0] cfg_n;
  logic [DIM_W-1:0] cfg_k;
  logic [31:0] src_a_addr;
  logic [31:0] src_b_addr;
  logic [31:0] dst_addr;
  logic quant_enable;
  logic relu_enable;
  logic [4:0] quant_shift;

  logic dma_busy;
  logic dma_done;
  logic dma_error;
  logic dma_start;
  ai_accel_pkg::dma_transfer_e dma_direction;
  logic [31:0] dma_src_addr;
  logic [31:0] dma_dst_addr;
  logic [31:0] dma_length_words;

  logic compute_busy;
  logic compute_done;
  logic compute_error;
  logic output_writer_busy;
  logic compute_start;
  logic start_accepted;
  logic [DIM_W-1:0] active_m;
  logic [DIM_W-1:0] active_n;
  logic [DIM_W-1:0] active_k;
  logic active_quant_enable;
  logic active_relu_enable;
  logic [4:0] active_quant_shift;

  logic busy;
  logic done;
  logic error;
  logic interrupt_event;
  ai_accel_pkg::accel_state_e status_state;
  ai_accel_pkg::error_code_e error_code;

  int unsigned dma_delay_q;
  int unsigned compute_delay_q;
  logic dma_pending_error_q;
  logic compute_pending_error_q;
  int fail_dma_command;
  bit fail_compute_command;
  int unsigned dma_command_count;
  int unsigned compute_command_count;
  int unsigned error_event_count;
  int unsigned checks;

  logic [DIM_W-1:0] expected_m;
  logic [DIM_W-1:0] expected_n;
  logic [DIM_W-1:0] expected_k;
  logic [31:0] expected_a_addr;
  logic [31:0] expected_b_addr;
  logic [31:0] expected_c_addr;
  logic expected_quant_enable;
  logic expected_relu_enable;
  logic [4:0] expected_quant_shift;

  accel_controller #(
    .DIM_W (DIM_W)
  ) dut (
    .clk                 (clk),
    .rst_n               (rst_n),
    .start               (start),
    .cfg_m               (cfg_m),
    .cfg_n               (cfg_n),
    .cfg_k               (cfg_k),
    .src_a_addr          (src_a_addr),
    .src_b_addr          (src_b_addr),
    .dst_addr            (dst_addr),
    .quant_enable        (quant_enable),
    .relu_enable         (relu_enable),
    .quant_shift         (quant_shift),
    .start_accepted      (start_accepted),
    .dma_busy            (dma_busy),
    .dma_done            (dma_done),
    .dma_error           (dma_error),
    .dma_start           (dma_start),
    .dma_direction       (dma_direction),
    .dma_src_addr        (dma_src_addr),
    .dma_dst_addr        (dma_dst_addr),
    .dma_length_words    (dma_length_words),
    .compute_busy        (compute_busy),
    .compute_done        (compute_done),
    .compute_error       (compute_error),
    .output_writer_busy  (output_writer_busy),
    .compute_start       (compute_start),
    .active_m            (active_m),
    .active_n            (active_n),
    .active_k            (active_k),
    .active_quant_enable (active_quant_enable),
    .active_relu_enable  (active_relu_enable),
    .active_quant_shift  (active_quant_shift),
    .busy                (busy),
    .done                (done),
    .error               (error),
    .interrupt_event     (interrupt_event),
    .status_state        (status_state),
    .error_code          (error_code)
  );

  always #5 clk = ~clk;

  task automatic fail(input string label, input string detail);
    begin
      $error("%s: %s", label, detail);
      $fatal(1, "tb_accel_controller failed");
    end
  endtask

  function automatic logic [31:0] packed_words(
    input logic [DIM_W-1:0] first,
    input logic [DIM_W-1:0] second
  );
    logic [63:0] elements;
    begin
      elements = 64'(first) * 64'(second);
      packed_words = 32'((elements + 64'd3) >> 2);
    end
  endfunction

  function automatic logic [31:0] output_words(
    input logic [DIM_W-1:0] m_value,
    input logic [DIM_W-1:0] n_value
  );
    logic [63:0] elements;
    begin
      elements = 64'(m_value) * 64'(n_value);
      output_words = elements[31:0];
    end
  endfunction

  task automatic check_active_config(input string label);
    begin
      checks += 9;
      if ((active_m !== expected_m) || (active_n !== expected_n)
          || (active_k !== expected_k)
          || (active_quant_enable !== expected_quant_enable)
          || (active_relu_enable !== expected_relu_enable)
          || (active_quant_shift !== expected_quant_shift)) begin
        fail(label, "active configuration changed after START");
      end
    end
  endtask

  task automatic check_dma_command(input int unsigned command_index);
    logic [31:0] expected_length;
    begin
      check_active_config("DMA command");
      checks += 5;
      case (command_index)
        0: begin
          expected_length = output_words(expected_m, expected_k);
          if ((dma_direction !== ai_accel_pkg::DMA_MEM_TO_ACTIVATION)
              || (dma_src_addr !== expected_a_addr)
              || (dma_dst_addr !== 32'd0)
              || (dma_length_words !== expected_length)) begin
            fail("LOAD_A", "DMA command payload mismatch");
          end
        end
        1: begin
          expected_length = output_words(expected_k, expected_n);
          if ((dma_direction !== ai_accel_pkg::DMA_MEM_TO_WEIGHT)
              || (dma_src_addr !== expected_b_addr)
              || (dma_dst_addr !== 32'd0)
              || (dma_length_words !== expected_length)) begin
            fail("LOAD_B", "DMA command payload mismatch");
          end
        end
        2: begin
          expected_length = output_words(expected_m, expected_n);
          if ((dma_direction !== ai_accel_pkg::DMA_OUTPUT_TO_MEM)
              || (dma_src_addr !== 32'd0)
              || (dma_dst_addr !== expected_c_addr)
              || (dma_length_words !== expected_length)) begin
            fail("STORE_OUTPUT", "DMA command payload mismatch");
          end
        end
        default: fail("DMA command", "too many commands issued");
      endcase
    end
  endtask

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dma_busy               <= 1'b0;
      dma_done               <= 1'b0;
      dma_error              <= 1'b0;
      dma_delay_q            <= 0;
      dma_pending_error_q    <= 1'b0;
      dma_command_count      <= 0;
    end else begin
      dma_done  <= 1'b0;
      dma_error <= 1'b0;

      if (dma_start) begin
        if (dma_busy) begin
          fail("DMA mock", "command issued while busy");
        end
        check_dma_command(dma_command_count);
        dma_busy            <= 1'b1;
        dma_delay_q         <= $urandom_range(1, 12);
        dma_pending_error_q <= (fail_dma_command == int'(dma_command_count + 1));
        dma_command_count   <= dma_command_count + 1;
      end else if (dma_busy) begin
        if (dma_delay_q == 0) begin
          dma_busy <= 1'b0;
          if (dma_pending_error_q) begin
            dma_error <= 1'b1;
          end else begin
            dma_done <= 1'b1;
          end
        end else begin
          dma_delay_q <= dma_delay_q - 1;
        end
      end
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      compute_busy            <= 1'b0;
      compute_done            <= 1'b0;
      compute_error           <= 1'b0;
      compute_delay_q         <= 0;
      compute_pending_error_q <= 1'b0;
      compute_command_count   <= 0;
    end else begin
      compute_done  <= 1'b0;
      compute_error <= 1'b0;

      if (compute_start) begin
        if (compute_busy) begin
          fail("compute mock", "command issued while busy");
        end
        check_active_config("compute command");
        checks += 2;
        if (compute_command_count != 0) begin
          fail("compute command", "compute was started more than once");
        end
        compute_busy            <= 1'b1;
        compute_delay_q         <= $urandom_range(1, 15);
        compute_pending_error_q <= fail_compute_command;
        compute_command_count   <= compute_command_count + 1;
      end else if (compute_busy) begin
        if (compute_delay_q == 0) begin
          compute_busy <= 1'b0;
          if (compute_pending_error_q) begin
            compute_error <= 1'b1;
          end else begin
            compute_done <= 1'b1;
          end
        end else begin
          compute_delay_q <= compute_delay_q - 1;
        end
      end
    end
  end

  always @(posedge clk) begin
    if (rst_n && error) begin
      error_event_count <= error_event_count + 1;
    end
  end

  task automatic set_job(
    input logic [DIM_W-1:0] m_value,
    input logic [DIM_W-1:0] n_value,
    input logic [DIM_W-1:0] k_value,
    input logic [31:0] a_address,
    input logic [31:0] b_address,
    input logic [31:0] c_address,
    input bit quant_value,
    input bit relu_value,
    input logic [4:0] shift_value
  );
    begin
      cfg_m         = m_value;
      cfg_n         = n_value;
      cfg_k         = k_value;
      src_a_addr    = a_address;
      src_b_addr    = b_address;
      dst_addr      = c_address;
      quant_enable  = quant_value;
      relu_enable   = relu_value;
      quant_shift   = shift_value;

      expected_m            = m_value;
      expected_n            = n_value;
      expected_k            = k_value;
      expected_a_addr       = a_address;
      expected_b_addr       = b_address;
      expected_c_addr       = c_address;
      expected_quant_enable = quant_value;
      expected_relu_enable  = relu_value;
      expected_quant_shift  = shift_value;
    end
  endtask

  task automatic pulse_start;
    begin
      @(negedge clk);
      start = 1'b1;
      @(posedge clk);
      #1;
      @(negedge clk);
      start = 1'b0;
    end
  endtask

  task automatic mutate_software_config;
    begin
      cfg_m         = 16'hFF01;
      cfg_n         = 16'hFF02;
      cfg_k         = 16'hFF03;
      src_a_addr    = 32'hFFFF_0000;
      src_b_addr    = 32'hFFFF_1000;
      dst_addr      = 32'hFFFF_2000;
      quant_enable  = ~expected_quant_enable;
      relu_enable   = ~expected_relu_enable;
      quant_shift   = expected_quant_shift + 1'b1;
    end
  endtask

  task automatic pulse_busy_start(input string label);
    begin
      @(negedge clk);
      start = 1'b1;
      @(posedge clk);
      #1;
      checks += 4;
      if (!busy || !error || !interrupt_event) begin
        fail(label, "busy START was not rejected with an error event");
      end
      @(negedge clk);
      start = 1'b0;
    end
  endtask

  task automatic wait_for_terminal(
    input bit expect_failure,
    input ai_accel_pkg::error_code_e expected_error_code,
    input string label
  );
    int unsigned timeout;
    bit terminal_seen;
    begin
      timeout = 0;
      terminal_seen = 1'b0;
      while (!terminal_seen) begin
        @(negedge clk);
        timeout++;
        if (timeout > 2000) begin
          fail(label, "timeout waiting for completion");
        end
        if (done) begin
          checks += 4;
          if (expect_failure || error || busy || !interrupt_event) begin
            fail(label, "unexpected normal completion event");
          end
          terminal_seen = 1'b1;
        end else if (error && !busy) begin
          checks += 4;
          if (!expect_failure || done || !interrupt_event
              || (error_code != expected_error_code)) begin
            fail(label, "unexpected error completion event");
          end
          terminal_seen = 1'b1;
        end else if (!busy) begin
          fail(label, "busy dropped before a terminal event");
        end
      end

      @(posedge clk);
      #1;
      checks += 4;
      if (busy || done || error || interrupt_event
          || (status_state != ai_accel_pkg::ACCEL_IDLE)) begin
        fail(label, "terminal event did not return to IDLE cleanly");
      end
    end
  endtask

  task automatic run_successful_job(
    input logic [DIM_W-1:0] m_value,
    input logic [DIM_W-1:0] n_value,
    input logic [DIM_W-1:0] k_value,
    input bit mutate_config,
    input bit retry_while_busy,
    input string label
  );
    begin
      fail_dma_command       = 0;
      fail_compute_command   = 1'b0;
      dma_command_count      = 0;
      compute_command_count  = 0;
      set_job(m_value, n_value, k_value,
              32'h0000_1000, 32'h0000_4000, 32'h0000_8000,
              m_value[0], n_value[0], k_value[4:0]);
      pulse_start();
      checks += 2;
      if (!busy || (status_state != ai_accel_pkg::ACCEL_LOAD)) begin
        fail(label, "valid START was not accepted");
      end
      if (mutate_config) begin
        mutate_software_config();
      end
      if (retry_while_busy) begin
        pulse_busy_start(label);
      end
      wait_for_terminal(1'b0, ai_accel_pkg::ERR_NONE, label);
      checks += 2;
      if ((dma_command_count != 3) || (compute_command_count != 1)) begin
        fail(label, "incorrect subsystem command count");
      end
    end
  endtask

  task automatic run_failure_job(
    input int dma_failure_index,
    input bit compute_failure,
    input ai_accel_pkg::error_code_e expected_code,
    input int unsigned expected_dma_count,
    input int unsigned expected_compute_count,
    input string label
  );
    begin
      fail_dma_command      = dma_failure_index;
      fail_compute_command  = compute_failure;
      dma_command_count     = 0;
      compute_command_count = 0;
      set_job(7, 6, 5, 32'h0000_1100, 32'h0000_2200,
              32'h0000_3300, 1'b0, 1'b1, 5'd3);
      pulse_start();
      wait_for_terminal(1'b1, expected_code, label);
      checks += 2;
      if ((dma_command_count != expected_dma_count)
          || (compute_command_count != expected_compute_count)) begin
        fail(label, "work continued after the failing subsystem");
      end
    end
  endtask

  task automatic test_invalid_config;
    begin
      fail_dma_command      = 0;
      fail_compute_command  = 1'b0;
      dma_command_count     = 0;
      compute_command_count = 0;
      set_job(0, 4, 2, 32'h1000, 32'h2000, 32'h3000,
              1'b0, 1'b0, 5'd0);
      pulse_start();
      checks += 5;
      if (!error || busy || done || !interrupt_event
          || (error_code != ai_accel_pkg::ERR_INVALID_DIM)) begin
        fail("invalid dimensions", "invalid job was not rejected");
      end
      @(posedge clk);
      #1;

      set_job(4, 4, 2, 32'h1002, 32'h2000, 32'h3000,
              1'b0, 1'b0, 5'd0);
      pulse_start();
      checks += 5;
      if (!error || busy || done
          || (error_code != ai_accel_pkg::ERR_ADDR_ALIGN)) begin
        fail("unaligned address", "unaligned job was not rejected");
      end
      @(posedge clk);
      #1;
      if ((dma_command_count != 0) || (compute_command_count != 0)) begin
        fail("invalid config", "invalid job reached a subsystem");
      end
    end
  endtask

  task automatic test_reset_during_job;
    begin
      fail_dma_command      = 0;
      fail_compute_command  = 1'b0;
      dma_command_count     = 0;
      compute_command_count = 0;
      set_job(12, 9, 7, 32'h1000, 32'h2000, 32'h3000,
              1'b1, 1'b1, 5'd4);
      pulse_start();
      while (dma_command_count == 0) begin
        @(negedge clk);
      end
      @(negedge clk);
      rst_n = 1'b0;
      #1;
      checks += 6;
      if (busy || done || error || interrupt_event || dma_start
          || compute_start) begin
        fail("reset during job", "controller did not abort immediately");
      end
      @(negedge clk);
      rst_n = 1'b1;
    end
  endtask

  initial begin
    clk                    = 1'b0;
    rst_n                  = 1'b1;
    start                  = 1'b0;
    cfg_m                  = '0;
    cfg_n                  = '0;
    cfg_k                  = '0;
    src_a_addr             = '0;
    src_b_addr             = '0;
    dst_addr               = '0;
    quant_enable           = 1'b0;
    relu_enable            = 1'b0;
    quant_shift            = '0;
    dma_busy               = 1'b0;
    dma_done               = 1'b0;
    dma_error              = 1'b0;
    compute_busy           = 1'b0;
    compute_done           = 1'b0;
    compute_error          = 1'b0;
    output_writer_busy     = 1'b0;
    fail_dma_command       = 0;
    fail_compute_command   = 1'b0;
    dma_command_count      = 0;
    compute_command_count  = 0;
    error_event_count      = 0;
    checks                 = 0;

    #1;
    rst_n = 1'b0;
    #1;
    if (busy || done || error || interrupt_event || dma_start
        || compute_start) begin
      fail("reset", "outputs did not reset");
    end
    @(negedge clk);
    rst_n = 1'b1;

    test_invalid_config();
    run_successful_job(1, 1, 1, 1'b0, 1'b0, "1x1x1 job");
    run_successful_job(4, 4, 4, 1'b1, 1'b1,
                       "latched config and busy retrigger");
    for (int unsigned job = 0; job < 8; job++) begin
      run_successful_job(DIM_W'($urandom_range(1, 17)),
                         DIM_W'($urandom_range(1, 17)),
                         DIM_W'($urandom_range(1, 23)),
                         (job[0] == 1'b0), 1'b0,
                         "random successful job");
    end

    run_failure_job(1, 1'b0, ai_accel_pkg::ERR_DMA_READ,
                    1, 0, "LOAD_A error");
    run_failure_job(2, 1'b0, ai_accel_pkg::ERR_DMA_READ,
                    2, 0, "LOAD_B error");
    run_failure_job(0, 1'b1, ai_accel_pkg::ERR_INTERNAL,
                    2, 1, "compute error");
    run_failure_job(3, 1'b0, ai_accel_pkg::ERR_DMA_WRITE,
                    3, 1, "STORE_OUTPUT error");

    test_reset_during_job();
    run_successful_job(9, 5, 3, 1'b0, 1'b0, "post-reset recovery");

    checks += 2;
    if (error_event_count < 7) begin
      fail("error coverage", "expected error events were not observed");
    end

    $display("tb_accel_controller PASS (%0d self-checks, %0d error events)",
             checks, error_event_count);
    $finish;
  end

endmodule
