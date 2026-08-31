# Parallel operand-feeder optimization

## Motivation

The original feeder reused one activation read port and one weight read port.
It fetched four A lanes and four B lanes sequentially before presenting a
single outer product to the 4x4 MAC array. `PERF_MAC_CYCLES` was numerically
correct, but operand delivery left the 16 multipliers idle during most
compute-active cycles.

The optimized datapath makes three RTL changes:

1. Activation and weight scratchpads store only the useful INT8 byte.
2. Each operand scratchpad is replicated four times to provide four unrelated
   synchronous read addresses while retaining simple inferred-RAM structures.
3. A two-entry elastic FIFO tracks an in-flight memory response and preserves
   ready/valid behavior when the compute controller applies backpressure.

The external programming model, numerical behavior, DMA request count, and
output layout are unchanged.

## Measured simulation results

Both versions were run with the same deterministic Python-generated vectors and
zero-wait memory profiles. Values are RTL performance-counter results.

| Case | Metric | Scalar feeder | Parallel feeder | Improvement |
|---|---:|---:|---:|---:|
| `stress_40_9x8x15` | Compute cycles | 841 | 133 | 84.2% reduction |
| `stress_40_9x8x15` | Total cycles | 1990 | 1282 | 35.6% reduction |
| `stress_40_9x8x15` | Operations/cycle | 1.085427 | 1.684867 | 55.2% increase |
| `edge_6x5x7_int32` | Compute cycles | 273 | 66 | 75.8% reduction |
| `edge_6x5x7_int32` | Operations/cycle | 0.619469 | 0.891720 | 43.9% increase |
| `positive_saturation` | Compute cycles | 78 | 16 | 79.5% reduction |
| `positive_saturation` | Operations/cycle | 0.684492 | 0.820513 | 19.9% increase |

DMA remains the dominant full-system cost because the external interface moves
one 32-bit word per INT8 element and permits one outstanding transaction.

## Verification

- `tb_multi_read_scratchpad` checks independent simultaneous reads, broadcast
  writes, per-port validity, and write-first collision behavior.
- `tb_parallel_operand_feeder` checks full and edge tiles, signed data, address
  generation, parallel lane issue, sustained one-beat-per-cycle delivery, FIFO
  accounting, and payload stability during backpressure.
- All 64 Python-referenced full-system jobs and all six error/recovery scenarios
  pass with the optimized feeder integrated into `ai_accelerator_top`.
- The DE25-Standard fabric self-test completes the embedded 2x2 signed INT8
  matrix multiplication in 78 measured accelerator cycles.
