// Assignment: write module multi_read_scratchpad.
//
// Parameters:
//   DATA_W, DEPTH, READ_PORTS, and address width. READ_PORTS defaults to four.
//
// Ports:
//   clk, active-low reset, a read-enable vector, one read address per port, one
//   registered data output per port, a read-valid vector, and one shared write
//   enable/address/data interface.
//
// The feeder needs four unrelated reads in the same cycle. Implement this using
// replicated memories: broadcast each write to every copy and give each copy
// one read address. All read responses arrive one clock after their requests.
// A same-address read/write collision must return the new write data on every
// active port. Reset validity/output registers without clearing memory contents.
//
// Verify independent simultaneous addresses, repeated addresses, partial port
// enables, signed byte patterns, broadcast writes, and collision behavior. In
// synthesis, inspect how many RAM blocks are inferred and explain the storage
// cost of obtaining extra read ports by replication.
