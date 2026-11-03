param([int]$BuildProcessId,[string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$snapshot=Join-Path $Root 'tmp/gesture_performance_build'
$receipt=Join-Path $snapshot 'background_result.json'
function Hash-File([string]$Path) {
    $stream=$null;$sha=[Security.Cryptography.SHA256]::Create()
    try {$stream=[IO.File]::OpenRead($Path);return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')}
    finally {if($null -ne $stream){$stream.Dispose()};$sha.Dispose()}
}
try {
    $checks=@(
        @{pid=33320;log='tmp/gesture_ui.log';marker='PASS independent gesture UI'},
        @{pid=37848;log='tmp/gesture_production.log';marker='PASS production FM32\+FX gesture'},
        @{pid=47948;log='tmp/gesture_rgb.log';marker='PASS RGB/XY raster'},
        @{pid=44736;log='tmp/gesture_polyphony.log';marker='PASS production test32'}
    )
    foreach($check in $checks) {
        Wait-Process -Id $check.pid -ErrorAction SilentlyContinue
        if(-not (Select-String -LiteralPath (Join-Path $Root $check.log) -Pattern $check.marker -Quiet)){throw ('Regression failed: '+$check.log)}
    }
    @{regressions_pass=$true} | ConvertTo-Json | Set-Content -Encoding utf8 -LiteralPath (Join-Path $snapshot 'test_result.json')
    Wait-Process -Id $BuildProcessId -ErrorAction SilentlyContinue
    if(-not (Select-String -LiteralPath (Join-Path $snapshot 'build.log') -Pattern 'PASS all constrained clocks: setup/hold TNS = 0' -Quiet)){throw 'Build/timing did not pass'}
    $manifest=Get-Content -Raw -LiteralPath (Join-Path $snapshot 'source_manifest.json') | ConvertFrom-Json
    foreach($entry in $manifest.files.PSObject.Properties) {
        if((Hash-File (Join-Path $snapshot $entry.Name)) -ne $entry.Value){throw ('Frozen input changed: '+$entry.Name)}
        if((Hash-File (Join-Path $Root $entry.Name)) -ne $entry.Value){throw ('Current input changed: '+$entry.Name)}
    }
    $built=Join-Path $snapshot 'impl/pnr/fm_138k_rgb_hdmi.fs'
    if((Get-Item -LiteralPath $built).Length -lt 1000000){throw 'Invalid bitstream size'}
    $expected=Hash-File $built
    $named=Join-Path $Root 'impl/pnr/fm_138k_gesture_performance.fs'
    if(Test-Path -LiteralPath $named){throw 'Named artifact already exists; review before replacing it'}
    Copy-Item -LiteralPath $built -Destination $named
    if((Hash-File $named) -ne $expected){throw 'Artifact copy hash mismatch'}
    $result=@{status='PASS';regressions_pass=$true;timing_pass=$true;bitstream=$named;sha256=$expected;standard_fs_replaced=$false;flashed=$false;keyboard='CH376';completed=(Get-Date).ToString('o')}
    $result | ConvertTo-Json | Set-Content -Encoding utf8 -LiteralPath $receipt
    $result | ConvertTo-Json | Set-Content -Encoding utf8 -LiteralPath (Join-Path $Root 'docs/releases/2026-11-02_gesture_performance.json')
} catch {
    @{status='NEEDS_REVIEW';standard_fs_replaced=$false;error=$_.Exception.Message;completed=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -Encoding utf8 -LiteralPath $receipt
    throw
}
