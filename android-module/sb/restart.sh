#!/system/bin/sh
# restart sing-box server
# usage: sh restart.sh

SB_HOME="${SB_HOME:-/data/adb/sing-box}"

_echo() { printf '%s\n' "$*"; }
_ok() { _echo "[OK] $*"; }

# prefer manager script if present
if [ -f "$SB_HOME/sb.sh" ]; then
  exec /system/bin/sh "$SB_HOME/sb.sh" restart
fi
HERE=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
if [ -f "$HERE/sb.sh" ]; then
  exec /system/bin/sh "$HERE/sb.sh" restart
fi

STOP="$HERE/stop.sh"
START="$HERE/start.sh"
[ -f "$STOP" ] || STOP="$SB_HOME/stop.sh"
[ -f "$START" ] || START="$SB_HOME/start.sh"

if [ -f "$STOP" ]; then
  /system/bin/sh "$STOP"
else
  _echo "[WARN] 未找到 stop.sh"
fi
sleep 1
if [ -f "$START" ]; then
  /system/bin/sh "$START"
else
  _echo "[ERR] 未找到 start.sh" >&2
  exit 1
fi
