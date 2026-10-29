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
    & $Python tools/gesture/plane_vectors.py
    if ($LASTEXITCODE -ne 0) { throw 'Plane reference generation failed' }
    $cases = @(
        @{ Name='tb_gesture_position'; Files=@('src/gesture/gesture_position.v') },
        @{ Name='tb_gesture_perform'; Files=@('src/ai_melody_composer.v','src/ai_melody_inference.v') },
        @{ Name='tb_composer_countin'; Files=@('src/ai_melody_composer.v','src/ai_melody_inference.v') },
        @{ Name='tb_gesture_snapshot'; Files=@('src/gesture/gesture_video_snapshot.v') },
        @{ Name='tb_gesture_vote_events'; Files=@('src/gesture/gesture_vote_events.v') },
        @{ Name='tb_gesture_normalize'; Files=@('src/gesture/gesture_normalize.v') },
        @{ Name='tb_gesture_plane_pipeline'; Files=@('src/gesture/gesture_roi.v','src/gesture/gesture_mailbox.v','src/gesture/gesture_mlp.v','src/gesture/gesture_events.v','src/gesture/gesture_pipeline.v') },
        @{ Name='tb_gesture_plane_controller'; Files=@('src/gesture/gesture_position.v','src/gesture/gesture_controller.v','src/gesture/gesture_roi.v','src/gesture/gesture_mailbox.v','src/gesture/gesture_mlp.v','src/gesture/gesture_events.v','src/gesture/gesture_pipeline.v','src/ai_melody_composer.v','src/ai_melody_inference.v') },
        @{ Name='tb_gesture_score_gate'; Files=@('src/gesture/gesture_score_gate.v') },
        @{ Name='tb_gesture_roi'; Files=@('src/gesture/gesture_roi.v') },
        @{ Name='tb_gesture_events'; Files=@('src/gesture/gesture_events.v') },
        @{ Name='tb_gesture_mailbox'; Files=@('src/gesture/gesture_mailbox.v') },
        @{ Name='tb_gesture_mlp'; Files=@('src/gesture/gesture_mlp.v') },
        @{ Name='tb_gesture_composer'; Files=@('src/ai_melody_composer.v','src/ai_melody_inference.v') },
        @{ Name='tb_gesture_video'; Files=@('src/gesture/gesture_video_snapshot.v','src/camera/camera_hdmi_video.v','src/camera/camera_diagnostics.v') },
        @{ Name='tb_gesture_controller'; Files=@('src/gesture/gesture_position.v','src/gesture/gesture_controller.v','src/gesture/gesture_roi.v','src/gesture/gesture_mailbox.v','src/gesture/gesture_mlp.v','src/gesture/gesture_events.v','src/gesture/gesture_pipeline.v','src/ai_melody_composer.v','src/ai_melody_inference.v') },
        @{ Name='tb_gesture_pipeline'; Files=@('src/gesture/gesture_roi.v','src/gesture/gesture_mailbox.v','src/gesture/gesture_mlp.v','src/gesture/gesture_events.v','src/gesture/gesture_pipeline.v') }
    )
    foreach ($case in $cases) {
        if ($case.Files -contains 'src/gesture/gesture_pipeline.v') { $case.Files += @('src/gesture/gesture_score_gate.v','src/gesture/gesture_normalize.v','src/gesture/gesture_vote_events.v') }
        $out = 'tmp/' + $case.Name + '.vvp'
        & $iv '-g2012' '-Wall' '-s' $case.Name '-o' $out ('sim/' + $case.Name + '.sv') @($case.Files)
        if ($LASTEXITCODE -ne 0) { throw "Compile failed: $($case.Name)" }
        & $vvp $out
        if ($LASTEXITCODE -ne 0) { throw "Simulation failed: $($case.Name)" }
    }
} finally { Pop-Location }
