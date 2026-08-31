# Architecture

## Data format

The accelerator computes `C = A x B` with signed INT8 inputs and signed INT32
accumulators. Matrices are row-major. Each input value occupies the low byte of
one 32-bit memory word, and output words contain either INT32 data or a
sign-extended INT8 result.

For INT8 output, the accumulator is optionally clamped by ReLU, shifted right
arithmetically, and saturated to `[-128, 127]`.

## Dataflow

The 4x4 MAC array is output-stationary. For each output tile, the controller
clears the 16 accumulators and walks through `K`. One accepted operand beat
contains four values from a column of A and four values from a row of B. The
array computes their 4x4 outer product in one cycle.

```text
for tile_m = 0; tile_m < M; tile_m += 4
  for tile_n = 0; tile_n < N; tile_n += 4
    clear accumulators
    for k = 0; k < K; k++
      acc[row][col] += A[tile_m + row][k] * B[k][tile_n + col]
    write valid results
```

Row and column masks disable PEs outside the programmed matrix dimensions, so
no padded memory accesses are needed for edge tiles.

## Memory path

`simple_dma` moves 32-bit words between the external ready/valid interface and
three local scratchpads. It permits one outstanding request and reports memory
response errors to the controller.

The activation and weight scratchpads are replicated four times. DMA writes go
to every copy, while each feeder lane has an independent registered read port.
This costs additional memory bits but supplies all eight operands in parallel.

`parallel_operand_feeder` keeps a two-entry FIFO because a scratchpad response
can already be in flight when the MAC side stalls. Once the pipeline is full,
the feeder can deliver one outer-product beat per cycle.

The output writer serializes a completed 4x4 tile into a 32-bit scratchpad.
DMA then writes the valid words back to system memory.

## RTL hierarchy

```text
ai_accelerator_top
|-- apb_accel_regs
|-- accel_controller
|-- simple_dma
|-- multi_read_scratchpad       activation
|-- multi_read_scratchpad       weights
|-- parallel_operand_feeder
|-- compute_controller
|-- mac_array_4x4
|   `-- 16 x mac_pe
|-- output_tile_writer
|   `-- requant_relu
|-- scratchpad_sram             output
|-- accel_status_irq
`-- perf_counters
```

## Control and errors

An APB start captures the programmed dimensions, base addresses, and output
mode. Zero dimensions, unaligned addresses, start while busy, and DMA response
errors set sticky error status. Done and error status are cleared through W1C
register bits.

The performance block counts total, compute, MAC, DMA, and stalled cycles for
each accepted job. Counters saturate at 32 bits.
