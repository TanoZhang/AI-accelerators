module requant_relu #(
  parameter int unsigned ARRAY_DIM = 4
) (
  input  logic signed [31:0] in_data  [0:ARRAY_DIM-1][0:ARRAY_DIM-1],
  input  logic               quant_enable,
  input  logic [4:0]         quant_shift,
  input  logic               relu_enable,
  output logic signed [7:0]  out_data [0:ARRAY_DIM-1][0:ARRAY_DIM-1]
);

  function automatic logic signed [7:0] convert_value(
    input logic signed [31:0] value,
    input logic               quant_en,
    input logic [4:0]         shift,
    input logic               relu_en
  );
    logic signed [31:0] relu_value;
    logic signed [31:0] shifted_value;
    begin
      relu_value = value;
      if (relu_en && (value < 32'sd0)) begin
        relu_value = 32'sd0;
      end

      if (quant_en) begin
        shifted_value = relu_value >>> shift;
      end else begin
        shifted_value = relu_value;
      end

      if (shifted_value > 32'sd127) begin
        convert_value = 8'sd127;
      end else if (shifted_value < -32'sd128) begin
        convert_value = 8'sh80;
      end else begin
        convert_value = $signed(shifted_value[7:0]);
      end
    end
  endfunction

  always_comb begin
    for (int unsigned row = 0; row < ARRAY_DIM; row++) begin
      for (int unsigned col = 0; col < ARRAY_DIM; col++) begin
        out_data[row][col] = convert_value(
          in_data[row][col], quant_enable, quant_shift, relu_enable
        );
      end
    end
  end

endmodule
