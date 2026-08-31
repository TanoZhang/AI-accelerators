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

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      accumulator <= '0;
    end else begin
      // TODO: add clear and signed multiply-accumulate behavior.
      // Hint: form a 2*DATA_W product, then sign-extend it to ACC_W.
      accumulator <= accumulator;
    end
  end

endmodule
