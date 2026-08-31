# DE25-Standard results

The test was run on a DE25-Standard Rev.D with the FPGA clocked at 50 MHz. Both
SOF files use the same 8x8x8 signed INT8 data, APB setup, DMA memory, output
checker, and clock constraint. `USE_PARALLEL_FEEDER` is the only RTL parameter
that changes.

## Board run

| Feeder | Lit status LEDs | HEX cycle count | Cycles |
|---|---|---:|---:|
| Scalar | `LEDR0`, `LEDR2` | `00040d` | 1037 |
| Parallel | `LEDR0`, `LEDR2`, `LEDR4` | `00031b` | 795 |

`LEDR0` is raised only after the on-chip checker has compared all 64 INT32
outputs. `LEDR2` is the completion interrupt and `LEDR4` identifies the
parallel build.

The measured end-to-end speedup is `1037 / 795 = 1.30x`. This includes both
input loads and output writeback. RTL counters show why the number is not
larger: compute falls from 309 to 67 cycles, while DMA remains 704 cycles in
both builds.

## Quartus results

Both images completed fitting and timing analysis with no timing violations.

| Result | Scalar | Parallel |
|---|---:|---:|
| Fmax | 181.29 MHz | 186.81 MHz |
| Worst setup slack at 50 MHz | +14.484 ns | +14.647 ns |
| Worst hold slack | +0.096 ns | +0.101 ns |
| ALMs | 4,310 | 3,850 |
| Registers | 7,149 | 6,692 |
| DSP blocks | 21 | 21 |
| M20K blocks | 1 | 9 |

The parallel scratchpad copies map to M20Ks. In the scalar build only port zero
is used, and Quartus implements the small operand memories in logic instead.

The board was left running the parallel image after the comparison.
