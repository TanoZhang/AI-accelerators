module simple_dma #(
  parameter int unsigned SPAD_DEPTH  = 1024,
  parameter int unsigned SPAD_ADDR_W = (SPAD_DEPTH > 1) ? $clog2(SPAD_DEPTH) : 1
) (
  input  logic                              clk,
  input  logic                              rst_n,
  input  logic                              start,
  input  ai_accel_pkg::dma_transfer_e       direction,
  input  logic [31:0]                       src_addr,
  input  logic [31:0]                       dst_addr,
  input  logic [31:0]                       length_words,
  output logic                              busy,
  output logic                              done,
  output logic                              error,
  output logic                              mem_req_valid,
  input  logic                              mem_req_ready,
  output logic                              mem_req_write,
  output logic [31:0]                       mem_req_addr,
  output logic [31:0]                       mem_req_wdata,
  output logic [3:0]                        mem_req_wstrb,
  input  logic                              mem_rsp_valid,
  output logic                              mem_rsp_ready,
  input  logic [31:0]                       mem_rsp_rdata,
  input  logic                              mem_rsp_error,
  output logic                              activation_write_en,
  output logic [SPAD_ADDR_W-1:0]            activation_write_addr,
  output logic [31:0]                       activation_write_data,
  output logic                              weight_write_en,
  output logic [SPAD_ADDR_W-1:0]            weight_write_addr,
  output logic [31:0]                       weight_write_data,
  output logic                              output_read_en,
  output logic [SPAD_ADDR_W-1:0]            output_read_addr,
  input  logic                              output_read_valid,
  input  logic [31:0]                       output_read_data
);

  // TODO: implement one outstanding transaction at a time.
  // Validate the complete transfer before raising mem_req_valid.
  always_comb begin
    busy                  = 1'b0;
    done                  = 1'b0;
    error                 = 1'b0;
    mem_req_valid         = 1'b0;
    mem_req_write         = 1'b0;
    mem_req_addr          = '0;
    mem_req_wdata         = '0;
    mem_req_wstrb         = '0;
    mem_rsp_ready         = 1'b0;
    activation_write_en   = 1'b0;
    activation_write_addr = '0;
    activation_write_data = '0;
    weight_write_en       = 1'b0;
    weight_write_addr     = '0;
    weight_write_data     = '0;
    output_read_en        = 1'b0;
    output_read_addr      = '0;
  end

endmodule
