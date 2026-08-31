# Operand feeder A/B comparison

The two simulations use the same APB setup, DMA model, scratchpads, 4x4 MAC array, and 8x8x8 signed INT8 input. The top-level `USE_PARALLEL_FEEDER` parameter is the only design change.

| Metric | Scalar | Parallel | Speedup |
|---|---:|---:|---:|
| Total accelerator cycles | 1037 | 795 | 1.30x |
| Compute cycles | 309 | 67 | 4.61x |
| DMA cycles | 704 | 704 | 1.00x |

Both versions produced the same 64 INT32 outputs and passed the full reference-model suite. DMA time is unchanged, so the total speedup is smaller than the compute-path speedup.

All per-case counter values are in `feeder_comparison.csv`.
