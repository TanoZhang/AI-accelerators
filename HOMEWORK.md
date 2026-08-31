# RTL homework branch

This branch is intentionally incomplete. The module ports, integration code,
testbenches, Python model, and FPGA build files are left in place. Five RTL
blocks contain `TODO` markers for you to implement.

Use `main` as the finished version, but try the tests first. The normal
regression stops at the first unfinished block, so it also gives a reasonable
work order:

1. `rtl/mac_pe.sv`
2. `rtl/parallel_operand_feeder.sv`
3. `rtl/requant_relu.sv`
4. `rtl/compute_controller.sv`
5. `rtl/simple_dma.sv`

Run this after each step:

```powershell
powershell -ExecutionPolicy Bypass -File .\run_regression.ps1
```

## Notes

### MAC processing element

The INT8 product is 16 bits. Sign-extend it before adding it to the wider
accumulator. Reset has the highest priority, followed by `clear_acc`, then
`mac_en`. When neither control is active, the accumulator must hold its value.

### Parallel operand feeder

For lane `i`, A comes from `(tile_row + i) * K + k`; B comes from
`k * N + tile_col + i`. Lanes outside M or N are masked and return zero.

The scratchpad response is registered. A request therefore cannot be treated
as data in the same cycle. The testbench also stalls `compute_ready`, so keep
the output vector and control fields stable until the transfer is accepted.
The finished design uses two entries: one can feed the MAC while the next RAM
response is being stored.

### Requantization and ReLU

Apply ReLU first, then an arithmetic right shift when quantization is enabled.
Clamp the final value to the signed INT8 range. Check `-128` separately; writing
`-8'sd128` is easy to get wrong because of literal sizing.

### Compute controller

One tile covers four rows by four columns. A tile needs a clear cycle, a feeder
start pulse, K accepted operand beats, and an output handshake. Capture the MAC
array one clock after accepting the last operand so the last products are
included. Hold `output_valid` and the tile data while `output_ready` is low.

### DMA

Keep only one external transaction outstanding. A load request is followed by
a response that writes either the activation or weight scratchpad. A store
first reads the output scratchpad, then sends the memory write.

Reject a zero length, an unaligned byte address, a scratchpad overrun, or a
32-bit memory-address wrap before issuing any request. Once `mem_req_valid` is
raised, its payload must not change until `mem_req_ready` is high.

## Useful places to inspect

- `verification/reference_model.py` defines the numerical result.
- `tb/unit/` shows each block's timing contract.
- `tb/integration/tb_end_to_end.sv` shows the APB-to-DMA-to-MAC path.
- `rtl/operand_feeder.sv` is a simpler lane-at-a-time feeder and is useful when
  writing the parallel version.

Do not start with the FPGA build. Get the module tests and full-system test to
pass first, then compile the parallel DE25 image.
