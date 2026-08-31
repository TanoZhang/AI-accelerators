// Assignment: write module compute_controller.
//
// Parameters:
//   dimension width, accumulator width, and array dimension.
//
// Configuration/control ports:
//   clock/reset, start, M/N/K, start_ready, busy, done, and error.
//
// Feeder/MAC ports:
//   one-cycle feeder_start_pulse; active dimensions; tile row/column and k index;
//   operand_valid/operand_ready; clear_acc; mac_en; and the signed accumulator
//   array returned by the MAC.
//
// Output ports:
//   output_valid/output_ready; captured signed result tile; and row/column masks.
//
// Traverse C as ARRAY_DIM by ARRAY_DIM tiles in row-major order. For each tile,
// clear the accumulators, pulse the feeder start, accept exactly K operand beats,
// then capture the MAC results. The accumulator registers update on the same
// edge that accepts the last operand, so capture on the following clock rather
// than in the last MAC state. Hold output_valid, tile data, coordinates, and
// masks stable until output_ready accepts them.
//
// M and N need not be multiples of ARRAY_DIM. Generate masks from the current
// tile origin and advance columns before rows. Reject zero dimensions. A legal
// start is accepted only while idle; busy covers the complete multi-tile job;
// done is a one-cycle terminal indication.
//
// The unit test stresses edge tiles, K counting, last-product capture, output
// stalls, invalid starts, tile order, and control-pulse widths.
