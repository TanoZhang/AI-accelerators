# Module Interface Contracts

## 1. Global conventions

- Clock: every sequential interface uses the rising edge of `clk`.
- Reset: `rst_n` is active-low and asynchronous. Control state and valid bits clear when `rst_n=0`.
- Handshake: a transfer occurs on a rising edge when both `valid` and `ready` are one.
- Backpressure: a source holds `valid` and its entire payload stable until transfer.
- Pulses: event and command pulses are one cycle unless explicitly acknowledged by a ready/valid handshake.
- Signed data: operands and accumulators use signed types from `ai_accel_pkg`; module ports must preserve signed declarations or cast explicitly at arithmetic boundaries.
- Lane order: tile element `(row,col)` maps to linear lane `row*4 + col`. Row and column lane zero are the lowest array indices.
- Masks: bit zero corresponds to row, column, or element lane zero.

Packed payload structs may be used internally, but leaf-module ports should remain explicit enough for waveform inspection and UVM interface binding.

## 2. Top-level external interfaces

### Clock and reset

```systemverilog
input logic clk;
input logic rst_n;
```

No unrelated clock domain is assumed. APB, DMA, scratchpads, and compute logic use `clk`.

### APB slave

```systemverilog
input  logic [APB_ADDR_W-1:0] paddr;
input  logic                  psel;
input  logic                  penable;
input  logic                  pwrite;
input  logic [31:0]           pwdata;
input  logic [3:0]            pstrb;
output logic [31:0]           prdata;
output logic                  pready;
output logic                  pslverr;
```

The transfer completes during the APB access phase. The baseline CSR block has no wait states. `PRDATA` and `PSLVERR` are valid for the completing access phase.

### External DMA memory master

The baseline uses one decoupled request channel and one read-response channel. At most one request is outstanding, which makes responses ordered by construction.

```systemverilog
output logic                  mem_req_valid;
input  logic                  mem_req_ready;
output logic                  mem_req_write;
output logic [ADDR_W-1:0]     mem_req_addr;
output logic [31:0]           mem_req_wdata;
output logic [3:0]            mem_req_wstrb;

input  logic                  mem_rsp_valid;
output logic                  mem_rsp_ready;
input  logic [31:0]           mem_rsp_rdata;
input  logic                  mem_rsp_error;
```

A request transfers on `mem_req_valid && mem_req_ready`. `mem_req_write=0` is a 32-bit read; write strobes are then zero. `mem_req_write=1` is a write, and each asserted strobe identifies a valid byte of `mem_req_wdata`. A read request produces exactly one response. A write error is returned as a response as well, so every accepted request receives exactly one `mem_rsp_valid` beat. The DMA holds `mem_rsp_ready` high whenever it can retire the outstanding request.

The external fabric may add arbitrary backpressure and response latency. Addresses are byte addresses. The DMA packs/unpacks signed INT8 elements without changing bit patterns.

`simple_dma` uses this interface with one request outstanding. Its transfer directions are memory-to-activation, memory-to-weight, and output-to-memory. System-memory addresses are byte addresses and advance by four for each 32-bit word. Scratchpad addresses are word indices and advance by one. Every accepted request receives one response, including writes.

### Interrupt

```systemverilog
output logic irq;
```

`irq` is level-sensitive and remains asserted until all enabled sticky events are cleared or disabled.

## 3. CSR block to controller

The CSR block exposes stable programmable configuration and a one-cycle command pulse. The controller returns job/status events.

```systemverilog
// CSR -> controller
output logic                  start_pulse;
output ai_accel_pkg::job_cfg_t job_cfg;

// controller -> CSR
input  logic                  busy;
input  ai_accel_pkg::accel_state_e state;
input  logic                  done_pulse;
input  logic                  error_pulse;
input  ai_accel_pkg::error_code_e error_code;
input  logic [31:0]           perf_cycles;
input  logic [31:0]           perf_compute_cycles;
input  logic [31:0]           perf_mac_cycles;
input  logic [31:0]           perf_dma_cycles;
input  logic [31:0]           perf_stall_cycles;
```

`job_cfg` is stable from an accepted `start_pulse` until `busy` deasserts. The CSR block may retain software programming registers separately so writes during a job affect only the next snapshot. `done_pulse` and `error_pulse` are mutually exclusive single-cycle events. Performance-counter values are read-only APB inputs and remain stable after a command terminates.

## 4. Controller to DMA engine

The controller issues a descriptor using ready/valid and receives one completion event. The descriptor identifies the matrix, transfer direction, tile origin, dimensions, and output format; the DMA derives all row-major addresses and scratchpad positions.

```systemverilog
output logic                       dma_cmd_valid;
input  logic                       dma_cmd_ready;
output ai_accel_pkg::dma_cmd_t     dma_cmd;

input  logic                       dma_done_pulse;
input  logic                       dma_error_pulse;
input  ai_accel_pkg::error_code_e  dma_error_code;
```

The controller holds `dma_cmd` stable while stalled. Only one command is active. `dma_done_pulse` occurs after the final scratchpad write for a load or after the final successful memory response for a store. An error produces `dma_error_pulse`, suppresses `dma_done_pulse`, and cancels remaining transfers in the command.

For operand loading, one activation and one weight descriptor may be issued sequentially. A future DMA may internally combine them, but must preserve the command contract.

## 5. Scratchpad ports

Activation and weight storage use separate `scratchpad_sram` instances. The DMA drives each write port, and the feeder drives each read port.

```systemverilog
input  logic                    write_en;
input  logic [SPAD_ADDR_W-1:0]  write_addr;
input  logic [DATA_W-1:0]       write_data;

input  logic                    read_en;
input  logic [SPAD_ADDR_W-1:0]  read_addr;
output logic [DATA_W-1:0]       read_data;
output logic                    read_valid;
```

Reads and writes are synchronous. A read request produces a registered response in the following cycle. Same-address read/write collisions are write-first. The memory array is not reset or initialized.

The initial feeder uses `DATA_W=8` and one read port for each operand scratchpad. Wider packed instances may be introduced with explicit pack/unpack logic outside the SRAM.

## 6. Controller to operand feeder

```systemverilog
output logic                 start_pulse;
output logic [DIM_W-1:0]     m_dim;
output logic [DIM_W-1:0]     n_dim;
output logic [DIM_W-1:0]     k_dim;
output logic [DIM_W-1:0]     tile_row;
output logic [DIM_W-1:0]     tile_col;
input  logic                 busy;
input  logic                 done_pulse;
```

The controller pulses `start_pulse` after the tile operands are available and the MAC accumulators are clear. The feeder snapshots the dimensions and tile origin, then emits exactly `K` accepted vectors. `done_pulse` follows acceptance of the last vector.

In the integrated datapath, `compute_controller.feeder_start_pulse` drives `operand_feeder.start_pulse`; the controller's active dimensions and tile coordinates drive the matching feeder inputs.

## 7. Operand feeder to MAC array

```systemverilog
output logic                         compute_valid;
input  logic                         compute_ready;
output logic signed [DATA_W-1:0]     a_vec [0:3];
output logic signed [DATA_W-1:0]     b_vec [0:3];
output logic [3:0]                   row_mask;
output logic [3:0]                   col_mask;
output logic                         last_k;
```

One `compute_valid && compute_ready` transfer represents one `k` outer product. The feeder holds operands, masks, and `last_k` stable while stalled. Invalid edge operands are zero.

At integration, `a_vec` and `b_vec` connect directly to `mac_array_4x4`, and `mac_en` is `compute_valid && compute_ready`. The masks remain available to the controller for output masking and performance accounting.

`operand_feeder.compute_valid` connects to `compute_controller.operand_valid`, and `compute_controller.operand_ready` connects to `operand_feeder.compute_ready`.

## 8. Controller and MAC array

```systemverilog
output logic                         clear_acc;
input  logic signed [ACC_W-1:0]      acc [0:3][0:3];
```

`clear_acc` synchronously clears all accumulators and has priority over `mac_en`. The controller captures `acc` after the accepted vector with `last_k=1`. Signed INT8 products are widened before signed INT32 accumulation; overflow wraps in two's-complement form.

## 9. Controller/MAC to output scratchpad

The output scratchpad is a single-entry 4x4 tile buffer:

```systemverilog
input  logic                         out_tile_wr_en;
input  ai_accel_pkg::int32_t         out_tile_wr_data [16];
input  logic [15:0]                  out_tile_wr_mask;
output ai_accel_pkg::int32_t         out_tile_rd_data [16];
output logic [15:0]                  out_tile_rd_mask;
output logic                         out_tile_valid;
input  logic                         out_tile_consume;
```

`out_tile_wr_en` captures all accumulator lanes and the element mask on one rising edge and sets `out_tile_valid`. Data and mask remain stable until `out_tile_consume`. The controller must not write while `out_tile_valid=1`. Consume clears valid after formatting/writeback has completed successfully or after the job is aborted.

## 10. Output scratchpad to quantization/ReLU

```systemverilog
input  logic signed [31:0]           in_data  [0:3][0:3];
input  logic                         quant_enable;
input  logic [4:0]                   quant_shift;
input  logic                         relu_enable;
output logic signed [7:0]            out_data [0:3][0:3];
```

`requant_relu` is combinational and connects directly to the 4x4 accumulator array. ReLU is applied before the arithmetic right shift and signed INT8 saturation. Within this conversion block, `quant_enable=0` bypasses only the shift. At the integrated output writer, `quant_enable=1` selects this INT8 result; `quant_enable=0` selects the full INT32 accumulator with optional ReLU and no saturation. Tile masks are carried separately by the controller.

## 11. Quantization unit to DMA writeback

The DMA store descriptor provides `C_BASE`, `N`, tile coordinates, and output mode. The formatted tile and mask remain stable until the DMA accepts ownership:

```systemverilog
output logic                         wb_valid;
input  logic                         wb_ready;
output ai_accel_pkg::int32_t         wb_i32 [16];
output ai_accel_pkg::int8_t          wb_i8 [16];
output logic [15:0]                  wb_mask;
output logic                         wb_output_int8;
```

After handshake, DMA may serialize lanes into memory requests. It visits valid elements in increasing row-major lane order and emits no request for a cleared mask bit. `dma_done_pulse` marks completion of all acknowledged writes.

## 12. Assertion and verification hooks

Every ready/valid source should assert payload stability under backpressure. UVM monitors should be able to observe:

- APB accepted starts and snapshotted job configuration.
- DMA descriptors and external request/response traffic.
- One feeder transaction per accepted `k`.
- MAC clear and accumulator capture boundaries.
- Edge masks at feeder, output scratchpad, and writeback.
- Completion/error events and all counter increments.

Internal arrays should use consistent lane ordering so scoreboards can compare a 16-element tile without hierarchy-specific remapping.
