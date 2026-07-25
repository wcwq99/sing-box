# Build Magisk zips with sing-box ANDROID core from GitHub (Windows)
# Output:
#   ..\dist\sing-box-android-arm64.zip   (64-bit, github android-arm64)
#   ..\dist\sing-box-android-armv7a.zip  (32-bit, github android-arm)
# MUST use android-* assets (bionic). linux-* depends on glibc and will NOT run on Android.
# Core downloaded at pack time and bundled; device does NOT download.
#
# Usage:
#   .\build-release.ps1
#   .\build-release.ps1 -CoreVer v1.12.0

param(
  [string]$CoreVer = $env:CORE_VER,
  [string]$CoreRepo = $(if ($env:CORE_REPO) { $env:CORE_REPO } else { "SagerNet/sing-box" }),
  [string]$ModuleVer = $(if ($env:MODULE_VER) { $env:MODULE_VER } else { "v1.0.2" }),
  [int]$ModuleCode = $(if ($env:MODULE_CODE) { [int]$env:MODULE_CODE } else { 102 })
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $Root
$Dist = if ($env:DIST) { $env:DIST } else { Join-Path $RepoRoot "dist" }
$Work = Join-Path $Root ".build"

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-LatestCoreTag {
  $api = "https://api.github.com/repos/$CoreRepo/releases/latest"
  $resp = Invoke-RestMethod -Uri $api -Headers @{ "User-Agent" = "sing-box-android-build" }
  return $resp.tag_name
}

if ([string]::IsNullOrWhiteSpace($CoreVer)) {
  Write-Host "[*] resolve latest core from GitHub..."
  $CoreVer = Get-LatestCoreTag
}
$CoreVer = "v$($CoreVer.TrimStart('v'))"
$CoreVerNum = $CoreVer.TrimStart('v')

Write-Host "[*] module=$ModuleVer  core=$CoreVer  repo=$CoreRepo"
Write-Host "[*] dist=$Dist"

if (Test-Path $Work) { Remove-Item $Work -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Work, $Dist | Out-Null

function Download-Core([string]$GhArch, [string]$OutBin) {
  # GhArch must be android release arch: arm64 | arm (NOT linux-arm64/armv7)
  $asset = "sing-box-$CoreVerNum-android-$GhArch.tar.gz"
  $url = "https://github.com/$CoreRepo/releases/download/$CoreVer/$asset"
  $tgz = Join-Path $Work $asset
  $extract = Join-Path $Work "extract-android-$GhArch"
  $minBytes = 5MB

  if ((Test-Path $tgz) -and ((Get-Item $tgz).Length -gt $minBytes)) {
    Write-Host "[*] reuse cached $tgz ($((Get-Item $tgz).Length) bytes)"
  } else {
    Write-Host "[*] download $url"
    Invoke-WebRequest -Uri $url -OutFile $tgz -UseBasicParsing
  }

  if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $extract | Out-Null
  tar -xzf $tgz -C $extract

  $bin = Get-ChildItem -Path $extract -Recurse -Filter "sing-box" -File | Select-Object -First 1
  if (-not $bin) { throw "sing-box binary not found in $asset" }
  $dir = Split-Path -Parent $OutBin
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  Copy-Item -Force $bin.FullName $OutBin
  Write-Host "[OK] core -> $OutBin ($((Get-Item $OutBin).Length) bytes) [android-$GhArch]"
}

function Add-ZipEntry($zip, [string]$src, [string]$entryName) {
  if (-not (Test-Path $src)) { throw "missing: $src" }
  [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
    $zip, $src, $entryName, [System.IO.Compression.CompressionLevel]::Optimal)
}

function Pack-One([string]$Abi, [string]$GhArch) {
  $stage = Join-Path $Work "stage-$Abi"
  $zipOut = Join-Path $Dist "sing-box-android-$Abi.zip"
  $coreNote = "GitHub $CoreRepo $CoreVer android-$GhArch (bundled)"

  Write-Host "[*] pack $Abi (github arch=$GhArch)"
  if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
  New-Item -ItemType Directory -Force -Path `
    (Join-Path $stage "META-INF\com\google\android"), `
    (Join-Path $stage "sb\bin") | Out-Null

  Copy-Item "$Root\customize.sh" $stage
  Copy-Item "$Root\service.sh" $stage
  Copy-Item "$Root\uninstall.sh" $stage
  Copy-Item "$Root\README.md" $stage
  Copy-Item "$Root\META-INF\com\google\android\update-binary" (Join-Path $stage "META-INF\com\google\android\")
  Copy-Item "$Root\META-INF\com\google\android\updater-script" (Join-Path $stage "META-INF\com\google\android\")
  Copy-Item "$Root\sb\sb.sh" (Join-Path $stage "sb\")
  Copy-Item "$Root\sb\start.sh" (Join-Path $stage "sb\")
  Copy-Item "$Root\sb\stop.sh" (Join-Path $stage "sb\")
  Copy-Item "$Root\sb\restart.sh" (Join-Path $stage "sb\")
  # menu: ASCII filename only
  if (-not (Test-Path "$Root\sb\menu.sh")) { throw "missing sb/menu.sh" }
  Copy-Item "$Root\sb\menu.sh" (Join-Path $stage "sb\menu.sh")

  # Force Unix LF for all staged text/scripts (Windows editors may inject CRLF)
  Get-ChildItem -Path $stage -Recurse -File | Where-Object {
    $_.Extension -in @('.sh', '.prop', '.md', '.version') -or $_.Name -eq 'updater-script' -or $_.Name -eq 'update-binary' -or $_.Name -eq 'core.version'
  } | ForEach-Object {
    $bytes = [IO.File]::ReadAllBytes($_.FullName)
    $text = [Text.Encoding]::UTF8.GetString($bytes) -replace "`r`n", "`n" -replace "`r", "`n"
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($_.FullName, $text, $utf8NoBom)
  }

  # IMPORTANT: both ABIs share the same module id so Magisk shows ONE module
  # and later flash replaces earlier (do not use per-abi id).
  $prop = @"
id=sing-box-server
name=sing-box Server
version=$ModuleVer
versionCode=$ModuleCode
author=233boy-android
description=sing-box server Android6+. abi=$Abi. Core: $coreNote. menu: /data/adb/sing-box/menu.sh
"@ -replace "`r`n", "`n"
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  [IO.File]::WriteAllText((Join-Path $stage "module.prop"), $prop, $utf8NoBom)

  $coreVerText = @"
core_repo=$CoreRepo
core_version=$CoreVer
core_arch=android-$GhArch
module_abi=$Abi
bundled=1
source=github_release_at_pack_time
"@ -replace "`r`n", "`n"
  [IO.File]::WriteAllText((Join-Path $stage "sb\core.version"), $coreVerText, $utf8NoBom)

  Download-Core $GhArch (Join-Path $stage "sb\bin\sing-box")

  if (Test-Path $zipOut) { Remove-Item $zipOut -Force }
  $zip = [System.IO.Compression.ZipFile]::Open($zipOut, [System.IO.Compression.ZipArchiveMode]::Create)
  try {
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
      "sb/menu.sh",
      "sb/core.version",
      "sb/bin/sing-box"
    )) { $entries.Add($rel) }
    foreach ($rel in $entries) {
      $src = Join-Path $stage ($rel -replace '/', '\')
      Add-ZipEntry $zip $src $rel
    }
  } finally {
    $zip.Dispose()
  }
  Write-Host "[OK] $zipOut ($((Get-Item $zipOut).Length) bytes)"
}

# GitHub android assets: android-arm64 / android-arm (NOT linux-arm64/armv7)
Pack-One "arm64" "arm64"
Pack-One "armv7a" "arm"

# remove legacy zip names from older builds
foreach ($legacy in @("sing-box-android-armv8a.zip", "sing-box-android-v7a.zip")) {
  $p = Join-Path $Dist $legacy
  if (Test-Path $p) {
    Remove-Item $p -Force
    Write-Host "[*] removed legacy $legacy"
  }
}

$manifest = @"
built_at=$((Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ"))
module_version=$ModuleVer
module_version_code=$ModuleCode
core_repo=$CoreRepo
core_version=$CoreVer
artifacts:
  sing-box-android-arm64.zip   # 64-bit, github android-arm64 binary bundled
  sing-box-android-armv7a.zip  # 32-bit, github android-arm binary bundled
note: MUST use android-* core (bionic). linux-* glibc binaries will not run on Android. Device install does not download. Install only ONE abi package.
"@
$manifest | Set-Content -Encoding utf8 (Join-Path $Dist "build-manifest.txt")
Write-Host "======== DONE ========"
Get-ChildItem (Join-Path $Dist "sing-box-android-*.zip") | Format-Table Name, Length
Get-Content (Join-Path $Dist "build-manifest.txt")
