`timescale 1ns/1ps

module tb_scratchpad_sram;

  localparam int unsigned DATA_W = 32;
  localparam int unsigned DEPTH  = 1024;
  localparam int unsigned ADDR_W = $clog2(DEPTH);
  localparam int unsigned RANDOM_TESTS = 100;

  logic                   clk;
  logic                   rst_n;
  logic                   read_en;
  logic [ADDR_W-1:0]      read_addr;
  logic [DATA_W-1:0]      read_data;
  logic                   read_valid;
  logic                   write_en;
  logic [ADDR_W-1:0]      write_addr;
  logic [DATA_W-1:0]      write_data;

  logic [DATA_W-1:0]      reference_memory [0:DEPTH-1];
  int unsigned            checks;

  scratchpad_sram #(
    .DATA_W (DATA_W),
    .DEPTH  (DEPTH),
    .ADDR_W (ADDR_W)
  ) dut (
    .clk        (clk),
    .rst_n      (rst_n),
    .read_en    (read_en),
    .read_addr  (read_addr),
    .read_data  (read_data),
    .read_valid (read_valid),
    .write_en   (write_en),
    .write_addr (write_addr),
    .write_data (write_data)
  );

  always #5 clk = ~clk;

  task automatic fail(input string label, input string detail);
    begin
      $error("%s: %s", label, detail);
      $fatal(1, "tb_scratchpad_sram failed");
    end
  endtask

  task automatic write_word(
    input logic [ADDR_W-1:0] address,
    input logic [DATA_W-1:0] data,
    input string             label
  );
    begin
      @(negedge clk);
      read_en   = 1'b0;
      write_en  = 1'b1;
      write_addr = address;
      write_data = data;

      @(posedge clk);
      #1;
      reference_memory[address] = data;
      checks++;
      if (read_valid !== 1'b0) begin
        fail(label, "write-only cycle unexpectedly produced read_valid");
      end

      @(negedge clk);
      write_en = 1'b0;
    end
  endtask

  task automatic read_and_check(
    input logic [ADDR_W-1:0] address,
    input string             label
  );
    begin
      @(negedge clk);
      write_en = 1'b0;
      read_en  = 1'b1;
      read_addr = address;

      // Response must wait for the clock edge.
      #1;
      checks++;
      if (read_valid !== 1'b0) begin
        fail(label, "read_valid asserted before the registered read edge");
      end

      @(posedge clk);
      #1;
      checks++;
      if (read_valid !== 1'b1) begin
        fail(label, "registered read response did not assert read_valid");
      end
      if (read_data !== reference_memory[address]) begin
        $error("%s: address=%0d data=0x%08h expected=0x%08h",
               label, address, read_data, reference_memory[address]);
        $fatal(1, "tb_scratchpad_sram data mismatch");
      end

      @(negedge clk);
      read_en = 1'b0;
      @(posedge clk);
      #1;
      checks++;
      if (read_valid !== 1'b0) begin
        fail(label, "read_valid did not deassert after read_en");
      end
    end
  endtask

  task automatic simultaneous_same_address(
    input logic [ADDR_W-1:0] address,
    input logic [DATA_W-1:0] new_data
  );
    begin
      @(negedge clk);
      read_en    = 1'b1;
      read_addr  = address;
      write_en   = 1'b1;
      write_addr = address;
      write_data = new_data;

      @(posedge clk);
      #1;
      reference_memory[address] = new_data;
      checks++;
      if ((read_valid !== 1'b1) || (read_data !== new_data)) begin
        $error("same-address collision: data=0x%08h expected new data=0x%08h",
               read_data, new_data);
        $fatal(1, "write-first behavior failed");
      end

      @(negedge clk);
      read_en  = 1'b0;
      write_en = 1'b0;
      @(posedge clk);
      #1;
      checks++;
      if (read_valid !== 1'b0) begin
        fail("same-address collision", "read_valid did not return low");
      end
    end
  endtask

  task automatic simultaneous_different_addresses(
    input logic [ADDR_W-1:0] read_address,
    input logic [ADDR_W-1:0] write_address_value,
    input logic [DATA_W-1:0] new_data
  );
    logic [DATA_W-1:0] expected_read_data;
    begin
      expected_read_data = reference_memory[read_address];
      @(negedge clk);
      read_en    = 1'b1;
      read_addr  = read_address;
      write_en   = 1'b1;
      write_addr = write_address_value;
      write_data = new_data;

      @(posedge clk);
      #1;
      reference_memory[write_address_value] = new_data;
      checks++;
      if ((read_valid !== 1'b1) || (read_data !== expected_read_data)) begin
        $error("different-address simultaneous access: read data=0x%08h expected=0x%08h",
               read_data, expected_read_data);
        $fatal(1, "independent read/write behavior failed");
      end

      @(negedge clk);
      read_en  = 1'b0;
      write_en = 1'b0;
      @(posedge clk);
      #1;
      checks++;
      if (read_valid !== 1'b0) begin
        fail("different-address access", "read_valid did not return low");
      end
    end
  endtask

  initial begin
    logic [ADDR_W-1:0] random_address;
    logic [DATA_W-1:0] random_data;

    clk        = 1'b0;
    rst_n      = 1'b1;
    read_en    = 1'b0;
    read_addr  = '0;
    write_en   = 1'b0;
    write_addr = '0;
    write_data = '0;
    checks     = 0;

    // Memory contents are not checked until written.
    #1;
    rst_n = 1'b0;
    #1;
    checks++;
    if ((read_valid !== 1'b0) || (read_data !== '0)) begin
      fail("initial reset", "read interface registers did not reset");
    end
    @(negedge clk);
    rst_n = 1'b1;

    // Sequential addresses
    for (int address = 0; address < 16; address++) begin
      write_word(address[ADDR_W-1:0], 32'h1000_0000 + address,
                 $sformatf("sequential write %0d", address));
    end
    for (int address = 0; address < 16; address++) begin
      read_and_check(address[ADDR_W-1:0],
                     $sformatf("sequential read %0d", address));
    end

    // Upper boundary
    write_word(ADDR_W'(DEPTH-1), 32'hDEAD_BEEF, "upper boundary write");
    read_and_check(ADDR_W'(DEPTH-1), "upper boundary read");

    // Overwrite
    write_word(ADDR_W'(7), 32'h0123_4567, "overwrite address 7");
    write_word(ADDR_W'(7), 32'h89AB_CDEF, "second overwrite address 7");
    read_and_check(ADDR_W'(7), "overwrite readback");

    // Random addresses
    for (int test_index = 0; test_index < RANDOM_TESTS; test_index++) begin
      random_address = $urandom_range(0, DEPTH-1);
      random_data    = $urandom;
      write_word(random_address, random_data,
                 $sformatf("random write %0d", test_index));
      read_and_check(random_address,
                     $sformatf("random read %0d", test_index));
    end

    // Simultaneous accesses
    write_word(ADDR_W'(42), 32'hAAAA_5555, "collision preload");
    simultaneous_same_address(ADDR_W'(42), 32'h55AA_0FF0);
    read_and_check(ADDR_W'(42), "collision readback");

    write_word(ADDR_W'(43), 32'hCAFE_BABE, "independent read preload");
    write_word(ADDR_W'(44), 32'h1111_2222, "independent write preload");
    simultaneous_different_addresses(ADDR_W'(43), ADDR_W'(44),
                                     32'h3333_4444);
    read_and_check(ADDR_W'(43), "independent read address unchanged");
    read_and_check(ADDR_W'(44), "independent write address updated");

    // Reset during a response
    @(negedge clk);
    read_en   = 1'b1;
    read_addr = ADDR_W'(42);
    @(posedge clk);
    #1;
    checks++;
    if (read_valid !== 1'b1) begin
      fail("reset precondition", "expected a valid read response");
    end
    #2;
    rst_n = 1'b0;
    #1;
    checks++;
    if ((read_valid !== 1'b0) || (read_data !== '0)) begin
      fail("asynchronous reset", "read interface did not clear immediately");
    end

    @(negedge clk);
    rst_n   = 1'b1;
    read_en = 1'b0;
    @(posedge clk);
    #1;
    checks++;
    if (read_valid !== 1'b0) begin
      fail("post-reset", "read_valid asserted without a new request");
    end

    $display("tb_scratchpad_sram PASS (%0d self-checks)", checks);
    $finish;
  end

endmodule
