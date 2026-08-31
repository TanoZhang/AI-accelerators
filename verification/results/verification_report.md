# Verification results

## Result

**PASS:** 15 RTL unit benches, 1 FPGA self-test bench, 64 full-system jobs, and 6 error/recovery scenarios.

Each job is programmed through APB and runs through DMA, scratchpads, the 4×4 MAC array, output formatting, and writeback. Results are checked against `verification/reference_model.py`.

## Requirement coverage

| Area | Coverage |
|---|---|
| Several matrix multiplications | 12 directed jobs plus 52 deterministic constrained-random jobs |
| Dimensions not divisible by four | Shapes from 1 through 15, including edge-heavy M/N/K values and multi-tile matrices |
| Negative INT8 values | Mixed signed random vectors and explicit -128 operand |
| Saturation | Dedicated positive-to-127 and negative-to--128 cases |
| Quantized outputs | Shifts 0, 1, 2, 3, 7, 15, and 31 with and without ReLU |
| INT32 outputs | Signed, multi-tile, and ReLU-enabled INT32 cases |
| DMA correctness | Exact request count and logical A/B/C address bounds checked per job |
| Parallel operand delivery | Four activation and four weight reads per issue; sustained one accepted K beat per cycle without backpressure |
| Edge-write safety | Canary words immediately before and after C checked per job |
| Performance | Total, MAC, compute, DMA, stall, utilization, and effective ops/cycle recorded below |
| Backpressure | Two request-stall patterns and response delays from 0 through 4 cycles |
| Error handling | Zero dimension, misalignment, DMA read error, DMA write error, start-while-busy, and clean recovery |

## Performance measurements

MAC utilization is `useful MACs / (16 × PERF_MAC_CYCLES)`. Operations per cycle is `2 × M × N × K / PERF_CYCLES`. Values come from RTL simulation.

| Case | Shape | Output | Memory | Total | MAC | Compute | DMA | Stall | MAC util. | Ops/cycle |
|---|---:|---|---|---:|---:|---:|---:|---:|---:|---:|
| `signed_min_1x1_int32` | 1×1×1 | INT32 | zero-wait | 44 | 1 | 9 | 11 | 0 | 6.250% | 0.045455 |
| `basic_2x2_int32` | 2×2×2 | INT32 | zero-wait | 90 | 2 | 10 | 56 | 0 | 25.000% | 0.177778 |
| `fpga_ab_8x8x8_int32` | 8×8×8 | INT32 | zero-wait | 795 | 32 | 67 | 704 | 0 | 100.000% | 1.288050 |
| `edge_5x3x7_int32` | 5×3×7 | INT32 | zero-wait | 441 | 14 | 32 | 385 | 0 | 46.875% | 0.476190 |
| `edge_3x5x5_quant_shift2` | 3×5×5 | INT8 | zero-wait | 304 | 10 | 30 | 250 | 0 | 46.875% | 0.493421 |
| `positive_saturation` | 4×4×8 | INT8 | zero-wait | 312 | 8 | 16 | 272 | 0 | 100.000% | 0.820513 |
| `negative_saturation` | 4×4×8 | INT8 | zero-wait | 392 | 8 | 16 | 352 | 0 | 100.000% | 0.653061 |
| `edge_7x6x3_quant_relu` | 7×6×3 | INT8 | zero-wait | 575 | 12 | 62 | 489 | 0 | 65.625% | 0.438261 |
| `relu_2x3x4_int32` | 2×3×4 | INT32 | zero-wait | 152 | 4 | 12 | 116 | 0 | 37.500% | 0.315789 |
| `edge_6x5x7_int32` | 6×5×7 | INT32 | zero-wait | 471 | 28 | 66 | 381 | 0 | 46.875% | 0.891720 |
| `backpressured_5x5x5_quant` | 5×5×5 | INT8 | stalled-2 | 738 | 20 | 64 | 650 | 150 | 39.063% | 0.338753 |
| `backpressured_1x6x5_relu` | 1×6×5 | INT8 | stalled-1 | 394 | 10 | 30 | 340 | 41 | 18.750% | 0.152284 |

## Interpretation

The best measured effective throughput is **1.684867 ops/cycle** on `stress_40_9x8x15`. Full 4×4 tiles reach 100% array utilization; narrow and edge-heavy matrices reduce useful-lane utilization, with the lowest measured value **6.250%** on `signed_min_1x1_int32`.

DMA dominates latency because requests transfer one word at a time and load, compute, and store do not overlap. `PERF_STALL_CYCLES` counts request backpressure; response delay is included in `PERF_DMA_CYCLES`.

The active datapath uses replicated four-read-port INT8 operand scratchpads and a two-entry elastic feeder FIFO. This removes the former lane-by-lane operand fetch bottleneck while preserving ready/valid backpressure behavior.

The table shows 12 directed cases. `performance.csv` contains all 64 jobs, including 52 fixed-seed random cases.

## Files

- `verification/results/figures/rtl-waveform-backpressured-5x5.png`: control and ready/valid waveform
- `verification/results/figures/performance-benchmark-summary.png`: cycle, utilization, and throughput plots
- `verification/results/figures/rtl-waveform-backpressured-5x5.csv`: plotted signal transitions
- `verification/results/rtl_trace.vcd`: source waveform
- `verification/results/performance.csv` and `verification/results/error_scenarios.csv`: raw results
- `verification/results/feeder_comparison.csv`: scalar/parallel A/B counters

Figure captions are stored with the PNG files.

## Error handling

- `zero_dimension`: PASS
- `misaligned_address`: PASS
- `dma_read_response_error`: PASS
- `dma_write_response_error`: PASS
- `start_while_busy_rejected_without_corruption`: PASS
- `clean_recovery_without_reset`: PASS

## Regression inventory

- `tb_accel_controller`: PASS (925 self-checks, 7 error events)
- `tb_accel_status_irq`: PASS (64 self-checks)
- `tb_ai_accelerator_top`: PASS (44 self-checks)
- `tb_apb_accel_regs`: PASS (201 self-checks)
- `tb_compute_controller`: PASS (2326 self-checks)
- `tb_mac_array_4x4`: PASS (2032 accumulator checks)
- `tb_mac_pe`: PASS (22 self-checks)
- `tb_multi_read_scratchpad`: PASS (13 self-checks)
- `tb_operand_feeder`: PASS (387 self-checks)
- `tb_output_tile_writer`: PASS (115 self-checks)
- `tb_parallel_operand_feeder`: PASS (474 self-checks, 16 vector reads)
- `tb_perf_counters`: PASS (75 self-checks)
- `tb_requant_relu`: PASS (32512 self-checks)
- `tb_scratchpad_sram`: PASS (493 self-checks)
- `tb_simple_dma`: PASS (372 self-checks, 42 request stalls, 298 response wait cycles)
- `tb_de25_standard_selftest_top`: PASS (67 self-checks, 1037 cycles, parallel=0)

The Python model has six tests for signed GEMM, saturation, shifts, ReLU, INT32 wrapping, and test-vector bounds.

## Reproduce

From the repository root on Windows with ModelSim and Python available:

```powershell
powershell -ExecutionPolicy Bypass -File .\run_regression.ps1
```

Performance data is in `verification/results/performance.csv`; logs are in `verification/logs/`.
