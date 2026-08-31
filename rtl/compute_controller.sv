module compute_controller #(
  parameter int unsigned DIM_W     = 16,
  parameter int unsigned ACC_W     = 32,
  parameter int unsigned ARRAY_DIM = 4
) (
  input  logic                                      clk,
  input  logic                                      rst_n,
  input  logic                                      start,
  input  logic [DIM_W-1:0]                          m_dim,
  input  logic [DIM_W-1:0]                          n_dim,
  input  logic [DIM_W-1:0]                          k_dim,
  output logic                                      start_ready,
  output logic                                      busy,
  output logic                                      done,
  output logic                                      error,
  output logic                                      feeder_start_pulse,
  output logic [DIM_W-1:0]                          active_m,
  output logic [DIM_W-1:0]                          active_n,
  output logic [DIM_W-1:0]                          active_k,
  output logic [DIM_W-1:0]                          tile_row,
  output logic [DIM_W-1:0]                          tile_col,
  output logic [DIM_W-1:0]                          k_index,
  input  logic                                      operand_valid,
  output logic                                      operand_ready,
  output logic                                      clear_acc,
  output logic                                      mac_en,
  input  logic signed [ACC_W-1:0]                   mac_acc [0:ARRAY_DIM-1]
                                                                  [0:ARRAY_DIM-1],
  output logic                                      output_valid,
  input  logic                                      output_ready,
  output logic signed [ACC_W-1:0]                   output_data [0:ARRAY_DIM-1]
                                                                      [0:ARRAY_DIM-1],
  output logic [ARRAY_DIM-1:0]                      row_mask,
  output logic [ARRAY_DIM-1:0]                      col_mask
);

  // TODO: implement the tile controller described in HOMEWORK.md.
  // The final MAC result is visible one clock after its input handshake.
  always_comb begin
    start_ready        = 1'b1;
    busy               = 1'b0;
    done               = 1'b0;
    error              = 1'b0;
    feeder_start_pulse = 1'b0;
    active_m           = '0;
    active_n           = '0;
    active_k           = '0;
    tile_row           = '0;
    tile_col           = '0;
    k_index            = '0;
    operand_ready      = 1'b0;
    clear_acc          = 1'b0;
    mac_en             = 1'b0;
    output_valid       = 1'b0;
    row_mask           = '0;
    col_mask           = '0;
    for (int unsigned row = 0; row < ARRAY_DIM; row++) begin
      for (int unsigned col = 0; col < ARRAY_DIM; col++) begin
        output_data[row][col] = '0;
      end
    end
  end

endmodule
