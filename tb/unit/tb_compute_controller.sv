`timescale 1ns/1ps

module tb_compute_controller;

  localparam int unsigned DIM_W     = 8;
  localparam int unsigned ACC_W     = 32;
  localparam int unsigned ARRAY_DIM = 4;

  logic clk;
  logic rst_n;
  logic start;
  logic [DIM_W-1:0] m_dim;
  logic [DIM_W-1:0] n_dim;
  logic [DIM_W-1:0] k_dim;
  logic start_ready;
  logic busy;
  logic done;
  logic error;
  logic feeder_start_pulse;
  logic [DIM_W-1:0] active_m;
  logic [DIM_W-1:0] active_n;
  logic [DIM_W-1:0] active_k;
  logic [DIM_W-1:0] tile_row;
  logic [DIM_W-1:0] tile_col;
  logic [DIM_W-1:0] k_index;
  logic operand_valid;
  logic operand_ready;
  logic clear_acc;
  logic mac_en;
  logic signed [ACC_W-1:0] mac_acc [0:ARRAY_DIM-1][0:ARRAY_DIM-1];
  logic output_valid;
  logic output_ready;
  logic signed [ACC_W-1:0] output_data [0:ARRAY_DIM-1][0:ARRAY_DIM-1];
  logic [ARRAY_DIM-1:0] row_mask;
  logic [ARRAY_DIM-1:0] col_mask;

  int unsigned mac_updates_this_tile;
  int unsigned feeder_starts;
  int unsigned clear_cycles;
  int unsigned checks;

  compute_controller #(
    .DIM_W     (DIM_W),
    .ACC_W     (ACC_W),
    .ARRAY_DIM (ARRAY_DIM)
  ) dut (
    .clk                (clk),
    .rst_n              (rst_n),
    .start              (start),
    .m_dim              (m_dim),
    .n_dim              (n_dim),
    .k_dim              (k_dim),
    .start_ready        (start_ready),
    .busy               (busy),
    .done               (done),
    .error              (error),
    .feeder_start_pulse (feeder_start_pulse),
    .active_m           (active_m),
    .active_n           (active_n),
    .active_k           (active_k),
    .tile_row           (tile_row),
    .tile_col           (tile_col),
    .k_index            (k_index),
    .operand_valid      (operand_valid),
    .operand_ready      (operand_ready),
    .clear_acc          (clear_acc),
    .mac_en             (mac_en),
    .mac_acc            (mac_acc),
    .output_valid       (output_valid),
    .output_ready       (output_ready),
    .output_data        (output_data),
    .row_mask           (row_mask),
    .col_mask           (col_mask)
  );

  always #5 clk = ~clk;

  task automatic fail(input string label, input string detail);
    begin
      $error("%s: %s", label, detail);
      $fatal(1, "tb_compute_controller failed");
    end
  endtask

  function automatic logic signed [ACC_W-1:0] pe_step(
    input int unsigned row,
    input int unsigned col
  );
    pe_step = $signed((row * ARRAY_DIM) + col + 1);
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mac_updates_this_tile <= 0;
      feeder_starts         <= 0;
      clear_cycles          <= 0;
      for (int unsigned row = 0; row < ARRAY_DIM; row++) begin
        for (int unsigned col = 0; col < ARRAY_DIM; col++) begin
          mac_acc[row][col] <= '0;
        end
      end
    end else begin
      if (clear_acc) begin
        mac_updates_this_tile <= 0;
        clear_cycles          <= clear_cycles + 1;
        for (int unsigned row = 0; row < ARRAY_DIM; row++) begin
          for (int unsigned col = 0; col < ARRAY_DIM; col++) begin
            mac_acc[row][col] <= '0;
          end
        end
      end else if (mac_en) begin
        mac_updates_this_tile <= mac_updates_this_tile + 1;
        for (int unsigned row = 0; row < ARRAY_DIM; row++) begin
          for (int unsigned col = 0; col < ARRAY_DIM; col++) begin
            if (row_mask[row] && col_mask[col]) begin
              mac_acc[row][col] <= mac_acc[row][col] + pe_step(row, col);
            end
          end
        end
      end

      if (feeder_start_pulse) begin
        feeder_starts <= feeder_starts + 1;
      end
    end
  end

  task automatic check_output_tile(
    input int unsigned expected_row,
    input int unsigned expected_col,
    input int unsigned m_value,
    input int unsigned n_value,
    input int unsigned k_value,
    input string       label
  );
    logic expected_row_valid;
    logic expected_col_valid;
    logic signed [ACC_W-1:0] expected_data;
    begin
      checks += 3;
      if (tile_row !== expected_row[DIM_W-1:0]) begin
        fail(label, "tile_row is incorrect");
      end
      if (tile_col !== expected_col[DIM_W-1:0]) begin
        fail(label, "tile_col is incorrect");
      end
      if (mac_updates_this_tile != k_value) begin
        fail(label, "output became valid before exactly K MAC updates");
      end

      for (int unsigned row = 0; row < ARRAY_DIM; row++) begin
        for (int unsigned col = 0; col < ARRAY_DIM; col++) begin
          expected_row_valid = (expected_row + row) < m_value;
          expected_col_valid = (expected_col + col) < n_value;
          expected_data = '0;
          if (expected_row_valid && expected_col_valid) begin
            expected_data = pe_step(row, col) * $signed(k_value);
          end

          checks += 3;
          if (row_mask[row] !== expected_row_valid) begin
            fail(label, $sformatf("row mask %0d is incorrect", row));
          end
          if (col_mask[col] !== expected_col_valid) begin
            fail(label, $sformatf("column mask %0d is incorrect", col));
          end
          if (output_data[row][col] !== expected_data) begin
            $error("%s: output[%0d][%0d]=%0d expected=%0d",
                   label, row, col, output_data[row][col], expected_data);
            $fatal(1, "captured tile data mismatch");
          end
        end
      end
    end
  endtask

  task automatic run_operation(
    input int unsigned m_value,
    input int unsigned n_value,
    input int unsigned k_value,
    input bit          inject_busy_start,
    input string       label
  );
    int unsigned expected_row;
    int unsigned expected_col;
    int unsigned expected_tiles;
    int unsigned stored_tiles;
    int unsigned feeder_starts_before;
    int unsigned clear_cycles_before;
    int unsigned timeout;
    bit stall_seen;
    bit finished;
    begin
      expected_row = 0;
      expected_col = 0;
      expected_tiles = ((m_value + ARRAY_DIM - 1) / ARRAY_DIM)
                     * ((n_value + ARRAY_DIM - 1) / ARRAY_DIM);
      stored_tiles = 0;
      feeder_starts_before = feeder_starts;
      clear_cycles_before  = clear_cycles;

      @(negedge clk);
      m_dim        = m_value[DIM_W-1:0];
      n_dim        = n_value[DIM_W-1:0];
      k_dim        = k_value[DIM_W-1:0];
      start        = 1'b1;
      operand_valid = 1'b0;
      output_ready = 1'b0;
      @(posedge clk);
      #1;
      checks += 4;
      if (!busy || start_ready || error || done) begin
        fail(label, "valid start produced incorrect status");
      end
      if ((active_m != m_value) || (active_n != n_value)
          || (active_k != k_value)) begin
        fail(label, "configuration was not captured");
      end

      @(negedge clk);
      if (inject_busy_start) begin
        start = 1'b1;
        @(posedge clk);
        #1;
        checks++;
        if (!error) begin
          fail(label, "start while busy did not raise error");
        end
        @(negedge clk);
      end
      start = 1'b0;

      timeout    = 0;
      stall_seen = 1'b0;
      finished   = 1'b0;

      while (!finished) begin
        @(negedge clk);
        timeout++;
        if (timeout > 5000) begin
          fail(label, "operation timeout");
        end

        if (done) begin
          checks += 3;
          if (!busy) begin
            fail(label, "busy dropped before the done pulse");
          end
          if (stored_tiles != expected_tiles) begin
            fail(label, "done asserted before all tiles were stored");
          end
          finished = 1'b1;
          operand_valid = 1'b0;
          output_ready  = 1'b0;
        end else begin
          operand_valid = operand_ready && ($urandom_range(0, 3) != 0);

          if (output_valid && !stall_seen) begin
            output_ready = 1'b0;
            stall_seen   = 1'b1;
          end else begin
            output_ready = output_valid && ($urandom_range(0, 2) != 0);
          end

          #1;

          if (mac_en) begin
            checks += 2;
            if (!operand_valid) begin
              fail(label, "mac_en asserted without operand_valid");
            end
            if (k_index != mac_updates_this_tile[DIM_W-1:0]) begin
              fail(label, "k_index does not match completed MAC count");
            end
          end

          if (output_valid) begin
            check_output_tile(expected_row, expected_col, m_value, n_value,
                              k_value, label);
            if (output_ready) begin
              stored_tiles++;
              stall_seen = 1'b0;
              if ((expected_col + ARRAY_DIM) < n_value) begin
                expected_col += ARRAY_DIM;
              end else begin
                expected_col = 0;
                expected_row += ARRAY_DIM;
              end
            end
          end
        end
      end

      @(posedge clk);
      #1;
      checks += 4;
      if (done || busy || !start_ready || error) begin
        fail(label, "controller did not return cleanly to idle");
      end
      if ((feeder_starts - feeder_starts_before) != expected_tiles) begin
        fail(label, "feeder start count does not match tile count");
      end
      if ((clear_cycles - clear_cycles_before) != expected_tiles) begin
        fail(label, "clear count does not match tile count");
      end
    end
  endtask

  task automatic check_invalid_start(
    input int unsigned m_value,
    input int unsigned n_value,
    input int unsigned k_value,
    input string       label
  );
    begin
      @(negedge clk);
      m_dim = m_value[DIM_W-1:0];
      n_dim = n_value[DIM_W-1:0];
      k_dim = k_value[DIM_W-1:0];
      start = 1'b1;
      @(posedge clk);
      #1;
      checks += 4;
      if (!error || busy || done || !start_ready) begin
        fail(label, "invalid configuration was not rejected");
      end
      @(negedge clk);
      start = 1'b0;
      @(posedge clk);
      #1;
      checks++;
      if (error) begin
        fail(label, "error did not pulse for one cycle");
      end
    end
  endtask

  initial begin
    clk           = 1'b0;
    rst_n         = 1'b1;
    start         = 1'b0;
    m_dim         = '0;
    n_dim         = '0;
    k_dim         = '0;
    operand_valid = 1'b0;
    output_ready  = 1'b0;
    checks        = 0;

    #1;
    rst_n = 1'b0;
    #1;
    if (busy || done || error || !start_ready) begin
      fail("reset", "status outputs did not reset");
    end
    @(negedge clk);
    rst_n = 1'b1;

    check_invalid_start(0, 4, 1, "M=0");
    check_invalid_start(4, 0, 1, "N=0");
    check_invalid_start(4, 4, 0, "K=0");

    run_operation(4, 4, 1, 1'b1, "single 4x4 tile K=1");
    run_operation(5, 7, 3, 1'b0, "partial M/N tiles");
    run_operation(8, 8, 4, 1'b0, "four full tiles");
    run_operation(1, 1, 2, 1'b0, "single-element edge tile");
    run_operation(1, 1, 255, 1'b0, "maximum K counter value");

    $display("tb_compute_controller PASS (%0d self-checks)", checks);
    $finish;
  end

endmodule
