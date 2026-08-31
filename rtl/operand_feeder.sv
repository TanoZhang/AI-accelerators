// Assignment: write module operand_feeder, the scalar baseline.
//
// Parameters:
//   DATA_W, DIM_W, ARRAY_DIM, SPAD_DEPTH, and scratchpad address width.
//
// Inputs:
//   clock/reset; a one-cycle start pulse; M, N, and K; tile_row and tile_col;
//   one activation read response; one weight read response; and compute_ready.
//
// Outputs:
//   busy and one-cycle done; one activation read request/address; one weight
//   read request/address; compute_valid; signed A and B vectors; row and column
//   masks; and last_k.
//
// For each k, fetch ARRAY_DIM activation values and ARRAY_DIM weight values one
// lane at a time. Activation address is (tile_row+lane)*K+k. Weight address is
// k*N+(tile_col+lane). A lane outside M or N is masked and filled with zero,
// without issuing an out-of-range memory request.
//
// The memories respond one clock after each request. Track activation and
// weight responses independently because they are separate handshakes. Present
// the completed vectors with ready/valid semantics. While compute_ready is low,
// every vector element, mask, and last_k must remain stable. Advance k only on
// an accepted output. Pulse done after the final k beat is accepted.
//
// Reject a start while active and reject zero or out-of-range dimensions. Use
// wide intermediate address arithmetic before truncating to the RAM address.
