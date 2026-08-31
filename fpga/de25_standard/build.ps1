[CmdletBinding()]
param(
    [string]$Device = 'A5ED013BB32AE4SCS',
    [string]$QuartusRoot,
    [switch]$Compile
)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path

function Find-QuartusShell {
    param([string]$RequestedRoot)

    if ($RequestedRoot) {
        $requestedShell = Join-Path $RequestedRoot 'quartus\bin64\quartus_sh.exe'
        if (-not (Test-Path -LiteralPath $requestedShell)) {
            throw "quartus_sh.exe was not found below QuartusRoot '$RequestedRoot'."
        }
        return $requestedShell
    }

    $pathShell = Get-Command quartus_sh.exe -ErrorAction SilentlyContinue
    if ($pathShell) {
        return $pathShell.Source
    }

    $installRoots = @('C:\altera_pro', 'C:\intelFPGA_pro')
    $candidates = foreach ($installRoot in $installRoots) {
        if (Test-Path -LiteralPath $installRoot) {
            Get-ChildItem -LiteralPath $installRoot -Directory -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $candidate = Join-Path $_.FullName 'quartus\bin64\quartus_sh.exe'
                    if (Test-Path -LiteralPath $candidate) {
                        Get-Item -LiteralPath $candidate
                    }
                }
        }
    }

    $selected = $candidates | Sort-Object FullName -Descending | Select-Object -First 1
    if (-not $selected) {
        throw 'quartus_sh.exe was not found. Install Quartus Prime Pro with Agilex 5 device support.'
    }
    return $selected.FullName
}

$quartusShell = Find-QuartusShell -RequestedRoot $QuartusRoot
Write-Host "Using Quartus: $quartusShell"
Write-Host "Target device: $Device (DE25-Standard Rev.D)"

$quartusBin = Split-Path -Parent $quartusShell
$quartusDirectory = Split-Path -Parent $quartusBin
$quartusInstallRoot = Split-Path -Parent $quartusDirectory
$ipDeploy = Join-Path $quartusInstallRoot 'qsys\bin\ip-deploy.exe'
if (-not (Test-Path -LiteralPath $ipDeploy)) {
    throw "Reset Release IP generator was not found at '$ipDeploy'."
}

$projectDirectory = Join-Path $scriptDirectory 'build_cli'
$resetReleaseDirectory = Join-Path $projectDirectory 'ip\reset_release'
New-Item -ItemType Directory -Path $resetReleaseDirectory -Force | Out-Null

Write-Host 'Generating the Agilex 5 Reset Release IP'
& $ipDeploy `
    --component-name=altera_s10_user_rst_clkgate `
    --part=$Device `
    --output-name=reset_release `
    --output-directory=$resetReleaseDirectory
if ($LASTEXITCODE -ne 0) {
    throw 'Reset Release IP generation failed.'
}

$resetReleaseIp = Join-Path $resetReleaseDirectory 'reset_release.ip'
if (-not (Test-Path -LiteralPath $resetReleaseIp)) {
    throw "Reset Release IP generation did not create '$resetReleaseIp'."
}

$env:DE25_DEVICE = $Device
$env:DE25_PROJECT_DIR = $projectDirectory
$env:DE25_RESET_RELEASE_IP = $resetReleaseIp
& $quartusShell -t (Join-Path $scriptDirectory 'create_project.tcl')
if ($LASTEXITCODE -ne 0) {
    throw 'Quartus project creation failed.'
}

if ($Compile) {
    $project = Join-Path $projectDirectory 'de25_standard_ai_accelerator'
    & $quartusShell --flow compile $project
    if ($LASTEXITCODE -ne 0) {
        throw 'Quartus compilation failed.'
    }
}
