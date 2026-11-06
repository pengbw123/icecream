[CmdletBinding()]
param([string]$Toolchain=$env:ANDROID_TOOLCHAIN,[ValidatePattern('^(-[A-Za-z0-9]+)*$')][string]$ArtifactSuffix='')
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$jdk=Get-ChildItem -LiteralPath "$Toolchain\jdk" -Directory | Select-Object -First 1
if(-not $jdk){throw 'Portable JDK not found'}
$java=Join-Path $jdk.FullName 'bin\java.exe'
$javac=Join-Path $jdk.FullName 'bin\javac.exe'
$keytool=Join-Path $jdk.FullName 'bin\keytool.exe'
$bt=Join-Path $Toolchain 'sdk\build-tools\android-15'
$androidJar=Join-Path $Toolchain 'sdk\platforms\android-35\android.jar'
foreach($file in @($java,$javac,$keytool,$androidJar,"$bt\aapt2.exe","$bt\lib\d8.jar","$bt\lib\apksigner.jar")) {
    if(-not(Test-Path -LiteralPath $file -PathType Leaf)){throw "Missing build dependency: $file"}
}
$build=Join-Path $root ('build\'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
$out=Join-Path $root 'outputs'
New-Item -ItemType Directory -Path "$build\classes","$build\dex","$build\tests",$out,"$Toolchain\tmp","$Toolchain\android-home","$Toolchain\signing" -Force | Out-Null
$oldTemp=$env:TEMP;$oldTmp=$env:TMP;$oldAndroidUser=$env:ANDROID_USER_HOME
$env:TEMP="$Toolchain\tmp";$env:TMP="$Toolchain\tmp";$env:ANDROID_USER_HOME="$Toolchain\android-home"
$taskAssets=Join-Path $build 'assets'
$null=New-Item -ItemType Directory -Path (Join-Path $taskAssets 'scores')
Get-ChildItem -LiteralPath "$root\assets" -Force | Where-Object {$_.Name -ne 'scores'} | Copy-Item -Destination $taskAssets -Recurse
Copy-Item -LiteralPath "$root\assets\scores\sunny_melody_test.mid" -Destination (Join-Path $taskAssets 'scores')
function Native([string]$program,[string[]]$arguments) {
    & $program @arguments
    if($LASTEXITCODE -ne 0){throw "Build step failed: $program ($LASTEXITCODE)"}
}
try {
    $resourceFiles=@()
    if(Test-Path -LiteralPath "$root\res"){
        Native "$bt\aapt2.exe" @('compile','--dir',"$root\res",'-o',"$build\resources.zip")
        $resourceFiles=@("$build\resources.zip")
    }
    Native "$bt\aapt2.exe" (@('link','-o',"$build\base.apk",'-I',$androidJar,'--manifest',"$root\AndroidManifest.xml",'-A',$taskAssets)+$resourceFiles)
    $sources=@(Get-ChildItem -LiteralPath "$root\src" -Filter '*.java' -Recurse | ForEach-Object {$_.FullName})
    Native $javac (@('-encoding','UTF-8','-source','8','-target','8','-bootclasspath',$androidJar,'-d',"$build\classes")+$sources)
    Native (Join-Path $jdk.FullName 'bin\jar.exe') @('cf',"$build\classes.jar",'-C',"$build\classes",'.')
    Native $java @("-Djava.io.tmpdir=$Toolchain\tmp",'-cp',"$bt\lib\d8.jar",'com.android.tools.r8.D8','--min-api','23','--lib',$androidJar,'--output',"$build\dex","$build\classes.jar")
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[System.IO.Compression.ZipFile]::Open("$build\base.apk",[System.IO.Compression.ZipArchiveMode]::Update)
    try {
        # Windows aapt2 may emit backslashes for nested asset paths. Android
        # AssetManager uses slash paths, so normalize before alignment/signing.
        foreach($entry in @($zip.Entries | Where-Object { $_.FullName.Contains('\') })) {
            $entryName=$entry.FullName.Replace('\','/')
            if($zip.GetEntry($entryName)){throw "Duplicate normalized APK entry: $entryName"}
            $entryBytes=[System.IO.MemoryStream]::new()
            $entryStream=$entry.Open()
            try {$entryStream.CopyTo($entryBytes)} finally {$entryStream.Dispose()}
            $entry.Delete()
            $entryTarget=$zip.CreateEntry($entryName,[System.IO.Compression.CompressionLevel]::Optimal).Open()
            try {$entryBytes.Position=0;$entryBytes.CopyTo($entryTarget)} finally {$entryTarget.Dispose();$entryBytes.Dispose()}
        }
        foreach($scoreFile in Get-ChildItem -LiteralPath (Join-Path $taskAssets 'scores') -Filter '*.mid' -File) {
            $scoreName=$scoreFile.Name
            $scoreEntry=$zip.GetEntry('assets/scores/'+$scoreName)
            if(-not $scoreEntry){throw "Missing score asset: $scoreName"}
            $scoreStream=$scoreEntry.Open()
            $scoreSha=[System.Security.Cryptography.SHA256]::Create()
            try {$scoreDigest=[BitConverter]::ToString($scoreSha.ComputeHash($scoreStream)).Replace('-','')}
            finally {$scoreStream.Dispose();$scoreSha.Dispose()}
            if($scoreDigest -ne (Get-FileHash -LiteralPath "$root\assets\scores\$scoreName").Hash){throw "APK score asset differs: $scoreName"}
        }
        foreach($dex in Get-ChildItem -LiteralPath "$build\dex" -Filter '*.dex') {
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$dex.FullName,$dex.Name,[System.IO.Compression.CompressionLevel]::Optimal)|Out-Null
    }}finally{$zip.Dispose()}
    Native "$bt\zipalign.exe" @('-p','-f','4',"$build\base.apk","$build\aligned.apk")
    $key=Join-Path $Toolchain 'signing\instrument-debug.jks'
    if(-not(Test-Path -LiteralPath $key)) {
        throw 'Existing signing key not found; refusing to generate a replacement.'
    }
    [xml]$taskManifest=Get-Content -LiteralPath "$root\AndroidManifest.xml" -Raw
    $taskVersion=$taskManifest.manifest.GetAttribute('versionName','http://schemas.android.com/apk/res/android')
    if($taskVersion -notmatch '^\d+\.\d+\.\d+$'){throw 'Invalid manifest versionName'}
    $apk=Join-Path $out ('Gowin-JDY23-Android-v'+$taskVersion+$ArtifactSuffix+'.apk')
    if(Test-Path -LiteralPath $apk){throw "Release already exists; preserve it and choose a new version: $apk"}
    Native $java @("-Djava.io.tmpdir=$Toolchain\tmp",'-jar',"$bt\lib\apksigner.jar",'sign','--ks',$key,'--ks-pass','pass:android','--key-pass','pass:android','--ks-key-alias','androiddebugkey','--out',$apk,"$build\aligned.apk")
    Native $java @('-jar',"$bt\lib\apksigner.jar",'verify','--verbose','--print-certs',$apk)
    Native "$bt\zipalign.exe" @('-c','4',$apk)
    Native "$bt\aapt.exe" @('dump','badging',$apk)
    Get-FileHash -LiteralPath $apk -Algorithm SHA256
    Write-Output "APK_BUILD_OK $apk"
}finally{$env:TEMP=$oldTemp;$env:TMP=$oldTmp;$env:ANDROID_USER_HOME=$oldAndroidUser}
