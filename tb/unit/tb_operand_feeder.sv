`timescale 1ns/1ps

module tb_operand_feeder;

  localparam int unsigned DATA_W      = 8;
  localparam int unsigned DIM_W       = 16;
  localparam int unsigned ARRAY_DIM   = 4;
  localparam int unsigned SPAD_DEPTH  = 512;
  localparam int unsigned SPAD_ADDR_W = $clog2(SPAD_DEPTH);

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

  logic activation_read_en;
  logic [SPAD_ADDR_W-1:0] activation_read_addr;
  logic activation_read_valid;
  logic [DATA_W-1:0] activation_read_data_raw;
  logic activation_write_en;
  logic [SPAD_ADDR_W-1:0] activation_write_addr;
  logic [DATA_W-1:0] activation_write_data;

  logic weight_read_en;
  logic [SPAD_ADDR_W-1:0] weight_read_addr;
  logic weight_read_valid;
  logic [DATA_W-1:0] weight_read_data_raw;
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
  int unsigned expected_activation_addresses[$];
  int unsigned expected_weight_addresses[$];
  int unsigned checks;

  operand_feeder #(
    .DATA_W      (DATA_W),
    .DIM_W       (DIM_W),
    .ARRAY_DIM   (ARRAY_DIM),
    .SPAD_DEPTH  (SPAD_DEPTH),
    .SPAD_ADDR_W (SPAD_ADDR_W)
  ) dut (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .start_pulse            (start_pulse),
    .m_dim                  (m_dim),
    .n_dim                  (n_dim),
    .k_dim                  (k_dim),
    .tile_row               (tile_row),
    .tile_col               (tile_col),
    .busy                   (busy),
    .done_pulse             (done_pulse),
    .activation_read_en     (activation_read_en),
    .activation_read_addr   (activation_read_addr),
    .activation_read_valid  (activation_read_valid),
    .activation_read_data   (activation_read_data_raw),
    .weight_read_en         (weight_read_en),
    .weight_read_addr       (weight_read_addr),
    .weight_read_valid      (weight_read_valid),
    .weight_read_data       (weight_read_data_raw),
    .compute_valid          (compute_valid),
    .compute_ready          (compute_ready),
    .a_vec                  (a_vec),
    .b_vec                  (b_vec),
    .row_mask               (row_mask),
    .col_mask               (col_mask),
    .last_k                 (last_k)
  );

  scratchpad_sram #(
    .DATA_W (DATA_W),
    .DEPTH  (SPAD_DEPTH),
    .ADDR_W (SPAD_ADDR_W)
  ) activation_sram (
    .clk        (clk),
    .rst_n      (rst_n),
    .read_en    (activation_read_en),
    .read_addr  (activation_read_addr),
    .read_data  (activation_read_data_raw),
    .read_valid (activation_read_valid),
    .write_en   (activation_write_en),
    .write_addr (activation_write_addr),
    .write_data (activation_write_data)
  );

  scratchpad_sram #(
    .DATA_W (DATA_W),
    .DEPTH  (SPAD_DEPTH),
    .ADDR_W (SPAD_ADDR_W)
  ) weight_sram (
    .clk        (clk),
    .rst_n      (rst_n),
    .read_en    (weight_read_en),
    .read_addr  (weight_read_addr),
    .read_data  (weight_read_data_raw),
    .read_valid (weight_read_valid),
    .write_en   (weight_write_en),
    .write_addr (weight_write_addr),
    .write_data (weight_write_data)
  );

  always #5 clk = ~clk;

  task automatic fail(input string label, input string detail);
    begin
      $error("%s: %s", label, detail);
      $fatal(1, "tb_operand_feeder failed");
    end
  endtask

  function automatic logic signed [DATA_W-1:0] matrix_value(
    input int unsigned address,
    input bit          is_weight
  );
    int signed value;
    begin
      case (address % 8)
        0: matrix_value = 8'sh80;
        1: matrix_value = 8'sd127;
        2: matrix_value = -8'sd1;
        3: matrix_value = 8'sd1;
        default: begin
          value = ((address * 29) + (is_weight ? 17 : 3)) % 255;
          matrix_value = value - 127;
        end
      endcase
    end
  endfunction

  task automatic write_activation(
    input int unsigned address,
    input logic signed [DATA_W-1:0] data
  );
    begin
      @(negedge clk);
      activation_write_en   = 1'b1;
      activation_write_addr = address[SPAD_ADDR_W-1:0];
      activation_write_data = data;
      @(posedge clk);
      activation_model[address] = data;
      @(negedge clk);
      activation_write_en = 1'b0;
    end
  endtask

  task automatic write_weight(
    input int unsigned address,
    input logic signed [DATA_W-1:0] data
  );
    begin
      @(negedge clk);
      weight_write_en   = 1'b1;
      weight_write_addr = address[SPAD_ADDR_W-1:0];
      weight_write_data = data;
      @(posedge clk);
      weight_model[address] = data;
      @(negedge clk);
      weight_write_en = 1'b0;
    end
  endtask

  task automatic load_matrices(
    input int unsigned m_value,
    input int unsigned n_value,
    input int unsigned k_value
  );
    logic signed [DATA_W-1:0] data;
    begin
      for (int address = 0; address < m_value*k_value; address++) begin
        data = matrix_value(address, 1'b0);
        write_activation(address, data);
      end
      for (int address = 0; address < k_value*n_value; address++) begin
        data = matrix_value(address, 1'b1);
        write_weight(address, data);
      end
    end
  endtask

  task automatic build_expected_addresses(
    input int unsigned m_value,
    input int unsigned n_value,
    input int unsigned k_value,
    input int unsigned tile_row_value,
    input int unsigned tile_col_value
  );
    begin
      expected_activation_addresses.delete();
      expected_weight_addresses.delete();
      for (int k = 0; k < k_value; k++) begin
        for (int lane = 0; lane < ARRAY_DIM; lane++) begin
          if ((tile_row_value + lane) < m_value) begin
            expected_activation_addresses.push_back(
              ((tile_row_value + lane) * k_value) + k);
          end
          if ((tile_col_value + lane) < n_value) begin
            expected_weight_addresses.push_back(
              (k * n_value) + tile_col_value + lane);
          end
        end
      end
    end
  endtask

  task automatic check_compute_payload(
    input int unsigned expected_k,
    input int unsigned m_value,
    input int unsigned n_value,
    input int unsigned k_value,
    input int unsigned tile_row_value,
    input int unsigned tile_col_value,
    input string       label
  );
    logic signed [DATA_W-1:0] expected_a;
    logic signed [DATA_W-1:0] expected_b;
    logic expected_row_valid;
    logic expected_col_valid;
    begin
      checks++;
      if (last_k !== (expected_k == k_value-1)) begin
        fail(label, "last_k is incorrect");
      end

      for (int lane = 0; lane < ARRAY_DIM; lane++) begin
        expected_row_valid = (tile_row_value + lane) < m_value;
        expected_col_valid = (tile_col_value + lane) < n_value;
        expected_a = expected_row_valid
                   ? activation_model[((tile_row_value + lane) * k_value)
                                      + expected_k]
                   : '0;
        expected_b = expected_col_valid
                   ? weight_model[(expected_k * n_value) + tile_col_value + lane]
                   : '0;

        checks += 4;
        if (row_mask[lane] !== expected_row_valid) begin
          fail(label, $sformatf("row mask lane %0d is incorrect", lane));
        end
        if (col_mask[lane] !== expected_col_valid) begin
          fail(label, $sformatf("column mask lane %0d is incorrect", lane));
        end
        if (a_vec[lane] !== expected_a) begin
          $error("%s: a_vec[%0d]=%0d expected=%0d",
                 label, lane, a_vec[lane], expected_a);
          $fatal(1, "activation operand mismatch");
        end
        if (b_vec[lane] !== expected_b) begin
          $error("%s: b_vec[%0d]=%0d expected=%0d",
                 label, lane, b_vec[lane], expected_b);
          $fatal(1, "weight operand mismatch");
        end
      end
    end
  endtask

  task automatic run_tile(
    input int unsigned m_value,
    input int unsigned n_value,
    input int unsigned k_value,
    input int unsigned tile_row_value,
    input int unsigned tile_col_value,
    input string       label
  );
    int unsigned accepted_k;
    int unsigned timeout;
    bit forced_stall;
    bit finished;
    begin
      load_matrices(m_value, n_value, k_value);
      build_expected_addresses(m_value, n_value, k_value,
                               tile_row_value, tile_col_value);

      @(negedge clk);
      m_dim         = m_value;
      n_dim         = n_value;
      k_dim         = k_value;
      tile_row      = tile_row_value;
      tile_col      = tile_col_value;
      start_pulse   = 1'b1;
      compute_ready = 1'b0;
      @(posedge clk);
      #1;
      if (busy !== 1'b1) begin
        fail(label, "start was not accepted");
      end
      @(negedge clk);
      start_pulse = 1'b0;

      accepted_k = 0;
      timeout     = 0;
      forced_stall = 1'b0;
      finished    = 1'b0;

      while (!finished) begin
        @(negedge clk);
        timeout++;
        if (timeout > 1000) begin
          fail(label, "timeout waiting for feeder completion");
        end

        if (done_pulse) begin
          finished = 1'b1;
        end else begin
          if (compute_valid && !forced_stall) begin
            compute_ready = 1'b0;
            forced_stall  = 1'b1;
          end else begin
            compute_ready = ($urandom_range(0, 3) != 0);
          end

          if (compute_valid) begin
            check_compute_payload(accepted_k, m_value, n_value, k_value,
                                  tile_row_value, tile_col_value, label);
            if (compute_ready) begin
              accepted_k++;
            end
          end
        end
      end

      checks += 4;
      if (accepted_k != k_value) begin
        fail(label, "incorrect number of accepted K vectors");
      end
      if (busy !== 1'b0) begin
        fail(label, "busy remained high after completion");
      end
      if (expected_activation_addresses.size() != 0) begin
        fail(label, "not all expected activation reads were issued");
      end
      if (expected_weight_addresses.size() != 0) begin
        fail(label, "not all expected weight reads were issued");
      end

      compute_ready = 1'b0;
    end
  endtask

  always @(posedge clk) begin
    int unsigned expected_address;
    if (rst_n && activation_read_en) begin
      checks++;
      if (expected_activation_addresses.size() == 0) begin
        fail("activation address monitor", "unexpected read request");
      end
      expected_address = expected_activation_addresses.pop_front();
      if (activation_read_addr !== expected_address[SPAD_ADDR_W-1:0]) begin
        $error("activation address=%0d expected=%0d",
               activation_read_addr, expected_address);
        $fatal(1, "activation row-major address mismatch");
      end
    end

    if (rst_n && weight_read_en) begin
      checks++;
      if (expected_weight_addresses.size() == 0) begin
        fail("weight address monitor", "unexpected read request");
      end
      expected_address = expected_weight_addresses.pop_front();
      if (weight_read_addr !== expected_address[SPAD_ADDR_W-1:0]) begin
        $error("weight address=%0d expected=%0d",
               weight_read_addr, expected_address);
        $fatal(1, "weight row-major address mismatch");
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

    #1;
    rst_n = 1'b0;
    #1;
    if ((busy !== 1'b0) || (done_pulse !== 1'b0)
        || (compute_valid !== 1'b0)) begin
      fail("reset", "control outputs did not reset");
    end
    @(negedge clk);
    rst_n = 1'b1;

    run_tile(4, 4, 1, 0, 0, "4x4 K=1");
    run_tile(7, 6, 3, 0, 0, "larger dimensions interior tile");
    run_tile(7, 6, 5, 4, 4, "larger dimensions edge tile");
    run_tile(5, 7, 2, 4, 4, "non-multiple edge tile");

    $display("tb_operand_feeder PASS (%0d self-checks)", checks);
    $finish;
  end

endmodule
