param([string]$IverilogDirectory='', [switch]$GesturePerformance)
$ErrorActionPreference='Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    $iv=if($IverilogDirectory){Join-Path $IverilogDirectory 'iverilog.exe'}else{'iverilog'}
    $vvp=if($IverilogDirectory){Join-Path $IverilogDirectory 'vvp.exe'}else{'vvp'}
    $sources=@('src/gesture/gesture_centroid.v','src/gesture/gesture_timbre_control.v','src/top.v','src/ai_bass_accompaniment.v','src/ai_bass_inference.v',
      'src/midi_arpeggiator.v','src/midi_note_owners.v','src/midi_performance_control.v',
      'src/fm_uart_control.v','src/fm_poly_synth.v','src/uart_rx.v','src/i2s_tx.v',
      'src/audio_performance_monitor.v','src/audio_note_latency.v','src/ai_melody_composer.v',
      'src/ai_melody_inference.v','src/ch376/usb_midi_event_decode.v',
      'src/ch376/midi_event_arbiter3.v','src/ch376/midi_input_queue.v',
      'src/score/score_event_arbiter.v','src/midi_bridge_rx.v',
      'src/gesture/gesture_performer.v','src/gesture/gesture_chopper.v',
      '../fpga_midi_bridge_25k/src/midi_frame_tx.v',
      'src/audio_fx.v','src/audio_chorus.v','src/audio_phaser.v','src/audio_delay.v','src/audio_reverb.v')
    if($GesturePerformance) {
        & $iv -g2012 -s tb_usb_single_voice -o tmp/gesture_production.vvp '-Ptb_usb_single_voice.BOARD_FX=1' '-Ptb_usb_single_voice.GESTURE_CASE=1' sim/tb_usb_single_voice.sv @sources
        if($LASTEXITCODE -ne 0){throw 'Gesture production compile failed'}
        & $vvp tmp/gesture_production.vvp
        if($LASTEXITCODE -ne 0){throw 'Gesture production regression failed'}
        return
    }
    foreach($bridge in @(1,0)) {
        $output='tmp/midi_ingress_'+$bridge+'.vvp'
        & $iv -g2012 -s tb_usb_single_voice -o $output '-Ptb_usb_single_voice.BOARD_FX=1' ("-Ptb_usb_single_voice.USE_BRIDGE=$bridge") sim/tb_usb_single_voice.sv @sources
        if($LASTEXITCODE -ne 0){throw 'MIDI ingress compile failed'}
        & $vvp $output
        if($LASTEXITCODE -ne 0){throw 'MIDI ingress regression failed'}
    }
    & $iv -g2012 -s tb_138k_io -o tmp/bridge_io.vvp sim/tb_138k_io.sv ../fpga_midi_bridge_25k/src/midi_frame_tx.v src/midi_bridge_rx.v src/uart_rx.v src/ws2812_keys.v src/tmds_encoder.v
    if($LASTEXITCODE -ne 0){throw 'Bridge protocol compile failed'}
    & $vvp tmp/bridge_io.vvp
    if($LASTEXITCODE -ne 0){throw 'Bridge protocol regression failed'}
} finally {Pop-Location}
