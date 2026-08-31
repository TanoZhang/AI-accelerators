// Assignment: write module simple_dma.
//
// Parameters:
//   SPAD_DEPTH and scratchpad address width.
//
// Command/status ports:
//   clock/reset, start, a dma_transfer_e direction, 32-bit source/destination,
//   word length, busy, done, and error.
//
// External memory request/response ports:
//   req_valid/req_ready, write flag, byte address, write data, byte strobes,
//   rsp_valid/rsp_ready, read data, and response error.
//
// Scratchpad ports:
//   activation write enable/address/data; weight write enable/address/data; and
//   output read enable/address with registered read-valid/data response.
//
// Support three transfers: memory to activation, memory to weight, and output
// scratchpad to memory. Keep one external transaction outstanding. For loads,
// hold the memory request until accepted, wait for its response, then pulse the
// selected scratchpad write. For stores, request the output scratchpad word,
// capture its registered response, issue a full-word external write, and wait
// for the write response before advancing.
//
// Memory addresses are bytes and increase by four. Scratchpad addresses are
// word indices and increase by one. Validate direction, nonzero length, word
// alignment, complete memory-address range, and complete scratchpad range before
// issuing the first request. Report read and write response errors through the
// common error output and stop the transfer cleanly.
//
// Ready/valid payloads must remain stable under request stalls. Response-ready
// must not consume an unrelated response. Pulse done only after the last
// successful response. The testbench checks long request stalls, response
// delays, exact address sequences, both error directions, and all bounds.
