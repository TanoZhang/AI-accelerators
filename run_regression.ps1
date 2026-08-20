[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $repoRoot

$modelSim = Get-Command vsim -ErrorAction SilentlyContinue
if (-not $modelSim) {
    $knownModelSim = 'C:\intelFPGA\20.1\modelsim_ase\win32aloem\vsim.exe'
    if (Test-Path -LiteralPath $knownModelSim) {
        $modelSimBin = Split-Path -Parent $knownModelSim
        $env:PATH = $modelSimBin + [IO.Path]::PathSeparator + $env:PATH
    } else {
        throw 'ModelSim was not found. Add the ModelSim bin directory to PATH.'
    }
}

$requiredTools = @('python', 'vlib', 'vlog', 'vsim')
foreach ($tool in $requiredTools) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required tool '$tool' was not found."
    }
}
& python -c 'import matplotlib, numpy'
if ($LASTEXITCODE -ne 0) {
    throw 'Python packages matplotlib and numpy are required.'
}

$logDirectory = Join-Path $repoRoot 'verification\logs'
$resultDirectory = Join-Path $repoRoot 'verification\results'
$generatedDirectory = Join-Path $repoRoot 'tb\generated'
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
New-Item -ItemType Directory -Force -Path $resultDirectory | Out-Null
New-Item -ItemType Directory -Force -Path $generatedDirectory | Out-Null

Write-Host '[1/7] Testing the Python reference model'
& python -m unittest discover -s verification -p 'test_*.py' -v
if ($LASTEXITCODE -ne 0) {
    throw 'Python reference-model tests failed.'
}

Write-Host '[2/7] Generating 64 deterministic end-to-end vectors'
& python verification/reference_model.py --output tb/generated/e2e_vectors.txt
if ($LASTEXITCODE -ne 0) {
    throw 'Reference vector generation failed.'
}

Write-Host '[3/7] Compiling RTL and testbenches'
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot 'work\_info'))) {
    & vlib work
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not create the ModelSim work library.'
    }
}

$rtlSources = @(
    'rtl/ai_accel_pkg.sv',
    'rtl/mac_pe.sv',
    'rtl/mac_array_4x4.sv',
    'rtl/scratchpad_sram.sv',
    'rtl/operand_feeder.sv',
    'rtl/requant_relu.sv',
    'rtl/output_tile_writer.sv',
    'rtl/compute_controller.sv',
    'rtl/simple_dma.sv',
    'rtl/perf_counters.sv',
    'rtl/accel_status_irq.sv',
    'rtl/apb_accel_regs.sv',
    'rtl/accel_controller.sv',
    'rtl/ai_accelerator_top.sv'
)
$testbenchSources = Get-ChildItem -LiteralPath 'tb\unit' -Filter '*.sv' |
    Sort-Object Name |
    ForEach-Object { $_.FullName }
$testbenchSources += Get-ChildItem -LiteralPath 'tb\integration' -Filter '*.sv' |
    Sort-Object Name |
    ForEach-Object { $_.FullName }
$compileLog = Join-Path $logDirectory 'compile.log'
& vlog -l $compileLog -sv @rtlSources @testbenchSources
if ($LASTEXITCODE -ne 0) {
    throw "RTL compilation failed. See $compileLog"
}

function Invoke-Simulation {
    param(
        [Parameter(Mandatory)]
        [string]$Testbench,
        [string]$DoCommand = 'run -all; quit -code 0'
    )

    $logPath = Join-Path $logDirectory ($Testbench + '.log')
    & vsim -c -lib work $Testbench -l $logPath -do $DoCommand
    if ($LASTEXITCODE -ne 0) {
        throw "$Testbench returned a non-zero simulator status. See $logPath"
    }
    if (Select-String -LiteralPath $logPath -Pattern '^# \*\* (Error|Fatal):' -Quiet) {
        throw "$Testbench reported a simulation error. See $logPath"
    }
    if (-not (Select-String -LiteralPath $logPath -Pattern ("# " + $Testbench + " PASS") -Quiet)) {
        throw "$Testbench did not emit its PASS signature. See $logPath"
    }
}

$unitTests = @(
    'tb_mac_pe',
    'tb_mac_array_4x4',
    'tb_scratchpad_sram',
    'tb_operand_feeder',
    'tb_requant_relu',
    'tb_output_tile_writer',
    'tb_compute_controller',
    'tb_simple_dma',
    'tb_perf_counters',
    'tb_accel_status_irq',
    'tb_apb_accel_regs',
    'tb_accel_controller',
    'tb_ai_accelerator_top'
)

Write-Host "[4/7] Running $($unitTests.Count) unit regressions"
foreach ($test in $unitTests) {
    Write-Host "  $test"
    Invoke-Simulation -Testbench $test
}

Write-Host '[5/7] Running integrated negative-path and recovery regression'
Invoke-Simulation -Testbench 'tb_end_to_end_errors'

Write-Host '[6/7] Running 64 Python-referenced jobs with RTL waveform capture'
$waveDo = @(
    'vcd file verification/results/rtl_trace.vcd',
    'vcd add /tb_end_to_end/dut/accel_busy',
    'vcd add /tb_end_to_end/dut/dma_busy',
    'vcd add /tb_end_to_end/dut/compute_busy',
    'vcd add /tb_end_to_end/dut/mac_en',
    'vcd add /tb_end_to_end/dut/output_writer_busy',
    'vcd add /tb_end_to_end/dut/mem_req_valid',
    'vcd add /tb_end_to_end/dut/mem_req_ready',
    'vcd add /tb_end_to_end/dut/mem_req_write',
    'vcd add /tb_end_to_end/dut/mem_rsp_valid',
    'vcd add /tb_end_to_end/dut/irq',
    'vcd add /tb_end_to_end/dut/compute_tile_row',
    'vcd add /tb_end_to_end/dut/compute_tile_col',
    'run -all',
    'vcd flush',
    'quit -code 0'
) -join '; '
Invoke-Simulation -Testbench 'tb_end_to_end' -DoCommand $waveDo

Write-Host '[7/7] Writing reports, CSV data, and plots'
& python verification/summarize_results.py `
    --logs verification/logs `
    --output verification/results
if ($LASTEXITCODE -ne 0) {
    throw 'Result summarization failed.'
}
& python verification/render_evidence.py `
    --vcd verification/results/rtl_trace.vcd `
    --log verification/logs/tb_end_to_end.log `
    --metrics verification/results/performance.csv `
    --output verification/results/figures
if ($LASTEXITCODE -ne 0) {
    throw 'Plot generation failed.'
}

Write-Host ''
Write-Host 'PASS: reference model, 13 unit benches, 64 end-to-end jobs, and 6 error scenarios'
Write-Host 'Report: verification/results/verification_report.md'
Write-Host 'Metrics: verification/results/performance.csv'
Write-Host 'Figures: verification/results/figures/'
