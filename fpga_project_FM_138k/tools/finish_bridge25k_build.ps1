param(
    [string]$Root=(Split-Path -Parent $PSScriptRoot),
    [string]$SnapshotDirectory='tmp/bridge25k_restore_build',
    [switch]$Publish
)
$ErrorActionPreference='Stop'

# Start-Process from PowerShell 7 can pass its module path to Windows
# PowerShell 5.1. Use .NET SHA-256 without depending on Get-FileHash.
function Get-Sha256([string]$FilePath) {
    $stream=$null
    $algorithm=[System.Security.Cryptography.SHA256]::Create()
    try {
        $stream=[System.IO.File]::OpenRead($FilePath)
        return [System.BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-','')
    } finally {
        if($null -ne $stream){$stream.Dispose()}
        $algorithm.Dispose()
    }
}

$rootPath=[System.IO.Path]::GetFullPath($Root)
$snapshot=Join-Path $rootPath $SnapshotDirectory
$receipt=Join-Path $snapshot 'validation_result.json'
if($Publish){$receipt=Join-Path $snapshot 'background_result.json'}
$standardReplaced=$false
$standardReplaceAttempted=$false
try {
    $log=Join-Path $snapshot 'build.log'
    $passed=(Test-Path -LiteralPath $log) -and (Select-String -LiteralPath $log -Pattern 'PASS all constrained clocks: setup/hold TNS = 0' -Quiet)
    if(-not $passed){throw 'Build has not passed all constrained clock timing checks; no release copied. Run again after build completion.'}
    $manifest=Get-Content -Raw -LiteralPath (Join-Path $snapshot 'source_manifest.json') | ConvertFrom-Json
    if($null -eq $manifest.files -or @($manifest.files.PSObject.Properties).Count -eq 0){throw 'Source manifest has no files'}
    foreach($entry in $manifest.files.PSObject.Properties) {
        if((Get-Sha256 (Join-Path $snapshot $entry.Name)) -ne $entry.Value){throw "Frozen input changed: $($entry.Name)"}
        if((Get-Sha256 (Join-Path $rootPath $entry.Name)) -ne $entry.Value){throw "Current input changed; review required before release: $($entry.Name)"}
    }
    $built=Join-Path $snapshot 'impl/pnr/fm_138k_rgb_hdmi.fs'
    if((Get-Item -LiteralPath $built).Length -lt 1000000){throw 'Missing or unexpectedly small bitstream'}
    $expected=Get-Sha256 $built
    $standard=Join-Path $rootPath 'impl/pnr/fm_138k_rgb_hdmi.fs'
    $named=Join-Path $rootPath 'impl/pnr/fm_138k_25k_bridge.fs'
    $result=@{status='VALIDATED_ONLY';build_and_timing_pass=$true;source_hashes_verified=$true;standard_fs_replaced=$false;sha256=$expected;built_bitstream=$built;completed=(Get-Date).ToString('o');flashed=$false}
    if($Publish) {
        $backupDir=Join-Path $rootPath 'impl/pnr/backup'
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
        $backup=Join-Path $backupDir ('fm_138k_rgb_hdmi_pre25k_'+(Get-Date -Format 'yyyyMMdd_HHmmss_fffffff')+'.fs')
        if(Test-Path -LiteralPath $standard) {
            $oldHash=Get-Sha256 $standard
            Copy-Item -LiteralPath $standard -Destination $backup
            if((Get-Sha256 $backup) -ne $oldHash){throw 'Backup hash mismatch; publication stopped'}
        }
        foreach($destination in @($named,$standard)) {
            if(Test-Path -LiteralPath $destination){(Get-Item -LiteralPath $destination).IsReadOnly=$false}
            if($destination -eq $standard){$standardReplaceAttempted=$true}
            Copy-Item -LiteralPath $built -Destination $destination -Force
            if($destination -eq $standard){$standardReplaced=$true}
            if((Get-Sha256 $destination) -ne $expected){throw "Published hash mismatch: $destination"}
        }
        $result.status='PASS'
        $result.standard_fs_replaced=$standardReplaced
        $result.bitstream=$standard
        $result.named_bitstream=$named
        $result.backup=$backup
        $releaseDir=Join-Path $rootPath 'docs/releases'
        New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null
        $result | ConvertTo-Json | Set-Content -Encoding utf8 -LiteralPath (Join-Path $releaseDir '2026-11-02_25k_bridge.json')
    }
    $result | ConvertTo-Json | Set-Content -Encoding utf8 -LiteralPath $receipt
    Write-Output ($result.status+': '+$expected)
} catch {
    @{status='NEEDS_REVIEW';publish_requested=[bool]$Publish;standard_fs_replaced=$standardReplaced;standard_replace_attempted=$standardReplaceAttempted;error=$_.Exception.Message;completed=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -Encoding utf8 -LiteralPath $receipt
    throw
}
