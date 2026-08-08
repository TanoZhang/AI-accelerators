// Reads one A column vector and one B row vector for each k in a tile.
// The two scratchpad ports have registered, one-cycle read responses.
module operand_feeder #(
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

  output logic                                      activation_read_en,
  output logic [SPAD_ADDR_W-1:0]                    activation_read_addr,
  input  logic                                      activation_read_valid,
  input  logic signed [DATA_W-1:0]                  activation_read_data,

  output logic                                      weight_read_en,
  output logic [SPAD_ADDR_W-1:0]                    weight_read_addr,
  input  logic                                      weight_read_valid,
  input  logic signed [DATA_W-1:0]                  weight_read_data,

  output logic                                      compute_valid,
  input  logic                                      compute_ready,
  output logic signed [DATA_W-1:0]                  a_vec [0:ARRAY_DIM-1],
  output logic signed [DATA_W-1:0]                  b_vec [0:ARRAY_DIM-1],
  output logic [ARRAY_DIM-1:0]                      row_mask,
  output logic [ARRAY_DIM-1:0]                      col_mask,
  output logic                                      last_k
);

  localparam int unsigned LANE_W = (ARRAY_DIM > 1) ? $clog2(ARRAY_DIM) : 1;
  localparam int unsigned CALC_W = (2 * DIM_W) + 1;

  typedef enum logic [1:0] {
    FEED_IDLE,
    FEED_ISSUE,
    FEED_WAIT,
    FEED_OUTPUT
  } feeder_state_e;

  feeder_state_e state_q;

  logic [DIM_W-1:0] m_q;
  logic [DIM_W-1:0] n_q;
  logic [DIM_W-1:0] k_q;
  logic [DIM_W-1:0] tile_row_q;
  logic [DIM_W-1:0] tile_col_q;
  logic [DIM_W-1:0] k_index_q;
  logic [LANE_W-1:0] lane_q;

  logic signed [DATA_W-1:0] a_buf_q [0:ARRAY_DIM-1];
  logic signed [DATA_W-1:0] b_buf_q [0:ARRAY_DIM-1];
  logic [ARRAY_DIM-1:0] row_mask_q;
  logic [ARRAY_DIM-1:0] col_mask_q;
  logic activation_received_q;
  logic weight_received_q;

  logic [DIM_W:0] row_index_full;
  logic [DIM_W:0] col_index_full;
  logic [DIM_W:0] lane_ext;
  logic [CALC_W-1:0] activation_addr_full;
  logic [CALC_W-1:0] weight_addr_full;
  logic current_row_valid;
  logic current_col_valid;
  logic activation_operand_ready;
  logic weight_operand_ready;
  logic start_config_valid;

  always_comb begin
    lane_ext       = (DIM_W + 1)'(lane_q);
    row_index_full = {1'b0, tile_row_q} + lane_ext;
    col_index_full = {1'b0, tile_col_q} + lane_ext;

    activation_addr_full = (CALC_W'(row_index_full) * CALC_W'(k_q))
                         + CALC_W'(k_index_q);
    weight_addr_full     = (CALC_W'(k_index_q) * CALC_W'(n_q))
                         + CALC_W'(col_index_full);

    current_row_valid = row_index_full < {1'b0, m_q};
    current_col_valid = col_index_full < {1'b0, n_q};

    activation_read_en   = (state_q == FEED_ISSUE) && current_row_valid;
    activation_read_addr = activation_addr_full[SPAD_ADDR_W-1:0];
    weight_read_en       = (state_q == FEED_ISSUE) && current_col_valid;
    weight_read_addr     = weight_addr_full[SPAD_ADDR_W-1:0];

    activation_operand_ready = activation_received_q
                             || activation_read_valid;
    weight_operand_ready = weight_received_q || weight_read_valid;

    start_config_valid = (m_dim != '0) && (n_dim != '0) && (k_dim != '0)
                      && (tile_row < m_dim) && (tile_col < n_dim);

    compute_valid = (state_q == FEED_OUTPUT);
    last_k        = (k_index_q == (k_q - 1'b1));
    row_mask      = row_mask_q;
    col_mask      = col_mask_q;

    for (int unsigned lane = 0; lane < ARRAY_DIM; lane++) begin
      a_vec[lane] = a_buf_q[lane];
      b_vec[lane] = b_buf_q[lane];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q               <= FEED_IDLE;
      m_q                   <= '0;
      n_q                   <= '0;
      k_q                   <= '0;
      tile_row_q            <= '0;
      tile_col_q            <= '0;
      k_index_q             <= '0;
      lane_q                <= '0;
      row_mask_q            <= '0;
      col_mask_q            <= '0;
      activation_received_q <= 1'b0;
      weight_received_q     <= 1'b0;
      busy                  <= 1'b0;
      done_pulse            <= 1'b0;
      for (int unsigned lane = 0; lane < ARRAY_DIM; lane++) begin
        a_buf_q[lane] <= '0;
        b_buf_q[lane] <= '0;
      end
    end else begin
      done_pulse <= 1'b0;

      case (state_q)
        FEED_IDLE: begin
          if (start_pulse && start_config_valid) begin
            m_q        <= m_dim;
            n_q        <= n_dim;
            k_q        <= k_dim;
            tile_row_q <= tile_row;
            tile_col_q <= tile_col;
            k_index_q  <= '0;
            lane_q     <= '0;
            busy       <= 1'b1;
            state_q    <= FEED_ISSUE;

            for (int unsigned lane = 0; lane < ARRAY_DIM; lane++) begin
              row_mask_q[lane] <= ((DIM_W + 1)'(tile_row) + (DIM_W + 1)'(lane))
                                < (DIM_W + 1)'(m_dim);
              col_mask_q[lane] <= ((DIM_W + 1)'(tile_col) + (DIM_W + 1)'(lane))
                                < (DIM_W + 1)'(n_dim);
              a_buf_q[lane]    <= '0;
              b_buf_q[lane]    <= '0;
            end
          end
        end

        FEED_ISSUE: begin
          activation_received_q <= !current_row_valid;
          weight_received_q     <= !current_col_valid;
          if (!current_row_valid) begin
            a_buf_q[lane_q] <= '0;
          end
          if (!current_col_valid) begin
            b_buf_q[lane_q] <= '0;
          end
          state_q <= FEED_WAIT;
        end

        FEED_WAIT: begin
          if (activation_read_valid) begin
            a_buf_q[lane_q]         <= $signed(activation_read_data);
            activation_received_q   <= 1'b1;
          end
          if (weight_read_valid) begin
            b_buf_q[lane_q]       <= $signed(weight_read_data);
            weight_received_q     <= 1'b1;
          end

          if (activation_operand_ready && weight_operand_ready) begin
            if (lane_q == ARRAY_DIM-1) begin
              state_q <= FEED_OUTPUT;
            end else begin
              lane_q  <= lane_q + 1'b1;
              state_q <= FEED_ISSUE;
            end
          end
        end

        FEED_OUTPUT: begin
          if (compute_ready) begin
            if (last_k) begin
              busy       <= 1'b0;
              done_pulse <= 1'b1;
              state_q    <= FEED_IDLE;
            end else begin
              k_index_q <= k_index_q + 1'b1;
              lane_q    <= '0;
              state_q   <= FEED_ISSUE;
            end
          end
        end

        default: begin
          state_q <= FEED_IDLE;
          busy    <= 1'b0;
        end
      endcase
    end
  end

`ifndef SYNTHESIS
  property p_valid_start;
    @(posedge clk) disable iff (!rst_n)
      start_pulse |-> ((state_q == FEED_IDLE) && start_config_valid);
  endproperty

  property p_activation_address;
    @(posedge clk) disable iff (!rst_n)
      activation_read_en |-> (current_row_valid && (k_index_q < k_q)
                           && (activation_addr_full < SPAD_DEPTH));
  endproperty

  property p_weight_address;
    @(posedge clk) disable iff (!rst_n)
      weight_read_en |-> (current_col_valid && (k_index_q < k_q)
                       && (weight_addr_full < SPAD_DEPTH));
  endproperty

  property p_control_stable_when_stalled;
    @(posedge clk) disable iff (!rst_n)
      (compute_valid && !compute_ready)
      |=> (compute_valid && $stable(row_mask) && $stable(col_mask)
                        && $stable(last_k));
  endproperty

  assert property (p_valid_start)
    else $error("operand_feeder received an invalid start");

  assert property (p_activation_address)
    else $error("operand_feeder activation address is out of range");

  assert property (p_weight_address)
    else $error("operand_feeder weight address is out of range");

  assert property (p_control_stable_when_stalled)
    else $error("operand_feeder control changed while stalled");

  for (genvar lane = 0; lane < ARRAY_DIM; lane++) begin : gen_stall_assertions
    property p_operand_stable_when_stalled;
      @(posedge clk) disable iff (!rst_n)
        (compute_valid && !compute_ready)
        |=> ($stable(a_vec[lane]) && $stable(b_vec[lane]));
    endproperty

    assert property (p_operand_stable_when_stalled)
      else $error("operand_feeder lane %0d changed while stalled", lane);
  end
`endif

endmodule
