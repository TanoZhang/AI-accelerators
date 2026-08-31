# DE25-Standard results

## Setup

| Field | Value |
|---|---|
| Board | Terasic DE25-Standard Rev.D |
| FPGA | `A5ED013BB32AE4SCS` |
| Quartus Prime Pro | 26.1.1 Build 130 |
| Programmer | On-board USB-Blaster III |
| Test date | 2026-08-29 |
| SOF checksum | `0x0608B59E` |

## Timing and resources

| Metric | Result |
|---|---:|
| Clock | 50.000 MHz |
| Fitter | PASS, 0 errors |
| Worst setup slack | +14.402 ns |
| Worst hold slack | +0.099 ns |
| Reported Fmax | 178.64 MHz |
| ALMs | 2,994 / 46,800 (6%) |
| Registers | 5,154 / 187,200 (2.8%) |
| DSP blocks | 21 / 376 (6%) |
| M20Ks | 9 / 358 (3%) |
| Embedded memory | 6,144 / 7,331,840 bits (<1%) |
| Pins | 67 / 414 (16%) |

The worst setup path is from
`u_accelerator|u_output_tile_writer|position_q[0]` to
`u_accelerator|u_output_sram|read_data[6]`.

The 4x4 MAC array uses 16 DSP blocks. The parallel feeder uses four, and the
output tile writer uses one. The accelerator scratchpads infer nine dual-port
M20Ks. The small board-test DMA memory has an asynchronous debug read and is
implemented in logic.

## Board test

The self-test completed one 2x2 signed INT8 matrix multiply and checked all four
INT32 results in hardware.

| Output | Observed |
|---|---|
| `LEDR[0]` PASS | On |
| `LEDR[1]` FAIL | Off |
| `LEDR[2]` completion IRQ | On |
| `LEDR[9]` heartbeat | Blinking |
| `HEX5..HEX0` cycle count | `00004E` (78 cycles) |

Power Analyzer and Signal Tap measurements were not collected for this run.
