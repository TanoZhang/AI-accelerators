`timescale 1ns/1ps

module tb_mac_array_4x4;

  localparam int unsigned DATA_W    = 8;
  localparam int unsigned ACC_W     = 32;
  localparam int unsigned ARRAY_DIM = 4;
  localparam int unsigned NUM_JOBS  = 6;
  localparam int unsigned MAX_K     = 24;

  logic                                      clk;
  logic                                      rst_n;
  logic                                      clear_acc;
  logic                                      mac_en;
  logic signed [DATA_W-1:0]                  a_vec [0:ARRAY_DIM-1];
  logic signed [DATA_W-1:0]                  b_vec [0:ARRAY_DIM-1];
  logic signed [ACC_W-1:0]                   acc   [0:ARRAY_DIM-1]
                                                    [0:ARRAY_DIM-1];

  int signed                                 reference [0:ARRAY_DIM-1]
                                                       [0:ARRAY_DIM-1];
  int unsigned                               checks;

  mac_array_4x4 #(
    .DATA_W    (DATA_W),
    .ACC_W     (ACC_W),
    .ARRAY_DIM (ARRAY_DIM)
  ) dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .clear_acc (clear_acc),
    .mac_en    (mac_en),
    .a_vec     (a_vec),
    .b_vec     (b_vec),
    .acc       (acc)
  );

  always #5 clk = ~clk;

  function automatic logic signed [DATA_W-1:0] random_int8();
    random_int8 = $urandom_range(0, 255);
  endfunction

  task automatic zero_reference;
    for (int i = 0; i < ARRAY_DIM; i++) begin
      for (int j = 0; j < ARRAY_DIM; j++) begin
        reference[i][j] = 0;
      end
    end
  endtask

  task automatic check_all(input string label);
    for (int i = 0; i < ARRAY_DIM; i++) begin
      for (int j = 0; j < ARRAY_DIM; j++) begin
        checks++;
        if (acc[i][j] !== reference[i][j]) begin
          $error("%s: acc[%0d][%0d]=%0d (0x%08h), expected=%0d (0x%08h)",
                 label, i, j, acc[i][j], acc[i][j],
                 reference[i][j], reference[i][j]);
          $fatal(1, "tb_mac_array_4x4 failed");
        end
      end
    end
  endtask

  // Reference outer product for one k.
  task automatic update_reference;
    int signed a_value;
    int signed b_value;
    for (int i = 0; i < ARRAY_DIM; i++) begin
      for (int j = 0; j < ARRAY_DIM; j++) begin
        a_value = $signed(a_vec[i]);
        b_value = $signed(b_vec[j]);
        reference[i][j] = reference[i][j] + (a_value * b_value);
      end
    end
  endtask

  task automatic accumulate_current_vector(input string label);
    begin
      clear_acc = 1'b0;
      mac_en    = 1'b1;
      update_reference();
      @(posedge clk);
      #1;
      check_all(label);
    end
  endtask

  task automatic clear_array(input string label);
    begin
      @(negedge clk);
      clear_acc = 1'b1;
      mac_en    = 1'b1; // Also verifies clear priority over accumulation.
      for (int lane = 0; lane < ARRAY_DIM; lane++) begin
        a_vec[lane] = 8'sd127;
        b_vec[lane] = 8'sh80;
      end
      zero_reference();
      @(posedge clk);
      #1;
      check_all(label);
      @(negedge clk);
      clear_acc = 1'b0;
      mac_en    = 1'b0;
    end
  endtask

  task automatic check_disabled_hold(input int unsigned cycles);
    begin
      @(negedge clk);
      clear_acc = 1'b0;
      mac_en    = 1'b0;
      for (int cycle = 0; cycle < cycles; cycle++) begin
        for (int lane = 0; lane < ARRAY_DIM; lane++) begin
          a_vec[lane] = random_int8();
          b_vec[lane] = random_int8();
        end
        @(posedge clk);
        #1;
        check_all("disabled hold");
        if (cycle != cycles-1) begin
          @(negedge clk);
        end
      end
    end
  endtask

  initial begin
    int unsigned k_cycles;

    clk       = 1'b0;
    rst_n     = 1'b1;
    clear_acc = 1'b0;
    mac_en    = 1'b0;
    checks    = 0;
    zero_reference();
    for (int lane = 0; lane < ARRAY_DIM; lane++) begin
      a_vec[lane] = '0;
      b_vec[lane] = '0;
    end

    // Reset
    #1;
    rst_n = 1'b0;
    #1;
    check_all("asynchronous reset");
    @(negedge clk);
    rst_n = 1'b1;

    // Signed corners
    clear_array("clear before corner cases");
    @(negedge clk);
    a_vec[0] =  8'sd127;
    a_vec[1] =  8'sh80;
    a_vec[2] = -8'sd1;
    a_vec[3] =  8'sd0;
    b_vec[0] =  8'sh80;
    b_vec[1] =  8'sd127;
    b_vec[2] =  8'sd1;
    b_vec[3] = -8'sd1;
    accumulate_current_vector("signed corner vector 0");

    @(negedge clk);
    a_vec[0] =  8'sh80;
    a_vec[1] =  8'sd127;
    a_vec[2] =  8'sh80;
    a_vec[3] =  8'sd127;
    b_vec[0] =  8'sd127;
    b_vec[1] =  8'sh80;
    b_vec[2] =  8'sh80;
    b_vec[3] =  8'sd127;
    accumulate_current_vector("signed corner vector 1");
    check_disabled_hold(3);

    // Random K lengths and operands
    for (int job = 0; job < NUM_JOBS; job++) begin
      clear_array($sformatf("random job %0d clear", job));
      k_cycles = $urandom_range(1, MAX_K);

      for (int k = 0; k < k_cycles; k++) begin
        @(negedge clk);
        for (int lane = 0; lane < ARRAY_DIM; lane++) begin
          a_vec[lane] = random_int8();
          b_vec[lane] = random_int8();
        end
        accumulate_current_vector(
          $sformatf("random job %0d, K cycle %0d/%0d", job, k, k_cycles));
      end
    end

    check_disabled_hold(4);
    $display("tb_mac_array_4x4 PASS (%0d accumulator checks)", checks);
    $finish;
  end

endmodule
