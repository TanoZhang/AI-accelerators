// Serializes one 4x4 result tile into the scalar output scratchpad port.
module output_tile_writer #(
  parameter int unsigned DIM_W      = 16,
  parameter int unsigned ARRAY_DIM  = 4,
  parameter int unsigned SPAD_DEPTH = 1024,
  parameter int unsigned SPAD_ADDR_W = (SPAD_DEPTH > 1)
                                     ? $clog2(SPAD_DEPTH) : 1
) (
  input  logic                                    clk,
  input  logic                                    rst_n,

  input  logic                                    tile_valid,
  output logic                                    tile_ready,
  input  logic signed [31:0]                      tile_data [0:ARRAY_DIM-1]
                                                               [0:ARRAY_DIM-1],
  input  logic [DIM_W-1:0]                        tile_row,
  input  logic [DIM_W-1:0]                        tile_col,
  input  logic [ARRAY_DIM-1:0]                    row_mask,
  input  logic [ARRAY_DIM-1:0]                    col_mask,

  input  logic [DIM_W-1:0]                        m_dim,
  input  logic [DIM_W-1:0]                        n_dim,
  input  logic                                    quant_enable,
  input  logic                                    relu_enable,
  input  logic [4:0]                              quant_shift,

  output logic                                    sram_wr_en,
  output logic [SPAD_ADDR_W-1:0]                  sram_wr_addr,
  output logic [31:0]                             sram_wr_data,
  output logic                                    busy,
  output logic                                    tile_done
);

  localparam int unsigned POS_W  = (ARRAY_DIM * ARRAY_DIM > 1)
                                 ? $clog2(ARRAY_DIM * ARRAY_DIM) : 1;
  localparam int unsigned CALC_W = (2 * DIM_W) + 1;

  typedef enum logic {
    WRITER_IDLE,
    WRITER_WRITE
  } writer_state_e;

  writer_state_e state_q;

  logic signed [31:0] tile_data_q [0:ARRAY_DIM-1][0:ARRAY_DIM-1];
  logic signed [7:0] quant_data [0:ARRAY_DIM-1][0:ARRAY_DIM-1];
  logic [DIM_W-1:0] tile_row_q;
  logic [DIM_W-1:0] tile_col_q;
  logic [DIM_W-1:0] m_q;
  logic [DIM_W-1:0] n_q;
  logic [ARRAY_DIM-1:0] row_mask_q;
  logic [ARRAY_DIM-1:0] col_mask_q;
  logic quant_enable_q;
  logic relu_enable_q;
  logic [4:0] quant_shift_q;
  logic [POS_W-1:0] position_q;

  logic [POS_W-1:0] local_row;
  logic [POS_W-1:0] local_col;
  logic [DIM_W:0] global_row;
  logic [DIM_W:0] global_col;
  logic [CALC_W-1:0] output_index;
  logic position_valid;

  requant_relu #(
    .ARRAY_DIM (ARRAY_DIM)
  ) u_requant_relu (
    .in_data      (tile_data_q),
    .quant_enable (quant_enable_q),
    .quant_shift  (quant_shift_q),
    .relu_enable  (relu_enable_q),
    .out_data     (quant_data)
  );

  always_comb begin
    local_row = position_q / POS_W'(ARRAY_DIM);
    local_col = position_q % POS_W'(ARRAY_DIM);
    global_row = {1'b0, tile_row_q} + (DIM_W + 1)'(local_row);
    global_col = {1'b0, tile_col_q} + (DIM_W + 1)'(local_col);
    output_index = (CALC_W'(global_row) * CALC_W'(n_q))
                 + CALC_W'(global_col);

    position_valid = row_mask_q[local_row]
                  && col_mask_q[local_col]
                  && (global_row < {1'b0, m_q})
                  && (global_col < {1'b0, n_q});

    tile_ready  = (state_q == WRITER_IDLE);
    busy        = (state_q == WRITER_WRITE);
    sram_wr_en  = busy && position_valid;
    sram_wr_addr = output_index[SPAD_ADDR_W-1:0];

    if (quant_enable_q) begin
      sram_wr_data = {{24{quant_data[local_row][local_col][7]}},
                      quant_data[local_row][local_col]};
    end else if (relu_enable_q && (tile_data_q[local_row][local_col] < 0)) begin
      sram_wr_data = 32'd0;
    end else begin
      sram_wr_data = $unsigned(tile_data_q[local_row][local_col]);
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q         <= WRITER_IDLE;
      tile_row_q      <= '0;
      tile_col_q      <= '0;
      m_q             <= '0;
      n_q             <= '0;
      row_mask_q      <= '0;
      col_mask_q      <= '0;
      quant_enable_q  <= 1'b0;
      relu_enable_q   <= 1'b0;
      quant_shift_q   <= '0;
      position_q      <= '0;
      tile_done       <= 1'b0;
      for (int unsigned row = 0; row < ARRAY_DIM; row++) begin
        for (int unsigned col = 0; col < ARRAY_DIM; col++) begin
          tile_data_q[row][col] <= '0;
        end
      end
    end else begin
      tile_done <= 1'b0;

      case (state_q)
        WRITER_IDLE: begin
          if (tile_valid && tile_ready) begin
            tile_row_q     <= tile_row;
            tile_col_q     <= tile_col;
            m_q            <= m_dim;
            n_q            <= n_dim;
            row_mask_q     <= row_mask;
            col_mask_q     <= col_mask;
            quant_enable_q <= quant_enable;
            relu_enable_q  <= relu_enable;
            quant_shift_q  <= quant_shift;
            position_q     <= '0;
            for (int unsigned row = 0; row < ARRAY_DIM; row++) begin
              for (int unsigned col = 0; col < ARRAY_DIM; col++) begin
                tile_data_q[row][col] <= tile_data[row][col];
              end
            end
            state_q <= WRITER_WRITE;
          end
        end

        WRITER_WRITE: begin
          if (position_q == POS_W'((ARRAY_DIM * ARRAY_DIM) - 1)) begin
            tile_done <= 1'b1;
            state_q   <= WRITER_IDLE;
          end else begin
            position_q <= position_q + 1'b1;
          end
        end

        default: begin
          state_q <= WRITER_IDLE;
        end
      endcase
    end
  end

`ifndef SYNTHESIS
  property p_accept_only_when_ready;
    @(posedge clk) disable iff (!rst_n)
      (tile_valid && !tile_ready) |-> busy;
  endproperty

  property p_one_write_per_cycle;
    @(posedge clk) disable iff (!rst_n)
      sram_wr_en |-> busy;
  endproperty

  property p_write_is_valid;
    @(posedge clk) disable iff (!rst_n)
      sram_wr_en |-> position_valid;
  endproperty

  property p_write_address_in_range;
    @(posedge clk) disable iff (!rst_n)
      sram_wr_en |-> (output_index < SPAD_DEPTH);
  endproperty

  property p_done_one_cycle;
    @(posedge clk) disable iff (!rst_n)
      tile_done |=> !tile_done;
  endproperty

  assert property (p_accept_only_when_ready);
  assert property (p_one_write_per_cycle);
  assert property (p_write_is_valid);
  assert property (p_write_address_in_range)
    else $error("output_tile_writer address exceeded scratchpad depth");
  assert property (p_done_one_cycle);
`endif

endmodule
