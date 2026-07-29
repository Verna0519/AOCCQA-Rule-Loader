<#
.SYNOPSIS
    Package SKILL.md + agents/ into an installable aoccqa-rule-loader.skill (ZIP).

.DESCRIPTION
    Build tool for the skill pipeline. After editing SKILL.md / agents/, run this
    to produce a clean .skill for reinstalling in the Claude desktop app. Notes:
      1. Includes ONLY what the skill runtime needs (SKILL.md + agents/). No
         README / .git / .gitignore.
      2. Normalizes text files to LF line endings (matches the version that is
         known to work; avoids CRLF-related frontmatter parsing issues).
      3. Builds the ZIP with .NET System.IO.Compression.ZipArchive:
           - entry names are written with FORWARD SLASHES (spec-compliant; the
             PowerShell Compress-Archive cmdlet writes BACKSLASHES, which some
             skill installers reject).
           - REPRODUCIBLE output: every entry gets a fixed timestamp and only the
             standard DOS time field is stored (no volatile atime/ctime extra
             fields that bsdtar/zip would embed). Identical source content ->
             byte-identical .skill, so the version-controlled artifact does not
             churn on rebuilds.
      4. Self-verifies after packaging: forward-slash entries + required files.

    NOTE: this script is intentionally ASCII-only. Windows PowerShell 5.1 reads
    BOM-less .ps1 files using the system ANSI codepage, which corrupts non-ASCII
    text. Keeping it ASCII makes it safe to edit with any tool. Requires .NET
    (present on any Windows with PowerShell); no external tools needed.

.PARAMETER OutDir
    Output directory for the .skill. Defaults to the repo root (script folder).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\build-skill.ps1
    pwsh ./build-skill.ps1
#>
[CmdletBinding()]
param(
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'

# --- Resolve repo root robustly (do NOT rely on $PSScriptRoot in a param default) ---
$RepoRoot = $PSScriptRoot
if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $OutDir)   { $OutDir = $RepoRoot }

$SkillName = 'aoccqa-rule-loader'
$OutFile   = Join-Path $OutDir "$SkillName.skill"

# Sources to include (relative to repo root). Runtime-only.
$Includes = @('SKILL.md', 'agents')
# Extensions to LF-normalize.
$TextExt  = @('.md', '.yaml', '.yml', '.json', '.txt')
# Fixed timestamp for reproducible archives (must be >= 1980 for DOS zip time).
$FixedTime = [DateTimeOffset]::new(2020, 1, 1, 0, 0, 0, [TimeSpan]::Zero)

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

# --- Preconditions ---
foreach ($item in $Includes) {
    if (-not (Test-Path (Join-Path $RepoRoot $item))) {
        throw "Missing source: $item (expected under $RepoRoot)"
    }
}

# --- 1. Collect entries: name (forward-slash, prefixed) + source path ---
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$entries = [System.Collections.Generic.List[object]]::new()
foreach ($item in $Includes) {
    Get-ChildItem -LiteralPath (Join-Path $RepoRoot $item) -Recurse -File | ForEach-Object {
        $rel  = $_.FullName.Substring($RepoRoot.Length).TrimStart('\', '/') -replace '\\', '/'
        $name = "$SkillName/$rel"
        $entries.Add([PSCustomObject]@{ Name = $name; Path = $_.FullName; Ext = $_.Extension.ToLower() })
    }
}
# Deterministic entry order.
$entries = $entries | Sort-Object Name

# --- 2. Write the ZIP via .NET (forward slashes, fixed timestamps) ---
Write-Step "Building $OutFile"
Add-Type -AssemblyName System.IO.Compression | Out-Null
if (Test-Path $OutFile) { Remove-Item -LiteralPath $OutFile -Force }

$fs = [System.IO.File]::Open($OutFile, [System.IO.FileMode]::CreateNew)
try {
    $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($e in $entries) {
            # Read + (for text) LF-normalize content.
            if ($TextExt -contains $e.Ext) {
                $text  = [System.IO.File]::ReadAllText($e.Path) -replace "`r`n", "`n"
                $bytes = $utf8NoBom.GetBytes($text)
            } else {
                $bytes = [System.IO.File]::ReadAllBytes($e.Path)
            }
            $entry = $zip.CreateEntry($e.Name, [System.IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = $FixedTime
            $es = $entry.Open()
            try { $es.Write($bytes, 0, $bytes.Length) } finally { $es.Dispose() }
            Write-Host "    + $($e.Name)"
        }
    } finally { $zip.Dispose() }
} finally { $fs.Dispose() }

# --- 3. Self-verify ---
Write-Step "Verifying package"
$fs2 = [System.IO.File]::OpenRead($OutFile)
try {
    $zip2  = New-Object System.IO.Compression.ZipArchive($fs2, [System.IO.Compression.ZipArchiveMode]::Read)
    try {
        $names = $zip2.Entries | ForEach-Object { $_.FullName }
        $bad = $names | Where-Object { $_ -match '\\' }
        if ($bad) { throw "Package contains backslash paths (not ZIP-spec compliant):`n$($bad -join "`n")" }
        if (-not ($names -contains "$SkillName/SKILL.md")) { throw "Package is missing $SkillName/SKILL.md" }
    } finally { $zip2.Dispose() }
} finally { $fs2.Dispose() }

$size = (Get-Item $OutFile).Length
Write-Host ""
Write-Host ("OK  ->  {0}  ({1} bytes)" -f $OutFile, $size) -ForegroundColor Green
Write-Host "entries:" -ForegroundColor Green
$entries | ForEach-Object { Write-Host "    $($_.Name)" }
Write-Host ""
Write-Host "Next: Claude desktop app -> Skills -> remove old $SkillName -> upload this .skill -> open a NEW chat to load it."
