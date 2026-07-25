# Pack Magisk zip WITHOUT core (debug only).
# For release with bundled GitHub core, use: .\build-release.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$out = Join-Path (Split-Path -Parent $root) "sing-box-android-server-nocore.zip"
if (Test-Path $out) { Remove-Item $out -Force }
Write-Host "[WARN] packing script-only zip (no core). Prefer build-release.ps1"

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$entries = New-Object System.Collections.Generic.List[string]
foreach ($rel in @(
  "module.prop",
  "customize.sh",
  "service.sh",
  "uninstall.sh",
  "README.md",
  "META-INF/com/google/android/update-binary",
  "META-INF/com/google/android/updater-script",
  "sb/sb.sh",
  "sb/start.sh",
  "sb/stop.sh",
  "sb/restart.sh",
  "sb/menu.sh"
)) { $entries.Add($rel) }

$zip = [System.IO.Compression.ZipFile]::Open($out, [System.IO.Compression.ZipArchiveMode]::Create)
try {
  foreach ($rel in $entries) {
    $src = Join-Path $root ($rel -replace '/', '\')
    if (-not (Test-Path $src)) { throw "missing: $src" }
    [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
      $zip, $src, $rel, [System.IO.Compression.CompressionLevel]::Optimal)
  }
} finally {
  $zip.Dispose()
}

Write-Host "OK: $out"