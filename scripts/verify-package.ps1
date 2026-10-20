$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$pkg = Join-Path $root 'dist/VidCoderPortable'
$mustHave = @(
  'VidCoderPortable.exe', 'App/VidCoder.exe', 'App/VidCoder.dll',
  'App/VidCoderCommon.dll', 'App/VidCoderWorker.exe', 'App/hb.dll',
  'App/AppInfo/appicon.ico', 'App/AppInfo/appinfo.ini',
  'Data/KEEP_DATA_README.txt', 'Other/Source/VidCoder-modified-source.zip',
  'Other/Source/patch-vidcoder.ps1', 'Other/Source/patch-fluent-ribbon.py', 'Other/Source/VidCoderPortable.cpp',
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
  # Inspect the archive directly: it must contain the patched XAML, not merely the patcher.
  $xaml = @($archive.Entries | Where-Object { $_.FullName -match '^VidCoder/.+\.xaml$' })
  $fluentCount = 0
  foreach ($entry in $xaml) {
    $reader = New-Object IO.StreamReader($entry.Open())
    try { $content = $reader.ReadToEnd() } finally { $reader.Dispose() }
    if ($content -match '(?s)<[A-Za-z_][\w.-]*:Ribbon(?=[\s/>])') {
      if ( $content -notmatch 'AutomaticStateManagement\s*=\s*(?:"False"|''False'')') {
        throw "Ribbon control found without the disabled-state attribute: $($entry.FullName)"
      }
      $fluentCount++
    }
  }
  if ($fluentCount -lt 1) { throw 'Modified source archive contains no disabled Fluent.Ribbon control.' }
} finally { $archive.Dispose() }
Write-Host 'Portable output and source patches: structural validation passed.'
Write-Host 'NOTE: a real Windows execution/encoding/remnants test is still required.'
