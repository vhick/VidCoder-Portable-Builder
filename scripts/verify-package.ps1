$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$pkg = Join-Path $root 'dist/VidCoderPortable'
$mustHave = @(
  'VidCoderPortable.exe', 'App/VidCoder.exe', 'App/VidCoder.dll',
  'App/VidCoderCommon.dll', 'App/VidCoderWorker.exe', 'App/hb.dll',
  'App/AppInfo/appicon.ico', 'App/AppInfo/appinfo.ini',
  'Data/KEEP_DATA_README.txt', 'Other/Source/VidCoder-modified-source.zip',
  'Other/Source/patch-vidcoder.ps1', 'Other/Source/VidCoderPortable.cpp',
  'Other/License/VidCoder-GPL-2.0.txt', 'README-START-HERE.txt'
)
foreach ($file in $mustHave) {
  if (-not (Test-Path (Join-Path $pkg $file))) { throw "Missing package file: $file" }
}
# Verify correspondingly modified source code really shipped in artifact, not just a patch recipe.
Add-Type -AssemblyName System.IO.Compression
$archive = [IO.Compression.ZipFile]::OpenRead((Join-Path $pkg 'Other/Source/VidCoder-modified-source.zip'))
try {
  foreach ($file in @('VidCoderCommon/Utilities/CommonUtilities.cs', 'VidCoder/Model/Database.cs', 'VidCoder/Utilities/Utilities.cs')) {
    $entry = $archive.GetEntry($file)
    if ($null -eq $entry) { throw "Source archive is missing $file" }
    $reader = New-Object IO.StreamReader($entry.Open())
    try { $content = $reader.ReadToEnd() } finally { $reader.Dispose() }
    if (-not $content.Contains('VIDCODER_PORTABLE_DATA_DIR')) { throw "Required isolation changes missing from $file" }
  }
} finally { $archive.Dispose() }
Write-Host 'Portable output and source patches: structural validation passed.'
Write-Host 'NOTE: a real Windows execution/encoding/remnants test is still required.'
