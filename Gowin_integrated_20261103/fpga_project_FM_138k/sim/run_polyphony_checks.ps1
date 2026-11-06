param([string]$IverilogDirectory='', [string]$Python='python')
$ErrorActionPreference='Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
 $iv=if($IverilogDirectory){Join-Path $IverilogDirectory 'iverilog.exe'}else{'iverilog'}
 $vvp=if($IverilogDirectory){Join-Path $IverilogDirectory 'vvp.exe'}else{'vvp'}
 & $Python tools/check_polyphony_spectrum.py --generate
 if($LASTEXITCODE -ne 0){throw 'FFT fixture generation failed'}
 $sources=@('src/gesture/gesture_centroid.v','src/gesture/gesture_timbre_control.v','src/top.v','src/ai_bass_accompaniment.v','src/ai_bass_inference.v',
 'src/midi_arpeggiator.v','src/midi_note_owners.v','src/midi_performance_control.v',
 'src/fm_uart_control.v','src/fm_poly_synth.v','src/uart_rx.v','src/i2s_tx.v',
 'src/audio_performance_monitor.v','src/audio_note_latency.v','src/ai_melody_composer.v',
 'src/ai_melody_inference.v','src/audio_fx.v','src/audio_chorus.v','src/audio_phaser.v',
 'src/audio_delay.v','src/audio_reverb.v','src/polyphony_test32.v')
 $cases=@(
  @{Name='tb_polyphony_test32';Files=@('src/polyphony_test32.v')},
  @{Name='tb_polyphony_spectrum';Files=@('src/audio_spectrum_analyzer.v')},
  @{Name='tb_polyphony_audio';Files=$sources}
 )
 foreach($case in $cases){
  $out='tmp/'+$case.Name+'.vvp'
  & $iv -g2012 -s $case.Name -o $out ('sim/'+$case.Name+'.sv') @($case.Files)
  if($LASTEXITCODE -ne 0){throw ('Compile '+$case.Name)}
  & $vvp $out
  if($LASTEXITCODE -ne 0){throw ('Test '+$case.Name)}
 }
 & $Python tools/check_polyphony_spectrum.py
 if($LASTEXITCODE -ne 0){throw 'Production PCM spectrum validation failed'}
 & $iv -g2012 -s tb_spectrum_snapshot '-Ptb_spectrum_snapshot.ADDRESS_BITS=9' -o tmp/linear_snapshot.vvp sim/tb_spectrum_snapshot.sv src/audio_spectrum_snapshot.v
 if($LASTEXITCODE -ne 0){throw 'Linear snapshot compile failed'}
 & $vvp tmp/linear_snapshot.vvp
 if($LASTEXITCODE -ne 0){throw 'Linear snapshot test failed'}
} finally {Pop-Location}
