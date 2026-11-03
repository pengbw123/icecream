param(
    [string]$Zig = $env:ZIG_EXE,
    [switch]$MidiProbe
)

$ErrorActionPreference = 'Stop'
$firmwareDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $Zig) {
    $zigCommand = Get-Command zig -ErrorAction SilentlyContinue
    if ($zigCommand) {
        $Zig = $zigCommand.Source
    }
}
if (-not $Zig -or -not (Test-Path -LiteralPath $Zig)) {
    throw 'zig executable not found. Pass -Zig <path-to-zig.exe> or set ZIG_EXE.'
}

$sources = @(
    'start.S',
    'main.c'
) | ForEach-Object { Join-Path $firmwareDir $_ }

$elf = Join-Path $firmwareDir 'firmware.elf'
$binary = Join-Path $firmwareDir 'firmware.bin'
$hex = Join-Path $firmwareDir 'firmware.hex'

# This soft core implements RV32I only.  Zig's baseline_rv32 also enables
# A/C/D/M, which allowed 16-bit compressed and multiply instructions into the
# image and made the CPU lose instruction alignment during startup.
$probeFlag=if($MidiProbe){'-DMIDI_INPUT_PROBE=1'}else{'-DMIDI_INPUT_PROBE=0'}
& $Zig cc `
    $probeFlag `
    -target riscv32-freestanding-none `
    -mcpu=generic_rv32 `
    -mabi=ilp32 `
    -Oz `
    -flto `
    -ffreestanding `
    -fno-builtin `
    -fno-pic `
    -fno-stack-protector `
    -fno-unwind-tables `
    -fno-asynchronous-unwind-tables `
    -DNOPRINT `
    -fdata-sections `
    -ffunction-sections `
    -msmall-data-limit=0 `
    -nostdlib `
    "-Wl,-T,$(Join-Path $firmwareDir 'linker.ld')" `
    '-Wl,--gc-sections' `
    '-Wl,--build-id=none' `
    @sources `
    -o $elf
if ($LASTEXITCODE -ne 0) { throw 'Firmware link failed.' }

& python (Join-Path $firmwareDir '../../tools/check_ui_layout.py') $elf
if ($LASTEXITCODE -ne 0) { throw 'UI Harvard memory-layout verification failed.' }

& $Zig objcopy -O binary $elf $binary
if ($LASTEXITCODE -ne 0) { throw 'Firmware objcopy failed.' }

$bytes = [System.IO.File]::ReadAllBytes($binary)
# UI instruction fetch has a 64 KiB base plus a 16 KiB extension. .bss is
# not part of the image and uses only the separate data RAM.
if ($bytes.Length -gt 81920) {
    throw "Firmware load image is $($bytes.Length) bytes, larger than the 80 KiB instruction ROM window."
}

# Pad to the full 96 KiB data-memory image.  The soft core loads the same hex
# into instruction ROM and the two data banks. Startup clears BSS through
# its 0x10020000 data alias; the independent instruction ROM is untouched.
$lines = [System.Collections.Generic.List[string]]::new(4096)
for ($offset = 0; $offset -lt 98304; $offset += 4) {
    $word = [uint32]0
    for ($byteIndex = 0; $byteIndex -lt 4; $byteIndex++) {
        $index = $offset + $byteIndex
        if ($index -lt $bytes.Length) {
            $word = $word -bor ([uint32]$bytes[$index] -shl (8 * $byteIndex))
        }
    }
    $lines.Add($word.ToString('X8'))
}
[System.IO.File]::WriteAllLines($hex, $lines, [System.Text.Encoding]::ASCII)
[System.IO.File]::WriteAllLines((Join-Path $firmwareDir 'firmware_high.hex'), $lines.GetRange(16384,4096), [System.Text.Encoding]::ASCII)

Write-Host "Touch/UI firmware: $($bytes.Length) / 81920 instruction-ROM bytes"
Write-Host "Generated: $hex"
