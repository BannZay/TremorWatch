# Builds dist/TremorWatch-<version>.zip containing only the files the addon needs at runtime.
# Usage: powershell -File tools/release.ps1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = Split-Path -Parent $PSScriptRoot
$name = 'TremorWatch'
$toc = Join-Path $root "$name.toc"

$version = (Select-String -Path $toc -Pattern '^## Version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()

# Every file listed in the toc must exist.
$missing = @()
foreach ($line in Get-Content $toc) {
	if ($line -match '^\s*(#|$)') { continue }
	if (-not (Test-Path (Join-Path $root $line.Trim()))) { $missing += $line.Trim() }
}
if ($missing) { throw "Files listed in the toc are missing: $($missing -join ', ')" }

# What goes into the release (relative to the repo root).
$include = @("$name.toc", '*.lua', 'LICENSE', 'README.md', 'libs', 'Sounds')

$files = foreach ($item in $include) {
	Get-ChildItem -Path (Join-Path $root $item) -File -Recurse:($item -in 'libs', 'Sounds') -ErrorAction SilentlyContinue
}
$files = $files | Sort-Object FullName -Unique

$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null
$zipPath = Join-Path $dist "$name-$version.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath }

$zip = [System.IO.Compression.ZipFile]::Open($zipPath, 'Create')
try {
	foreach ($f in $files) {
		$rel = $f.FullName.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
		[void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.FullName, "$name/$rel", 'Optimal')
	}
} finally {
	$zip.Dispose()
}

"{0}: {1} files, {2:N1} MB" -f $zipPath, $files.Count, ((Get-Item $zipPath).Length / 1MB)
