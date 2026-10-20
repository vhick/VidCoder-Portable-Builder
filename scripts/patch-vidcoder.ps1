$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root 'upstream'
if (-not (Test-Path $src)) { throw 'Official upstream source not found.' }

function Apply-UniquePatch([string]$relative, [string]$pattern, [string]$replacement, [string]$note) {
    $path = Join-Path $src $relative
    if (-not (Test-Path $path)) { throw "Required upstream source missing: $relative" }
    $content = [IO.File]::ReadAllText($path)
    $matches = [regex]::Matches($content, $pattern)
    if ($matches.Count -ne 1) {
        throw "Upstream source changed; expected one match for '$note' in $relative but found $($matches.Count). Refusing an unsafe build."
    }
    $updated = [regex]::Replace($content, $pattern, $replacement)
    [IO.File]::WriteAllText($path, $updated, [Text.UTF8Encoding]::new($false))
    Write-Host "Patched: $relative - $note"
}

# The replacements are stored in variables to avoid fragile multiline argument parsing.
$folderReplacement = @'
$1
        // Portable build: all application settings, logs and backup data stay in Data/Settings.
        string isolatedFolder = Environment.GetEnvironmentVariable("VIDCODER_PORTABLE_DATA_DIR");
        if (!string.IsNullOrWhiteSpace(isolatedFolder))
        {
            return Path.GetFullPath(isolatedFolder);
        }
'@
Apply-UniquePatch 'VidCoderCommon/Utilities/CommonUtilities.cs' '(public static string GetAppFolder\(bool beta\)\s*\{)' $folderReplacement 'portable app settings, logs, backups and cache'

$localReplacement = @'
$1
            string isolatedFolder = Environment.GetEnvironmentVariable("VIDCODER_PORTABLE_DATA_DIR");
            if (!string.IsNullOrWhiteSpace(isolatedFolder))
            {
                return Path.Combine(Path.GetFullPath(isolatedFolder), "Local");
            }
'@
Apply-UniquePatch 'VidCoderCommon/Utilities/CommonUtilities.cs' '(public static string LocalAppFolder\s*\{\s*get\s*\{)' $localReplacement 'portable local application directory'

$databaseReplacement = @'
$1
        string isolatedFolder = Environment.GetEnvironmentVariable("VIDCODER_PORTABLE_DATA_DIR");
        if (!string.IsNullOrWhiteSpace(isolatedFolder))
        {
            return Path.Combine(Path.GetFullPath(isolatedFolder), CommonDatabase.ConfigDatabaseFile);
        }
'@
Apply-UniquePatch 'VidCoder/Model/Database.cs' '(private static string GetDatabaseFilePath\(\)\s*\{)' $databaseReplacement 'prevent host SQLite database access'

$installTypeReplacement = @'
$1
        if (!string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("VIDCODER_PORTABLE_DATA_DIR")))
        {
            InstallType = VidCoderInstallType.Portable;
            return;
        }
'@
Apply-UniquePatch 'VidCoder/Utilities/Utilities.cs' '(static Utilities\(\)\s*\{)' $installTypeReplacement 'force portable install type, disable self-updates and watcher'

# Fluent.Ribbon uses .NET IsolatedStorage for automatic ribbon state. Windows treats that
# as a Known Folder and it is NOT reliably redirected by APPDATA/LOCALAPPDATA env vars.
# Disable this specific optional feature at XAML source level before compiling.
# Never remove or modify the machine's existing IsolatedStorage directories.
& python (Join-Path $PSScriptRoot 'patch-fluent-ribbon.py') $src
if ($LASTEXITCODE -ne 0) { throw 'Fluent.Ribbon IsolatedStorage prevention patch failed.' }

Write-Host 'All required portability patches, including Fluent.Ribbon, applied.' 
