`timescale 1ns/1ps

module tb_requant_relu;

  localparam int unsigned ARRAY_DIM   = 4;
  localparam int unsigned RANDOM_RUNS = 2000;

  logic signed [31:0] in_data  [0:ARRAY_DIM-1][0:ARRAY_DIM-1];
  logic               quant_enable;
  logic [4:0]         quant_shift;
  logic               relu_enable;
  logic signed [7:0]  out_data [0:ARRAY_DIM-1][0:ARRAY_DIM-1];
  int unsigned        checks;

  requant_relu #(
    .ARRAY_DIM (ARRAY_DIM)
  ) dut (
    .in_data      (in_data),
    .quant_enable (quant_enable),
    .quant_shift  (quant_shift),
    .relu_enable  (relu_enable),
    .out_data     (out_data)
  );

  function automatic logic signed [7:0] reference_convert(
    input logic signed [31:0] value,
    input logic               quant_en,
    input logic [4:0]         shift,
    input logic               relu_en
  );
    logic signed [31:0] relu_value;
    logic signed [31:0] shifted_value;
    begin
      if (relu_en && (value < 0)) begin
        relu_value = 0;
      end else begin
        relu_value = value;
      end

      shifted_value = quant_en ? (relu_value >>> shift) : relu_value;

      if (shifted_value > 127) begin
        reference_convert = 127;
      end else if (shifted_value < -128) begin
        reference_convert = -128;
      end else begin
        reference_convert = $signed(shifted_value[7:0]);
      end
    end
  endfunction

  task automatic check_all(input string label);
    logic signed [7:0] expected;
    begin
      #1;
      for (int unsigned row = 0; row < ARRAY_DIM; row++) begin
        for (int unsigned col = 0; col < ARRAY_DIM; col++) begin
          expected = reference_convert(
            in_data[row][col], quant_enable, quant_shift, relu_enable
          );
          checks++;
          if (out_data[row][col] !== expected) begin
            $error("%s: out_data[%0d][%0d]=%0d expected=%0d input=%0d shift=%0d quant=%0b relu=%0b",
                   label, row, col, out_data[row][col], expected,
                   in_data[row][col], quant_shift, quant_enable, relu_enable);
            $fatal(1, "tb_requant_relu failed");
          end
        end
      end
    end
  endtask

  task automatic load_directed_values;
    begin
      in_data[0][0] = 32'sh8000_0000;
      in_data[0][1] = -32'sd100000;
      in_data[0][2] = -32'sd129;
      in_data[0][3] = -32'sd128;
      in_data[1][0] = -32'sd127;
      in_data[1][1] = -32'sd1;
      in_data[1][2] = 32'sd0;
      in_data[1][3] = 32'sd1;
      in_data[2][0] = 32'sd2;
      in_data[2][1] = 32'sd126;
      in_data[2][2] = 32'sd127;
      in_data[2][3] = 32'sd128;
      in_data[3][0] = 32'sd129;
      in_data[3][1] = 32'sd100000;
      in_data[3][2] = 32'sh7fff_ffff;
      in_data[3][3] = -32'sd2;
    end
  endtask

  initial begin
    int unsigned directed_shifts [0:7];

    checks       = 0;
    quant_enable = 1'b0;
    quant_shift  = '0;
    relu_enable  = 1'b0;

    directed_shifts[0] = 0;
    directed_shifts[1] = 1;
    directed_shifts[2] = 2;
    directed_shifts[3] = 7;
    directed_shifts[4] = 8;
    directed_shifts[5] = 15;
    directed_shifts[6] = 30;
    directed_shifts[7] = 31;

    load_directed_values();
    for (int unsigned quant = 0; quant < 2; quant++) begin
      for (int unsigned relu = 0; relu < 2; relu++) begin
        for (int unsigned shift_index = 0; shift_index < 8; shift_index++) begin
          quant_enable = quant[0];
          relu_enable  = relu[0];
          quant_shift  = directed_shifts[shift_index][4:0];
          check_all($sformatf("directed quant=%0d relu=%0d shift=%0d",
                              quant, relu, quant_shift));
        end
      end
    end

    for (int unsigned run = 0; run < RANDOM_RUNS; run++) begin
      quant_enable = ($urandom_range(0, 1) != 0);
      relu_enable  = ($urandom_range(0, 1) != 0);
      quant_shift  = 5'($urandom_range(0, 31));
      for (int unsigned row = 0; row < ARRAY_DIM; row++) begin
        for (int unsigned col = 0; col < ARRAY_DIM; col++) begin
          in_data[row][col] = $signed($urandom);
        end
      end
      check_all($sformatf("random run %0d", run));
    end

    $display("tb_requant_relu PASS (%0d self-checks)", checks);
    $finish;
  end

endmodule
