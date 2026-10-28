param([string]$IverilogDirectory = '', [string]$Python = 'python')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    $iv = if ($IverilogDirectory) { Join-Path $IverilogDirectory 'iverilog.exe' } else { 'iverilog' }
    $vvp = if ($IverilogDirectory) { Join-Path $IverilogDirectory 'vvp.exe' } else { 'vvp' }
    New-Item -ItemType Directory -Force tmp | Out-Null
    & $Python tools/gesture/check_export.py
    if ($LASTEXITCODE -ne 0) { throw 'Gesture export reference check failed' }
    $cases = @(
        @{ Name='tb_gesture_roi'; Files=@('src/gesture/gesture_roi.v') },
        @{ Name='tb_gesture_events'; Files=@('src/gesture/gesture_events.v') },
        @{ Name='tb_gesture_mailbox'; Files=@('src/gesture/gesture_mailbox.v') },
        @{ Name='tb_gesture_mlp'; Files=@('src/gesture/gesture_mlp.v') },
        @{ Name='tb_gesture_pipeline'; Files=@('src/gesture/gesture_roi.v','src/gesture/gesture_mailbox.v','src/gesture/gesture_mlp.v','src/gesture/gesture_events.v','src/gesture/gesture_pipeline.v') }
    )
    foreach ($case in $cases) {
        $out = 'tmp/' + $case.Name + '.vvp'
        & $iv '-g2012' '-Wall' '-s' $case.Name '-o' $out ('sim/' + $case.Name + '.sv') @($case.Files)
        if ($LASTEXITCODE -ne 0) { throw "Compile failed: $($case.Name)" }
        & $vvp $out
        if ($LASTEXITCODE -ne 0) { throw "Simulation failed: $($case.Name)" }
    }
} finally { Pop-Location }
