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
    & $Python tools/gesture/check_gray_cnn.py
    if($LASTEXITCODE -ne 0){throw 'CNN export failed'}
    $cases=@(
        @{Name='tb_gesture_gray_cnn';Files=@('src/gesture/gesture_gray_cnn.v')},
        @{Name='tb_gesture_gray_pipeline';Files=@('src/gesture/gesture_gray_frontend.v','src/gesture/gesture_gray_roi.v','src/gesture/gesture_gray_mailbox.v','src/gesture/gesture_gray_cnn.v','src/gesture/gesture_gray_pipeline.v','src/gesture/gesture_vote_events.v')},
        @{Name='tb_gesture_gray_video';Files=@('src/gesture/gesture_video_snapshot.v','src/camera/camera_hdmi_video.v','src/camera/camera_diagnostics.v')}
    )
    foreach($case in $cases){
        $out='tmp/'+$case.Name+'.vvp'
        & $iv -g2012 -s $case.Name -o $out ('sim/'+$case.Name+'.sv') @($case.Files)
        if($LASTEXITCODE -ne 0){throw ('Compile '+$case.Name)}
        & $vvp $out
        if($LASTEXITCODE -ne 0){throw ('Test '+$case.Name)}
    }
} finally {Pop-Location}
