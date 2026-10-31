param([string]$IverilogDirectory='')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$iv=if($IverilogDirectory){Join-Path $IverilogDirectory 'iverilog.exe'}else{'iverilog'}
$vvp=if($IverilogDirectory){Join-Path $IverilogDirectory 'vvp.exe'}else{'vvp'}
$guide=@('src/uart_rx.v','src/uart_tx.v','src/uart_packet_rx.v','src/uart_status_reply.v',
    'src/led_guide/debounced_press.v','src/led_guide/sunny_tutorial_player.v',
    'src/led_guide/sunny_tutorial_system.v','src/led_guide/score_strip_guide.v',
    'src/led_guide/ws2812_frame_tx.v','src/score/score_player.v')
$audio=@('src/top.v','src/ai_bass_accompaniment.v','src/ai_bass_inference.v',
    'src/midi_arpeggiator.v','src/midi_note_owners.v','src/midi_performance_control.v',
    'src/fm_uart_control.v','src/fm_poly_synth.v','src/uart_rx.v','src/i2s_tx.v',
    'src/audio_performance_monitor.v','src/audio_note_latency.v',
    'src/ai_melody_composer.v','src/ai_melody_inference.v')
$cases=@(
    @{Name='tb_ui_sparse';Files=@('src/usb_midi/rtl/rv32i.v')},
    @{Name='tb_score_arbiter';Files=@('src/score/score_event_arbiter.v')},
    @{Name='tb_score_player';Files=@('src/score/score_player.v')},
    @{Name='tb_score_capacity';Files=@('src/score/score_player.v')},
    @{Name='tb_sunny_tutorial_player';Files=@('src/led_guide/sunny_tutorial_player.v')},
    @{Name='tb_sunny_tutorial_system';Files=$guide},
    @{Name='tb_sunny_compiled_defaults';Files=$guide},
    @{Name='tb_sunny_wait_for_key';Files=$guide},
    @{Name='tb_138k_score_tutorial';Files=$guide},
    @{Name='tb_score_guard';Files=$guide},
    @{Name='tb_138k_score_window';Files=$guide;Args=@('+PACKETS=sim/fixtures/android_truth_part2_words.mem')},
    @{Name='tb_138k_score_window';Files=$guide;Compile=@('-Ptb_138k_score_window.PHYSICAL_TIMING=1');Args=@('+PACKETS=sim/fixtures/android_truth_part2_words.mem')},
    @{Name='tb_score_audio';Files=$audio}
)
Push-Location $root
try {
    New-Item -ItemType Directory -Force tmp | Out-Null
    foreach($case in $cases){
        $out='tmp/import_'+$case.Name+'.vvp'
        $compileArgs=@('-g2012','-s',$case.Name,'-o',$out,('sim/'+$case.Name+'.sv'))
        if($case.Compile){$compileArgs+=@($case.Compile)}
        $compileArgs+=@($case.Files)
        & $iv @compileArgs
        if($LASTEXITCODE -ne 0){throw ('Compile failed: '+$case.Name)}
        if($case.Args){ & $vvp $out @($case.Args) }else{ & $vvp $out }
        if($LASTEXITCODE -ne 0){throw ('Simulation failed: '+$case.Name)}
    }
    Write-Output 'PASS Bluetooth/score/LED migration RTL regression'
} finally {Pop-Location}
