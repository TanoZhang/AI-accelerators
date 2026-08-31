`timescale 1ns/1ps

module tb_mac_pe;

  logic                         clk;
  logic                         rst_n;
  logic                         clear_acc;
  logic                         mac_en;
  ai_accel_pkg::int8_t          activation;
  ai_accel_pkg::int8_t          weight;
  ai_accel_pkg::int32_t         accumulator;

  logic signed [31:0]           reference_acc;
  int unsigned                  checks;

  mac_pe dut (
    .clk         (clk),
    .rst_n       (rst_n),
    .clear_acc   (clear_acc),
    .mac_en      (mac_en),
    .activation  (activation),
    .weight      (weight),
    .accumulator (accumulator)
  );

  always #5 clk = ~clk;

  task automatic check_accumulator(input string label);
    begin
      checks++;
      if (accumulator !== reference_acc) begin
        $error("%s: accumulator=%0d (0x%08h), expected=%0d (0x%08h)",
               label, accumulator, accumulator, reference_acc, reference_acc);
        $fatal(1, "tb_mac_pe failed");
      end
    end
  endtask

  task automatic apply_mac(
    input logic signed [7:0] activation_value,
    input logic signed [7:0] weight_value,
    input string             label
  );
    int signed reference_product;
    begin
      @(negedge clk);
      clear_acc  = 1'b0;
      mac_en     = 1'b1;
      activation = activation_value;
      weight     = weight_value;

      reference_product = $signed(activation_value) * $signed(weight_value);
      @(posedge clk);
      reference_acc = reference_acc + reference_product;
      #1;
      check_accumulator(label);
    end
  endtask

  task automatic apply_clear(input string label);
    begin
      @(negedge clk);
      // Check clear priority.
      clear_acc  = 1'b1;
      mac_en     = 1'b1;
      activation = 8'sd127;
      weight     = 8'sd127;
      @(posedge clk);
      reference_acc = 32'sd0;
      #1;
      check_accumulator(label);

      @(negedge clk);
      clear_acc = 1'b0;
      mac_en    = 1'b0;
    end
  endtask

  task automatic check_hold(input int unsigned cycles);
    int unsigned cycle;
    begin
      @(negedge clk);
      clear_acc  = 1'b0;
      mac_en     = 1'b0;
      // Operands may change while disabled.
      activation = 8'sh80;
      weight     = 8'sd127;
      for (cycle = 0; cycle < cycles; cycle++) begin
        @(posedge clk);
        #1;
        check_accumulator("mac_en hold behavior");
      end
    end
  endtask

  initial begin
    clk           = 1'b0;
    rst_n         = 1'b1;
    clear_acc     = 1'b0;
    mac_en        = 1'b0;
    activation    = '0;
    weight        = '0;
    reference_acc = 32'sd0;
    checks        = 0;

    // Initial reset
    #1;
    rst_n = 1'b0;
    #1;
    check_accumulator("initial reset");
    @(negedge clk);
    rst_n = 1'b1;

    apply_mac( 8'sd12,    8'sd7,   "positive x positive");
    apply_mac( 8'sd9,    -8'sd5,   "positive x negative");
    apply_mac(-8'sd11,    8'sd6,   "negative x positive");
    apply_mac(-8'sd13,   -8'sd4,   "negative x negative");

    apply_clear("clear priority over mac_en");
    apply_mac(8'sh80,   8'sd1,   "-128 activation edge");
    apply_mac(8'sd1,    8'sh80,  "-128 weight edge");
    apply_mac(8'sh80,   8'sh80,  "-128 x -128 edge");
    apply_mac( 8'sd127,   8'sd127, "127 x 127 edge");

    // Repeated accumulation
    apply_clear("clear before repeated accumulation");
    apply_mac(8'sd7, -8'sd6, "repeated accumulation 1");
    apply_mac(8'sd7, -8'sd6, "repeated accumulation 2");
    apply_mac(8'sd7, -8'sd6, "repeated accumulation 3");
    apply_mac(8'sd7, -8'sd6, "repeated accumulation 4");
    check_hold(3);

    // Reset between clock edges with mac_en still high.
    @(negedge clk);
    mac_en     = 1'b1;
    activation = 8'sd9;
    weight     = 8'sd9;
    @(posedge clk);
    reference_acc = reference_acc + 32'sd81;
    #1;
    check_accumulator("precondition before reset during operation");
    #2;
    rst_n         = 1'b0;
    reference_acc = 32'sd0;
    #1;
    check_accumulator("asynchronous reset during operation");
    @(posedge clk);
    #1;
    check_accumulator("reset hold during operation");

    @(negedge clk);
    rst_n     = 1'b1;
    mac_en    = 1'b0;
    clear_acc = 1'b0;
    @(posedge clk);
    #1;
    check_accumulator("post-reset hold");

    $display("tb_mac_pe PASS (%0d self-checks)", checks);
    $finish;
  end

endmodule
