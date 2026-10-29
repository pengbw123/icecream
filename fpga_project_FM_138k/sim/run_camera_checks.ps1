param([string]$IverilogDirectory='', [string]$Python='python', [string]$VendorTftTable='')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    $iv=if($IverilogDirectory){Join-Path $IverilogDirectory 'iverilog.exe'}else{'iverilog'}
    $vvp=if($IverilogDirectory){Join-Path $IverilogDirectory 'vvp.exe'}else{'vvp'}
    if($VendorTftTable){
        & $Python tools/check_ov5640_tft_profile.py $VendorTftTable --record assets/camera_tft/profile_reference.json
        if($LASTEXITCODE -ne 0){throw 'TFT profile differs from supplied working source'}
    }
    $gesture=@('src/gesture/gesture_controller.v','src/gesture/gesture_pipeline.v','src/gesture/gesture_roi.v',
        'src/gesture/gesture_mailbox.v','src/gesture/gesture_normalize.v','src/gesture/gesture_mlp.v','src/gesture/gesture_score_gate.v',
        'src/gesture/gesture_events.v','src/gesture/gesture_vote_events.v','src/gesture/gesture_video_snapshot.v')
    $cases=@(
        @{Name='tb_ov5640_config';Files=@('src/camera/ov5640_config.v','src/camera/camera_sccb.v','sim/ov5640_sccb_model.sv')},
        @{Name='tb_ov5640_capture';Files=@('src/camera/ov5640_capture.v')},
        @{Name='tb_camera_diagnostics';Files=@('src/camera/camera_diagnostics.v')},
        @{Name='tb_camera_recovery';Files=@('src/camera/camera_hdmi_video.v','src/camera/camera_diagnostics.v','src/camera/camera_framebuffer.v')},
        @{Name='tb_ov5640_capture_tft';Files=@('src/camera/ov5640_capture.v')},
        @{Name='tb_camera_pipeline';Files=@('src/camera/camera_hdmi_tx.v','src/camera/ov5640_config.v','src/camera/camera_sccb.v','src/camera/ov5640_capture.v','src/camera/camera_framebuffer.v','src/camera/camera_hdmi_video.v','src/camera/camera_diagnostics.v','src/tmds_encoder.v','sim/ov5640_sccb_model.sv')+$gesture}
    )
    New-Item -ItemType Directory -Force tmp | Out-Null
    foreach($case in $cases){
        $out='tmp/tft_'+$case.Name+'.vvp'
        & $iv -g2012 -s $case.Name -o $out ('sim/'+$case.Name+'.sv') @($case.Files)
        if($LASTEXITCODE -ne 0){throw ('Compile failed '+$case.Name)}
        & $vvp $out *> ('tmp/tft_'+$case.Name+'.log')
        if($LASTEXITCODE -ne 0){throw ('Simulation failed '+$case.Name)}
        Get-Content ('tmp/tft_'+$case.Name+'.log') -Tail 2
    }
} finally {Pop-Location}
