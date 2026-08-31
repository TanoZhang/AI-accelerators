module parallel_operand_feeder #(
  parameter int unsigned DATA_W       = 8,
  parameter int unsigned DIM_W        = 16,
  parameter int unsigned ARRAY_DIM    = 4,
  parameter int unsigned SPAD_DEPTH   = 1024,
  parameter int unsigned SPAD_ADDR_W  = (SPAD_DEPTH > 1) ? $clog2(SPAD_DEPTH) : 1
) (
  input  logic                                      clk,
  input  logic                                      rst_n,
  input  logic                                      start_pulse,
  input  logic [DIM_W-1:0]                          m_dim,
  input  logic [DIM_W-1:0]                          n_dim,
  input  logic [DIM_W-1:0]                          k_dim,
  input  logic [DIM_W-1:0]                          tile_row,
  input  logic [DIM_W-1:0]                          tile_col,
  output logic                                      busy,
  output logic                                      done_pulse,
  output logic [ARRAY_DIM-1:0]                      activation_read_en,
  output logic [SPAD_ADDR_W-1:0]                    activation_read_addr
                                                        [0:ARRAY_DIM-1],
  input  logic [ARRAY_DIM-1:0]                      activation_read_valid,
  input  logic [DATA_W-1:0]                         activation_read_data
                                                        [0:ARRAY_DIM-1],
  output logic [ARRAY_DIM-1:0]                      weight_read_en,
  output logic [SPAD_ADDR_W-1:0]                    weight_read_addr
                                                        [0:ARRAY_DIM-1],
  input  logic [ARRAY_DIM-1:0]                      weight_read_valid,
  input  logic [DATA_W-1:0]                         weight_read_data
                                                        [0:ARRAY_DIM-1],
  output logic                                      compute_valid,
  input  logic                                      compute_ready,
  output logic signed [DATA_W-1:0]                  a_vec [0:ARRAY_DIM-1],
  output logic signed [DATA_W-1:0]                  b_vec [0:ARRAY_DIM-1],
  output logic [ARRAY_DIM-1:0]                      row_mask,
  output logic [ARRAY_DIM-1:0]                      col_mask,
  output logic                                      last_k
);

  // TODO: issue one A and one B read per active lane, capture the registered
  // responses, and feed them through a two-entry ready/valid FIFO.
  //
  // Address equations:
  //   A[(tile_row + lane) * K + k]
  //   B[k * N + tile_col + lane]
  //
  // Keep the output stable while compute_valid && !compute_ready.
  always_comb begin
    busy               = 1'b0;
    done_pulse         = 1'b0;
    activation_read_en = '0;
    weight_read_en     = '0;
    compute_valid      = 1'b0;
    row_mask           = '0;
    col_mask           = '0;
    last_k             = 1'b0;
    for (int unsigned lane = 0; lane < ARRAY_DIM; lane++) begin
      activation_read_addr[lane] = '0;
      weight_read_addr[lane]     = '0;
      a_vec[lane]                = '0;
      b_vec[lane]                = '0;
    end
  end

endmodule
