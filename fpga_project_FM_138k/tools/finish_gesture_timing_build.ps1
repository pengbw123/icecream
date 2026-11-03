param([int]$BuildProcessId,[string]$Root=(Split-Path -Parent $PSScriptRoot),[string]$SnapshotDirectory='tmp/gesture_performance_timing_build_v2',[string]$ArtifactName='fm_138k_gesture_performance.fs',[string]$ReleaseName='2026-11-02_gesture_performance_timing.json')
$ErrorActionPreference='Stop'
$snapshot=Join-Path $Root $SnapshotDirectory
$receipt=Join-Path $snapshot 'background_result.json'
function Hash-File([string]$Path) {
    $stream=$null;$sha=[Security.Cryptography.SHA256]::Create()
    try {$stream=[IO.File]::OpenRead($Path);return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')}
    finally {if($null -ne $stream){$stream.Dispose()};$sha.Dispose()}
}
try {
    $jobs=Get-Content -Raw -LiteralPath (Join-Path $Root 'tmp/opt_test_jobs.json') | ConvertFrom-Json
    foreach($job in $jobs){Wait-Process -Id $job.pid -ErrorAction SilentlyContinue}
    $checks=@(
        @{log='tmp/opt_poly.log';marker='PASS production FM32 PCM: 32 independent peaks'},
        @{log='tmp/opt_poly.log';marker='PASS spectrum CDC'},
        @{log='tmp/opt_poly_gesture.log';marker='PASS production test32'},
        @{log='tmp/opt_gesture.log';marker='PASS production FM32\+FX gesture'},
        @{log='tmp/opt_latency.log';marker='17 measured pulses exactly equal counters'},
        @{log='tmp/opt_rgb_gesture.log';marker='PASS RGB/XY raster'},
        @{log='tmp/opt_rgb_voices.log';marker='PASS RGB/XY raster'},
        @{log='tmp/opt_rgb_linear.log';marker='PASS RGB/XY raster'},
        @{log='tmp/opt_strip160.log';marker='PASS bounded strip index'},
        @{log='tmp/opt_strip1.log';marker='PASS bounded strip index'},
        @{log='tmp/opt_tutorial.log';marker='SCORE_TUTORIAL_138K_OK'},
        @{log='tmp/opt_observer.log';marker='PASS MIDI observer'},
        @{log='tmp/opt_spectrum.log';marker='PASS spectrum FFT'},
        @{log='tmp/opt_ingress.log';marker='Input path USE_BRIDGE=0'}
    )
    foreach($check in $checks){
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
    $named=Join-Path (Join-Path $Root 'impl/pnr') $ArtifactName
    if(Test-Path -LiteralPath $named){throw 'Named artifact already exists; review before replacing it'}
    Copy-Item -LiteralPath $built -Destination $named
    if((Hash-File $named) -ne $expected){throw 'Artifact copy hash mismatch'}
    $result=@{status='PASS';regressions_pass=$true;timing_pass=$true;bitstream=$named;sha256=$expected;standard_fs_replaced=$false;flashed=$false;keyboard='CH376';completed=(Get-Date).ToString('o')}
    $result | ConvertTo-Json | Set-Content -Encoding utf8 -LiteralPath $receipt
    $result | ConvertTo-Json | Set-Content -Encoding utf8 -LiteralPath (Join-Path (Join-Path $Root 'docs/releases') $ReleaseName)
} catch {
    @{status='NEEDS_REVIEW';standard_fs_replaced=$false;error=$_.Exception.Message;completed=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -Encoding utf8 -LiteralPath $receipt
    throw
}
