# run_all.ps1 - full regression: every test in sw/tests, checked two ways.
#
# For each <test>.s:
#   1. assemble it
#   2. run it on the Python ISS (sw/iss.py) to produce an independent
#      golden final state
#   3. if a hand-written <test>.exp exists, cross-check the ISS against it
#      (catches ISS bugs)
#   4. run the RTL in xsim against the ISS golden state - every register
#      and memory word checked, no don't-cares (catches RTL bugs)
#
# Usage: powershell -File scripts\run_all.ps1
param(
    [string]$VivadoBin = "C:\Xilinx\2025.1\Vivado\bin"
)
$ErrorActionPreference = "Stop"

$root  = Split-Path -Parent $PSScriptRoot
$build = Join-Path $root "build\regress"
New-Item -ItemType Directory -Force -Path $build | Out-Null

# ---- compile + elaborate once ----
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

    # ---- run every test ----
    $results = @()
    $fail = 0
    foreach ($src in Get-ChildItem (Join-Path $root "sw\tests\*.s") | Sort-Object Name) {
        $t = $src.BaseName
        $status = "PASS"
        $note = ""

        python (Join-Path $root "sw\asm.py") $src.FullName -o "$t.hex" | Out-Null
        if ($LASTEXITCODE -ne 0) { $status = "FAIL"; $note = "assembly failed" }

        if ($status -eq "PASS") {
            $hand = Join-Path $root "sw\tests\$t.exp"
            if (Test-Path $hand) {
                python (Join-Path $root "sw\iss.py") "$t.hex" -o "$t.golden.exp" --check $hand | Out-Null
            } else {
                python (Join-Path $root "sw\iss.py") "$t.hex" -o "$t.golden.exp" | Out-Null
            }
            if ($LASTEXITCODE -ne 0) { $status = "FAIL"; $note = "ISS error or ISS/exp mismatch" }
        }

        if ($status -eq "PASS") {
            Copy-Item "$t.hex" "program.hex" -Force
            Copy-Item "$t.golden.exp" "expected.hex" -Force
            $out = & "$VivadoBin\xsim.bat" tb_core_top_sim -R --nolog
            $perf = ($out | Select-String "perf:").Line
            if ($out -match "tb_core_top: PASSED") {
                $note = $perf -replace "^perf: ", ""
            } else {
                $status = "FAIL"; $note = "RTL/golden mismatch (see xsim output)"
                $out | Write-Host
            }
        }

        if ($status -eq "FAIL") { $fail++ }
        $results += "{0,-6} {1,-14} {2}" -f $status, $t, $note
    }

    Write-Host ""
    Write-Host "==== regression summary ===="
    $results | ForEach-Object { Write-Host $_ }
    if ($fail -eq 0) { Write-Host "==== ALL TESTS PASSED ===="; exit 0 }
    else             { Write-Host "==== $fail TEST(S) FAILED ===="; exit 1 }
}
finally {
    Pop-Location
}
