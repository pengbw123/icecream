param([string]$IverilogDirectory = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    $iverilog = if ($IverilogDirectory) { Join-Path $IverilogDirectory 'iverilog.exe' } else { 'iverilog' }
    $vvp = if ($IverilogDirectory) { Join-Path $IverilogDirectory 'vvp.exe' } else { 'vvp' }
    New-Item -ItemType Directory -Force -Path 'tmp' | Out-Null
    $cases = @(
        @{ Name='tb_visual_auto_gain'; Sources=@('sim/tb_visual_auto_gain.sv','src/visual_auto_gain.v') },
        @{ Name='tb_audio_xy_scope'; Sources=@('sim/tb_audio_xy_scope.sv','src/audio_xy_scope.v') },
        @{ Name='tb_audio_wave_scope'; Sources=@('sim/tb_audio_wave_scope.sv','src/audio_wave_scope.v') },
        @{ Name='tb_char_display'; Sources=@('sim/tb_char_display.sv','src/rtl_char_display.v') },
    @{ Name='tb_eg_curve'; Sources=@('sim/tb_eg_curve.sv','src/ui_eg_curve.v') },
    @{ Name='tb_audio_fx'; Sources=@('sim/tb_audio_fx.sv','src/audio_fx.v') },
    @{ Name='tb_algo_map'; Sources=@('sim/tb_algo_map.sv','src/ui_algo_map.v') },
        @{ Name='tb_fm_readback'; Sources=@('sim/tb_fm_readback.sv','src/fm_uart_control.v','src/fm_poly_synth.v','src/uart_rx.v','src/audio_fx.v') },
        @{ Name='tb_138k_io'; Sources=@('sim/tb_138k_io.sv','../fpga_midi_bridge_25k/src/midi_frame_tx.v','src/midi_bridge_rx.v','src/uart_rx.v','src/ws2812_keys.v','src/tmds_encoder.v') },
        @{ Name='tb_touch_ui'; Sources=@('sim/tb_touch_ui.sv','src/touch_ui_controller.v','src/gt9147_reset.v','src/usb_midi/rtl/rv32i.v','src/usb_midi/rtl/usb_midi_host.v') },
        @{ Name='tb_rgb_visualizer'; Sources=@('sim/tb_rgb_visualizer.sv','src/rgb_visualizer.v','src/audio_xy_scope.v','src/audio_wave_scope.v','src/rtl_performance_text.v','src/rtl_char_display.v','src/ui_eg_curve.v','src/ui_algo_map.v') }
    )
    foreach ($case in $cases) {
        $outputFile = 'tmp/' + $case.Name + '.vvp'
        $arguments = @('-g2012','-s',$case.Name,'-o',$outputFile) + $case.Sources
        & $iverilog @arguments
        if ($LASTEXITCODE -ne 0) { throw ('Compile failed: ' + $case.Name) }
        & $vvp $outputFile
        if ($LASTEXITCODE -ne 0) { throw ('Simulation failed: ' + $case.Name) }
        if ($case.Name -eq 'tb_rgb_visualizer') {
            & $vvp $outputFile '+quiet'
            if ($LASTEXITCODE -ne 0) { throw 'Quiet-signal RGB simulation failed.' }
            & $vvp $outputFile '+wave'
            if ($LASTEXITCODE -ne 0) { throw 'Waveform RGB simulation failed.' }
            & $vvp $outputFile '+messy'
            if ($LASTEXITCODE -ne 0) { throw 'Complex-waveform continuity regression failed.' }
        }
        if ($case.Name -eq 'tb_audio_xy_scope') {
            & $vvp $outputFile '+attack'
            if ($LASTEXITCODE -ne 0) { throw 'XY attack regression failed.' }
        }
    }
    Write-Host 'All 138K I/O, touch and RGB regression checks passed.'
} finally { Pop-Location }



