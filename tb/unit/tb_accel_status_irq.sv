`timescale 1ns/1ps

module tb_accel_status_irq;

  logic clk;
  logic rst_n;
  logic done_event;
  logic dma_error_event;
  logic compute_config_error_event;
  logic [1:0] int_enable;
  logic [1:0] w1c_clear;
  logic done_status;
  logic error_status;
  logic [1:0] int_status;
  logic irq;

  int unsigned checks;

  accel_status_irq dut (
    .clk                        (clk),
    .rst_n                      (rst_n),
    .done_event                 (done_event),
    .dma_error_event            (dma_error_event),
    .compute_config_error_event (compute_config_error_event),
    .int_enable                 (int_enable),
    .w1c_clear                  (w1c_clear),
    .done_status                (done_status),
    .error_status               (error_status),
    .int_status                 (int_status),
    .irq                        (irq)
  );

  always #5 clk = ~clk;

  task automatic fail(input string label, input string detail);
    begin
      $error("%s: %s", label, detail);
      $fatal(1, "tb_accel_status_irq failed");
    end
  endtask

  task automatic check_state(
    input logic [1:0] expected_status,
    input logic       expected_irq,
    input string      label
  );
    begin
      checks += 4;
      if ((int_status !== expected_status)
          || (done_status !== expected_status[0])
          || (error_status !== expected_status[1])
          || (irq !== expected_irq)) begin
        fail(label, "status or IRQ mismatch");
      end
    end
  endtask

  task automatic apply_cycle(
    input logic       next_done,
    input logic       next_dma_error,
    input logic       next_compute_error,
    input logic [1:0] next_clear
  );
    begin
      @(negedge clk);
      done_event                = next_done;
      dma_error_event           = next_dma_error;
      compute_config_error_event = next_compute_error;
      w1c_clear                 = next_clear;
      @(posedge clk);
      #1;
      @(negedge clk);
      done_event                 = 1'b0;
      dma_error_event            = 1'b0;
      compute_config_error_event = 1'b0;
      w1c_clear                  = 2'b00;
    end
  endtask

  initial begin
    clk                        = 1'b0;
    rst_n                      = 1'b1;
    done_event                 = 1'b0;
    dma_error_event            = 1'b0;
    compute_config_error_event = 1'b0;
    int_enable                 = 2'b00;
    w1c_clear                  = 2'b00;
    checks                     = 0;

    #1;
    rst_n = 1'b0;
    #1;
    check_state(2'b00, 1'b0, "reset");
    @(negedge clk);
    rst_n = 1'b1;

    apply_cycle(1'b1, 1'b0, 1'b0, 2'b00);
    check_state(2'b01, 1'b0, "masked completion");

    int_enable = 2'b01;
    #1;
    check_state(2'b01, 1'b1, "enabled completion");

    int_enable = 2'b00;
    #1;
    check_state(2'b01, 1'b0, "interrupt mask");

    apply_cycle(1'b0, 1'b0, 1'b0, 2'b01);
    check_state(2'b00, 1'b0, "DONE W1C");

    apply_cycle(1'b0, 1'b1, 1'b0, 2'b00);
    check_state(2'b10, 1'b0, "masked DMA error");

    int_enable = 2'b10;
    #1;
    check_state(2'b10, 1'b1, "enabled DMA error");

    apply_cycle(1'b0, 1'b0, 1'b0, 2'b10);
    check_state(2'b00, 1'b0, "ERROR W1C");

    apply_cycle(1'b0, 1'b0, 1'b1, 2'b00);
    check_state(2'b10, 1'b1, "compute/configuration error");

    apply_cycle(1'b0, 1'b1, 1'b0, 2'b10);
    check_state(2'b10, 1'b1, "error set dominates clear");

    int_enable = 2'b11;
    apply_cycle(1'b1, 1'b0, 1'b1, 2'b10);
    check_state(2'b11, 1'b1, "multiple simultaneous events");

    apply_cycle(1'b1, 1'b0, 1'b0, 2'b11);
    check_state(2'b01, 1'b1, "DONE set dominates dual clear");

    apply_cycle(1'b0, 1'b1, 1'b1, 2'b01);
    check_state(2'b10, 1'b1, "selective clear with multiple errors");

    int_enable = 2'b01;
    #1;
    check_state(2'b10, 1'b0, "error masked by DONE enable");

    int_enable = 2'b10;
    #1;
    check_state(2'b10, 1'b1, "stored error re-enabled");

    rst_n = 1'b0;
    #1;
    check_state(2'b00, 1'b0, "asynchronous reset");

    $display("tb_accel_status_irq PASS (%0d self-checks)", checks);
    $finish;
  end

endmodule
