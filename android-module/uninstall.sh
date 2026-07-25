#!/system/bin/sh
# Magisk module uninstall: keep conf by default; remove runtime only if empty marker set
# Data at /data/adb/sing-box is intentionally kept so reinstall restores configs.
# To wipe fully after uninstall:
#   rm -rf /data/adb/sing-box

# stop process if running
if [ -f /data/adb/sing-box/stop.sh ]; then
  /system/bin/sh /data/adb/sing-box/stop.sh >/dev/null 2>&1
elif [ -f /data/adb/sing-box/sb.sh ]; then
  /system/bin/sh /data/adb/sing-box/sb.sh stop >/dev/null 2>&1
fi
