// Assignment: write module accel_controller.
//
// Inputs:
//   clock/reset; start; programmed M/N/K, A/B/C addresses, and quant/ReLU/shift;
//   DMA busy/done/error; compute busy/done/error; and output-writer busy.
//
// Outputs:
//   start_accepted; DMA start, transfer type, source, destination, and word
//   length; compute start and latched active configuration; overall busy, done,
//   error, interrupt event, public accelerator state, and precise error code.
//
// Validate a command while idle. Dimensions must be nonzero, base addresses
// must be word aligned, and M*K, K*N, and M*N must fit the 32-bit length fields.
// Latch the complete job only after acceptance so later APB writes cannot alter
// a running operation.
//
// Sequence these phases:
//   1. load M*K A words into activation scratchpad index zero;
//   2. load K*N B words into weight scratchpad index zero;
//   3. start compute once and wait for completion;
//   4. wait until the output tile writer is idle;
//   5. store M*N output words to the programmed C byte address;
//   6. raise a one-cycle completion/interrupt event and return idle.
//
// Each child start is a pulse and must not repeat while that child is busy.
// Map DMA errors in either load to ERR_DMA_READ, store errors to ERR_DMA_WRITE,
// and compute errors to ERR_INTERNAL. A start while busy reports ERR_START_BUSY
// without corrupting the active job. Invalid idle commands report their error
// and issue no DMA request. Terminal states return to idle cleanly so a valid
// job can run after every error.
//
// The testbench checks request order and lengths, latched configuration, all
// validation paths, start-while-busy, child errors, state visibility, interrupt
// timing, and recovery.
