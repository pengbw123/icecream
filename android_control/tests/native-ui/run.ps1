[CmdletBinding()]
param(
    [string]$WorkRoot='',
    [string]$Apk='E:\gaoyun111111\android_control\outputs\Gowin-JDY23-Android-v0.4.6-r1.apk',
    [string]$Tests=''
)
$ErrorActionPreference='Stop'
if(-not $WorkRoot){$WorkRoot='E:\gaoyun111111\android_toolchain\work\native-ui-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff')}
$WorkRoot=[IO.Path]::GetFullPath($WorkRoot)
if(-not $WorkRoot.StartsWith('E:\',[StringComparison]::OrdinalIgnoreCase)){throw 'UI test outputs must stay on drive E.'}
$uiTools='E:\gaoyun111111\android_toolchain\ui-test-tools'
$uiMaven=Join-Path $uiTools 'apache-maven-3.9.9'
$uiJdk=(Get-ChildItem -LiteralPath 'E:\gaoyun111111\android_toolchain\jdk' -Directory | Select-Object -First 1).FullName
$uiJava=Join-Path $uiJdk 'bin\java.exe'
$uiBootstrap=(Get-ChildItem -LiteralPath (Join-Path $uiMaven 'boot') -Filter 'plexus-classworlds-*.jar' | Select-Object -First 1).FullName
New-Item -ItemType Directory -Path (Join-Path $uiTools 'tmp'),(Join-Path $uiTools 'home') -Force | Out-Null
function Invoke-UiMaven([string]$uiGoal) {
    $uiTestArguments=@();if($Tests){$uiTestArguments+=@("-Dtest=$Tests")}
    & $uiJava "-Djava.io.tmpdir=$uiTools\tmp" "-Duser.home=$uiTools\home" "-Dmaven.home=$uiMaven" "-Dmaven.multiModuleProjectDirectory=$PSScriptRoot" "-Dclassworlds.conf=$uiMaven\bin\m2.conf" -cp $uiBootstrap org.codehaus.plexus.classworlds.launcher.Launcher -B -ntp "-Dmaven.repo.local=$uiTools\repository" "-Dqa.work=$WorkRoot" "-Dqa.apk=$Apk" @uiTestArguments -f "$PSScriptRoot\pom.xml" $uiGoal
    if($LASTEXITCODE -ne 0){throw ('Native UI test preparation failed: '+$uiGoal)}
}
$uiAars=@{
    'androidx\test\monitor\1.8.0\monitor-1.8.0.aar'='monitor'
    'androidx\test\espresso\espresso-idling-resource\3.7.0\espresso-idling-resource-3.7.0.aar'='espresso'
}
if(@($uiAars.Keys | Where-Object {-not(Test-Path -LiteralPath (Join-Path $uiTools ('repository\'+$_)))}).Count){Invoke-UiMaven 'dependency:resolve'}
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
foreach($uiAar in $uiAars.GetEnumerator()) {
    $uiTarget=Join-Path $WorkRoot $uiAar.Value
    New-Item -ItemType Directory -Path $uiTarget -Force | Out-Null
    $uiArchive=[IO.Compression.ZipFile]::OpenRead((Join-Path $uiTools ('repository\'+$uiAar.Key)))
    try {
        $uiEntry=$uiArchive.GetEntry('classes.jar')
        if(-not $uiEntry){throw 'Android test AAR has no classes.jar'}
        $uiStream=$uiEntry.Open()
        $uiOutput=[IO.File]::Create((Join-Path $uiTarget 'classes.jar'))
        try{$uiStream.CopyTo($uiOutput)}finally{$uiStream.Dispose();$uiOutput.Dispose()}
    }finally{$uiArchive.Dispose()}
}
Invoke-UiMaven 'test'
if($LASTEXITCODE -ne 0){throw 'Native Android UI regression failed; see Maven log'}

