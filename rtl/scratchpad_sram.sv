// Single-clock, one-read/one-write scratchpad.
// Reads are registered for one cycle. Same-address collisions are write-first.
// Reset clears the read interface; memory remains undefined until written.
module scratchpad_sram #(
  parameter int unsigned DATA_W = 32,
  parameter int unsigned DEPTH  = 1024,
  parameter int unsigned ADDR_W = (DEPTH > 1) ? $clog2(DEPTH) : 1
) (
  input  logic                  clk,
  input  logic                  rst_n,

  input  logic                  read_en,
  input  logic [ADDR_W-1:0]     read_addr,
  output logic [DATA_W-1:0]     read_data,
  output logic                  read_valid,

  input  logic                  write_en,
  input  logic [ADDR_W-1:0]     write_addr,
  input  logic [DATA_W-1:0]     write_data
);

  logic [DATA_W-1:0] memory [0:DEPTH-1];

  // Do not add a reset to the memory array.
  always_ff @(posedge clk) begin
    if (rst_n && write_en) begin
      memory[write_addr] <= write_data;
    end
  end

  // The bypass fixes same-address behavior across memory implementations.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      read_data  <= '0;
      read_valid <= 1'b0;
    end else begin
      read_valid <= read_en;
      if (read_en) begin
        if (write_en && (read_addr == write_addr)) begin
          read_data <= write_data;
        end else begin
          read_data <= memory[read_addr];
        end
      end
    end
  end

`ifndef SYNTHESIS
  property p_legal_read_address;
    @(posedge clk) disable iff (!rst_n)
      read_en |-> ($unsigned(read_addr) < DEPTH);
  endproperty

  property p_legal_write_address;
    @(posedge clk) disable iff (!rst_n)
      write_en |-> ($unsigned(write_addr) < DEPTH);
  endproperty

  property p_read_valid_latency;
    @(posedge clk) disable iff (!rst_n)
      read_en |=> read_valid;
  endproperty

  property p_no_spurious_read_valid;
    @(posedge clk) disable iff (!rst_n)
      !read_en |=> !read_valid;
  endproperty

  property p_write_first_collision;
    @(posedge clk) disable iff (!rst_n)
      (read_en && write_en && (read_addr == write_addr))
      |=> (read_valid && (read_data == $past(write_data)));
  endproperty

  assert property (p_legal_read_address)
    else $error("scratchpad_sram read address is outside DEPTH");

  assert property (p_legal_write_address)
    else $error("scratchpad_sram write address is outside DEPTH");

  assert property (p_read_valid_latency)
    else $error("scratchpad_sram read response latency violation");

  assert property (p_no_spurious_read_valid)
    else $error("scratchpad_sram asserted read_valid without a read request");

  assert property (p_write_first_collision)
    else $error("scratchpad_sram same-address collision was not write-first");
`endif

endmodule
