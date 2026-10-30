param([string]$IverilogDirectory='', [string]$Python='python')
$ErrorActionPreference='Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    $iv=if($IverilogDirectory){Join-Path $IverilogDirectory 'iverilog.exe'}else{'iverilog'}
    $vvp=if($IverilogDirectory){Join-Path $IverilogDirectory 'vvp.exe'}else{'vvp'}
    & $Python tools/gesture/gray_reference.py
    if($LASTEXITCODE -ne 0){throw 'Gray software oracle failed'}
    & $iv -g2012 -Wall -s tb_gesture_gray -o tmp/gray.vvp sim/tb_gesture_gray.sv src/gesture/gesture_gray_frontend.v src/gesture/gesture_gray_roi.v src/gesture/gesture_gray_mailbox.v
    if($LASTEXITCODE -ne 0){throw 'Gray RTL compile failed'}
    & $vvp tmp/gray.vvp
    if($LASTEXITCODE -ne 0){throw 'Gray RTL checks failed'}
} finally {Pop-Location}
