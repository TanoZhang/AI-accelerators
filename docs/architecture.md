# INT8 AI Accelerator Architecture

## 1. Scope

This design computes `C = A x B` for signed INT8 input matrices:

- `A` has shape `M x K`.
- `B` has shape `K x N`.
- Matrices are stored row-major in external memory.
- Each product is signed INT8 by signed INT8.
- Accumulation is signed INT32.
- The compute core is a 4x4 output-stationary array containing 16 processing elements (PEs).
- Results are written either as signed INT32 or as requantized signed INT8.
- Requantization is an arithmetic right shift followed by signed saturation to `[-128, 127]`.
- Optional ReLU clamps negative output values to zero.

This document fixes the initial microarchitecture and the boundaries between modules. It does not define RTL implementation details beyond what is required for deterministic cycle-level contracts.

## 2. Programming and execution model

Software programs dimensions, external base addresses, output formatting, and the requantization shift through APB. This baseline maps one logical matrix element to one 32-bit external-memory word. Signed INT8 inputs occupy the low byte; INT8 outputs are sign-extended to 32 bits:

- `A[m][k]` byte address: `A_BASE + 4*(m*K + k)`
- `B[k][n]` byte address: `B_BASE + 4*(k*N + n)`
- INT32 `C[m][n]` byte address: `C_BASE + 4*(m*N + n)`
- INT8 `C[m][n]` byte address: `C_BASE + 4*(m*N + n)`

All base addresses must be 32-bit aligned. Packing four INT8 elements into one external-memory word is a possible future bandwidth optimization, not part of the current interface.

Writing `CTRL.START` when the accelerator is idle snapshots all job configuration registers. Later APB writes do not affect the active job. A start request while busy is rejected and records an error; it never restarts or corrupts the active job. Zero-valued `M`, `N`, or `K` is an invalid job.

Only one job and one output tile are active at a time. This intentionally favors a simple, verifiable first implementation. Overlap or double buffering may be added later only if the external contracts and numerical behavior remain unchanged.

## 3. Tiled output-stationary dataflow

The controller traverses output tiles in row-major order:

```text
for tile_m = 0; tile_m < M; tile_m += 4
  for tile_n = 0; tile_n < N; tile_n += 4
    clear all 16 accumulators
    for k = 0; k < K; k++
      present A[tile_m + row][k] on four row lanes
      present B[k][tile_n + col] on four column lanes
      accumulate the 16-lane outer product
    format and write valid elements of the 4x4 output tile
```

For a given `k`, the operand feeder broadcasts four activation values by row and four weight values by column. PE `(row,col)` performs:

```text
acc[row][col] <= acc[row][col]
               + signed(A[row]) * signed(B[col])
```

The accumulators remain resident in the MAC array for the complete `K` traversal of one output tile. They are synchronously cleared exactly once before the first accepted operand beat of that tile. A feeder beat advances `k` only when its ready/valid handshake succeeds.

The activation and weight scratchpads hold the operands needed for the active tile. Their default capacity is sufficient for four full rows/columns up to `MAX_K`; implementations may internally load legal chunks when `K` exceeds a chosen physical bank depth, but must not clear the output accumulators between chunks.

## 4. Edge masking

The controller computes stable masks when a tile begins:

- `row_mask[row] = (tile_m + row) < M`
- `col_mask[col] = (tile_n + col) < N`

These masks accompany every operand beat for the tile. PE `(row,col)` accumulates only when the feeder beat is accepted and both `row_mask[row]` and `col_mask[col]` are one. Invalid activation or weight lanes may carry any value; they must not affect architectural state.

The same masks control output capture and DMA writeback. Invalid edge elements are never written to external memory. This is required for `M` and `N` values that are not multiples of four.

No padding is visible to software, and no external memory access may cross the programmed logical bounds merely to fill a 4x4 tile.

## 5. Output formatting

After the final `k` beat is accepted, the INT32 accumulator tile is captured into the output scratchpad. The quantization/ReLU unit formats each valid element during writeback:

1. If ReLU is enabled, clamp a negative accumulator to zero.
2. If INT8 output is selected, perform signed arithmetic shift `acc >>> QUANT_SHIFT`.
3. Saturate the shifted result to signed INT8 range `[-128, 127]`.

For INT32 output, no shift or saturation is applied. If ReLU is enabled, the signed INT32 value is clamped to zero before writeback.

The initial architecture uses a single unsigned shift amount in the range 0 through 31. It has no multiplier, rounding offset, zero point, or per-channel scaling; those features must not be inferred or fabricated.

## 6. Module hierarchy

```text
ai_accel_top
|-- apb_csr
|   `-- interrupt/status and performance-counter register access
|-- accel_controller
|-- dma_engine
|-- activation_scratchpad
|-- weight_scratchpad
|-- output_scratchpad
|-- operand_feeder
|-- mac_array_4x4
|   `-- 16 x mac_pe
`-- quant_relu
```

### `ai_accel_top`

Instantiates and connects all blocks. It exposes the APB slave, external DMA memory master, interrupt output, clock, and reset. It contains no independent scheduling policy.

### `apb_csr`

Implements APB register accesses, job configuration storage, command pulses, sticky status, interrupt enable/status, and readable performance counters. It supplies a configuration snapshot to the controller on an accepted start.

### `accel_controller`

Owns job sequencing and tile coordinates. It requests operand loads, clears the array, starts feeder traversal, captures completed accumulator tiles, requests output formatting/writeback, updates counters, and reports completion or errors.

The compute portion is implemented by `compute_controller`. Its tile flow is `IDLE -> CLEAR -> START_FEEDER -> COMPUTE -> CAPTURE -> STORE -> NEXT_TILE -> DONE`. `NEXT_TILE` returns to `CLEAR` until all row-major 4x4 tiles are complete. `CAPTURE` provides one cycle between the final MAC update and result storage.

### `dma_engine`

Translates controller tile-transfer commands into external memory requests. It calculates row-major addresses, obeys logical matrix bounds, and transfers data between external memory and scratchpads. Only one DMA command is required to be outstanding in the baseline design.

### Scratchpads

The activation and weight scratchpads store signed INT8 operands. The output scratchpad stores the signed INT32 4x4 accumulator result until formatting/writeback completes. Scratchpads have explicit write enables and synchronous read contracts; no behavior depends on uninitialized data.

### `operand_feeder`

Reads four activation lanes and four weight lanes for one `k` index, aligns synchronous scratchpad responses, and presents one outer-product beat to the MAC array. It holds data, masks, and `last_k` stable while backpressured.

### `mac_array_4x4` and `mac_pe`

The array distributes row and column operands to 16 PEs. Each PE owns one signed INT32 accumulator, supports synchronous clear, and accumulates one signed product per accepted beat when enabled. Accumulator clear has priority over accumulation.

### `quant_relu`

Accepts a complete signed INT32 tile and its element mask. It produces either INT32 values with optional ReLU or INT8 values using the specified shift/saturation/ReLU operation. The baseline contract permits a fully parallel 16-element datapath.

## 7. Controller phase model

The controller uses these architectural phases, encoded by `accel_state_e` in `ai_accel_pkg.sv`:

1. `IDLE`: wait for a valid start.
2. `LOAD`: ask DMA to populate activation and weight scratchpads for the tile.
3. `CLEAR`: assert synchronous accumulator clear for one cycle.
4. `COMPUTE`: allow the feeder to stream exactly `K` accepted beats.
5. `CAPTURE`: store the 16 accumulators and tile mask in the output scratchpad.
6. `WRITEBACK`: format and DMA-write all valid tile elements.
7. `NEXT_TILE`: advance `tile_n`, then `tile_m`, or finish.
8. `DONE`: generate the completion event and return to idle.
9. `ERROR`: preserve an error code, generate the error event, and return to idle after status is recorded.

An implementation may combine adjacent phases when all documented handshakes and cycle priorities are preserved. It must never accept an operand beat in the clear cycle.

## 8. Reset, errors, and interrupts

All modules use active-low asynchronous reset `rst_n`. Architectural state, valid bits, sticky interrupt status, and counters reset to zero. Scratchpad data arrays need not be reset because their contents are guarded by control state and explicit writes.

The interrupt output is level-sensitive:

```text
irq = (IRQ_STATUS.DONE  & IRQ_ENABLE.DONE)
    | (IRQ_STATUS.ERROR & IRQ_ENABLE.ERROR)
```

Completion and error events set sticky interrupt status bits. Software clears them by writing one to the corresponding `IRQ_STATUS` bit. `STATUS.DONE` and `STATUS.ERROR` reflect those sticky event bits; `STATUS.BUSY` reflects an active job.

At minimum, the controller reports invalid dimensions, misaligned addresses, start-while-busy, and DMA response errors. An errored job stops issuing new work and never asserts normal completion.

## 9. Performance accounting

All counters are 32-bit saturating counters. An accepted accelerator start clears them and counts as the first total cycle. The completion or error edge is included, after which the final values remain stable until the next accepted command.

- `PERF_CYCLES`: every cycle from accepted start through the terminal event, inclusive.
- `PERF_COMPUTE_CYCLES`: cycles with the compute operation active.
- `PERF_MAC_CYCLES`: cycles with `mac_en` asserted.
- `PERF_DMA_CYCLES`: cycles with the DMA active.
- `PERF_STALL_CYCLES`: wall-clock cycles in which active compute or DMA work is blocked by ready/valid backpressure. Concurrent stalls count once.

## 10. Local invariants to assert in RTL

Module implementations should include synthesis-guarded SystemVerilog assertions for these invariants where the relevant signals are local:

- A start is accepted only when idle and configuration is valid.
- Clear and accumulate are never active for a PE in the same cycle.
- Feeder payload and masks remain stable while `valid && !ready`.
- Exactly `K` operand beats are accepted per output tile.
- Invalid row/column lanes never update a PE accumulator.
- DMA never writes an invalid edge element.
- A command or response handshake changes ownership exactly once.
- A scratchpad read response is consumed only when valid.
- The quantization shift is at most 31.
- Completion and error events are mutually exclusive for a job.
