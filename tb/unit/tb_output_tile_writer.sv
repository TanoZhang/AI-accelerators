`timescale 1ns/1ps

module tb_output_tile_writer;

  localparam int unsigned DIM_W       = 16;
  localparam int unsigned ARRAY_DIM   = 4;
  localparam int unsigned SPAD_DEPTH  = 256;
  localparam int unsigned SPAD_ADDR_W = $clog2(SPAD_DEPTH);

  logic clk;
  logic rst_n;
  logic tile_valid;
  logic tile_ready;
  logic signed [31:0] tile_data [0:ARRAY_DIM-1][0:ARRAY_DIM-1];
  logic [DIM_W-1:0] tile_row;
  logic [DIM_W-1:0] tile_col;
  logic [ARRAY_DIM-1:0] row_mask;
  logic [ARRAY_DIM-1:0] col_mask;
  logic [DIM_W-1:0] m_dim;
  logic [DIM_W-1:0] n_dim;
  logic quant_enable;
  logic relu_enable;
  logic [4:0] quant_shift;
  logic sram_wr_en;
  logic [SPAD_ADDR_W-1:0] sram_wr_addr;
  logic [31:0] sram_wr_data;
  logic busy;
  logic tile_done;

  logic [SPAD_ADDR_W-1:0] expected_addr [0:15];
  logic [31:0] expected_data [0:15];
  int unsigned expected_writes;
  int unsigned observed_writes;
  bit scoreboard_active;
  int unsigned checks;

  output_tile_writer #(
    .DIM_W       (DIM_W),
    .ARRAY_DIM   (ARRAY_DIM),
    .SPAD_DEPTH  (SPAD_DEPTH),
    .SPAD_ADDR_W (SPAD_ADDR_W)
  ) dut (
    .clk          (clk),
    .rst_n        (rst_n),
    .tile_valid   (tile_valid),
    .tile_ready   (tile_ready),
    .tile_data    (tile_data),
    .tile_row     (tile_row),
    .tile_col     (tile_col),
    .row_mask     (row_mask),
    .col_mask     (col_mask),
    .m_dim        (m_dim),
    .n_dim        (n_dim),
    .quant_enable (quant_enable),
    .relu_enable  (relu_enable),
    .quant_shift  (quant_shift),
    .sram_wr_en   (sram_wr_en),
    .sram_wr_addr (sram_wr_addr),
    .sram_wr_data (sram_wr_data),
    .busy         (busy),
    .tile_done    (tile_done)
  );

  always #5 clk = ~clk;

  task automatic fail(input string label, input string detail);
    begin
      $error("%s: %s", label, detail);
      $fatal(1, "tb_output_tile_writer failed");
    end
  endtask

  function automatic logic signed [7:0] quant_reference(
    input logic signed [31:0] value,
    input logic               relu,
    input logic [4:0]         shift
  );
    logic signed [31:0] adjusted;
    logic signed [31:0] shifted;
    begin
      adjusted = (relu && (value < 0)) ? 32'sd0 : value;
      shifted = adjusted >>> shift;
      if (shifted > 127) begin
        quant_reference = 8'sd127;
      end else if (shifted < -128) begin
        quant_reference = -8'sd128;
      end else begin
        quant_reference = $signed(shifted[7:0]);
      end
    end
  endfunction

  task automatic build_expected;
    int unsigned index;
    int unsigned global_row_int;
    int unsigned global_col_int;
    int unsigned n_int;
    logic signed [7:0] quantized;
    begin
      expected_writes = 0;
      for (int unsigned row = 0; row < ARRAY_DIM; row++) begin
        for (int unsigned col = 0; col < ARRAY_DIM; col++) begin
          global_row_int = 32'(tile_row);
          global_row_int = global_row_int + row;
          global_col_int = 32'(tile_col);
          global_col_int = global_col_int + col;
          n_int = 32'(n_dim);
          if (row_mask[row] && col_mask[col]
              && (global_row_int < $unsigned(m_dim))
              && (global_col_int < $unsigned(n_dim))) begin
            index = (global_row_int * n_int) + global_col_int;
            expected_addr[expected_writes] = SPAD_ADDR_W'(index);
            if (quant_enable) begin
              quantized = quant_reference(tile_data[row][col], relu_enable,
                                          quant_shift);
              expected_data[expected_writes] = {{24{quantized[7]}}, quantized};
            end else begin
              expected_data[expected_writes] = $unsigned(tile_data[row][col]);
            end
            expected_writes++;
          end
        end
      end
    end
  endtask

  always @(posedge clk) begin
    if (rst_n && scoreboard_active && sram_wr_en) begin
      if (observed_writes >= expected_writes) begin
        fail("write scoreboard", "unexpected extra SRAM write");
      end
      checks += 2;
      if (sram_wr_addr !== expected_addr[observed_writes]) begin
        fail("write scoreboard", "SRAM address mismatch");
      end
      if (sram_wr_data !== expected_data[observed_writes]) begin
        fail("write scoreboard", "SRAM data mismatch");
      end
      observed_writes <= observed_writes + 1;
    end
  end

  task automatic set_masks;
    begin
      for (int unsigned lane = 0; lane < ARRAY_DIM; lane++) begin
        row_mask[lane] = (((DIM_W + 1)'(tile_row)
                         + (DIM_W + 1)'(lane)) < (DIM_W + 1)'(m_dim));
        col_mask[lane] = (((DIM_W + 1)'(tile_col)
                         + (DIM_W + 1)'(lane)) < (DIM_W + 1)'(n_dim));
      end
    end
  endtask

  task automatic fill_pattern(input int signed base);
    begin
      for (int unsigned row = 0; row < ARRAY_DIM; row++) begin
        for (int unsigned col = 0; col < ARRAY_DIM; col++) begin
          tile_data[row][col] = base + int'(row * 10) + int'(col);
        end
      end
    end
  endtask

  task automatic run_tile(input bit hold_valid_busy, input string label);
    int unsigned timeout;
    begin
      build_expected();
      observed_writes = 0;
      scoreboard_active = 1'b1;

      @(negedge clk);
      if (!tile_ready) begin
        fail(label, "writer was not ready before tile input");
      end
      tile_valid = 1'b1;
      @(posedge clk);
      #1;
      checks += 2;
      if (!busy || tile_ready) begin
        fail(label, "tile handshake did not start serialization");
      end

      if (!hold_valid_busy) begin
        @(negedge clk);
        tile_valid = 1'b0;
      end else begin
        for (int unsigned row = 0; row < ARRAY_DIM; row++) begin
          for (int unsigned col = 0; col < ARRAY_DIM; col++) begin
            tile_data[row][col] = -32'sd9999;
          end
        end
      end

      timeout = 0;
      while (!tile_done) begin
        @(negedge clk);
        timeout++;
        if (timeout > 40) begin
          fail(label, "timeout waiting for tile completion");
        end
        if (busy && tile_ready) begin
          fail(label, "tile_ready asserted while writer was busy");
        end
      end

      if (hold_valid_busy) begin
        tile_valid = 1'b0;
      end
      checks += 4;
      if ((observed_writes != expected_writes) || busy || !tile_ready) begin
        fail(label, "incorrect write count or final handshake state");
      end
      scoreboard_active = 1'b0;

      @(posedge clk);
      #1;
      if (tile_done || sram_wr_en) begin
        fail(label, "completion pulse or write lasted too long");
      end
    end
  endtask

  initial begin
    clk          = 1'b0;
    rst_n        = 1'b1;
    tile_valid   = 1'b0;
    tile_row     = '0;
    tile_col     = '0;
    row_mask     = '0;
    col_mask     = '0;
    m_dim        = '0;
    n_dim        = '0;
    quant_enable = 1'b0;
    relu_enable  = 1'b0;
    quant_shift  = '0;
    expected_writes = 0;
    observed_writes = 0;
    scoreboard_active = 1'b0;
    checks = 0;
    fill_pattern(0);

    #1;
    rst_n = 1'b0;
    #1;
    checks += 4;
    if (!tile_ready || busy || tile_done || sram_wr_en) begin
      fail("reset", "writer did not reset to idle");
    end
    @(negedge clk);
    rst_n = 1'b1;

    m_dim = 4;
    n_dim = 4;
    tile_row = 0;
    tile_col = 0;
    fill_pattern(0);
    set_masks();
    quant_enable = 1'b0;
    run_tile(1'b0, "full 4x4 INT32 tile");
    if (expected_writes != 16) begin
      fail("full 4x4 INT32 tile", "expected count was not 16");
    end

    m_dim = 6;
    n_dim = 5;
    tile_row = 4;
    tile_col = 4;
    fill_pattern(100);
    set_masks();
    run_tile(1'b0, "partial row and column tile");
    checks += 3;
    if ((expected_writes != 2) || (expected_addr[0] != 24)
        || (expected_addr[1] != 29)) begin
      fail("partial row and column tile", "edge addresses are incorrect");
    end

    m_dim = 4;
    n_dim = 6;
    tile_row = 0;
    tile_col = 4;
    fill_pattern(200);
    set_masks();
    run_tile(1'b0, "partial columns");
    checks++;
    if (expected_writes != 8) begin
      fail("partial columns", "expected count was not 8");
    end

    m_dim = 1;
    n_dim = 4;
    tile_row = 0;
    tile_col = 0;
    row_mask = 4'b0001;
    col_mask = 4'b1111;
    tile_data[0][0] = 32'sd126;
    tile_data[0][1] = -32'sd3;
    tile_data[0][2] = 32'sd1000;
    tile_data[0][3] = -32'sd1000;
    quant_enable = 1'b1;
    relu_enable = 1'b0;
    quant_shift = 0;
    run_tile(1'b0, "quantization saturation");

    tile_data[0][0] = -32'sd9;
    tile_data[0][1] = 32'sd20;
    tile_data[0][2] = 32'sd508;
    tile_data[0][3] = 32'sd512;
    relu_enable = 1'b1;
    quant_shift = 2;
    run_tile(1'b0, "quantization shift and ReLU");

    m_dim = 1;
    n_dim = 1;
    tile_row = 0;
    tile_col = 0;
    row_mask = 4'b0001;
    col_mask = 4'b0001;
    quant_enable = 1'b0;
    tile_data[0][0] = -32'sd77;
    run_tile(1'b1, "latched tile handshake");
    checks++;
    if (expected_writes != 1) begin
      fail("latched tile handshake", "1x1 output did not write once");
    end

    $display("tb_output_tile_writer PASS (%0d self-checks)", checks);
    $finish;
  end

endmodule
