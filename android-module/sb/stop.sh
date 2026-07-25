#!/system/bin/sh
# stop sing-box server
# usage: sh stop.sh

SB_HOME="${SB_HOME:-/data/adb/sing-box}"
SB_BIN="$SB_HOME/bin/sing-box"
SB_TMP="$SB_HOME/tmp"
PID_FILE="$SB_TMP/sing-box.pid"

_echo() { printf '%s\n' "$*"; }
_ok() { _echo "[OK] $*"; }
_warn() { _echo "[WARN] $*"; }

# prefer manager script if present
if [ -f "$SB_HOME/sb.sh" ]; then
  exec /system/bin/sh "$SB_HOME/sb.sh" stop
fi
HERE=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
if [ -f "$HERE/sb.sh" ]; then
  exec /system/bin/sh "$HERE/sb.sh" stop
fi

stopped=0
if [ -f "$PID_FILE" ]; then
  pid=$(cat "$PID_FILE" 2>/dev/null)
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null
    sleep 1
    kill -9 "$pid" 2>/dev/null
    stopped=1
  fi
  rm -f "$PID_FILE"
fi

# kill leftover by binary path
for d in /proc/[0-9]*; do
  [ -r "$d/cmdline" ] || continue
  if tr '\0' ' ' <"$d/cmdline" 2>/dev/null | grep -q "$SB_BIN"; then
    kill "${d##*/}" 2>/dev/null
    stopped=1
  fi
done

if [ "$stopped" = "1" ]; then
  _ok "已停止"
else
  _warn "当前未运行"
fi
