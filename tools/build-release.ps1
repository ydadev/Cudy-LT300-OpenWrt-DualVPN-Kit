[CmdletBinding()]
param(
    [string]$Version = ''
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $Version) {
    $Version = (Get-Content -LiteralPath (Join-Path $RepoRoot 'VERSION') -Raw).Trim()
}
if ($Version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$') {
    throw "Invalid version: $Version"
}

& (Join-Path $PSScriptRoot 'validate-repo.ps1')

$Dist = Join-Path $RepoRoot 'dist'
New-Item -ItemType Directory -Path $Dist -Force | Out-Null
$ArchiveName = "Cudy-LT300-OpenWrt-DualVPN-Kit-v$Version.zip"
$ArchivePath = Join-Path $Dist $ArchiveName
$HashPath = "$ArchivePath.sha256"

$TempBase = [IO.Path]::GetTempPath()
$TempRoot = Join-Path $TempBase ("cudy-release-" + [guid]::NewGuid().ToString('N'))
$PackageRoot = Join-Path $TempRoot 'Cudy-LT300-OpenWrt-DualVPN-Kit'
New-Item -ItemType Directory -Path $PackageRoot -Force | Out-Null

try {
    $Files = Get-ChildItem -LiteralPath $RepoRoot -Recurse -File | Where-Object {
        $Relative = $_.FullName.Substring($RepoRoot.Length + 1)
        $Relative -notmatch '^(\.git|dist)([\\/]|$)' -and
        $Relative -notmatch '(^|[\\/])router-credentials\.md$' -and
        $Relative -notmatch '\.(zip|backup|bak|tar\.gz)$' -and
        ($_.Extension -ne '.conf' -or $Relative -match '^examples[\\/].+\.example\.conf$')
    }
    foreach ($File in $Files) {
        $Relative = $File.FullName.Substring($RepoRoot.Length + 1)
        $Target = Join-Path $PackageRoot $Relative
        New-Item -ItemType Directory -Path (Split-Path $Target -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $File.FullName -Destination $Target
    }
    if (Test-Path -LiteralPath $ArchivePath) { Remove-Item -LiteralPath $ArchivePath -Force }
    if (Test-Path -LiteralPath $HashPath) { Remove-Item -LiteralPath $HashPath -Force }
    Add-Type -AssemblyName System.IO.Compression
    $ZipStream = [IO.File]::Open($ArchivePath, [IO.FileMode]::CreateNew)
    $Zip = [IO.Compression.ZipArchive]::new($ZipStream, [IO.Compression.ZipArchiveMode]::Create, $false)
    try {
        foreach ($File in Get-ChildItem -LiteralPath $PackageRoot -Recurse -File) {
            $Relative = $File.FullName.Substring($PackageRoot.Length + 1).Replace('\', '/')
            $Entry = $Zip.CreateEntry("Cudy-LT300-OpenWrt-DualVPN-Kit/$Relative", [IO.Compression.CompressionLevel]::Optimal)
            $Input = [IO.File]::OpenRead($File.FullName)
            $Output = $Entry.Open()
            try { $Input.CopyTo($Output) } finally { $Output.Dispose(); $Input.Dispose() }
        }
    } finally {
        $Zip.Dispose()
        $ZipStream.Dispose()
    }
    $Hash = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText($HashPath, "$Hash  $ArchiveName`n", [Text.UTF8Encoding]::new($false))
} finally {
    if ($TempRoot.StartsWith($TempBase, [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $TempRoot)) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force
    }
}

Write-Host "Created: $ArchivePath"
Write-Host "SHA256: $Hash"
