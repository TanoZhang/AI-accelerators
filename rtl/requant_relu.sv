module requant_relu #(
  parameter int unsigned ARRAY_DIM = 4
) (
  input  logic signed [31:0] in_data  [0:ARRAY_DIM-1][0:ARRAY_DIM-1],
  input  logic               quant_enable,
  input  logic [4:0]         quant_shift,
  input  logic               relu_enable,
  output logic signed [7:0]  out_data [0:ARRAY_DIM-1][0:ARRAY_DIM-1]
);

  always_comb begin
    for (int unsigned row = 0; row < ARRAY_DIM; row++) begin
      for (int unsigned col = 0; col < ARRAY_DIM; col++) begin
        // TODO: ReLU, arithmetic shift, then signed INT8 saturation.
        out_data[row][col] = '0;
      end
    end
  end

endmodule
