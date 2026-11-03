$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$scriptPath=Join-Path $PSScriptRoot 'finish_bridge25k_build.ps1'
$testRoot=Join-Path $project ('tmp/publish_script_test_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$winPs=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'

function New-Fixture([string]$Name) {
    $fixture=Join-Path $testRoot $Name
    $snapshot=Join-Path $fixture 'tmp/bridge25k_restore_build'
    foreach($directory in @('src','impl/pnr','tmp/bridge25k_restore_build/src','tmp/bridge25k_restore_build/impl/pnr')) {
        New-Item -ItemType Directory -Force -Path (Join-Path $fixture $directory) | Out-Null
    }
    [IO.File]::WriteAllText((Join-Path $fixture 'src/input.v'),'fixture source')
    Copy-Item -LiteralPath (Join-Path $fixture 'src/input.v') -Destination (Join-Path $snapshot 'src/input.v')
    $hash=(Get-FileHash -LiteralPath (Join-Path $fixture 'src/input.v')).Hash
    @{files=@{'src/input.v'=$hash}} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $snapshot 'source_manifest.json')
    [IO.File]::WriteAllText((Join-Path $snapshot 'build.log'),'PASS all constrained clocks: setup/hold TNS = 0')
    [IO.File]::WriteAllBytes((Join-Path $snapshot 'impl/pnr/fm_138k_rgb_hdmi.fs'),(New-Object byte[] 1000100))
    [IO.File]::WriteAllText((Join-Path $fixture 'impl/pnr/fm_138k_rgb_hdmi.fs'),'old standard fixture')
    return $fixture
}
function Run-Child([string]$Fixture,[bool]$Publish,[bool]$ExpectSuccess) {
    $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$scriptPath+'" -Root "'+$Fixture+'"'
    if($Publish){$arguments+=' -Publish'}
    $process=Start-Process -FilePath $winPs -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput (Join-Path $Fixture 'stdout.log') -RedirectStandardError (Join-Path $Fixture 'stderr.log')
    if(($process.ExitCode -eq 0) -ne $ExpectSuccess){throw "Unexpected child exit $($process.ExitCode): $Fixture"}
}
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}

$fixture=New-Fixture 'validate'
$standard=Join-Path $fixture 'impl/pnr/fm_138k_rgb_hdmi.fs'
$oldHash=(Get-FileHash -LiteralPath $standard).Hash
Run-Child $fixture $false $true
$result=Get-Content -Raw -LiteralPath (Join-Path $fixture 'tmp/bridge25k_restore_build/validation_result.json') | ConvertFrom-Json
Assert ($result.status -eq 'VALIDATED_ONLY') 'Default did not validate only'
Assert ((Get-FileHash -LiteralPath $standard).Hash -eq $oldHash) 'Validation changed standard file'
Assert (-not (Test-Path (Join-Path $fixture 'impl/pnr/fm_138k_25k_bridge.fs'))) 'Validation created published file'
Assert (-not (Test-Path (Join-Path $fixture 'docs/releases'))) 'Validation created release record'

$fixture=New-Fixture 'publish_sandbox'
$standard=Join-Path $fixture 'impl/pnr/fm_138k_rgb_hdmi.fs'
$oldHash=(Get-FileHash -LiteralPath $standard).Hash
(Get-Item -LiteralPath $standard).IsReadOnly=$true
Run-Child $fixture $true $true
$result=Get-Content -Raw -LiteralPath (Join-Path $fixture 'tmp/bridge25k_restore_build/background_result.json') | ConvertFrom-Json
Assert ($result.status -eq 'PASS' -and $result.standard_fs_replaced) 'Sandbox publish failed'
Assert ((Get-FileHash -LiteralPath $standard).Hash -eq $result.sha256) 'Published hash wrong'
Assert ((Get-FileHash -LiteralPath $result.backup).Hash -eq $oldHash) 'Backup changed original data'
Assert ((Get-FileHash -LiteralPath $result.named_bitstream).Hash -eq $result.sha256) 'Named bitstream mismatch'

foreach($kind in @('timing','frozen_source','current_source')) {
    $fixture=New-Fixture $kind
    $standard=Join-Path $fixture 'impl/pnr/fm_138k_rgb_hdmi.fs'
    $oldHash=(Get-FileHash -LiteralPath $standard).Hash
    switch($kind) {
        'timing' {[IO.File]::WriteAllText((Join-Path $fixture 'tmp/bridge25k_restore_build/build.log'),'timing failed')}
        'frozen_source' {[IO.File]::WriteAllText((Join-Path $fixture 'tmp/bridge25k_restore_build/src/input.v'),'modified')}
        'current_source' {[IO.File]::WriteAllText((Join-Path $fixture 'src/input.v'),'modified')}
    }
    Run-Child $fixture $true $false
    $result=Get-Content -Raw -LiteralPath (Join-Path $fixture 'tmp/bridge25k_restore_build/background_result.json') | ConvertFrom-Json
    Assert ($result.status -eq 'NEEDS_REVIEW' -and -not $result.standard_fs_replaced) "Failure receipt wrong: $kind"
    Assert ((Get-FileHash -LiteralPath $standard).Hash -eq $oldHash) "Failure replaced standard: $kind"
    Assert (-not (Test-Path (Join-Path $fixture 'impl/pnr/backup'))) "Failure reached publication: $kind"
}
Write-Output 'PASS: Windows PowerShell 5.1 background validation, sandbox publish/backup, timing rejection, frozen/current hash rejection'
Write-Output ('Fixtures: '+$testRoot)
