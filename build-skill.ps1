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
      3. Uses the built-in Windows tar.exe (bsdtar), which writes spec-compliant
         FORWARD-SLASH zip entry paths. PowerShell's Compress-Archive writes
         BACKSLASHES, which some skill installers reject, so it is not used.
      4. Self-verifies after packaging: forward-slash entries + required files.

    NOTE: this script is intentionally ASCII-only. Windows PowerShell 5.1 reads
    BOM-less .ps1 files using the system ANSI codepage, which corrupts non-ASCII
    text. Keeping it ASCII makes it safe to edit with any tool.

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
$TmpZip    = Join-Path $OutDir "$SkillName.zip"   # tar needs a .zip extension to auto-pick the format
$TarExe    = Join-Path $env:SystemRoot 'System32\tar.exe'

# Sources to include (relative to repo root). Runtime-only.
$Includes = @('SKILL.md', 'agents')
# Extensions to LF-normalize.
$TextExt  = @('.md', '.yaml', '.yml', '.json', '.txt')

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

# --- Preconditions ---
if (-not (Test-Path $TarExe)) {
    throw "Windows tar.exe not found ($TarExe). Requires the bsdtar bundled with Windows 10/11."
}
foreach ($item in $Includes) {
    if (-not (Test-Path (Join-Path $RepoRoot $item))) {
        throw "Missing source: $item (expected under $RepoRoot)"
    }
}

# --- 1. Build a clean staging dir: <temp>/<guid>/aoccqa-rule-loader/... ---
$Stage    = Join-Path ([System.IO.Path]::GetTempPath()) ("skillpkg_" + [System.Guid]::NewGuid().ToString('N'))
$StageTop = Join-Path $Stage $SkillName
Write-Step "Staging: $StageTop"
New-Item -ItemType Directory -Path $StageTop -Force | Out-Null

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$srcFiles  = foreach ($item in $Includes) {
    Get-ChildItem -LiteralPath (Join-Path $RepoRoot $item) -Recurse -File
}
foreach ($f in $srcFiles) {
    $rel  = $f.FullName.Substring($RepoRoot.Length).TrimStart('\', '/')
    $dest = Join-Path $StageTop $rel
    New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null
    if ($TextExt -contains $f.Extension.ToLower()) {
        $text = [System.IO.File]::ReadAllText($f.FullName)
        $text = $text -replace "`r`n", "`n"          # CRLF -> LF
        [System.IO.File]::WriteAllText($dest, $text, $utf8NoBom)
    } else {
        Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
    }
    Write-Host ("    + {0}/{1}" -f $SkillName, ($rel -replace '\\', '/'))
}

# --- 2. Zip with bsdtar (forward slashes), then rename to .skill ---
Write-Step "Compressing (bsdtar)"
foreach ($p in @($TmpZip, $OutFile)) { if (Test-Path $p) { Remove-Item -LiteralPath $p -Force } }
& $TarExe -a -c -f $TmpZip -C $Stage $SkillName
if ($LASTEXITCODE -ne 0) { throw "tar failed, exit=$LASTEXITCODE" }
Move-Item -LiteralPath $TmpZip -Destination $OutFile -Force

# --- 3. Self-verify ---
Write-Step "Verifying package"
$entries = & $TarExe -tf $OutFile
$bad = $entries | Where-Object { $_ -match '\\' }
if ($bad) { throw "Package contains backslash paths (not ZIP-spec compliant):`n$($bad -join "`n")" }
if (-not ($entries -contains "$SkillName/SKILL.md")) {
    throw "Package is missing $SkillName/SKILL.md"
}

# --- Cleanup ---
Remove-Item -LiteralPath $Stage -Recurse -Force

$size = (Get-Item $OutFile).Length
Write-Host ""
Write-Host ("OK  ->  {0}  ({1} bytes)" -f $OutFile, $size) -ForegroundColor Green
Write-Host "entries:" -ForegroundColor Green
$entries | ForEach-Object { Write-Host "    $_" }
Write-Host ""
Write-Host "Next: Claude desktop app -> Skills -> remove old $SkillName -> upload this .skill -> open a NEW chat to load it."
