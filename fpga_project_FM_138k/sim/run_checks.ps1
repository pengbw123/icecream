param([string]$IverilogDirectory = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    $iverilog = if ($IverilogDirectory) { Join-Path $IverilogDirectory 'iverilog.exe' } else { 'iverilog' }
    $vvp = if ($IverilogDirectory) { Join-Path $IverilogDirectory 'vvp.exe' } else { 'vvp' }
    New-Item -ItemType Directory -Force -Path 'tmp' | Out-Null
    $cases = @(
        @{ Name='tb_audio_performance_monitor'; Sources=@('sim/tb_audio_performance_monitor.sv','src/audio_performance_monitor.v') },
        @{ Name='tb_step_sequencer'; Sources=@('sim/tb_step_sequencer.sv','src/step_sequencer.v') },
        @{ Name='tb_midi_arpeggiator'; Sources=@('sim/tb_midi_arpeggiator.sv','src/midi_arpeggiator.v') },
        @{ Name='tb_lesson_player'; Sources=@('sim/tb_lesson_player.sv','src/lesson_player.v','src/lesson_score_memory.v') },
        @{ Name='tb_midi_note_owners'; Sources=@('sim/tb_midi_note_owners.sv','src/midi_note_owners.v') },
        @{ Name='tb_midi_owner_queue'; Sources=@('sim/tb_midi_owner_queue.sv','src/midi_note_owners.v') },
        @{ Name='tb_lesson_view'; Sources=@('sim/tb_lesson_view.sv','src/lesson_view.v','src/lesson_score_memory.v') },
        @{ Name='tb_lesson_loader'; Sources=@('sim/tb_lesson_loader.sv','src/lesson_player.v','src/lesson_score_memory.v','src/step_sequencer.v','src/touch_ui_controller.v','src/gt9147_reset.v','src/usb_midi/rtl/rv32i.v','src/usb_midi/rtl/usb_midi_host.v') },
        @{ Name='tb_velocity80'; Sources=@('sim/tb_velocity80.sv','../fpga_midi_bridge_25k/src/top_bridge.v','../fpga_midi_bridge_25k/src/midi_frame_tx.v','src/midi_performance_control.v') },
        @{ Name='tb_audio_spectrum'; Sources=@('sim/tb_audio_spectrum.sv','src/audio_spectrum_analyzer.v') },
        @{ Name='tb_spectrum_snapshot'; Sources=@('sim/tb_spectrum_snapshot.sv','src/audio_spectrum_snapshot.v') },
        @{ Name='tb_i2s_output_select'; Sources=@('sim/tb_i2s_output_select.sv','src/i2s_tx.v') },
        @{ Name='tb_visual_auto_gain'; Sources=@('sim/tb_visual_auto_gain.sv','src/visual_auto_gain.v') },
        @{ Name='tb_audio_xy_scope'; Sources=@('sim/tb_audio_xy_scope.sv','src/audio_xy_scope.v') },
        @{ Name='tb_audio_wave_scope'; Sources=@('sim/tb_audio_wave_scope.sv','src/audio_wave_scope.v') },
        @{ Name='tb_char_display'; Sources=@('sim/tb_char_display.sv','src/rtl_char_display.v') },
    @{ Name='tb_eg_curve'; Sources=@('sim/tb_eg_curve.sv','src/ui_eg_curve.v') },
    @{ Name='tb_eg_multi'; Sources=@('sim/tb_eg_multi.sv','src/ui_eg_multi.v') },
    @{ Name='tb_audio_fx'; Sources=@('sim/tb_audio_fx.sv','src/audio_fx.v','src/audio_chorus.v','src/audio_phaser.v','src/audio_delay.v','src/audio_reverb.v') },
    @{ Name='tb_chorus_reverb'; Sources=@('sim/tb_chorus_reverb.sv','src/audio_chorus.v','src/audio_reverb.v') },
    @{ Name='tb_delay_phaser'; Sources=@('sim/tb_delay_phaser.sv','src/audio_delay.v','src/audio_phaser.v') },
    @{ Name='tb_es8388_output'; Sources=@('sim/tb_es8388_output.sv','src/es8388_output.v','src/i2s_tx.v') },
    @{ Name='tb_es8388_i2c_faults'; Sources=@('sim/tb_es8388_i2c_faults.sv','src/es8388_output.v') },
        @{ Name='tb_hdmi_scope_video'; Sources=@('sim/tb_hdmi_scope_video.sv','src/lesson_view.v','src/lesson_score_memory.v','src/hdmi_scope_video.v','src/audio_spectrum_snapshot.v','src/audio_wave_scope.v','src/audio_xy_scope.v') },
    @{ Name='tb_algo_map'; Sources=@('sim/tb_algo_map.sv','src/ui_algo_map.v') },
        @{ Name='tb_fm_sine_interpolation'; Sources=@('sim/tb_fm_sine_interpolation.sv','src/fm_poly_synth.v') },
        @{ Name='tb_fm_readback'; Sources=@('sim/tb_fm_readback.sv','src/audio_performance_monitor.v','src/fm_uart_control.v','src/fm_poly_synth.v','src/uart_rx.v','src/audio_fx.v','src/audio_chorus.v','src/audio_phaser.v','src/audio_delay.v','src/audio_reverb.v') },
        @{ Name='tb_138k_io'; Sources=@('sim/tb_138k_io.sv','../fpga_midi_bridge_25k/src/midi_frame_tx.v','src/midi_bridge_rx.v','src/uart_rx.v','src/ws2812_keys.v','src/tmds_encoder.v') },
        @{ Name='tb_touch_ui'; Sources=@('sim/tb_touch_ui.sv','src/midi_arpeggiator.v','src/lesson_player.v','src/lesson_score_memory.v','src/step_sequencer.v','src/touch_ui_controller.v','src/gt9147_reset.v','src/usb_midi/rtl/rv32i.v','src/usb_midi/rtl/usb_midi_host.v') },
        @{ Name='tb_rgb_visualizer'; Sources=@('sim/tb_rgb_visualizer.sv','src/lesson_view.v','src/lesson_score_memory.v','src/rgb_visualizer.v','src/audio_spectrum_snapshot.v','src/audio_xy_scope.v','src/audio_wave_scope.v','src/rtl_performance_text.v','src/rtl_char_display.v','src/ui_eg_curve.v','src/ui_algo_map.v','src/ui_eg_multi.v') }
    )
    foreach ($case in $cases) {
        $outputFile = 'tmp/' + $case.Name + '.vvp'
        $arguments = @('-g2012','-s',$case.Name,'-o',$outputFile) + $case.Sources
        & $iverilog @arguments
        if ($LASTEXITCODE -ne 0) { throw ('Compile failed: ' + $case.Name) }
        & $vvp $outputFile
        if ($LASTEXITCODE -ne 0) { throw ('Simulation failed: ' + $case.Name) }
        if ($case.Name -eq 'tb_rgb_visualizer') {
            & $vvp $outputFile '+arp'
            if ($LASTEXITCODE -ne 0) { throw 'Arpeggiator RGB keyboard regression failed.' }
            & $vvp $outputFile '+seq'
            if ($LASTEXITCODE -ne 0) { throw 'Sequencer RGB keyboard regression failed.' }
            & $vvp $outputFile '+quiet'
            if ($LASTEXITCODE -ne 0) { throw 'Quiet-signal RGB simulation failed.' }
            & $vvp $outputFile '+wave'
            if ($LASTEXITCODE -ne 0) { throw 'Waveform RGB simulation failed.' }
            & $vvp $outputFile '+messy'
            if ($LASTEXITCODE -ne 0) { throw 'Complex-waveform continuity regression failed.' }
            & $vvp $outputFile '+spectrum'
            if ($LASTEXITCODE -ne 0) { throw 'RGB spectrum bars/gaps regression failed.' }
        }
        if ($case.Name -eq 'tb_audio_xy_scope') {
            & $vvp $outputFile '+attack'
            if ($LASTEXITCODE -ne 0) { throw 'XY attack regression failed.' }
        }
        if ($case.Name -eq 'tb_hdmi_scope_video') {
            & $vvp $outputFile '+spectrum'
            if ($LASTEXITCODE -ne 0) { throw 'HDMI spectrum raster regression failed.' }
        }
        if ($case.Name -eq 'tb_fm_readback') {
            & $vvp $outputFile '+metrics'
            if ($LASTEXITCODE -ne 0) { throw 'Real FM performance telemetry regression failed.' }
            $metrics16 = 'tmp/tb_fm_metrics16.vvp'
            & $iverilog '-g2012' '-s' 'tb_fm_readback' '-Ptb_fm_readback.TEST_VOICES=16' '-o' $metrics16 @($case.Sources)
            if ($LASTEXITCODE -ne 0) { throw '16-voice telemetry compile failed.' }
            & $vvp $metrics16 '+metrics'
            if ($LASTEXITCODE -ne 0) { throw '16-voice telemetry regression failed.' }
            & $vvp $outputFile '+legato'
            if ($LASTEXITCODE -ne 0) { throw 'Mono legato regression failed.' }
        }
        if ($case.Name -eq 'tb_touch_ui') {
            & $vvp $outputFile '+metrics'
            if ($LASTEXITCODE -ne 0) { throw 'Performance monitor UI regression failed.' }
            & $vvp $outputFile '+seq'
            if ($LASTEXITCODE -ne 0) { throw 'Step sequencer UI regression failed.' }
            & $vvp $outputFile '+seq' '+glide_delay'
            if ($LASTEXITCODE -ne 0) { throw 'Delayed glide readback across automatic tools failed.' }
            & $vvp $outputFile '+arp'
            if ($LASTEXITCODE -ne 0) { throw 'Arpeggiator UI regression failed.' }
            & $vvp $outputFile '+lesson'
            if ($LASTEXITCODE -ne 0) { throw 'Assisted performance UI regression failed.' }

            & $vvp $outputFile '+keyboard'
            if ($LASTEXITCODE -ne 0) { throw 'Full-width keyboard, velocity and output-selection regression failed.' }
            & $vvp $outputFile '+spectrum'
            if ($LASTEXITCODE -ne 0) { throw 'Spectrum UI mode/shortcut regression failed.' }
            & $vvp $outputFile '+performance'
            if ($LASTEXITCODE -ne 0) { throw '128 presets and glide menu regression failed.' }
        }
    }
    Write-Host 'All 138K I/O, touch and RGB regression checks passed.'
} finally { Pop-Location }



