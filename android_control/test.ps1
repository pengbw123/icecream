[CmdletBinding()]
param([string]$Toolchain='E:\gaoyun111111\android_toolchain',[string]$JdkDirectory='')
$ErrorActionPreference='Stop'
$jdk=if($JdkDirectory){Get-Item -LiteralPath $JdkDirectory}else{Get-ChildItem -LiteralPath "$Toolchain\jdk" -Directory | Select-Object -First 1}
if(-not $jdk){throw 'Portable JDK not found'}
$testDir=Join-Path $PSScriptRoot ('build\tests-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $testDir -Force|Out-Null
$oldBytecode=$env:PYTHONDONTWRITEBYTECODE
$env:PYTHONDONTWRITEBYTECODE='1'
try {
    & python "$PSScriptRoot\tests\fixtures.py" "$testDir\reference.bin"
    if($LASTEXITCODE -ne 0){throw 'Python reference generation failed'}
    & (Join-Path $jdk.FullName 'bin\javac.exe') -encoding UTF-8 -d $testDir "$PSScriptRoot\src\com\gowin\instrument\Protocol.java" "$PSScriptRoot\src\com\gowin\instrument\Preset.java" "$PSScriptRoot\src\com\gowin\instrument\Score.java" "$PSScriptRoot\src\com\gowin\instrument\ScoreCapabilities.java" "$PSScriptRoot\src\com\gowin\instrument\ReliableScoreProtocol.java" "$PSScriptRoot\src\com\gowin\instrument\ReplyDecoder.java" "$PSScriptRoot\tests\ProtocolTest.java"
    if($LASTEXITCODE -ne 0){throw 'Protocol test compilation failed'}
    & (Join-Path $jdk.FullName 'bin\java.exe') -cp $testDir com.gowin.instrument.ProtocolTest "$testDir\reference.bin"
    if($LASTEXITCODE -ne 0){throw 'Protocol tests failed'}
}finally{$env:PYTHONDONTWRITEBYTECODE=$oldBytecode}
