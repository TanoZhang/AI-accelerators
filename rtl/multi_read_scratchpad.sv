// Replication trades memory bits for independent read ports; writes fan out.
module multi_read_scratchpad #(
  parameter int unsigned DATA_W     = 8,
  parameter int unsigned DEPTH      = 1024,
  parameter int unsigned READ_PORTS = 4,
  parameter int unsigned ADDR_W     = (DEPTH > 1) ? $clog2(DEPTH) : 1
) (
  input  logic                              clk,
  input  logic                              rst_n,

  input  logic [READ_PORTS-1:0]             read_en,
  input  logic [ADDR_W-1:0]                 read_addr [0:READ_PORTS-1],
  output logic [DATA_W-1:0]                 read_data [0:READ_PORTS-1],
  output logic [READ_PORTS-1:0]             read_valid,

  input  logic                              write_en,
  input  logic [ADDR_W-1:0]                 write_addr,
  input  logic [DATA_W-1:0]                 write_data
);

  for (genvar port_index = 0; port_index < READ_PORTS; port_index++) begin : gen_read_port
    // Keep both attributes so Quartus and Vivado infer embedded RAM.
    (* ramstyle = "M20K", ram_style = "block" *)
    logic [DATA_W-1:0] memory [0:DEPTH-1];

    // Do not reset memory contents so the array can map to embedded RAM.
    always_ff @(posedge clk) begin
      if (rst_n && write_en) begin
        memory[write_addr] <= write_data;
      end
    end

    always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        read_data[port_index]  <= '0;
        read_valid[port_index] <= 1'b0;
      end else begin
        read_valid[port_index] <= read_en[port_index];
        if (read_en[port_index]) begin
          if (write_en && (read_addr[port_index] == write_addr)) begin
            read_data[port_index] <= write_data;
          end else begin
            read_data[port_index] <= memory[read_addr[port_index]];
          end
        end
      end
    end

`ifndef SYNTHESIS
    property p_legal_read_address;
      @(posedge clk) disable iff (!rst_n)
        read_en[port_index] |-> ($unsigned(read_addr[port_index]) < DEPTH);
    endproperty

    property p_read_valid_latency;
      @(posedge clk) disable iff (!rst_n)
        read_en[port_index] |=> read_valid[port_index];
    endproperty

    assert property (p_legal_read_address)
      else $error("multi_read_scratchpad port %0d read address is out of range",
                  port_index);
    assert property (p_read_valid_latency)
      else $error("multi_read_scratchpad port %0d read latency violation",
                  port_index);
`endif
  end

`ifndef SYNTHESIS
  property p_legal_write_address;
    @(posedge clk) disable iff (!rst_n)
      write_en |-> ($unsigned(write_addr) < DEPTH);
  endproperty

  assert property (p_legal_write_address)
    else $error("multi_read_scratchpad write address is out of range");
`endif

endmodule
