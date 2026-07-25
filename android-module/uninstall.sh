#!/system/bin/sh
# Magisk module uninstall: stop process and remove runtime data fully

SB_HOME=/data/adb/sing-box

# stop process first
if [ -f "$SB_HOME/stop.sh" ]; then
  /system/bin/sh "$SB_HOME/stop.sh" >/dev/null 2>&1
elif [ -f "$SB_HOME/sb.sh" ]; then
  /system/bin/sh "$SB_HOME/sb.sh" stop >/dev/null 2>&1
fi

# kill leftover by binary path
if [ -x "$SB_HOME/bin/sing-box" ]; then
  for d in /proc/[0-9]*; do
    [ -r "$d/cmdline" ] || continue
    if tr '\0' ' ' <"$d/cmdline" 2>/dev/null | grep -q "$SB_HOME/bin/sing-box"; then
      kill "${d##*/}" 2>/dev/null
      kill -9 "${d##*/}" 2>/dev/null
    fi
  done
fi

# remove fixed home completely (scripts/binary/conf/log)
rm -rf "$SB_HOME"
