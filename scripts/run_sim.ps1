# run_sim.ps1 - assemble a test program and run it through xsim.
# Usage: powershell -File scripts\run_sim.ps1 [-Test m1_arith]
param(
    [string]$Test = "m1_arith",
    [string]$VivadoBin = "C:\Xilinx\2025.1\Vivado\bin"
)
$ErrorActionPreference = "Stop"

$root  = Split-Path -Parent $PSScriptRoot
$build = Join-Path $root "build\sim"
New-Item -ItemType Directory -Force -Path $build | Out-Null

# ---- assemble ----
python (Join-Path $root "sw\asm.py") (Join-Path $root "sw\tests\$Test.s") `
    -o (Join-Path $build "$Test.hex") -l (Join-Path $build "$Test.lst")
if ($LASTEXITCODE -ne 0) { Write-Host "assembly failed"; exit 1 }

# ---- compile + elaborate + simulate ----
# compile order doesn't matter to xvlog/xelab, so just take everything
$srcs = @(Get-ChildItem (Join-Path $root "rtl\*.v")) +
        @(Get-ChildItem (Join-Path $root "sim\tb_core_top.v")) |
        ForEach-Object { $_.FullName }

$incdir = Join-Path $root "rtl"

Push-Location $build
try {
    & "$VivadoBin\xvlog.bat" --nolog -i $incdir @srcs
    if ($LASTEXITCODE -ne 0) { Write-Host "xvlog failed"; exit 1 }

    & "$VivadoBin\xelab.bat" tb_core_top --snapshot tb_core_top_sim --nolog --timescale 1ns/1ps
    if ($LASTEXITCODE -ne 0) { Write-Host "xelab failed"; exit 1 }

    # cmd.exe splits 'HEX=x' plusargs on '=', so use the TB's default names
    Copy-Item "$Test.hex" "program.hex" -Force
    Copy-Item (Join-Path $root "sw\tests\$Test.exp") "expected.hex" -Force
    $out = & "$VivadoBin\xsim.bat" tb_core_top_sim -R --nolog
    $out | Write-Host
    if ($out -match "tb_core_top: PASSED") { exit 0 } else { exit 1 }
}
finally {
    Pop-Location
}
