// Assignment: write module requant_relu.
//
// Parameter:
//   ARRAY_DIM, default four.
//
// Ports:
//   a two-dimensional ARRAY_DIM by ARRAY_DIM signed INT32 input tile;
//   quant_enable; a five-bit right-shift amount; relu_enable; and a matching
//   two-dimensional signed INT8 output tile.
//
// Convert every cell combinationally. Apply ReLU before quantization so a
// negative value becomes zero even when a large shift is selected. When
// quantization is enabled, use an arithmetic right shift that preserves the
// sign. When it is disabled, feed the unshifted value into saturation. Clamp
// above 127 and below -128, otherwise keep the low signed byte.
//
// Avoid unsigned comparisons and literal-sizing mistakes around -128. The unit
// test sweeps many inputs and all important shift/saturation boundaries. A
// helper function is encouraged so the cell loop contains no duplicated logic.
