// Assignment: write module apb_accel_regs.
//
// Parameters:
//   APB address width and dimension width.
//
// APB ports:
//   clock/reset, paddr, psel, penable, pwrite, 32-bit pwdata, four byte strobes,
//   32-bit prdata, pready, and pslverr.
//
// Accelerator-facing outputs:
//   one-cycle start and soft-reset pulses; M/N/K registers; A/B/C base address
//   registers; quant_enable, relu_enable, five-bit shift; two interrupt-enable
//   bits; and a two-bit W1C pulse for interrupt status.
//
// Hardware inputs:
//   busy, interrupt status, and total/compute/MAC/DMA/stall counters.
//
// Implement a zero-wait APB slave: decode and respond only in the access phase
// when psel and penable are both high. Reads must be combinational from the
// selected register. Writes occur once per access and honor pstrb for each byte.
// Return pslverr for unaligned, undefined, or illegal writes; never modify state
// on an errored transfer.
//
// CONTROL bit 0 generates start and bit 1 generates soft reset. They are pulses,
// not stored levels. STATUS reports busy, done, and error. QUANT_CONFIG uses bit
// 0 for quantization, bit 1 for ReLU, and bits 6:2 for shift. Interrupt enable
// uses bits 1:0. A write of one to the matching INT_STATUS bit produces a W1C
// pulse. Performance registers and STATUS are read-only.
//
// Reset every stored register. Keep configuration stable without a legal write.
// Unit tests cover APB phase timing, byte strobes, register reads, read-only
// protection, W1C, invalid addresses, pulse widths, and reset.
