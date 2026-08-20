# 4×4 INT8 AI accelerator

SystemVerilog implementation of a 4×4 INT8 MAC accelerator with APB control, DMA, scratchpad memories, quantization, ReLU, and performance counters.

## Tests

- 13 RTL unit benches
- 64 full-system jobs checked against a Python reference
- 11 directed and 53 fixed-seed random matrix cases
- 6 error and recovery scenarios
- Dimensions 1–15, signed INT8, saturation, ReLU, INT8/INT32 output, DMA stalls, address bounds, and performance counters

Results are in [`verification/results/verification_report.md`](verification/results/verification_report.md), [`verification/results/performance.csv`](verification/results/performance.csv), and [`verification/results/figures/`](verification/results/figures/).

## Run everything

```powershell
powershell -ExecutionPolicy Bypass -File .\run_regression.ps1
```

Requires Python 3, NumPy, Matplotlib, and ModelSim (`vlib`, `vlog`, and `vsim`).
