param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+$')]
    [string]$Version
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root 'upstream'
$dist = Join-Path $root 'dist/VidCoderPortable'
$app = Join-Path $dist 'App'
$stageWorker = Join-Path $root 'worker-publish'
$requiredPatched = @(
    'VidCoderCommon/Utilities/CommonUtilities.cs',
    'VidCoder/Model/Database.cs',
    'VidCoder/Utilities/Utilities.cs'
)
foreach ($relative in $requiredPatched) {
    $file = Join-Path $src $relative
    if (-not (Test-Path $file) -or -not ([IO.File]::ReadAllText($file)).Contains('VIDCODER_PORTABLE_DATA_DIR')) {
        throw "The portability modification is missing from $relative. Refusing to build."
    }
}
# Fail closed if a future upstream update removes or re-enables ribbon persistence.
& python (Join-Path $root 'scripts/patch-fluent-ribbon.py') $src --check
if ($LASTEXITCODE -ne 0) { throw 'Ribbon state isolation validation failed.' }
if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
$folders = @($app, (Join-Path $dist 'Data'), (Join-Path $dist 'Other/License'), (Join-Path $dist 'Other/Source'), (Join-Path $app 'AppInfo'))
New-Item -ItemType Directory -Force -Path $folders | Out-Null

Write-Host 'Compiling VidCoder from the official tagged source, with our Data-only modifications...'
# Self-contained: the final app needs no preinstalled .NET runtime.
# Publish directory holds individual binaries, rather than a temporary-extraction SFX.
& dotnet publish (Join-Path $src 'VidCoder/VidCoder.csproj') `
    --configuration Release --runtime win-x64 --self-contained true `
    -p:Platform=x64 -p:PublishSingleFile=false -p:PublishReadyToRun=false `
    "-p:Version=$Version.0.0" --output $app
if ($LASTEXITCODE -ne 0) { throw 'VidCoder source compilation failed.' }

# Upstream explicitly republishes Worker to make it self-contained; do the same here.
& dotnet publish (Join-Path $src 'VidCoderWorker/VidCoderWorker.csproj') `
    --configuration Release --runtime win-x64 --self-contained true `
    -p:Platform=x64 -p:PublishSingleFile=false -p:PublishReadyToRun=false `
    "-p:Version=$Version.0.0" --output $stageWorker
if ($LASTEXITCODE -ne 0) { throw 'VidCoderWorker compilation failed.' }
foreach ($f in @('VidCoderWorker.exe', 'VidCoderWorker.dll', 'VidCoderWorker.deps.json', 'VidCoderWorker.runtimeconfig.json')) {
    $from = Join-Path $stageWorker $f
    if (-not (Test-Path $from)) { throw "Self-contained worker file missing: $f" }
    Copy-Item $from $app -Force
}
foreach ($f in @('VidCoder.exe', 'VidCoder.dll', 'VidCoderCommon.dll', 'VidCoderWorker.exe', 'hb.dll')) {
    if (-not (Test-Path (Join-Path $app $f))) { throw "Compiled application file missing: $f" }
}

# Embed the real upstream icon directly in a native, standalone launcher.
$icon = Join-Path $src 'VidCoder/VidCoder_icon.ico'
if (-not (Test-Path $icon)) { throw 'Original VidCoder icon not found; no generic icon fallback is allowed.' }
Copy-Item $icon (Join-Path $app 'AppInfo/appicon.ico') -Force
Copy-Item $icon (Join-Path $root 'launcher/vidcoder.ico') -Force

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (-not (Test-Path $vswhere)) { throw 'Visual Studio Build Tools not installed on this runner.' }
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs -or -not (Test-Path $vs)) { throw 'Cannot locate Visual Studio C++ compiler.' }
$vcvars = Join-Path $vs 'VC/Auxiliary/Build/vcvars64.bat'
if (-not (Test-Path $vcvars)) { throw 'Cannot find MSVC x64 compiler environment.' }
$launcherDir = Join-Path $root 'launcher'
$launcherOut = Join-Path $dist 'VidCoderPortable.exe'
# vcvars64 configures cl.exe and rc.exe for this cmd session, including the original icon resource.
$command = 'call "' + $vcvars + '" >nul && cd /d "' + $launcherDir + `
    '" && rc.exe /nologo /fo "appicon.res" "VidCoderPortable.rc" && ' + `
    'cl.exe /nologo /std:c++17 /O2 /MT /EHsc /DUNICODE /D_UNICODE ' + `
    '/Fe:"' + $launcherOut + '" "VidCoderPortable.cpp" "appicon.res" ' + `
    '/link /SUBSYSTEM:WINDOWS /MACHINE:X64 shell32.lib user32.lib'
Write-Host 'Building Windows-native launcher with original VidCoder icon...'
& cmd.exe /d /s /c $command
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $launcherOut)) { throw 'Windows launcher compilation failed.' }

$upstreamLicense = Join-Path $src 'License.txt'
if (-not (Test-Path $upstreamLicense)) { throw 'Upstream license is missing.' }
Copy-Item $upstreamLicense (Join-Path $dist 'Other/License/VidCoder-GPL-2.0.txt') -Force
Copy-Item (Join-Path $src 'ThirdPartyLicenses.txt') (Join-Path $dist 'Other/License/ThirdPartyLicenses.txt') -Force
Copy-Item (Join-Path $root 'scripts/patch-vidcoder.ps1') (Join-Path $dist 'Other/Source/patch-vidcoder.ps1') -Force
Copy-Item (Join-Path $root 'scripts/patch-fluent-ribbon.py') (Join-Path $dist 'Other/Source/patch-fluent-ribbon.py') -Force
Copy-Item (Join-Path $root 'launcher/VidCoderPortable.cpp') (Join-Path $dist 'Other/Source/VidCoderPortable.cpp') -Force
Copy-Item (Join-Path $root 'launcher/VidCoderPortable.rc') (Join-Path $dist 'Other/Source/VidCoderPortable.rc') -Force

# Ship corresponding upstream source WITH all modified source and XAML files included (GPL-2.0).
# Only tracked files are archived, excluding transient build outputs and any .git data.
& python (Join-Path $root 'scripts/pack-source.py') $src (Join-Path $dist 'Other/Source/VidCoder-modified-source.zip')
if ($LASTEXITCODE -ne 0) { throw 'Cannot package corresponding modified source.' }

@"
[Format]
Type=PortableApps.comFormat
Version=3.8
[Details]
Name=VidCoder Portable
AppID=VidCoderPortable
Publisher=RandomEngy (VidCoder), portable modifications by this builder
Homepage=https://github.com/RandomEngy/VidCoder
Category=Music & Video
Description=Windows video converter using HandBrake engine
[Version]
PackageVersion=$Version.0.0
DisplayVersion=$Version
[Control]
Icons=1
Start=VidCoderPortable.exe
"@ | Set-Content (Join-Path $app 'AppInfo/appinfo.ini') -Encoding utf8

@"
Data is the persistent user-data directory. DO NOT DELETE during upgrades.
Never launch App/VidCoder.exe directly: open VidCoderPortable.exe at the package root.
Database, logs, cached data, backups: Data/Settings
Temporary files: Data/Temp (cleaned by the launcher when VidCoder closes normally)
Fluent.Ribbon automatic state saving: disabled to avoid Windows IsolatedStorage.
Ribbon minimized/customized state may reset each launch; encoding presets remain in SQLite.
Version: $Version, official stable tagged source plus isolation patches.
"@ | Set-Content (Join-Path $dist 'Data/KEEP_DATA_README.txt') -Encoding utf8

@"
VidCoder Portable $Version -- SOURCE-BUILT, NOT OFFICIALLY CERTIFIED BY VIDCODER

LAUNCH: Double-click VidCoderPortable.exe (never App/VidCoder.exe).
No external .NET installation needed. The first launch creates Data subfolders automatically.

UPDATES: Build again using this workflow. To update your existing portable copy,
replace ONLY App/, Other/, and root VidCoderPortable.exe. KEEP your existing Data/.
Back up Data/ before major versions. Do not run different VidCoder versions against
one database concurrently.

PORTABILITY: Process-local variables plus source changes force VidCoder's SQLite
and CommonUtilities.AppFolder into Data/Settings. Temporary files use Data/Temp.
Fluent.Ribbon automatic ribbon-state persistence is disabled, preventing its known
IsolatedStorage write. Previously existing Windows IsolatedStorage is NOT touched.
Ribbon minimized/customized state may reset each launch. Other VidCoder settings
and encoding presets remain in Data/Settings. Windows OS-managed state, codec/GPU
caches or shell artifacts outside this
application's control cannot be guaranteed trace-free.

SOURCE AND LICENSE: Other/Source/VidCoder-modified-source.zip includes the full
corresponding, modified tracked VidCoder source for this release. The launcher C++
source and patch scripts are next to it. VidCoder GPL-2.0 and third-party licenses
are included in Other/License/.

IMPORTANT: This package was compiled on GitHub Actions. Windows portability,
encoding, and residual-trace tests must still be run on a real Windows machine.
"@ | Set-Content (Join-Path $dist 'README-START-HERE.txt') -Encoding utf8

Write-Host "VidCoderPortable $Version is ready under: $dist"
