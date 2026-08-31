// Assignment: write module scratchpad_sram.
//
// Parameters:
//   DATA_W, DEPTH, and an address width derived safely when DEPTH is one.
//
// Ports:
//   clk, active-low reset, one synchronous read request with address, registered
//   read_data and read_valid, and one write request with address and data.
//
// Implement a synthesizable single-clock memory. A read request produces valid
// data on the following cycle. Reset clears control/output registers but should
// not require clearing the whole memory array. Define the same-address
// read/write collision behavior explicitly; the unit bench expects write-first
// data. Ignore disabled reads and keep read_valid as a one-cycle response flag.
//
// Guard against out-of-range accesses in simulation. Check the Quartus report
// later to confirm the storage maps to an embedded RAM rather than thousands of
// registers.
