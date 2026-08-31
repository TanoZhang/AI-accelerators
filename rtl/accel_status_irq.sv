// Assignment: write module accel_status_irq.
//
// Ports:
//   clock/reset; done_event; DMA-error event; compute/configuration-error event;
//   two interrupt-enable bits; two write-one-to-clear bits; sticky done and
//   error outputs; the two-bit interrupt status; and irq.
//
// Bit zero represents DONE and bit one represents ERROR. Set DONE on a
// completion event. Set ERROR when either error input is asserted. Both bits
// remain set until their matching W1C request. If a set event and clear request
// happen together, the new event wins so software cannot lose it. Reset clears
// both bits. Generate irq combinationally from enabled sticky status.
//
// The unit bench checks stickiness, independent clears, simultaneous set/clear,
// enable masking, reset priority, and status stability. Add assertions linking
// irq exactly to enabled status and proving that events remain visible.
