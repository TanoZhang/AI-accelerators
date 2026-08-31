`timescale 1ns/1ps

module tb_parallel_operand_feeder;

  localparam int unsigned DATA_W       = 8;
  localparam int unsigned DIM_W        = 16;
  localparam int unsigned ARRAY_DIM    = 4;
  localparam int unsigned SPAD_DEPTH   = 512;
  localparam int unsigned SPAD_ADDR_W  = $clog2(SPAD_DEPTH);

  logic clk;
  logic rst_n;
  logic start_pulse;
  logic [DIM_W-1:0] m_dim;
  logic [DIM_W-1:0] n_dim;
  logic [DIM_W-1:0] k_dim;
  logic [DIM_W-1:0] tile_row;
  logic [DIM_W-1:0] tile_col;
  logic busy;
  logic done_pulse;

  logic [ARRAY_DIM-1:0] activation_read_en;
  logic [SPAD_ADDR_W-1:0] activation_read_addr [0:ARRAY_DIM-1];
  logic [ARRAY_DIM-1:0] activation_read_valid;
  logic [DATA_W-1:0] activation_read_data [0:ARRAY_DIM-1];
  logic activation_write_en;
  logic [SPAD_ADDR_W-1:0] activation_write_addr;
  logic [DATA_W-1:0] activation_write_data;

  logic [ARRAY_DIM-1:0] weight_read_en;
  logic [SPAD_ADDR_W-1:0] weight_read_addr [0:ARRAY_DIM-1];
  logic [ARRAY_DIM-1:0] weight_read_valid;
  logic [DATA_W-1:0] weight_read_data [0:ARRAY_DIM-1];
  logic weight_write_en;
  logic [SPAD_ADDR_W-1:0] weight_write_addr;
  logic [DATA_W-1:0] weight_write_data;

  logic compute_valid;
  logic compute_ready;
  logic signed [DATA_W-1:0] a_vec [0:ARRAY_DIM-1];
  logic signed [DATA_W-1:0] b_vec [0:ARRAY_DIM-1];
  logic [ARRAY_DIM-1:0] row_mask;
  logic [ARRAY_DIM-1:0] col_mask;
  logic last_k;

  logic signed [DATA_W-1:0] activation_model [0:SPAD_DEPTH-1];
  logic signed [DATA_W-1:0] weight_model [0:SPAD_DEPTH-1];
  int unsigned checks;
  int unsigned issue_count;

  parallel_operand_feeder #(
    .DATA_W      (DATA_W),
    .DIM_W       (DIM_W),
    .ARRAY_DIM   (ARRAY_DIM),
    .SPAD_DEPTH  (SPAD_DEPTH),
    .SPAD_ADDR_W (SPAD_ADDR_W)
  ) dut (
    .clk                   (clk),
    .rst_n                 (rst_n),
    .start_pulse           (start_pulse),
    .m_dim                 (m_dim),
    .n_dim                 (n_dim),
    .k_dim                 (k_dim),
    .tile_row              (tile_row),
    .tile_col              (tile_col),
    .busy                  (busy),
    .done_pulse            (done_pulse),
    .activation_read_en    (activation_read_en),
    .activation_read_addr  (activation_read_addr),
    .activation_read_valid (activation_read_valid),
    .activation_read_data  (activation_read_data),
    .weight_read_en        (weight_read_en),
    .weight_read_addr      (weight_read_addr),
    .weight_read_valid     (weight_read_valid),
    .weight_read_data      (weight_read_data),
    .compute_valid         (compute_valid),
    .compute_ready         (compute_ready),
    .a_vec                 (a_vec),
    .b_vec                 (b_vec),
    .row_mask              (row_mask),
    .col_mask              (col_mask),
    .last_k                (last_k)
  );

  multi_read_scratchpad #(
    .DATA_W     (DATA_W),
    .DEPTH      (SPAD_DEPTH),
    .READ_PORTS (ARRAY_DIM),
    .ADDR_W     (SPAD_ADDR_W)
  ) activation_sram (
    .clk        (clk),
    .rst_n      (rst_n),
    .read_en    (activation_read_en),
    .read_addr  (activation_read_addr),
    .read_data  (activation_read_data),
    .read_valid (activation_read_valid),
    .write_en   (activation_write_en),
    .write_addr (activation_write_addr),
    .write_data (activation_write_data)
  );

  multi_read_scratchpad #(
    .DATA_W     (DATA_W),
    .DEPTH      (SPAD_DEPTH),
    .READ_PORTS (ARRAY_DIM),
    .ADDR_W     (SPAD_ADDR_W)
  ) weight_sram (
    .clk        (clk),
    .rst_n      (rst_n),
    .read_en    (weight_read_en),
    .read_addr  (weight_read_addr),
    .read_data  (weight_read_data),
    .read_valid (weight_read_valid),
    .write_en   (weight_write_en),
    .write_addr (weight_write_addr),
    .write_data (weight_write_data)
  );

  always #5 clk = ~clk;

  task automatic fail(input string label, input string detail);
    begin
      $error("%s: %s", label, detail);
      $fatal(1, "tb_parallel_operand_feeder failed");
    end
  endtask

  function automatic logic signed [DATA_W-1:0] make_a_value(
    input int unsigned row,
    input int unsigned k_index
  );
    return DATA_W'((row * 17) + (k_index * 5) - 73);
  endfunction

  function automatic logic signed [DATA_W-1:0] make_b_value(
    input int unsigned k_index,
    input int unsigned col
  );
    return DATA_W'((k_index * 19) - (col * 7) + 41);
  endfunction

  task automatic load_matrices(
    input int unsigned m_value,
    input int unsigned n_value,
    input int unsigned k_value
  );
    int unsigned address;
    logic signed [DATA_W-1:0] value;
    begin
      for (int unsigned row = 0; row < m_value; row++) begin
        for (int unsigned k_index = 0; k_index < k_value; k_index++) begin
          address = (row * k_value) + k_index;
          value = make_a_value(row, k_index);
          activation_model[address] = value;
          @(negedge clk);
          activation_write_en   = 1'b1;
          activation_write_addr = SPAD_ADDR_W'(address);
          activation_write_data = value;
          @(posedge clk);
          #1;
        end
      end
      @(negedge clk);
      activation_write_en = 1'b0;

      for (int unsigned k_index = 0; k_index < k_value; k_index++) begin
        for (int unsigned col = 0; col < n_value; col++) begin
          address = (k_index * n_value) + col;
          value = make_b_value(k_index, col);
          weight_model[address] = value;
          @(negedge clk);
          weight_write_en   = 1'b1;
          weight_write_addr = SPAD_ADDR_W'(address);
          weight_write_data = value;
          @(posedge clk);
          #1;
        end
      end
      @(negedge clk);
      weight_write_en = 1'b0;
    end
  endtask

  task automatic check_payload(
    input int unsigned accepted_k,
    input int unsigned m_value,
    input int unsigned n_value,
    input int unsigned k_value,
    input int unsigned tile_row_value,
    input int unsigned tile_col_value,
    input string label
  );
    int unsigned global_row;
    int unsigned global_col;
    int unsigned address;
    logic signed [DATA_W-1:0] expected;
    begin
      for (int unsigned lane = 0; lane < ARRAY_DIM; lane++) begin
        global_row = tile_row_value + lane;
        global_col = tile_col_value + lane;
        checks += 4;

        if (row_mask[lane] !== (global_row < m_value)) begin
          fail(label, "row mask mismatch");
        end
        if (col_mask[lane] !== (global_col < n_value)) begin
          fail(label, "column mask mismatch");
        end

        if (global_row < m_value) begin
          address = (global_row * k_value) + accepted_k;
          expected = activation_model[address];
        end else begin
          expected = '0;
        end
        if (a_vec[lane] !== expected) begin
          fail(label, "activation vector mismatch");
        end

        if (global_col < n_value) begin
          address = (accepted_k * n_value) + global_col;
          expected = weight_model[address];
        end else begin
          expected = '0;
        end
        if (b_vec[lane] !== expected) begin
          fail(label, "weight vector mismatch");
        end
      end

      checks++;
      if (last_k !== (accepted_k == (k_value - 1))) begin
        fail(label, "last_k mismatch");
      end
    end
  endtask

  task automatic run_tile(
    input int unsigned m_value,
    input int unsigned n_value,
    input int unsigned k_value,
    input int unsigned tile_row_value,
    input int unsigned tile_col_value,
    input bit exercise_stall,
    input string label
  );
    int unsigned accepted_k;
    int unsigned timeout;
    int unsigned last_accept_cycle;
    int unsigned cycle_count;
    int unsigned stall_left;
    bit saw_accept;
    bit finished;
    begin
      load_matrices(m_value, n_value, k_value);

      @(negedge clk);
      m_dim         = DIM_W'(m_value);
      n_dim         = DIM_W'(n_value);
      k_dim         = DIM_W'(k_value);
      tile_row      = DIM_W'(tile_row_value);
      tile_col      = DIM_W'(tile_col_value);
      start_pulse   = 1'b1;
      compute_ready = 1'b0;
      @(posedge clk);
      #1;
      checks++;
      if (!busy) begin
        fail(label, "start was not accepted");
      end
      @(negedge clk);
      start_pulse = 1'b0;

      accepted_k       = 0;
      timeout          = 0;
      last_accept_cycle = 0;
      cycle_count      = 0;
      stall_left       = exercise_stall ? 3 : 0;
      saw_accept       = 1'b0;
      finished         = 1'b0;

      while (!finished) begin
        @(negedge clk);
        timeout++;
        cycle_count++;
        if (timeout > 500) begin
          fail(label, "timeout waiting for completion");
        end

        if (done_pulse) begin
          finished = 1'b1;
        end else begin
          if (exercise_stall && compute_valid && (stall_left != 0)) begin
            compute_ready = 1'b0;
            stall_left--;
          end else begin
            compute_ready = 1'b1;
          end

          if (compute_valid) begin
            check_payload(accepted_k, m_value, n_value, k_value,
                          tile_row_value, tile_col_value, label);
            if (compute_ready) begin
              if (saw_accept && !exercise_stall) begin
                checks++;
                if (cycle_count != (last_accept_cycle + 1)) begin
                  fail(label, "accepted K beats were not consecutive");
                end
              end
              saw_accept        = 1'b1;
              last_accept_cycle = cycle_count;
              accepted_k++;
            end
          end
        end
      end

      checks += 3;
      if (accepted_k != k_value) begin
        fail(label, "incorrect number of accepted K beats");
      end
      if (busy) begin
        fail(label, "busy remained asserted after the final beat");
      end
      if (!saw_accept) begin
        fail(label, "no compute beat was accepted");
      end
      compute_ready = 1'b0;
    end
  endtask

  // All valid lanes must issue in parallel for the same K index.
  always @(posedge clk) begin
    if (rst_n && (|activation_read_en || |weight_read_en)) begin
      issue_count++;
      for (int unsigned lane = 0; lane < ARRAY_DIM; lane++) begin
        checks += 2;
        if (activation_read_en[lane] !== row_mask[lane]) begin
          fail("read monitor", "activation lanes did not issue in parallel");
        end
        if (weight_read_en[lane] !== col_mask[lane]) begin
          fail("read monitor", "weight lanes did not issue in parallel");
        end
      end
    end
  end

  initial begin
    clk                     = 1'b0;
    rst_n                   = 1'b1;
    start_pulse             = 1'b0;
    m_dim                   = '0;
    n_dim                   = '0;
    k_dim                   = '0;
    tile_row                = '0;
    tile_col                = '0;
    compute_ready           = 1'b0;
    activation_write_en     = 1'b0;
    activation_write_addr   = '0;
    activation_write_data   = '0;
    weight_write_en         = 1'b0;
    weight_write_addr       = '0;
    weight_write_data       = '0;
    checks                  = 0;
    issue_count             = 0;

    #1;
    rst_n = 1'b0;
    #1;
    checks++;
    if (busy || done_pulse || compute_valid) begin
      fail("reset", "control outputs did not reset");
    end
    @(negedge clk);
    rst_n = 1'b1;

    run_tile(4, 4, 8, 0, 0, 1'b0, "full tile sustained throughput");
    run_tile(7, 6, 5, 4, 4, 1'b1, "edge tile with backpressure");
    run_tile(5, 7, 3, 0, 4, 1'b0, "partial column tile");

    checks++;
    if (issue_count != (8 + 5 + 3)) begin
      fail("read monitor", "read issue count did not equal total K beats");
    end

    $display("tb_parallel_operand_feeder PASS (%0d self-checks, %0d vector reads)",
             checks, issue_count);
    $finish;
  end

endmodule
