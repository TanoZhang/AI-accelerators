// Assignment: write module mac_array_4x4.
//
// Parameters:
//   DATA_W, ACC_W, and ARRAY_DIM. The default configuration is 4x4.
//
// Ports:
//   clk, active-low reset, common clear_acc and mac_en controls, an unpacked
//   signed A vector with ARRAY_DIM elements, an unpacked signed B vector, and a
//   two-dimensional signed accumulator output array.
//
// Instantiate ARRAY_DIM*ARRAY_DIM mac_pe modules with nested generate loops.
// PE[row][col] receives A[row] and B[col], so one accepted cycle computes an
// outer product. Do not put a second accumulator in this wrapper and do not
// duplicate the multiply expression here. Parameter and signedness must pass
// cleanly through the hierarchy.
//
// The testbench compares every accumulator after many random outer products,
// checks simultaneous clear, and confirms that disabled cycles preserve all
// elements. Add array-level assertions only after the structural version works.
