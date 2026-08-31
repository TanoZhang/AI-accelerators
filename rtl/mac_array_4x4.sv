module mac_array_4x4 #(
  parameter int unsigned DATA_W    = 8,
  parameter int unsigned ACC_W     = 32,
  parameter int unsigned ARRAY_DIM = 4
) (
  input  logic                                      clk,
  input  logic                                      rst_n,
  input  logic                                      clear_acc,
  input  logic                                      mac_en,
  input  logic signed [DATA_W-1:0]                  a_vec [0:ARRAY_DIM-1],
  input  logic signed [DATA_W-1:0]                  b_vec [0:ARRAY_DIM-1],
  output logic signed [ACC_W-1:0]                   acc   [0:ARRAY_DIM-1]
                                                            [0:ARRAY_DIM-1]
);

  for (genvar row = 0; row < ARRAY_DIM; row++) begin : gen_row
    for (genvar col = 0; col < ARRAY_DIM; col++) begin : gen_col
      mac_pe #(
        .DATA_W (DATA_W),
        .ACC_W  (ACC_W)
      ) u_mac_pe (
        .clk         (clk),
        .rst_n       (rst_n),
        .clear_acc   (clear_acc),
        .mac_en      (mac_en),
        .activation  (a_vec[row]),
        .weight      (b_vec[col]),
        .accumulator (acc[row][col])
      );

`ifndef SYNTHESIS
      property p_array_clear;
        @(posedge clk) disable iff (!rst_n)
          clear_acc |=> (acc[row][col] == '0);
      endproperty

      property p_array_stable_when_disabled;
        @(posedge clk) disable iff (!rst_n)
          (!clear_acc && !mac_en) |=> $stable(acc[row][col]);
      endproperty

      assert property (p_array_clear)
        else $error("mac_array_4x4 PE[%0d][%0d] did not clear", row, col);

      assert property (p_array_stable_when_disabled)
        else $error("mac_array_4x4 PE[%0d][%0d] changed while disabled",
                    row, col);
`endif
    end
  end

endmodule
