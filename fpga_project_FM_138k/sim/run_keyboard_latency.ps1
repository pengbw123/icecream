param([string]$IverilogDirectory='')
$ErrorActionPreference='Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
 $iv=if($IverilogDirectory){Join-Path $IverilogDirectory 'iverilog.exe'}else{'iverilog'}
 $vvp=if($IverilogDirectory){Join-Path $IverilogDirectory 'vvp.exe'}else{'vvp'}
 $sources=@('src/top.v','src/ai_bass_accompaniment.v','src/ai_bass_inference.v',
 'src/midi_arpeggiator.v','src/midi_note_owners.v','src/midi_performance_control.v',
 'src/fm_uart_control.v','src/fm_poly_synth.v','src/uart_rx.v','src/i2s_tx.v',
 'src/audio_performance_monitor.v','src/audio_note_latency.v','src/ai_melody_composer.v',
 'src/ai_melody_inference.v','src/ch376/usb_midi_event_decode.v',
 'src/ch376/midi_event_arbiter3.v','src/ch376/midi_input_queue.v')
 New-Item -ItemType Directory -Force tmp | Out-Null
 & $iv -g2012 -s tb_keyboard_latency_audio -o tmp/keyboard_latency.vvp sim/tb_keyboard_latency_audio.sv @sources
 if($LASTEXITCODE -ne 0){throw 'Keyboard latency compile failed'}
 & $vvp tmp/keyboard_latency.vvp
 if($LASTEXITCODE -ne 0){throw 'Keyboard latency simulation failed'}
} finally {Pop-Location}
