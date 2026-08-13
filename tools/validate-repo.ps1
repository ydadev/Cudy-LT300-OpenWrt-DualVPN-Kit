[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure([string]$Message) {
    $Failures.Add($Message)
    Write-Host "ERROR: $Message" -ForegroundColor Red
}

$Required = @(
    'README.md', 'LICENSE', 'VERSION', 'CHANGELOG.md', 'SECURITY.md',
    'checksums/SHA256SUMS', 'docs/QUICKSTART-RU.md', 'docs/INSTALL-RU.md',
    'docs/ARCHITECTURE-RU.md', 'docs/WIFI-MT7603-RU.md',
    'docs/TROUBLESHOOTING-RU.md', 'docs/OTHER-DEVICES-RU.md', 'docs/FILES-RU.md',
    'scripts/quick-setup-1-prepare.sh', 'scripts/quick-setup-2-activate.sh'
)

foreach ($Relative in $Required) {
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $Relative))) {
        Add-Failure "missing required file: $Relative"
    }
}

$ChecksumFile = Join-Path $RepoRoot 'checksums/SHA256SUMS'
if (Test-Path -LiteralPath $ChecksumFile) {
    foreach ($Line in Get-Content -LiteralPath $ChecksumFile) {
        if ($Line -notmatch '^([0-9a-f]{64})  (.+)$') {
            Add-Failure "invalid SHA256SUMS line: $Line"
            continue
        }
        $Expected = $Matches[1]
        $Relative = $Matches[2].Replace('/', [IO.Path]::DirectorySeparatorChar)
        $Path = Join-Path $RepoRoot $Relative
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            Add-Failure "checksum target is missing: $Relative"
            continue
        }
        $Actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($Actual -ne $Expected) {
            Add-Failure "checksum mismatch: $Relative"
        }
    }
}

$TextFiles = Get-ChildItem -LiteralPath $RepoRoot -Recurse -File | Where-Object {
    $_.FullName -notmatch '[\\/](\.git|dist)[\\/]' -and
    $_.Extension -in @('.md', '.sh', '.conf', '.example', '.ps1', '.py', '.yml', '.yaml')
}
$SecretPatterns = @(
    '(?im)^\s*(PrivateKey|PresharedKey)\s*=\s*(?!REPLACE_WITH_)[A-Za-z0-9+/]{40,}={0,2}\s*$',
    '(?im)^\s*option\s+(private_key|preshared_key|password)\s+''(?!REPLACE_WITH_)[^'']+''\s*$'
)
foreach ($File in $TextFiles) {
    $Content = Get-Content -LiteralPath $File.FullName -Raw
    foreach ($Pattern in $SecretPatterns) {
        if ($Content -match $Pattern) {
            Add-Failure "possible secret in $($File.FullName.Substring($RepoRoot.Length + 1))"
        }
    }
}

$Python = Get-Command python -ErrorAction SilentlyContinue
if ($Python) {
    & $Python.Source (Join-Path $RepoRoot 'tools/check-markdown-links.py') $RepoRoot
    if ($LASTEXITCODE -ne 0) { Add-Failure 'Markdown link validation failed' }
} else {
    $LinkRegex = [regex]'(?<!!)\[[^\]]*\]\(([^)]+)\)'
    foreach ($Document in Get-ChildItem -LiteralPath $RepoRoot -Recurse -File -Filter '*.md') {
        if ($Document.FullName -match '[\\/](\.git|dist)[\\/]') { continue }
        $Content = Get-Content -LiteralPath $Document.FullName -Raw
        foreach ($Match in $LinkRegex.Matches($Content)) {
            $Target = $Match.Groups[1].Value.Trim().Trim('<', '>')
            if (-not $Target -or $Target -match '^(https?://|mailto:|#)') { continue }
            $Target = [uri]::UnescapeDataString(($Target -split '#', 2)[0])
            if (-not $Target) { continue }
            $Resolved = [IO.Path]::GetFullPath((Join-Path $Document.DirectoryName $Target))
            if (-not $Resolved.StartsWith($RepoRoot, [StringComparison]::OrdinalIgnoreCase)) {
                Add-Failure "Markdown link leaves repository in $($Document.Name): $Target"
            } elseif (-not (Test-Path -LiteralPath $Resolved)) {
                Add-Failure "missing Markdown link target in $($Document.Name): $Target"
            }
        }
    }
}

$ShellChecked = $false
$Wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
if ($Wsl) {
    $WslRoot = (& $Wsl.Source wslpath -a $RepoRoot 2>$null)
    if ($LASTEXITCODE -eq 0 -and $WslRoot) {
        & $Wsl.Source sh -c "find '$WslRoot/scripts' -type f -exec sh -n {} \;"
        if ($LASTEXITCODE -ne 0) { Add-Failure 'shell syntax validation failed' }
        $ShellChecked = $true
    }
}
if (-not $ShellChecked) {
    $Git = Get-Command git -ErrorAction SilentlyContinue
    $GitSh = if ($Git) { Join-Path (Split-Path (Split-Path $Git.Source -Parent) -Parent) 'usr\bin\sh.exe' }
    if ($GitSh -and (Test-Path -LiteralPath $GitSh)) {
        foreach ($Script in Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'scripts') -File) {
            & $GitSh -n $Script.FullName
            if ($LASTEXITCODE -ne 0) { Add-Failure "shell syntax failed: $($Script.Name)" }
        }
        $ShellChecked = $true
    }
}
if (-not $ShellChecked) {
    Write-Warning 'WSL not found; shell syntax was not checked'
}

if ($Failures.Count -gt 0) {
    throw "Repository validation failed with $($Failures.Count) error(s)."
}
Write-Host 'Repository validation: OK' -ForegroundColor Green
