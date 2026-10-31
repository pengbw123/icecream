[CmdletBinding()]
param([string]$Toolchain='E:\gaoyun111111\android_toolchain',[string]$JdkDirectory='')
$ErrorActionPreference='Stop'
$taskJdk=if($JdkDirectory){Get-Item -LiteralPath $JdkDirectory}else{Get-ChildItem -LiteralPath "$Toolchain\jdk" -Directory | Select-Object -First 1}
$taskDir=Join-Path $PSScriptRoot ('build\score-tests-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $taskDir -Force | Out-Null
$taskMidiFiles=@(Get-ChildItem -LiteralPath "$PSScriptRoot\assets\scores" -Filter '*.mid' -File | Sort-Object Name | ForEach-Object { $_.FullName })
& "$($taskJdk.FullName)\bin\javac.exe" -encoding UTF-8 -d $taskDir "$PSScriptRoot\src\com\gowin\instrument\Protocol.java" "$PSScriptRoot\src\com\gowin\instrument\Preset.java" "$PSScriptRoot\src\com\gowin\instrument\Score.java" "$PSScriptRoot\src\com\gowin\instrument\ScoreCapabilities.java" "$PSScriptRoot\src\com\gowin\instrument\ScoreTransfer.java" "$PSScriptRoot\src\com\gowin\instrument\ScoreBurstTransfer.java" "$PSScriptRoot\src\com\gowin\instrument\UploadPacing.java" "$PSScriptRoot\tests\ScoreTest.java" "$PSScriptRoot\tests\ScoreFixture.java"
if($LASTEXITCODE -ne 0){throw 'Score test compile failed'}
& "$($taskJdk.FullName)\bin\java.exe" '-Dfile.encoding=UTF-8' -cp $taskDir com.gowin.instrument.ScoreTest @taskMidiFiles
if($LASTEXITCODE -ne 0){throw 'Score tests failed'}
& "$($taskJdk.FullName)\bin\java.exe" '-Dfile.encoding=UTF-8' -cp $taskDir com.gowin.instrument.ScoreFixture "$PSScriptRoot\build\score-fixtures" "$PSScriptRoot\assets\scores\ode_to_joy.mid" "$PSScriptRoot\assets\scores\fur_elise.mid" "$PSScriptRoot\assets\scores\sunny_melody_test.mid"
if($LASTEXITCODE -ne 0){throw 'Score fixture export failed'}
& "$($taskJdk.FullName)\bin\javac.exe" -encoding UTF-8 -cp $taskDir -d $taskDir "$PSScriptRoot\src\com\gowin\instrument\ScoreDownload.java" "$PSScriptRoot\tests\ScoreDownloadTest.java"
if($LASTEXITCODE -ne 0){throw 'Download test compile failed'}
& "$($taskJdk.FullName)\bin\java.exe" '-Dfile.encoding=UTF-8' -cp $taskDir com.gowin.instrument.ScoreDownloadTest "$taskDir\cache" "$PSScriptRoot\assets\scores\ode_to_joy.mid"
if($LASTEXITCODE -ne 0){throw 'Download tests failed'}
& "$($taskJdk.FullName)\bin\javac.exe" -encoding UTF-8 -cp $taskDir -d $taskDir "$PSScriptRoot\src\com\gowin\instrument\ScoreCatalog.java" "$PSScriptRoot\tests\ScoreCatalogTest.java"
if($LASTEXITCODE -ne 0){throw 'Catalog test compile failed'}
& "$($taskJdk.FullName)\bin\java.exe" '-Dfile.encoding=UTF-8' -cp $taskDir com.gowin.instrument.ScoreCatalogTest "$PSScriptRoot\tests\fixtures"
if($LASTEXITCODE -ne 0){throw 'Catalog tests failed'}
Write-Output "SCORE_TEST_CLASSES $taskDir"
& "$($taskJdk.FullName)\bin\javac.exe" -encoding UTF-8 -cp $taskDir -d $taskDir "$PSScriptRoot\src\com\gowin\instrument\ReliableScoreProtocol.java" "$PSScriptRoot\src\com\gowin\instrument\ReliableScoreTransfer.java" "$PSScriptRoot\src\com\gowin\instrument\ReplyDecoder.java" "$PSScriptRoot\tests\BluetoothUpgradeTest.java" "$PSScriptRoot\tests\ScoreBurstTest.java" "$PSScriptRoot\tests\ReliableScoreTest.java"
if($LASTEXITCODE -ne 0){throw 'Burst test compile failed'}
& "$($taskJdk.FullName)\bin\java.exe" '-Dfile.encoding=UTF-8' -cp $taskDir com.gowin.instrument.ScoreBurstTest @taskMidiFiles
if($LASTEXITCODE -ne 0){throw 'Burst tests failed'}
& "$($taskJdk.FullName)\bin\java.exe" '-Dfile.encoding=UTF-8' -cp $taskDir com.gowin.instrument.BluetoothUpgradeTest "$PSScriptRoot\assets\scores\the_truth_that_you_leave_full.mid" "$PSScriptRoot\assets\scores\the_truth_that_you_leave_part1.mid" "$PSScriptRoot\assets\scores\the_truth_that_you_leave_part2.mid" "$PSScriptRoot\build\score-fixtures"
if($LASTEXITCODE -ne 0){throw 'Bluetooth upgrade tests failed'}
& "$($taskJdk.FullName)\bin\java.exe" '-Dfile.encoding=UTF-8' -cp $taskDir com.gowin.instrument.ReliableScoreTest "$PSScriptRoot\assets\scores\the_truth_that_you_leave_full.mid" "$PSScriptRoot\build\reliable-vectors"
if($LASTEXITCODE -ne 0){throw 'Reliable v2 tests failed'}
& "$($taskJdk.FullName)\bin\javac.exe" -encoding UTF-8 -cp $taskDir -d $taskDir "$PSScriptRoot\src\com\gowin\instrument\WebMidiDownload.java" "$PSScriptRoot\tests\WebMidiDownloadTest.java"
if($LASTEXITCODE -ne 0){throw 'Web MIDI test compile failed'}
& "$($taskJdk.FullName)\bin\java.exe" '-Dfile.encoding=UTF-8' -cp $taskDir com.gowin.instrument.WebMidiDownloadTest "$taskDir\web-cache" "$PSScriptRoot\assets\scores\ode_to_joy.mid"
if($LASTEXITCODE -ne 0){throw 'Web MIDI tests failed'}
