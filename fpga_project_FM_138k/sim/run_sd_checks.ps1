param([Parameter(Mandatory=$true)][string]$Zig,
      [Parameter(Mandatory=$true)][string]$IverilogDirectory)
$ErrorActionPreference='Stop'
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    New-Item -ItemType Directory -Force tmp | Out-Null
    & $Zig cc -O1 sim/test_sd_patch_store.c -o tmp/test_sd_patch_store.exe
    if ($LASTEXITCODE -ne 0) { throw 'SD firmware model compile failed' }
    & ./tmp/test_sd_patch_store.exe
    if ($LASTEXITCODE -ne 0) { throw 'SD firmware model failed' }
    & (Join-Path $IverilogDirectory 'iverilog.exe') -g2012 -s tb_sd_spi_byte -o tmp/tb_sd_spi_byte.vvp sim/tb_sd_spi_byte.sv src/sd_spi_byte.v
    if ($LASTEXITCODE -ne 0) { throw 'SD RTL compile failed' }
    & (Join-Path $IverilogDirectory 'vvp.exe') tmp/tb_sd_spi_byte.vvp
    if ($LASTEXITCODE -ne 0) { throw 'SD RTL test failed' }
} finally { Pop-Location }
