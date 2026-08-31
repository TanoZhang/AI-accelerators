# DE25-Standard self-test

This image runs without HPS software or external DDR. After configuration, a
small RTL state machine writes the APB registers and starts an 8x8x8 signed
INT8 multiply. The DMA memory and output checker are also in the FPGA fabric.

The input pattern is deliberately easy to inspect. Each row of A is one of
`-4, -3, -2, -1, 1, 2, 3, 4`, while the columns of B are either `-1` or `1`.
All 64 INT32 outputs are checked before PASS is asserted.

## Board outputs

- `LEDR[0]`: PASS
- `LEDR[1]`: FAIL or timeout
- `LEDR[2]`: sticky completion interrupt; remains lit after PASS
- `LEDR[3]`: DMA request/response activity
- `LEDR[4]`: feeder build, on for parallel and off for scalar
- `LEDR[8:5]`: mirrors `SW[3:0]`
- `LEDR[9]`: heartbeat
- `HEX5..HEX0`: hexadecimal hardware cycle count

The LEDs and seven-segment display are active-low at the FPGA pins.

## Build

The checked-in assignments target the DE25-Standard Rev.D device
`A5ED013BB32AE4SCS`. The two builds differ only in the operand feeder selected
at the top level.

```powershell
.\build.ps1 -Feeder Scalar -Compile
.\build.ps1 -Feeder Parallel -Compile
```

The SOF files are written below `build_scalar` and `build_parallel`. Use
`-QuartusRoot` if Quartus is not found automatically. The Rev.D pin file should
not be used on another board revision without checking the board manual.

The matching simulation is `tb/fpga/tb_de25_standard_selftest_top.sv`. Physical
results are in `verification/fpga/de25_standard_results.md`.
