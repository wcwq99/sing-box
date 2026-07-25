#!/system/bin/sh
# start sing-box server
# usage: sh start.sh

SB_HOME="${SB_HOME:-/data/adb/sing-box}"
SB_BIN="$SB_HOME/bin/sing-box"
SB_CONF="$SB_HOME/conf"
SB_LOG="$SB_HOME/log"
SB_TMP="$SB_HOME/tmp"
SB_CFG="$SB_HOME/config.json"
PID_FILE="$SB_TMP/sing-box.pid"

_echo() { printf '%s\n' "$*"; }
_err() { _echo "[ERR] $*" >&2; exit 1; }
_ok() { _echo "[OK] $*"; }
_warn() { _echo "[WARN] $*"; }

mkdir -p "$SB_HOME" "$SB_CONF" "$SB_LOG" "$SB_TMP" "$SB_HOME/bin"

# prefer manager script if present
if [ -f "$SB_HOME/sb.sh" ]; then
  exec /system/bin/sh "$SB_HOME/sb.sh" start
fi
# fallback: same dir as this script
HERE=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
if [ -f "$HERE/sb.sh" ]; then
  exec /system/bin/sh "$HERE/sb.sh" start
fi

[ -x "$SB_BIN" ] || _err "missing binary: $SB_BIN"

if [ -f "$PID_FILE" ]; then
  old=$(cat "$PID_FILE" 2>/dev/null)
  if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
    _warn "already running (pid=$old)"
    exit 0
  fi
fi

if [ ! -f "$SB_CFG" ]; then
  cat >"$SB_CFG" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true,
    "output": "$SB_LOG/access.log"
  },
  "dns": {
    "servers": [
      { "type": "udp", "tag": "dns-google", "server": "8.8.8.8" },
      { "type": "udp", "tag": "dns-cloudflare", "server": "1.1.1.1" },
      { "type": "udp", "tag": "dns-ali", "server": "223.5.5.5" }
    ],
    "final": "dns-google",
    "strategy": "ipv4_only"
  },
  "outbounds": [
    { "type": "direct", "tag": "direct" }
  ],
  "route": {
    "default_domain_resolver": "dns-google"
  }
}
EOF
fi

"$SB_BIN" run -c "$SB_CFG" -C "$SB_CONF" >"$SB_LOG/stdout.log" 2>&1 &
echo $! >"$PID_FILE"
sleep 1
pid=$(cat "$PID_FILE" 2>/dev/null)
if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
  _ok "started (pid=$pid)"
else
  _err "start failed, see $SB_LOG/stdout.log"
fi
