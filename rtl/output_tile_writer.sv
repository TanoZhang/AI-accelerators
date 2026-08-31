// Assignment: write module output_tile_writer.
//
// Parameters:
//   DIM_W, ARRAY_DIM, SPAD_DEPTH, and scratchpad address width.
//
// Tile input interface:
//   tile_valid/tile_ready; a signed INT32 ARRAY_DIM by ARRAY_DIM tile; tile_row
//   and tile_col; row and column masks; full M and N dimensions; quant_enable,
//   relu_enable, and quant_shift.
//
// Scratchpad/status outputs:
//   sram_wr_en, word address, 32-bit write data, busy, and one-cycle tile_done.
//
// Accept a tile only when idle, then hold a private copy while serializing its
// cells. Visit positions in row-major order. Skip masked rows/columns and never
// write outside M*N. Output address is global_row*N+global_col; use a wide
// intermediate before checking and truncating it to the scratchpad address.
//
// For INT32 mode, write the complete signed accumulator after optional ReLU.
// For quantized mode, apply requant_relu and store the sign-extended INT8 result
// in a 32-bit scratchpad word. Do not pulse tile_done until every valid cell has
// been processed. Keep tile_ready low while a captured tile is active.
//
// Tests include full tiles, edge masks, signed values, ReLU, saturation, address
// bounds, and back-to-back tile attempts. Add assertions that every write is
// within the logical C matrix and physical scratchpad.
