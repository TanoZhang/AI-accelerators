`timescale 1ns/1ps

module tb_multi_read_scratchpad;

  localparam int unsigned DATA_W     = 8;
  localparam int unsigned DEPTH      = 32;
  localparam int unsigned READ_PORTS = 4;
  localparam int unsigned ADDR_W     = $clog2(DEPTH);

  logic clk;
  logic rst_n;
  logic [READ_PORTS-1:0] read_en;
  logic [ADDR_W-1:0] read_addr [0:READ_PORTS-1];
  logic [DATA_W-1:0] read_data [0:READ_PORTS-1];
  logic [READ_PORTS-1:0] read_valid;
  logic write_en;
  logic [ADDR_W-1:0] write_addr;
  logic [DATA_W-1:0] write_data;
  int unsigned checks;

  multi_read_scratchpad #(
    .DATA_W     (DATA_W),
    .DEPTH      (DEPTH),
    .READ_PORTS (READ_PORTS),
    .ADDR_W     (ADDR_W)
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

  task automatic fail(input string detail);
    begin
      $error("%s", detail);
      $fatal(1, "tb_multi_read_scratchpad failed");
    end
  endtask

  task automatic write_word(
    input int unsigned address,
    input logic [DATA_W-1:0] data
  );
    begin
      @(negedge clk);
      write_en   = 1'b1;
      write_addr = ADDR_W'(address);
      write_data = data;
      @(posedge clk);
      #1;
      @(negedge clk);
      write_en = 1'b0;
    end
  endtask

  initial begin
    clk        = 1'b0;
    rst_n      = 1'b1;
    read_en    = '0;
    write_en   = 1'b0;
    write_addr = '0;
    write_data = '0;
    checks     = 0;
    for (int unsigned port_index = 0;
         port_index < READ_PORTS; port_index++) begin
      read_addr[port_index] = '0;
    end

    #1;
    rst_n = 1'b0;
    #1;
    checks++;
    if (read_valid !== '0) begin
      fail("read_valid was asserted during reset");
    end
    @(negedge clk);
    rst_n = 1'b1;

    write_word(3, 8'h13);
    write_word(7, 8'h27);
    write_word(11, 8'h8B);
    write_word(19, 8'hD3);

    @(negedge clk);
    read_en      = 4'b1111;
    read_addr[0] = ADDR_W'(3);
    read_addr[1] = ADDR_W'(7);
    read_addr[2] = ADDR_W'(11);
    read_addr[3] = ADDR_W'(19);
    @(posedge clk);
    #1;
    checks += 5;
    if (read_valid !== 4'b1111) begin
      fail("parallel read-valid vector mismatch");
    end
    if ((read_data[0] !== 8'h13) || (read_data[1] !== 8'h27)
        || (read_data[2] !== 8'h8B) || (read_data[3] !== 8'hD3)) begin
      fail("parallel read data mismatch");
    end

    // Verify that a broadcast write is visible through every replica and that
    // the documented same-address behavior is write-first.
    @(negedge clk);
    read_en      = 4'b1111;
    write_en     = 1'b1;
    write_addr   = ADDR_W'(5);
    write_data   = 8'hA5;
    for (int unsigned port_index = 0;
         port_index < READ_PORTS; port_index++) begin
      read_addr[port_index] = ADDR_W'(5);
    end
    @(posedge clk);
    #1;
    checks += 5;
    if (read_valid !== 4'b1111) begin
      fail("write-first read-valid vector mismatch");
    end
    for (int unsigned port_index = 0;
         port_index < READ_PORTS; port_index++) begin
      if (read_data[port_index] !== 8'hA5) begin
        fail("broadcast write did not update every memory replica");
      end
    end

    @(negedge clk);
    read_en  = 4'b0101;
    write_en = 1'b0;
    @(posedge clk);
    #1;
    checks++;
    if (read_valid !== 4'b0101) begin
      fail("per-port read enable was not preserved");
    end

    @(negedge clk);
    read_en = '0;
    @(posedge clk);
    #1;
    checks++;
    if (read_valid !== '0) begin
      fail("read_valid persisted without a request");
    end

    $display("tb_multi_read_scratchpad PASS (%0d self-checks)", checks);
    $finish;
  end

endmodule
