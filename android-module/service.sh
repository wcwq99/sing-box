#!/system/bin/sh
# Magisk late_start service: auto start sing-box if binary + conf exist

MODDIR=${0%/*}
SB_HOME=/data/adb/sing-box
SB_BIN=$SB_HOME/bin/sing-box
SB_SH=$SB_HOME/sb.sh
PID_FILE=$SB_HOME/tmp/sing-box.pid

# wait boot complete
i=0
while [ $i -lt 60 ]; do
  boot=$(getprop sys.boot_completed 2>/dev/null)
  [ "$boot" = "1" ] && break
  i=$((i + 1))
  sleep 2
done

[ -x "$SB_BIN" ] || exit 0
[ -f "$SB_HOME/config.json" ] || exit 0

# already running
if [ -f "$PID_FILE" ]; then
  old=$(cat "$PID_FILE" 2>/dev/null)
  if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
    exit 0
  fi
fi

# prefer start.sh, then sb.sh
if [ -f "$SB_HOME/start.sh" ]; then
  /system/bin/sh "$SB_HOME/start.sh" >/dev/null 2>&1
  exit 0
fi
if [ -f "$SB_SH" ]; then
  /system/bin/sh "$SB_SH" start >/dev/null 2>&1
  exit 0
fi

mkdir -p "$SB_HOME/log" "$SB_HOME/tmp"
"$SB_BIN" run -c "$SB_HOME/config.json" -C "$SB_HOME/conf" \
  >"$SB_HOME/log/stdout.log" 2>&1 &
echo $! >"$PID_FILE"
