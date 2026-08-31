// Assignment: write module perf_counters.
//
// Parameter:
//   COUNTER_W, default 32.
//
// Inputs:
//   clock/reset; start_accepted; done_event; error_event; compute_active; mac_en;
//   dma_active; compute_stall; and dma_stall.
//
// Outputs:
//   total cycles, compute cycles, MAC cycles, DMA cycles, and stall cycles.
//
// A new accepted job clears the old measurements and counts its start cycle.
// Continue counting while the job is active, including its terminal cycle.
// Compute, MAC, and DMA counters increment only when their qualifier is true.
// Stall increments for a compute stall while compute is active or a DMA stall
// while DMA is active; do not double count a cycle if both conditions are true.
// Stop after done or error and hold the final values until the next job.
//
// Every counter must saturate at all ones instead of wrapping. Reset clears all
// values and the internal active flag. The unit test covers simultaneous events,
// one-cycle jobs, error termination, saturation, and idle stability.
