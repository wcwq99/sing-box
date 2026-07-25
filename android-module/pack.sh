#!/bin/sh
# Pack Magisk zip WITHOUT core (debug only).
# For release with bundled GitHub core, use: ./build-release.sh
set -e
cd "$(dirname "$0")"
OUT="../sing-box-android-server-nocore.zip"
rm -f "$OUT"
echo "[WARN] packing script-only zip (no core). Prefer build-release.sh"
zip -r "$OUT" \
  module.prop customize.sh service.sh uninstall.sh README.md \
  META-INF/com/google/android/update-binary \
  META-INF/com/google/android/updater-script \
  sb/sb.sh sb/start.sh sb/stop.sh sb/restart.sh sb/menu.sh
echo "OK: $OUT"