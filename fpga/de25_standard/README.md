# DE25-Standard self-test

This design runs the accelerator directly in FPGA fabric. An RTL state machine
loads a test case, writes the APB registers, services DMA, and checks all four
results.

```text
[[1, 2],     [[5, 6],     [[19, 22],
 [3, 4]]  x   [7, 8]]  =   [43, 50]]
```

No HPS software or external DDR is required.

## Board outputs

- `LEDR[0]`: PASS
- `LEDR[1]`: FAIL or timeout
- `LEDR[2]`: sticky completion interrupt; remains lit after PASS
- `LEDR[3]`: DMA request/response activity
- `LEDR[8:4]`: mirrors `SW[4:0]`
- `LEDR[9]`: heartbeat
- `HEX5..HEX0`: hexadecimal hardware cycle count

The LEDs and seven-segment display are active-low at the FPGA pins.

## Build

The checked-in assignments target DE25-Standard Rev.D device
`A5ED013BB32AE4SCS`. `build.ps1` generates the Agilex 5 Reset Release IP and
creates an isolated Quartus project under `build_cli`.

```powershell
.\build.ps1
.\build.ps1 -Compile
```

Use `-QuartusRoot` for a non-default Quartus installation. Do not use the Rev.D
pin file on another board revision without checking its manual.

The matching simulation is `tb/fpga/tb_de25_standard_selftest_top.sv`. Physical
results are in `verification/fpga/de25_standard_results.md`.
