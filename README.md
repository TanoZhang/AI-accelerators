# 4x4 INT8 matrix accelerator

Synthesizable SystemVerilog accelerator with a 4x4 output-stationary MAC array.

## RTL

- Signed INT8 inputs and INT32 accumulation
- APB4 control/status registers
- Ready/valid DMA with error handling
- Replicated operand scratchpads with four parallel read lanes
- Two-entry elastic operand feeder
- INT32 or saturated INT8 output with optional ReLU
- Sticky interrupts and performance counters

The datapath accepts one 16-MAC outer product per cycle after pipeline fill.

## Verification

- 15 module-level RTL benches
- 64 Python-referenced system tests: 11 directed and 53 fixed-seed random
- 6 error and recovery tests
- Matrix dimensions 1-15, signed corner cases, saturation, ReLU, DMA stalls,
  address checks, INT8/INT32 output, and counter checks

See [verification_report.md](verification/results/verification_report.md) and
[performance.csv](verification/results/performance.csv).

## FPGA result

The RTL was compiled and run on a Terasic DE25-Standard Rev.D at 50 MHz. The
fabric self-test configures the accelerator over APB, services DMA from on-chip
memory, and checks a 2x2 matrix multiply in hardware.

- Board result: PASS, four INT32 results matched
- Hardware cycle count: 78
- TimeQuest Fmax: 178.64 MHz
- Resources: 2,994 ALMs, 5,154 registers, 21 DSP blocks, 9 M20Ks

Measured data is recorded in
[de25_standard_results.md](verification/fpga/de25_standard_results.md). HPS and
external DDR are not used by this board test.

## Run regression

```powershell
powershell -ExecutionPolicy Bypass -File .\run_regression.ps1
```

Requires Python 3, NumPy, Matplotlib, and ModelSim (`vlib`, `vlog`, `vsim`).
