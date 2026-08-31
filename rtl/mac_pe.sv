// Assignment: write module mac_pe.
//
// Parameters:
//   DATA_W for each signed operand and ACC_W for the signed accumulator.
//
// Ports:
//   clk, active-low asynchronous rst_n, clear_acc, mac_en, signed activation,
//   signed weight, and signed accumulator output.
//
// On each enabled clock, multiply activation by weight and add the signed
// product to the accumulator. The product width must be 2*DATA_W. Sign-extend
// the product before adding it to ACC_W; do not rely on implicit expression
// sizing. Reset has highest priority, clear has the next priority, and mac_en
// has the lowest. With clear and enable both low, the register must hold.
//
// The testbench covers all sign combinations, repeated accumulation, the most
// negative INT8 value, disabled cycles, clear priority, and reset behavior.
// Add assertions for stable hold behavior and successful clear after the basic
// implementation passes.
