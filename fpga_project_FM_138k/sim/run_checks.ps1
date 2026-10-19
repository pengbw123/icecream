param([string]$IverilogDirectory = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    $iverilog = if ($IverilogDirectory) { Join-Path $IverilogDirectory 'iverilog.exe' } else { 'iverilog' }
    $vvp = if ($IverilogDirectory) { Join-Path $IverilogDirectory 'vvp.exe' } else { 'vvp' }
    New-Item -ItemType Directory -Force -Path 'tmp' | Out-Null
    $cases = @(
        @{ Name='tb_audio_xy_scope'; Sources=@('sim/tb_audio_xy_scope.sv','src/audio_xy_scope.v') },
        @{ Name='tb_138k_io'; Sources=@('sim/tb_138k_io.sv','../fpga_midi_bridge_25k/src/midi_frame_tx.v','src/midi_bridge_rx.v','src/uart_rx.v','src/ws2812_keys.v','src/tmds_encoder.v') },
        @{ Name='tb_touch_ui'; Sources=@('sim/tb_touch_ui.sv','src/touch_ui_controller.v','src/gt9147_reset.v','src/usb_midi/rtl/rv32i.v','src/usb_midi/rtl/usb_midi_host.v') },
        @{ Name='tb_rgb_visualizer'; Sources=@('sim/tb_rgb_visualizer.sv','src/rgb_visualizer.v','src/audio_xy_scope.v') }
    )
    foreach ($case in $cases) {
        $outputFile = 'tmp/' + $case.Name + '.vvp'
        $arguments = @('-g2012','-s',$case.Name,'-o',$outputFile) + $case.Sources
        & $iverilog @arguments
        if ($LASTEXITCODE -ne 0) { throw ('Compile failed: ' + $case.Name) }
        & $vvp $outputFile
        if ($LASTEXITCODE -ne 0) { throw ('Simulation failed: ' + $case.Name) }
    }
    Write-Host 'All 138K I/O, touch and RGB regression checks passed.'
} finally { Pop-Location }
