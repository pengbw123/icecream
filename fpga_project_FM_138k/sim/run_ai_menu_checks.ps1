param([string]$IverilogDirectory='')
$ErrorActionPreference='Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    $iv=if($IverilogDirectory){Join-Path $IverilogDirectory 'iverilog.exe'}else{'iverilog'}
    $vp=if($IverilogDirectory){Join-Path $IverilogDirectory 'vvp.exe'}else{'vvp'}
    New-Item -ItemType Directory -Force tmp | Out-Null
    $sources=@('sim/tb_touch_ui.sv','src/midi_arpeggiator.v','src/lesson_player.v',
        'src/lesson_score_memory.v','src/step_sequencer.v','src/touch_ui_controller.v',
        'src/gt9147_reset.v','src/usb_midi/rtl/rv32i.v','src/usb_midi/rtl/usb_midi_host.v',
        'src/ai_melody_composer.v','src/ai_melody_inference.v',
        'src/ai_bass_accompaniment.v','src/ai_bass_inference.v','src/sd_spi_byte.v')
    & $iv -g2012 -s tb_touch_ui -o tmp/ai_menu_ui.vvp @sources
    if($LASTEXITCODE -ne 0){throw 'AI menu firmware testbench compile failed'}
    foreach($case in @('nav_exit','ai','composer','glide_time','keyboard')){
        $log='tmp/ai_menu_'+$case+'.log'
        & $vp tmp/ai_menu_ui.vvp ('+'+$case) *> $log
        if($LASTEXITCODE -ne 0){throw ('AI menu regression failed: '+$case)}
        Get-Content $log -Tail 2
    }
} finally {Pop-Location}
