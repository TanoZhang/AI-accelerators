// Sequences 4x4 output tiles. The feeder owns operand reads within each tile.
// CAPTURE separates the final MAC edge from the output register write.
// Flow: IDLE, CLEAR, START_FEEDER, COMPUTE, CAPTURE, STORE, NEXT_TILE, DONE.
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

  typedef enum logic [2:0] {
    CTRL_IDLE,
    CTRL_CLEAR,
    CTRL_START_FEEDER,
    CTRL_COMPUTE,
    CTRL_CAPTURE,
    CTRL_STORE,
    CTRL_NEXT_TILE,
    CTRL_DONE
  } controller_state_e;

  controller_state_e state_q;

  logic [DIM_W-1:0] m_q;
  logic [DIM_W-1:0] n_q;
  logic [DIM_W-1:0] k_q;
  logic [DIM_W-1:0] tile_row_q;
  logic [DIM_W-1:0] tile_col_q;
  logic [DIM_W:0]   mac_count_q;
  logic signed [ACC_W-1:0] output_data_q [0:ARRAY_DIM-1]
                                                [0:ARRAY_DIM-1];

  logic config_valid;
  logic [DIM_W:0] next_tile_row;
  logic [DIM_W:0] next_tile_col;

  always_comb begin
    config_valid = (m_dim != '0) && (n_dim != '0) && (k_dim != '0);
    next_tile_row = {1'b0, tile_row_q} + (DIM_W + 1)'(ARRAY_DIM);
    next_tile_col = {1'b0, tile_col_q} + (DIM_W + 1)'(ARRAY_DIM);

    start_ready        = (state_q == CTRL_IDLE);
    busy               = (state_q != CTRL_IDLE);
    done               = (state_q == CTRL_DONE);
    clear_acc          = (state_q == CTRL_CLEAR);
    feeder_start_pulse = (state_q == CTRL_START_FEEDER);
    operand_ready      = (state_q == CTRL_COMPUTE);
    mac_en             = operand_valid && operand_ready;
    output_valid       = (state_q == CTRL_STORE);

    active_m = m_q;
    active_n = n_q;
    active_k = k_q;
    tile_row = tile_row_q;
    tile_col = tile_col_q;
    k_index  = mac_count_q[DIM_W-1:0];

    for (int unsigned lane = 0; lane < ARRAY_DIM; lane++) begin
      row_mask[lane] = ((DIM_W + 1)'(tile_row_q) + (DIM_W + 1)'(lane))
                     < (DIM_W + 1)'(m_q);
      col_mask[lane] = ((DIM_W + 1)'(tile_col_q) + (DIM_W + 1)'(lane))
                     < (DIM_W + 1)'(n_q);
    end

    for (int unsigned row = 0; row < ARRAY_DIM; row++) begin
      for (int unsigned col = 0; col < ARRAY_DIM; col++) begin
        output_data[row][col] = output_data_q[row][col];
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q      <= CTRL_IDLE;
      m_q          <= '0;
      n_q          <= '0;
      k_q          <= '0;
      tile_row_q   <= '0;
      tile_col_q   <= '0;
      mac_count_q  <= '0;
      error        <= 1'b0;
      for (int unsigned row = 0; row < ARRAY_DIM; row++) begin
        for (int unsigned col = 0; col < ARRAY_DIM; col++) begin
          output_data_q[row][col] <= '0;
        end
      end
    end else begin
      error <= 1'b0;

      if (start && (state_q != CTRL_IDLE)) begin
        error <= 1'b1;
      end

      case (state_q)
        CTRL_IDLE: begin
          if (start) begin
            if (config_valid) begin
              m_q         <= m_dim;
              n_q         <= n_dim;
              k_q         <= k_dim;
              tile_row_q  <= '0;
              tile_col_q  <= '0;
              mac_count_q <= '0;
              state_q     <= CTRL_CLEAR;
            end else begin
              error <= 1'b1;
            end
          end
        end

        CTRL_CLEAR: begin
          mac_count_q <= '0;
          state_q     <= CTRL_START_FEEDER;
        end

        CTRL_START_FEEDER: begin
          state_q <= CTRL_COMPUTE;
        end

        CTRL_COMPUTE: begin
          if (operand_valid) begin
            mac_count_q <= mac_count_q + 1'b1;
            if (mac_count_q == ({1'b0, k_q} - 1'b1)) begin
              state_q <= CTRL_CAPTURE;
            end
          end
        end

        CTRL_CAPTURE: begin
          for (int unsigned row = 0; row < ARRAY_DIM; row++) begin
            for (int unsigned col = 0; col < ARRAY_DIM; col++) begin
              output_data_q[row][col] <= mac_acc[row][col];
            end
          end
          state_q <= CTRL_STORE;
        end

        CTRL_STORE: begin
          if (output_ready) begin
            state_q <= CTRL_NEXT_TILE;
          end
        end

        CTRL_NEXT_TILE: begin
          if (next_tile_col < {1'b0, n_q}) begin
            tile_col_q <= next_tile_col[DIM_W-1:0];
            state_q    <= CTRL_CLEAR;
          end else if (next_tile_row < {1'b0, m_q}) begin
            tile_row_q <= next_tile_row[DIM_W-1:0];
            tile_col_q <= '0;
            state_q    <= CTRL_CLEAR;
          end else begin
            state_q <= CTRL_DONE;
          end
        end

        CTRL_DONE: begin
          state_q <= CTRL_IDLE;
        end

        default: begin
          state_q <= CTRL_IDLE;
          error   <= 1'b1;
        end
      endcase
    end
  end

`ifndef SYNTHESIS
  property p_start_accept;
    @(posedge clk) disable iff (!rst_n)
      (start && start_ready && config_valid) |=> busy;
  endproperty

  property p_start_while_busy;
    @(posedge clk) disable iff (!rst_n)
      (start && busy) |=> error;
  endproperty

  property p_invalid_start;
    @(posedge clk) disable iff (!rst_n)
      (start && start_ready && !config_valid) |=> (!busy && error);
  endproperty

  property p_mac_requires_operand;
    @(posedge clk) disable iff (!rst_n)
      mac_en |-> (operand_valid && operand_ready);
  endproperty

  property p_done_one_cycle;
    @(posedge clk) disable iff (!rst_n)
      done |=> !done;
  endproperty

  property p_store_after_all_k;
    @(posedge clk) disable iff (!rst_n)
      output_valid |-> (mac_count_q == {1'b0, k_q});
  endproperty

  property p_counter_in_range;
    @(posedge clk) disable iff (!rst_n)
      busy |-> (mac_count_q <= {1'b0, k_q});
  endproperty

  property p_idle_transition;
    @(posedge clk) disable iff (!rst_n)
      (state_q == CTRL_IDLE)
      |=> (state_q inside {CTRL_IDLE, CTRL_CLEAR});
  endproperty

  property p_clear_transition;
    @(posedge clk) disable iff (!rst_n)
      (state_q == CTRL_CLEAR) |=> (state_q == CTRL_START_FEEDER);
  endproperty

  property p_feeder_transition;
    @(posedge clk) disable iff (!rst_n)
      (state_q == CTRL_START_FEEDER) |=> (state_q == CTRL_COMPUTE);
  endproperty

  property p_compute_transition;
    @(posedge clk) disable iff (!rst_n)
      (state_q == CTRL_COMPUTE)
      |=> (state_q inside {CTRL_COMPUTE, CTRL_CAPTURE});
  endproperty

  property p_compute_waits_for_operand;
    @(posedge clk) disable iff (!rst_n)
      ((state_q == CTRL_COMPUTE) && !operand_valid)
      |=> (state_q == CTRL_COMPUTE);
  endproperty

  property p_compute_continues_before_last_k;
    @(posedge clk) disable iff (!rst_n)
      ((state_q == CTRL_COMPUTE) && mac_en
       && ((mac_count_q + 1'b1) < {1'b0, k_q}))
      |=> (state_q == CTRL_COMPUTE);
  endproperty

  property p_compute_finishes_on_last_k;
    @(posedge clk) disable iff (!rst_n)
      ((state_q == CTRL_COMPUTE) && mac_en
       && ((mac_count_q + 1'b1) == {1'b0, k_q}))
      |=> ((state_q == CTRL_CAPTURE) && (mac_count_q == {1'b0, k_q}));
  endproperty

  property p_capture_transition;
    @(posedge clk) disable iff (!rst_n)
      (state_q == CTRL_CAPTURE) |=> (state_q == CTRL_STORE);
  endproperty

  property p_store_transition;
    @(posedge clk) disable iff (!rst_n)
      (state_q == CTRL_STORE)
      |=> (state_q inside {CTRL_STORE, CTRL_NEXT_TILE});
  endproperty

  property p_store_waits_for_ready;
    @(posedge clk) disable iff (!rst_n)
      ((state_q == CTRL_STORE) && !output_ready)
      |=> (state_q == CTRL_STORE);
  endproperty

  property p_store_advances_on_ready;
    @(posedge clk) disable iff (!rst_n)
      ((state_q == CTRL_STORE) && output_ready)
      |=> (state_q == CTRL_NEXT_TILE);
  endproperty

  property p_next_tile_transition;
    @(posedge clk) disable iff (!rst_n)
      (state_q == CTRL_NEXT_TILE)
      |=> (state_q inside {CTRL_CLEAR, CTRL_DONE});
  endproperty

  property p_next_column;
    @(posedge clk) disable iff (!rst_n)
      ((state_q == CTRL_NEXT_TILE) && (next_tile_col < {1'b0, n_q}))
      |=> (state_q == CTRL_CLEAR);
  endproperty

  property p_next_row;
    @(posedge clk) disable iff (!rst_n)
      ((state_q == CTRL_NEXT_TILE) && !(next_tile_col < {1'b0, n_q})
       && (next_tile_row < {1'b0, m_q}))
      |=> (state_q == CTRL_CLEAR);
  endproperty

  property p_all_tiles_done;
    @(posedge clk) disable iff (!rst_n)
      ((state_q == CTRL_NEXT_TILE) && !(next_tile_col < {1'b0, n_q})
       && !(next_tile_row < {1'b0, m_q}))
      |=> (state_q == CTRL_DONE);
  endproperty

  property p_done_transition;
    @(posedge clk) disable iff (!rst_n)
      (state_q == CTRL_DONE) |=> (state_q == CTRL_IDLE);
  endproperty

  property p_output_stable_when_stalled;
    @(posedge clk) disable iff (!rst_n)
      (output_valid && !output_ready)
      |=> (output_valid && $stable(tile_row) && $stable(tile_col)
                        && $stable(row_mask) && $stable(col_mask));
  endproperty

  assert property (p_start_accept)
    else $error("compute_controller did not accept a valid idle start");
  assert property (p_start_while_busy)
    else $error("compute_controller did not reject start while busy");
  assert property (p_invalid_start)
    else $error("compute_controller accepted invalid dimensions");
  assert property (p_mac_requires_operand)
    else $error("compute_controller enabled MAC without operands");
  assert property (p_done_one_cycle)
    else $error("compute_controller done lasted more than one cycle");
  assert property (p_store_after_all_k)
    else $error("compute_controller stored a tile before K updates");
  assert property (p_counter_in_range)
    else $error("compute_controller MAC counter exceeded K");
  assert property (p_idle_transition);
  assert property (p_clear_transition);
  assert property (p_feeder_transition);
  assert property (p_compute_transition);
  assert property (p_compute_waits_for_operand);
  assert property (p_compute_continues_before_last_k);
  assert property (p_compute_finishes_on_last_k);
  assert property (p_capture_transition);
  assert property (p_store_transition);
  assert property (p_store_waits_for_ready);
  assert property (p_store_advances_on_ready);
  assert property (p_next_tile_transition);
  assert property (p_next_column);
  assert property (p_next_row);
  assert property (p_all_tiles_done);
  assert property (p_done_transition);
  assert property (p_output_stable_when_stalled)
    else $error("compute_controller output changed while stalled");

  for (genvar row = 0; row < ARRAY_DIM; row++) begin : gen_output_row_sva
    for (genvar col = 0; col < ARRAY_DIM; col++) begin : gen_output_col_sva
      property p_output_data_stable;
        @(posedge clk) disable iff (!rst_n)
          (output_valid && !output_ready) |=> $stable(output_data[row][col]);
      endproperty

      assert property (p_output_data_stable)
        else $error("compute_controller output data changed while stalled");
    end
  end
`endif

endmodule
