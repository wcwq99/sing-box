#!/usr/bin/env bash
# Build Magisk zips with sing-box ANDROID core from GitHub releases.
# Output:
#   dist/sing-box-android-arm64.zip    (64-bit, github android-arm64 binary bundled)
#   dist/sing-box-android-armv7a.zip   (32-bit, github android-arm binary bundled)
#
# MUST use android-* assets (bionic). linux-* depends on glibc and will NOT run on Android.
# Core is downloaded at pack time and embedded into the zip.
# Device install does NOT download core.
#
# Usage:
#   ./build-release.sh              # latest core
#   ./build-release.sh v1.12.0      # pin core version
#   CORE_VER=v1.11.0 ./build-release.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$ROOT/.." && pwd)"
DIST="${DIST:-$REPO_ROOT/dist}"
WORK="${WORK:-$ROOT/.build}"
CORE_REPO="${CORE_REPO:-SagerNet/sing-box}"
MODULE_VER="${MODULE_VER:-v1.0.2}"
MODULE_CODE="${MODULE_CODE:-102}"

CORE_VER="${1:-${CORE_VER:-}}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[ERR] need command: $1" >&2
    exit 1
  }
}

need curl
need tar
need zip
need sed
need grep

api_latest() {
  curl -fsSL "https://api.github.com/repos/${CORE_REPO}/releases/latest" \
    | grep -oE '"tag_name":[[:space:]]*"[^"]+"' \
    | head -1 \
    | sed 's/.*"\(v[^"]*\)".*/\1/'
}

if [[ -z "${CORE_VER}" ]]; then
  echo "[*] resolve latest core from GitHub..."
  CORE_VER="$(api_latest)"
fi
[[ -n "${CORE_VER}" ]] || {
  echo "[ERR] cannot resolve core version" >&2
  exit 1
}
# strip leading v for asset name path segment
CORE_VER_NUM="${CORE_VER#v}"
CORE_VER="v${CORE_VER_NUM}"

echo "[*] module=${MODULE_VER}  core=${CORE_VER}  repo=${CORE_REPO}"
echo "[*] dist=${DIST}"

rm -rf "$WORK"
mkdir -p "$WORK" "$DIST"

download_core() {
  local gh_arch="$1" # android release arch: arm64 | arm
  local out_bin="$2"
  local asset="sing-box-${CORE_VER_NUM}-android-${gh_arch}.tar.gz"
  local url="https://github.com/${CORE_REPO}/releases/download/${CORE_VER}/${asset}"
  local tgz="$WORK/${asset}"
  local extract="$WORK/extract-android-${gh_arch}"

  echo "[*] download ${url}"
  curl -fL --retry 3 --retry-delay 2 -o "$tgz" "$url"

  rm -rf "$extract"
  mkdir -p "$extract"
  tar -xzf "$tgz" -C "$extract"

  # tarball usually: sing-box-<ver>-android-<arch>/sing-box
  local bin
  bin="$(find "$extract" -type f -name sing-box | head -1)"
  [[ -n "$bin" && -f "$bin" ]] || {
    echo "[ERR] sing-box binary not found in $asset" >&2
    exit 1
  }
  mkdir -p "$(dirname "$out_bin")"
  cp -f "$bin" "$out_bin"
  chmod 755 "$out_bin"
  echo "[OK] core -> $out_bin ($(wc -c <"$out_bin") bytes) [android-${gh_arch}]"
}

pack_one() {
  local abi="$1"      # arm64 | armv7a
  local gh_arch="$2"  # android release arch: arm64 | arm
  local stage="$WORK/stage-${abi}"
  local zip_out="$DIST/sing-box-android-${abi}.zip"
  local core_note="GitHub ${CORE_REPO} ${CORE_VER} android-${gh_arch} (bundled)"

  echo "[*] pack ${abi} (github arch=${gh_arch})"
  rm -rf "$stage"
  mkdir -p "$stage/META-INF/com/google/android" \
    "$stage/sb/bin" \
    "$stage/system/bin"

  # scripts / meta
  cp -f "$ROOT/customize.sh" "$stage/"
  cp -f "$ROOT/service.sh" "$stage/"
  cp -f "$ROOT/uninstall.sh" "$stage/"
  cp -f "$ROOT/README.md" "$stage/"
  cp -f "$ROOT/META-INF/com/google/android/update-binary" "$stage/META-INF/com/google/android/"
  cp -f "$ROOT/META-INF/com/google/android/updater-script" "$stage/META-INF/com/google/android/"
  cp -f "$ROOT/sb/sb.sh" "$stage/sb/"
  cp -f "$ROOT/sb/start.sh" "$stage/sb/"
  cp -f "$ROOT/sb/stop.sh" "$stage/sb/"
  cp -f "$ROOT/sb/restart.sh" "$stage/sb/"
  cp -f "$ROOT/sb/menu.sh" "$stage/sb/menu.sh"

  # BOTH abis share the same Magisk module id -> only ONE entry in Magisk UI
  cat >"$stage/module.prop" <<EOF
id=sing-box-server
name=sing-box Server
version=${MODULE_VER}
versionCode=${MODULE_CODE}
author=233boy-android
description=sing-box server Android6+. abi=${abi}. Core: ${core_note}. menu: /data/adb/sing-box/menu.sh
EOF

  # core version stamp
  cat >"$stage/sb/core.version" <<EOF
core_repo=${CORE_REPO}
core_version=${CORE_VER}
core_arch=android-${gh_arch}
module_abi=${abi}
bundled=1
source=github_release_at_pack_time
EOF

  download_core "$gh_arch" "$stage/sb/bin/sing-box"

  # zip with forward-slash paths
  rm -f "$zip_out"
  (
    cd "$stage"
    zip -r9 "$zip_out" \
      module.prop customize.sh service.sh uninstall.sh README.md \
      META-INF/com/google/android/update-binary \
      META-INF/com/google/android/updater-script \
      sb/sb.sh sb/start.sh sb/stop.sh sb/restart.sh sb/menu.sh \
      sb/core.version sb/bin/sing-box
  )
  echo "[OK] $zip_out ($(wc -c <"$zip_out") bytes)"
}

# GitHub android assets: android-arm64 / android-arm (NOT linux-arm64/armv7)
pack_one "arm64" "arm64"
pack_one "armv7a" "arm"

# remove legacy zip names from older builds
rm -f "$DIST/sing-box-android-armv8a.zip" "$DIST/sing-box-android-v7a.zip"

# also write a small manifest
cat >"$DIST/build-manifest.txt" <<EOF
built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
module_version=${MODULE_VER}
module_version_code=${MODULE_CODE}
core_repo=${CORE_REPO}
core_version=${CORE_VER}
artifacts:
  sing-box-android-arm64.zip   # 64-bit, github android-arm64 binary bundled
  sing-box-android-armv7a.zip  # 32-bit, github android-arm binary bundled
note: MUST use android-* core (bionic). linux-* glibc binaries will not run on Android. Device install does not download. Install only ONE abi package.
EOF

echo
echo "======== DONE ========"
ls -lh "$DIST"/sing-box-android-*.zip
cat "$DIST/build-manifest.txt"
