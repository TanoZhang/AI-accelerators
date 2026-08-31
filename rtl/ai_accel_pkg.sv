// Assignment: recreate package ai_accel_pkg.
//
// This package is the shared contract for every RTL and testbench file. Define
// the default geometry and widths: a 4x4 array, signed INT8 operands, signed
// INT32 accumulation, 32-bit byte addresses, 12-bit APB addresses, and 16-bit
// matrix dimensions. Add typedefs for operands, accumulators, addresses,
// dimensions, row masks, column masks, and the flattened 16-element tile mask.
//
// Define these public enum groups with explicit encodings:
//   - accelerator states: idle, load, clear, compute, capture, writeback,
//     next-tile, done, and error;
//   - error codes: none, invalid dimension, address alignment, start while busy,
//     DMA read, DMA write, and internal error;
//   - matrix selection and load/store direction;
//   - DMA transfer targets: memory-to-activation, memory-to-weight, and
//     output-to-memory.
//
// Define packed job and DMA-command structures. They must carry dimensions,
// base addresses, tile coordinates, masks, quantization settings, and output
// mode without using unpacked fields.
//
// Recreate the APB map at byte offsets 0x000 through 0x03c. It contains
// CONTROL, STATUS, M, N, K, A base, B base, C base, quantization, interrupt
// enable/status, and five performance-counter registers. Keep every register
// word aligned; the unit test expects the exact offsets from the README map.
//
// Add three pure helper functions:
//   1. combine row and column masks into a row-major 16-bit element mask;
//   2. apply optional ReLU, arithmetic right shift, and signed INT8 saturation;
//   3. apply optional ReLU to an INT32 value without changing positive values.
//
// Be careful with signed literals, return types, and the -128 corner. Package
// definitions must compile before any module can be tested.
