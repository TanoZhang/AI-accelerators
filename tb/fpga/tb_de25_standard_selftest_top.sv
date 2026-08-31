`timescale 1ns/1ps

module tb_de25_standard_selftest_top #(
  parameter bit USE_PARALLEL_FEEDER = 1'b1
);

  logic CLOCK_50;
  logic [3:0] KEY;
  logic [9:0] SW;
  logic [9:0] LEDR;
  logic [6:0] HEX0;
  logic [6:0] HEX1;
  logic [6:0] HEX2;
  logic [6:0] HEX3;
  logic [6:0] HEX4;
  logic [6:0] HEX5;
  int unsigned checks;
  int unsigned timeout;

  de25_standard_selftest_top #(
    .USE_PARALLEL_FEEDER (USE_PARALLEL_FEEDER)
  ) dut (.*);

  function automatic logic signed [31:0] expected_result(
    input int unsigned index
  );
    logic signed [31:0] value;
    value = (index / 8 < 4) ? $signed(index / 8) - 4
                            : $signed(index / 8) - 3;
    value = value <<< 3;
    return (index % 8 < 4) ? -value : value;
  endfunction

  always #10 CLOCK_50 = ~CLOCK_50;

  initial begin
    CLOCK_50 = 1'b0;
    KEY      = 4'hF;
    SW       = 10'd0;
    checks   = 0;

    #1;
    KEY[0] = 1'b0;
    repeat (3) @(posedge CLOCK_50);
    KEY[0] = 1'b1;

    timeout = 0;
    // The DE25-Standard LEDs are active-low, so both status LEDs are off
    // while both pins remain high.
    while (LEDR[0] && LEDR[1]) begin
      @(posedge CLOCK_50);
      timeout++;
      if (timeout > 20000) begin
        $fatal(1, "DE25 self-test timed out");
      end
    end

    checks += 3;
    if (LEDR[0] || !LEDR[1]) begin
      $fatal(1, "DE25 self-test reported failure");
    end
    if (dut.cycle_count_q == 0) begin
      $fatal(1, "DE25 self-test did not capture the performance counter");
    end
    if (LEDR[4] !== !USE_PARALLEL_FEEDER) begin
      $fatal(1, "DE25 self-test mode indicator was incorrect");
    end
    for (int unsigned index = 0; index < 64; index++) begin
      checks++;
      if ($signed(dut.u_memory.memory[128 + index]) !== expected_result(index)) begin
        $fatal(1, "DE25 result %0d was incorrect", index);
      end
    end

    $display("tb_de25_standard_selftest_top PASS (%0d self-checks, %0d cycles, parallel=%0d)",
             checks, dut.cycle_count_q, USE_PARALLEL_FEEDER);
    $finish;
  end

endmodule
