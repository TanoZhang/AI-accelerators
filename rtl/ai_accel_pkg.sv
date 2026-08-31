// Shared types, constants, and arithmetic helpers.
package ai_accel_pkg;

  // Compute geometry
  parameter int unsigned ARRAY_ROWS    = 4;
  parameter int unsigned ARRAY_COLS    = 4;
  parameter int unsigned ARRAY_LANES   = ARRAY_ROWS * ARRAY_COLS;

  // Default widths and limits
  parameter int unsigned DATA_W        = 8;
  parameter int unsigned ACC_W         = 32;
  parameter int unsigned ADDR_W        = 32;
  parameter int unsigned APB_ADDR_W    = 12;
  parameter int unsigned DIM_W         = 16;
  parameter int unsigned MAX_K         = 1024;

  typedef logic signed [DATA_W-1:0] int8_t;
  typedef logic signed [ACC_W-1:0]  int32_t;
  typedef logic        [ADDR_W-1:0] addr_t;
  typedef logic        [DIM_W-1:0]  dim_t;
  typedef logic        [ARRAY_ROWS-1:0] row_mask_t;
  typedef logic        [ARRAY_COLS-1:0] col_mask_t;
  typedef logic        [ARRAY_LANES-1:0] elem_mask_t;

  // STATUS.STATE encoding
  typedef enum logic [3:0] {
    ACCEL_IDLE       = 4'd0,
    ACCEL_LOAD       = 4'd1,
    ACCEL_CLEAR      = 4'd2,
    ACCEL_COMPUTE    = 4'd3,
    ACCEL_CAPTURE    = 4'd4,
    ACCEL_WRITEBACK  = 4'd5,
    ACCEL_NEXT_TILE  = 4'd6,
    ACCEL_DONE       = 4'd7,
    ACCEL_ERROR      = 4'd8
  } accel_state_e;

  typedef enum logic [3:0] {
    ERR_NONE         = 4'd0,
    ERR_INVALID_DIM  = 4'd1,
    ERR_ADDR_ALIGN   = 4'd2,
    ERR_START_BUSY   = 4'd3,
    ERR_DMA_READ     = 4'd4,
    ERR_DMA_WRITE    = 4'd5,
    ERR_INTERNAL     = 4'd6
  } error_code_e;

  typedef enum logic [1:0] {
    DMA_MATRIX_A = 2'd0,
    DMA_MATRIX_B = 2'd1,
    DMA_MATRIX_C = 2'd2
  } dma_matrix_e;

  typedef enum logic {
    DMA_LOAD  = 1'b0,
    DMA_STORE = 1'b1
  } dma_direction_e;

  typedef enum logic [1:0] {
    DMA_MEM_TO_ACTIVATION = 2'd0,
    DMA_MEM_TO_WEIGHT     = 2'd1,
    DMA_OUTPUT_TO_MEM     = 2'd2
  } dma_transfer_e;

  // Active job configuration
  typedef struct packed {
    dim_t       m;
    dim_t       n;
    dim_t       k;
    addr_t      a_base;
    addr_t      b_base;
    addr_t      c_base;
    logic [4:0] quant_shift;
    logic       output_int8;
    logic       relu_enable;
  } job_cfg_t;

  // Logical tile transfer
  typedef struct packed {
    dma_matrix_e    matrix;
    dma_direction_e direction;
    addr_t          base_addr;
    dim_t           m_dim;
    dim_t           n_dim;
    dim_t           k_dim;
    dim_t           tile_m;
    dim_t           tile_n;
    dim_t           k_start;
    dim_t           k_count;
    row_mask_t      row_mask;
    col_mask_t      col_mask;
    logic           output_int8;
  } dma_cmd_t;

  // APB byte offsets
  localparam logic [APB_ADDR_W-1:0] CSR_CONTROL          = 12'h000;
  localparam logic [APB_ADDR_W-1:0] CSR_STATUS           = 12'h004;
  localparam logic [APB_ADDR_W-1:0] CSR_M                = 12'h008;
  localparam logic [APB_ADDR_W-1:0] CSR_N                = 12'h00C;
  localparam logic [APB_ADDR_W-1:0] CSR_K                = 12'h010;
  localparam logic [APB_ADDR_W-1:0] CSR_SRC_A_ADDR       = 12'h014;
  localparam logic [APB_ADDR_W-1:0] CSR_SRC_B_ADDR       = 12'h018;
  localparam logic [APB_ADDR_W-1:0] CSR_DST_ADDR         = 12'h01C;
  localparam logic [APB_ADDR_W-1:0] CSR_QUANT_CONFIG     = 12'h020;
  localparam logic [APB_ADDR_W-1:0] CSR_INT_ENABLE       = 12'h024;
  localparam logic [APB_ADDR_W-1:0] CSR_INT_STATUS       = 12'h028;
  localparam logic [APB_ADDR_W-1:0] CSR_PERF_CYCLES      = 12'h02C;
  localparam logic [APB_ADDR_W-1:0] CSR_PERF_MAC_CYCLES  = 12'h030;
  localparam logic [APB_ADDR_W-1:0] CSR_PERF_COMPUTE_CYCLES = 12'h034;
  localparam logic [APB_ADDR_W-1:0] CSR_PERF_DMA_CYCLES     = 12'h038;
  localparam logic [APB_ADDR_W-1:0] CSR_PERF_STALL_CYCLES   = 12'h03C;

  // Row-major tile mask
  function automatic elem_mask_t make_elem_mask(
    input row_mask_t row_mask,
    input col_mask_t col_mask
  );
    elem_mask_t result;
    int unsigned row;
    int unsigned col;
    begin
      result = '0;
      for (row = 0; row < ARRAY_ROWS; row++) begin
        for (col = 0; col < ARRAY_COLS; col++) begin
          result[(row * ARRAY_COLS) + col] = row_mask[row] & col_mask[col];
        end
      end
      return result;
    end
  endfunction

  // Apply ReLU, shift, then saturate.
  function automatic int8_t requantize_int32(
    input int32_t    value,
    input logic [4:0] shift,
    input logic       relu_enable
  );
    int32_t relu_value;
    int32_t shifted;
    int8_t  saturated;
    begin
      relu_value = value;
      if (relu_enable && (value < 32'sd0)) begin
        relu_value = 32'sd0;
      end
      shifted = relu_value >>> shift;

      if (shifted > 32'sd127) begin
        saturated = 8'sd127;
      end else if (shifted < -32'sd128) begin
        saturated = -8'sd128;
      end else begin
        saturated = int8_t'(shifted[7:0]);
      end

      return saturated;
    end
  endfunction

  // INT32 output uses ReLU only.
  function automatic int32_t relu_int32(
    input int32_t value,
    input logic   relu_enable
  );
    begin
      if (relu_enable && (value < 32'sd0)) begin
        return 32'sd0;
      end
      return value;
    end
  endfunction

endpackage
