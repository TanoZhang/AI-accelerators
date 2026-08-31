# 4x4 INT8 accelerator homework

This branch is a specification-only starter. Files under `rtl/` contain no
module declarations, ports, state machines, or datapath code. Each file tells
you what must be built. The complete implementation remains on `main`.

The provided material is the project harness:

- `tb/unit/` defines the cycle-level contract for each block.
- `tb/integration/` checks the complete APB, DMA, compute, and error paths.
- `verification/reference_model.py` supplies signed GEMM results and vectors.
- `fpga/de25_standard/` contains the board wrapper, pin assignments, and build
  flow. Do not start FPGA work until the RTL regression passes.

## Suggested order

### Part 1: contracts and arithmetic

1. Recreate `ai_accel_pkg.sv`: widths, CSR offsets, state types, DMA directions,
   and error codes.
2. Write `mac_pe.sv` and pass its signed arithmetic, reset, clear, enable, and
   hold checks.
3. Build `mac_array_4x4.sv` from 16 PEs. Avoid copying the PE behavior into the
   array; instantiate it with generate loops.
4. Write `requant_relu.sv`, including arithmetic shift, ReLU, and both signed
   saturation limits.

### Part 2: local memories and operand movement

5. Implement one-read-port `scratchpad_sram.sv` with the required collision
   behavior.
6. Implement `multi_read_scratchpad.sv`. Decide how one write is reflected into
   four independently addressed read copies.
7. Write the scalar `operand_feeder.sv` first. It is slower, but its FSM makes
   address generation and edge masks easier to debug.
8. Write `parallel_operand_feeder.sv` with registered RAM responses, a two-entry
   elastic buffer, and stable ready/valid output under backpressure.
9. Implement `output_tile_writer.sv` to serialize one 4x4 result tile, skip
   masked cells, and select INT8 or INT32 output formatting.

### Part 3: controllers and data transfer

10. Implement `compute_controller.sv`. It owns tile traversal, accumulator
    clearing, K-beat counting, result capture, and output handshakes.
11. Implement `simple_dma.sv` as a single-outstanding-transaction engine for A
    loads, B loads, and C stores. Validate the complete transfer before the
    first request.
12. Implement `accel_controller.sv` to sequence load A, load B, compute, and
    store C, while reporting the first error precisely.

### Part 4: programming model

13. Write `accel_status_irq.sv` with sticky done/error state and write-one-to-
    clear interrupt bits.
14. Write `perf_counters.sv` for total, compute, MAC, DMA, and stall cycles.
15. Implement `apb_accel_regs.sv`. Follow APB setup/access timing, byte strobes,
    read-only fields, start pulses, soft reset, and invalid-address errors.
16. Connect the complete design in `ai_accelerator_top.sv`. Keep reset and error
    ownership clear; avoid adding behavior that belongs inside a child module.

### Part 5: system verification and FPGA

17. Pass every unit bench without editing its expected values.
18. Pass the full reference-model suite in scalar mode, then in parallel mode.
19. Pass the negative-path regression and show that a clean job can run after
    each injected error.
20. Compile both DE25 feeder variants at 50 MHz and record timing and resources.
21. Program both SOF files, record the hardware counter shown on HEX, and explain
    why compute speedup is larger than end-to-end speedup.

## Graduate-scale extensions

Choose two or three after the base design works. These are intentionally not
wired into the starter because defining the interface is part of the exercise.

22. Replace single-word DMA with a small burst engine and compare request
    overhead, buffering cost, and total cycles.
23. Add ping-pong activation and weight buffers so DMA can overlap compute.
24. Add a small command queue that accepts several GEMM descriptors through
    APB and raises one interrupt per completed descriptor.
25. Add per-output-channel bias before quantization. Define its memory layout
    and extend the Python reference rather than hard-coding constants.
26. Make `ARRAY_DIM` genuinely parameterized and verify at least 2x2 and 4x4
    configurations with the same source.
27. Add assertion-based checks for ready/valid stability, bounded progress,
    legal state transitions, address bounds, and no writes outside C.
28. Add functional coverage for matrix edge sizes, saturation, ReLU, DMA stalls,
    and each recovery path. Explain which bins are meaningful instead of only
    reporting a percentage.
29. Capture a Signal Tap trace on the FPGA showing feeder activity, MAC enable,
    DMA activity, and completion. Relate the trace to the counter values.
30. Compare one architectural change using identical data and clock settings.
    Report both its benefit and the resource or timing cost.

## What to submit

- Your RTL and any new tests.
- A block diagram and a short register map.
- Regression logs showing the reference-model and error-path results.
- Quartus timing and resource summaries.
- Scalar/parallel FPGA cycle measurements.
- A short discussion of the bottleneck you found and what you would change next.

Keep a small design notebook while working. Record assumptions, failed ideas,
and waveform observations. That material is more useful in an interview than a
large final code dump with no explanation of how it was debugged.
