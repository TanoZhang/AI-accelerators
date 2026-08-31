// Two FIFO entries cover the registered RAM response while the MAC is stalled.
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

  localparam int unsigned FIFO_DEPTH = 2;
  localparam int unsigned CALC_W     = (2 * DIM_W) + 1;

  logic active_q;
  logic [DIM_W-1:0] m_q;
  logic [DIM_W-1:0] n_q;
  logic [DIM_W-1:0] k_q;
  logic [DIM_W-1:0] next_k_q;
  logic [DIM_W-1:0] request_k_q;
  logic [ARRAY_DIM-1:0] row_mask_q;
  logic [ARRAY_DIM-1:0] col_mask_q;

  logic [CALC_W-1:0] activation_addr_q [0:ARRAY_DIM-1];
  logic [CALC_W-1:0] weight_addr_q [0:ARRAY_DIM-1];

  logic signed [DATA_W-1:0] a_fifo_q [0:FIFO_DEPTH-1][0:ARRAY_DIM-1];
  logic signed [DATA_W-1:0] b_fifo_q [0:FIFO_DEPTH-1][0:ARRAY_DIM-1];
  logic [DIM_W-1:0] k_fifo_q [0:FIFO_DEPTH-1];
  logic read_ptr_q;
  logic write_ptr_q;
  logic [1:0] fifo_count_q;
  logic request_pending_q;

  logic start_config_valid;
  logic pop_fifo;
  logic push_fifo;
  logic issue_reads;
  logic [2:0] reserved_entries;
  logic [2:0] reserved_after_pop;
  logic response_ports_valid;

  always_comb begin
    start_config_valid = (m_dim != '0) && (n_dim != '0) && (k_dim != '0)
                      && (tile_row < m_dim) && (tile_col < n_dim);

    compute_valid = (fifo_count_q != 0);
    pop_fifo      = compute_valid && compute_ready;
    push_fifo     = request_pending_q;

    reserved_entries = {1'b0, fifo_count_q}
                     + {{2{1'b0}}, request_pending_q};
    reserved_after_pop = reserved_entries
                       - {{2{1'b0}}, pop_fifo};
    issue_reads = active_q && (next_k_q < k_q)
               && (reserved_after_pop < FIFO_DEPTH);

    busy      = active_q;
    row_mask  = row_mask_q;
    col_mask  = col_mask_q;
    last_k    = compute_valid
             && (k_fifo_q[read_ptr_q] == (k_q - 1'b1));

    response_ports_valid = 1'b1;
    for (int unsigned lane = 0; lane < ARRAY_DIM; lane++) begin
      activation_read_en[lane] = issue_reads && row_mask_q[lane];
      weight_read_en[lane]     = issue_reads && col_mask_q[lane];
      activation_read_addr[lane] = activation_addr_q[lane]
                                                   [SPAD_ADDR_W-1:0];
      weight_read_addr[lane] = weight_addr_q[lane][SPAD_ADDR_W-1:0];

      a_vec[lane] = a_fifo_q[read_ptr_q][lane];
      b_vec[lane] = b_fifo_q[read_ptr_q][lane];

      if (request_pending_q) begin
        if (row_mask_q[lane] && !activation_read_valid[lane]) begin
          response_ports_valid = 1'b0;
        end
        if (col_mask_q[lane] && !weight_read_valid[lane]) begin
          response_ports_valid = 1'b0;
        end
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active_q         <= 1'b0;
      m_q              <= '0;
      n_q              <= '0;
      k_q              <= '0;
      next_k_q         <= '0;
      request_k_q      <= '0;
      row_mask_q       <= '0;
      col_mask_q       <= '0;
      read_ptr_q       <= 1'b0;
      write_ptr_q      <= 1'b0;
      fifo_count_q     <= '0;
      request_pending_q <= 1'b0;
      done_pulse       <= 1'b0;

      for (int unsigned lane = 0; lane < ARRAY_DIM; lane++) begin
        activation_addr_q[lane] <= '0;
        weight_addr_q[lane]     <= '0;
      end
      for (int unsigned entry = 0; entry < FIFO_DEPTH; entry++) begin
        k_fifo_q[entry] <= '0;
        for (int unsigned lane = 0; lane < ARRAY_DIM; lane++) begin
          a_fifo_q[entry][lane] <= '0;
          b_fifo_q[entry][lane] <= '0;
        end
      end
    end else begin
      done_pulse <= 1'b0;

      if (!active_q) begin
        request_pending_q <= 1'b0;
        fifo_count_q      <= '0;
        read_ptr_q        <= 1'b0;
        write_ptr_q       <= 1'b0;

        if (start_pulse && start_config_valid) begin
          active_q    <= 1'b1;
          m_q         <= m_dim;
          n_q         <= n_dim;
          k_q         <= k_dim;
          next_k_q    <= '0;

          for (int unsigned lane = 0; lane < ARRAY_DIM; lane++) begin
            row_mask_q[lane] <= ((DIM_W + 1)'(tile_row)
                               + (DIM_W + 1)'(lane))
                              < (DIM_W + 1)'(m_dim);
            col_mask_q[lane] <= ((DIM_W + 1)'(tile_col)
                               + (DIM_W + 1)'(lane))
                              < (DIM_W + 1)'(n_dim);

            activation_addr_q[lane]
              <= CALC_W'((DIM_W + 1)'(tile_row)
                       + (DIM_W + 1)'(lane)) * CALC_W'(k_dim);
            weight_addr_q[lane]
              <= CALC_W'((DIM_W + 1)'(tile_col)
                       + (DIM_W + 1)'(lane));
          end
        end
      end else begin
        request_pending_q <= issue_reads;

        if (issue_reads) begin
          request_k_q <= next_k_q;
          next_k_q    <= next_k_q + 1'b1;
          for (int unsigned lane = 0; lane < ARRAY_DIM; lane++) begin
            if (row_mask_q[lane]) begin
              activation_addr_q[lane] <= activation_addr_q[lane] + 1'b1;
            end
            if (col_mask_q[lane]) begin
              weight_addr_q[lane] <= weight_addr_q[lane] + CALC_W'(n_q);
            end
          end
        end

        if (push_fifo) begin
          k_fifo_q[write_ptr_q] <= request_k_q;
          for (int unsigned lane = 0; lane < ARRAY_DIM; lane++) begin
            if (row_mask_q[lane]) begin
              a_fifo_q[write_ptr_q][lane]
                <= $signed(activation_read_data[lane]);
            end else begin
              a_fifo_q[write_ptr_q][lane] <= '0;
            end

            if (col_mask_q[lane]) begin
              b_fifo_q[write_ptr_q][lane]
                <= $signed(weight_read_data[lane]);
            end else begin
              b_fifo_q[write_ptr_q][lane] <= '0;
            end
          end
          write_ptr_q <= write_ptr_q + 1'b1;
        end

        if (pop_fifo) begin
          read_ptr_q <= read_ptr_q + 1'b1;
        end

        case ({push_fifo, pop_fifo})
          2'b10: fifo_count_q <= fifo_count_q + 1'b1;
          2'b01: fifo_count_q <= fifo_count_q - 1'b1;
          default: begin
          end
        endcase

        if (pop_fifo && last_k) begin
          active_q   <= 1'b0;
          done_pulse <= 1'b1;
        end
      end
    end
  end

`ifndef SYNTHESIS
  property p_valid_start;
    @(posedge clk) disable iff (!rst_n)
      start_pulse |-> (!active_q && start_config_valid);
  endproperty

  property p_fifo_never_overflows;
    @(posedge clk) disable iff (!rst_n)
      fifo_count_q <= FIFO_DEPTH;
  endproperty

  property p_response_has_space;
    @(posedge clk) disable iff (!rst_n)
      push_fifo |-> ((fifo_count_q < FIFO_DEPTH) || pop_fifo);
  endproperty

  property p_response_ports_arrive_together;
    @(posedge clk) disable iff (!rst_n)
      push_fifo |-> response_ports_valid;
  endproperty

  property p_control_stable_when_stalled;
    @(posedge clk) disable iff (!rst_n)
      (compute_valid && !compute_ready)
      |=> (compute_valid && $stable(row_mask) && $stable(col_mask)
                        && $stable(last_k));
  endproperty

  property p_done_one_cycle;
    @(posedge clk) disable iff (!rst_n)
      done_pulse |=> !done_pulse;
  endproperty

  assert property (p_valid_start)
    else $error("parallel_operand_feeder received an invalid start");
  assert property (p_fifo_never_overflows)
    else $error("parallel_operand_feeder FIFO overflowed");
  assert property (p_response_has_space)
    else $error("parallel_operand_feeder received data without FIFO space");
  assert property (p_response_ports_arrive_together)
    else $error("parallel_operand_feeder scratchpad response misalignment");
  assert property (p_control_stable_when_stalled)
    else $error("parallel_operand_feeder control changed while stalled");
  assert property (p_done_one_cycle);

  for (genvar lane = 0; lane < ARRAY_DIM; lane++) begin : gen_assertions
    property p_activation_address_in_range;
      @(posedge clk) disable iff (!rst_n)
        activation_read_en[lane]
        |-> (activation_addr_q[lane] < SPAD_DEPTH);
    endproperty

    property p_weight_address_in_range;
      @(posedge clk) disable iff (!rst_n)
        weight_read_en[lane] |-> (weight_addr_q[lane] < SPAD_DEPTH);
    endproperty

    property p_operand_stable_when_stalled;
      @(posedge clk) disable iff (!rst_n)
        (compute_valid && !compute_ready)
        |=> ($stable(a_vec[lane]) && $stable(b_vec[lane]));
    endproperty

    assert property (p_activation_address_in_range)
      else $error("parallel_operand_feeder activation lane %0d address overflow",
                  lane);
    assert property (p_weight_address_in_range)
      else $error("parallel_operand_feeder weight lane %0d address overflow",
                  lane);
    assert property (p_operand_stable_when_stalled)
      else $error("parallel_operand_feeder lane %0d changed while stalled", lane);
  end
`endif

endmodule
