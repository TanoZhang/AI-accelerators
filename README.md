# 4x4 INT8 matrix accelerator

> Homework branch: several RTL bodies are intentionally unfinished. Start with
> [HOMEWORK.md](HOMEWORK.md). The complete implementation is on `main`.

SystemVerilog implementation of a small matrix-multiply accelerator.

## Design

- 4x4 output-stationary MAC array
- Signed INT8 input and INT32 accumulation
- APB control and status registers
- Ready/valid DMA interface
- Multi-read operand scratchpads
- Quantized INT8 or INT32 output with optional ReLU
- Interrupts and performance counters

The operand path reads one activation vector and one weight vector in parallel.
A small FIFO keeps the MAC input stable when the downstream logic stalls.

The older lane-at-a-time feeder is still available as a build option. It is
used as a baseline, not as a second accelerator. Both builds run the same data
through the rest of the design. The counter comparison is in
[feeder_comparison.md](verification/results/feeder_comparison.md).

## Verification

The RTL is tested at module and system level. System tests use a Python
reference model and cover signed values, edge tiles, output saturation, DMA
stalls, invalid configurations, and recovery after errors.

Results are available in
[verification_report.md](verification/results/verification_report.md) and
[performance.csv](verification/results/performance.csv).

## FPGA

The design was compiled and tested on a Terasic DE25-Standard Rev.D at 50 MHz.
The board test configures the accelerator through APB, services DMA requests
from on-chip memory, and checks the output matrix in hardware.

Build and measured results are documented under
[fpga/de25_standard](fpga/de25_standard/) and
[de25_standard_results.md](verification/fpga/de25_standard_results.md).

## Run

```powershell
powershell -ExecutionPolicy Bypass -File .\run_regression.ps1
```

Python, NumPy, Matplotlib, and ModelSim are required.
