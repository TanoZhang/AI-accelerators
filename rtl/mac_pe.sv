module mac_pe #(
  parameter int unsigned DATA_W = ai_accel_pkg::DATA_W,
  parameter int unsigned ACC_W  = ai_accel_pkg::ACC_W
) (
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic                         clear_acc,
  input  logic                         mac_en,
  input  logic signed [DATA_W-1:0]     activation,
  input  logic signed [DATA_W-1:0]     weight,
  output logic signed [ACC_W-1:0]      accumulator
);

  localparam int unsigned PRODUCT_W = 2 * DATA_W;

  logic signed [PRODUCT_W-1:0] product;
  logic signed [ACC_W-1:0]     product_ext;

  assign product     = $signed(activation) * $signed(weight);
  // Widen before accumulation to preserve the product sign.
  assign product_ext = ACC_W'($signed(product));

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      accumulator <= '0;
    end else if (clear_acc) begin
      accumulator <= '0;
    end else if (mac_en) begin
      accumulator <= $signed(accumulator) + $signed(product_ext);
    end
  end

`ifndef SYNTHESIS
  property p_accumulator_stable_when_disabled;
    @(posedge clk) disable iff (!rst_n)
      (!clear_acc && !mac_en) |=> $stable(accumulator);
  endproperty

  property p_clear_accumulator;
    @(posedge clk) disable iff (!rst_n)
      clear_acc |=> (accumulator == '0);
  endproperty

  property p_reset_accumulator;
    @(posedge clk)
      (!rst_n) |-> (accumulator == '0);
  endproperty

  assert property (p_accumulator_stable_when_disabled)
    else $error("mac_pe accumulator changed while disabled");

  assert property (p_clear_accumulator)
    else $error("mac_pe accumulator did not clear");

  assert property (p_reset_accumulator)
    else $error("mac_pe accumulator is nonzero during reset");
`endif

endmodule
