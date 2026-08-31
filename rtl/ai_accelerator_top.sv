// Assignment: write module ai_accelerator_top and integrate the complete core.
//
// Parameters:
//   APB and dimension widths, data and accumulator widths, array dimension,
//   USE_PARALLEL_FEEDER, scratchpad depth, and derived scratchpad address width.
//
// External ports:
//   clock and active-low reset; the full APB slave interface; one external
//   ready/valid memory request channel with write payload and byte strobes; one
//   memory response channel with data/error; and irq.
//
// Instantiate and connect:
//   apb_accel_regs, accel_controller, simple_dma, activation scratchpad, weight
//   scratchpad, scalar or parallel operand feeder selected at elaboration,
//   compute_controller, mac_array_4x4, output_tile_writer, output scratchpad,
//   accel_status_irq, and perf_counters.
//
// Keep three different handshakes separate: external DMA request/response,
// feeder-to-compute ready/valid, and compute-to-output-writer ready/valid. Do not
// combine valid pulses or infer that busy means ready. Broadcast DMA writes to
// replicated operand memories and route output scratchpad reads back to DMA.
//
// Soft reset should clear the running core without destroying APB programming
// state needed by software. Generate completion and error events once, connect
// W1C status correctly, and count total/compute/MAC/DMA/stall cycles from real
// activity signals. A memory-request stall is req_valid without req_ready; a
// compute stall is a valid feeder output without compute readiness.
//
// The scalar/parallel parameter must change only the operand feeder. APB, DMA,
// scratchpads, MAC array, output path, clock, and test vectors remain the same
// so the A/B performance result is meaningful.
//
// First pass the top-level unit bench, then the error integration bench, then
// the Python-referenced full-system suite. Finally connect this module to the
// provided DE25 wrapper; do not edit board pin assignments to hide RTL errors.
