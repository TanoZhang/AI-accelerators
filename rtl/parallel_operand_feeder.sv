// Assignment: write module parallel_operand_feeder.
//
// Use the same configuration, status, vector, mask, last_k, and ready/valid
// interfaces as operand_feeder. Replace each scalar scratchpad connection with
// ARRAY_DIM read enables, addresses, valid responses, and data responses.
//
// One request cycle should issue all active A and B lanes for the same k:
//   A address for lane i = (tile_row+i)*K+k
//   B address for lane i = k*N+(tile_col+i)
// Invalid edge lanes are masked, return zero, and issue no memory access.
//
// The scratchpads have registered outputs, so request metadata must survive
// until the response cycle. Add a two-entry elastic FIFO holding both vectors,
// their k index, and any control needed at the output. The design should accept
// a memory response while the previous vector is being consumed. Handle push
// and pop in the same cycle without corrupting the count or pointers.
//
// Backpressure is part of the functional contract. When compute_valid is high
// and compute_ready is low, A, B, masks, and last_k must remain stable. Never
// overwrite a full FIFO, never issue a request without room reserved for its
// future response, and generate done exactly once after the final beat leaves.
//
// The unit test checks full and edge tiles, signed data, address sequences,
// continuous one-k-per-cycle delivery, FIFO accounting, and long output stalls.
// Compare its compute cycles with the scalar feeder after both pass.
