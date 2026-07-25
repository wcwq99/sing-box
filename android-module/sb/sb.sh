#!/system/bin/sh
# sing-box Android server manager
# target: Android 6+ (Magisk / root shell)
# fixed home: /data/adb/sing-box
# core NOT bundled — put binary at $SB_HOME/bin/sing-box

SB_HOME="${SB_HOME:-/data/adb/sing-box}"
SB_BIN="$SB_HOME/bin/sing-box"
SB_CONF="$SB_HOME/conf"
SB_LOG="$SB_HOME/log"
SB_TMP="$SB_HOME/tmp"
SB_CFG="$SB_HOME/config.json"
PID_FILE="$SB_TMP/sing-box.pid"
SCRIPT_VER="v1.0.0-android"

# busybox / toybox helpers
_echo() { printf '%s\n' "$*"; }
_err() { _echo "[ERR] $*" >&2; exit 1; }
_warn() { _echo "[WARN] $*"; }
_ok() { _echo "[OK] $*"; }
_info() { _echo "[*] $*"; }

_mkdir() { mkdir -p "$@" 2>/dev/null; }

_ensure_dirs() {
  _mkdir "$SB_HOME" "$SB_CONF" "$SB_LOG" "$SB_TMP" "$SB_HOME/bin"
}

_rand_hex() {
  # $1 = bytes (default 8)
  n=${1:-8}
  if [ -r /dev/urandom ]; then
    # od may exist on android
    if command -v od >/dev/null 2>&1; then
      od -An -N"$n" -tx1 /dev/urandom 2>/dev/null | tr -d ' \n'
      return
    fi
    if command -v hexdump >/dev/null 2>&1; then
      hexdump -n "$n" -e '1/1 "%02x"' /dev/urandom 2>/dev/null
      return
    fi
  fi
  # fallback
  date +%s%N 2>/dev/null | md5sum 2>/dev/null | cut -c1-$((n * 2))
}

_uuid() {
  # try core first
  if [ -x "$SB_BIN" ]; then
    u=$("$SB_BIN" generate uuid 2>/dev/null)
    [ -n "$u" ] && { _echo "$u"; return; }
  fi
  if [ -r /proc/sys/kernel/random/uuid ]; then
    cat /proc/sys/kernel/random/uuid
    return
  fi
  # RFC4122-ish fallback (mksh/Android6 safe, no bash substr)
  h=$(_rand_hex 16)
  a=$(printf '%s' "$h" | cut -c1-8)
  b=$(printf '%s' "$h" | cut -c9-12)
  c=$(printf '%s' "$h" | cut -c13-16)
  d=$(printf '%s' "$h" | cut -c17-20)
  e=$(printf '%s' "$h" | cut -c21-32)
  _echo "$a-$b-$c-$d-$e"
}

_get_port() {
  # random 10000-60000, check with /proc/net if possible
  i=0
  seed=$(date +%s 2>/dev/null)
  [ -z "$seed" ] && seed=12345
  while [ $i -lt 50 ]; do
    p=$(( (seed + i * 97) % 50000 + 10000 ))
    if ! _port_used "$p"; then
      _echo "$p"
      return
    fi
    i=$((i + 1))
  done
  _echo "23333"
}

_port_used() {
  port="$1"
  if [ -r /proc/net/tcp ] || [ -r /proc/net/tcp6 ]; then
    # rough check: convert port to hex upper
    if command -v printf >/dev/null 2>&1; then
      hx=$(printf '%04X' "$port" 2>/dev/null)
      grep -qi ":$hx " /proc/net/tcp /proc/net/tcp6 2>/dev/null && return 0
    fi
  fi
  # ss/netstat optional
  if command -v ss >/dev/null 2>&1; then
    ss -lntu 2>/dev/null | grep -q ":$port " && return 0
  fi
  if command -v netstat >/dev/null 2>&1; then
    netstat -lntu 2>/dev/null | grep -q ":$port " && return 0
  fi
  return 1
}

_is_ipv4() {
  echo "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'
}

_get_ip() {
  # 1) manual override
  if [ -n "$SB_IP" ] && _is_ipv4 "$SB_IP"; then
    _echo "$SB_IP"
    return
  fi
  if [ -f "$SB_HOME/ip.txt" ]; then
    ip=$(tr -d ' \r\n\t' <"$SB_HOME/ip.txt" 2>/dev/null)
    if _is_ipv4 "$ip"; then
      _echo "$ip"
      return
    fi
  fi

  ip=""

  # 2) Android props (LAN, best for same-subnet clients)
  for p in dhcp.wlan0.ipaddress dhcp.eth0.ipaddress dhcp.wlan1.ipaddress; do
    ip=$(getprop "$p" 2>/dev/null)
    _is_ipv4 "$ip" && break
    ip=""
  done

  # 3) ip route get ... src X (no awk)
  if [ -z "$ip" ] && command -v ip >/dev/null 2>&1; then
    line=$(ip route get 1.1.1.1 2>/dev/null | head -1)
    # ... src 192.168.x.x ...
    ip=$(echo "$line" | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
    # better: token after src
    if echo "$line" | grep -q ' src '; then
      ip=$(echo "$line" | sed -n 's/.* src \([0-9.]*\).*/\1/p')
    fi
    _is_ipv4 "$ip" || ip=""
  fi

  # 4) ip -f inet addr show
  if [ -z "$ip" ] && command -v ip >/dev/null 2>&1; then
    for iface in wlan0 eth0 rmnet_data0 ap0; do
      line=$(ip -f inet addr show "$iface" 2>/dev/null | grep 'inet ' | head -1)
      ip=$(echo "$line" | sed -n 's/.*inet \([0-9.]*\).*/\1/p')
      if _is_ipv4 "$ip" && [ "$ip" != "127.0.0.1" ]; then
        break
      fi
      ip=""
    done
  fi

  # 5) ifconfig
  if [ -z "$ip" ] && command -v ifconfig >/dev/null 2>&1; then
    for iface in wlan0 eth0; do
      line=$(ifconfig "$iface" 2>/dev/null | grep 'inet ' | head -1)
      ip=$(echo "$line" | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')
      [ -z "$ip" ] && ip=$(echo "$line" | sed -n 's/.*inet \([0-9.]*\).*/\1/p')
      if _is_ipv4 "$ip" && [ "$ip" != "127.0.0.1" ]; then
        break
      fi
      ip=""
    done
  fi

  # 6) public IP last (often useless for LAN tcping)
  if [ -z "$ip" ] && command -v wget >/dev/null 2>&1; then
    ip=$(wget -qO- --timeout=3 https://one.one.one.one/cdn-cgi/trace 2>/dev/null | grep '^ip=' | cut -d= -f2)
    _is_ipv4 "$ip" || ip=""
  fi
  if [ -z "$ip" ] && command -v curl >/dev/null 2>&1; then
    ip=$(curl -fsS --max-time 3 https://one.one.one.one/cdn-cgi/trace 2>/dev/null | grep '^ip=' | cut -d= -f2)
    _is_ipv4 "$ip" || ip=""
  fi

  [ -z "$ip" ] && ip="127.0.0.1"
  _echo "$ip"
}

_check_bin() {
  if [ ! -x "$SB_BIN" ]; then
    _err "未找到 sing-box 可执行文件: $SB_BIN
请下载 Android/linux-arm64 版放到该路径并 chmod +x
示例:
  adb push sing-box $SB_BIN
  chmod 755 $SB_BIN"
  fi
}

_ensure_base_config() {
  _ensure_dirs
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
}

_pid() {
  if [ -f "$PID_FILE" ]; then
    cat "$PID_FILE" 2>/dev/null
  fi
}

# true if $1 is a live sing-box worker pid (not shell/pgrep helpers)
_is_bin_pid() {
  pid="$1"
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  [ -r "/proc/$pid/cmdline" ] || return 1
  cmd=$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null)
  # must be the binary itself, not manager scripts / pgrep / sh
  echo "$cmd" | grep -q "$SB_BIN" || return 1
  echo "$cmd" | grep -Eq '(^|/)(pgrep|grep|sh|bash|mksh)( |$)' && return 1
  # exe symlink best-effort
  if [ -L "/proc/$pid/exe" ]; then
    exe=$(readlink "/proc/$pid/exe" 2>/dev/null)
    [ -n "$exe" ] && [ "$exe" != "$SB_BIN" ] && return 1
  fi
  return 0
}

_is_running() {
  pid=$(_pid)
  if _is_bin_pid "$pid"; then
    return 0
  fi
  # /proc scan (avoid pgrep -f self-match on the pattern string)
  for d in /proc/[0-9]*; do
    [ -r "$d/cmdline" ] || continue
    pid=${d##*/}
    _is_bin_pid "$pid" && return 0
  done
  return 1
}

_find_bin_pid() {
  pid=$(_pid)
  if _is_bin_pid "$pid"; then
    _echo "$pid"
    return 0
  fi
  for d in /proc/[0-9]*; do
    [ -r "$d/cmdline" ] || continue
    pid=${d##*/}
    if _is_bin_pid "$pid"; then
      _echo "$pid"
      return 0
    fi
  done
  return 1
}

cmd_status() {
  _ensure_dirs
  if _is_running; then
    pid=$(_find_bin_pid)
    _ok "sing-box 运行中 (pid=$pid)"
    if [ -x "$SB_BIN" ]; then
      ver=$("$SB_BIN" version 2>/dev/null | head -1)
      _info "core: $ver"
    fi
  else
    _warn "sing-box 已停止"
  fi
  n=$(ls "$SB_CONF"/*.json 2>/dev/null | wc -l | tr -d ' ')
  _info "配置数: ${n:-0}  目录: $SB_HOME"
}

cmd_start() {
  _check_bin
  _ensure_base_config
  if _is_running; then
    _warn "已在运行"
    return 0
  fi
  # validate
  if ! "$SB_BIN" check -c "$SB_CFG" -C "$SB_CONF" >/dev/null 2>&1; then
    _warn "配置检查失败，仍尝试启动；详见 $SB_LOG/error.log"
    "$SB_BIN" check -c "$SB_CFG" -C "$SB_CONF" >"$SB_LOG/error.log" 2>&1 || true
  fi
  "$SB_BIN" run -c "$SB_CFG" -C "$SB_CONF" >"$SB_LOG/stdout.log" 2>&1 &
  echo $! >"$PID_FILE"
  sleep 1
  if _is_running; then
    _ok "已启动 (pid=$(cat "$PID_FILE"))"
  else
    _err "启动失败，详见 $SB_LOG/stdout.log"
  fi
}

cmd_stop() {
  pid=$(_pid)
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null
    sleep 1
    kill -9 "$pid" 2>/dev/null
    rm -f "$PID_FILE"
    _ok "已停止"
    return
  fi
  # kill by path
  for d in /proc/[0-9]*; do
    [ -r "$d/cmdline" ] || continue
    if tr '\0' ' ' <"$d/cmdline" 2>/dev/null | grep -q "$SB_BIN"; then
      kill "${d##*/}" 2>/dev/null
    fi
  done
  rm -f "$PID_FILE"
  _ok "已停止"
}

cmd_restart() {
  cmd_stop
  sleep 1
  cmd_start
}

# ---------- protocol: write inbound json ----------
# minimal set for Android:
#   vmess-ws (required)
#   shadowsocks / socks / http / vless-reality
#   hysteria2 (optional, self-signed tls)

_write_vmess_ws() {
  name="$1"; port="$2"; uuid="$3"; path="$4"; host="$5"
  [ -z "$path" ] && path="/$uuid"
  [ -z "$host" ] && host="www.bing.com"
  file="$SB_CONF/${name}.json"
  cat >"$file" <<EOF
{
  "inbounds": [
    {
      "tag": "${name}.json",
      "type": "vmess",
      "listen": "0.0.0.0",
      "listen_port": $port,
      "users": [
        { "uuid": "$uuid", "alterId": 0 }
      ],
      "transport": {
        "type": "ws",
        "path": "$path",
        "headers": { "Host": "$host" },
        "early_data_header_name": "Sec-WebSocket-Protocol"
      }
    }
  ]
}
EOF
  _echo "$file"
}

_write_shadowsocks() {
  name="$1"; port="$2"; method="$3"; password="$4"
  [ -z "$method" ] && method="aes-128-gcm"
  file="$SB_CONF/${name}.json"
  cat >"$file" <<EOF
{
  "inbounds": [
    {
      "tag": "${name}.json",
      "type": "shadowsocks",
      "listen": "0.0.0.0",
      "listen_port": $port,
      "method": "$method",
      "password": "$password"
    }
  ]
}
EOF
  _echo "$file"
}

_write_socks() {
  name="$1"; port="$2"; user="$3"; pass="$4"
  file="$SB_CONF/${name}.json"
  cat >"$file" <<EOF
{
  "inbounds": [
    {
      "tag": "${name}.json",
      "type": "socks",
      "listen": "0.0.0.0",
      "listen_port": $port,
      "users": [
        { "username": "$user", "password": "$pass" }
      ]
    }
  ]
}
EOF
  _echo "$file"
}

_write_http() {
  name="$1"; port="$2"; user="$3"; pass="$4"
  file="$SB_CONF/${name}.json"
  cat >"$file" <<EOF
{
  "inbounds": [
    {
      "tag": "${name}.json",
      "type": "http",
      "listen": "0.0.0.0",
      "listen_port": $port,
      "users": [
        { "username": "$user", "password": "$pass" }
      ]
    }
  ]
}
EOF
  _echo "$file"
}

_write_vless_reality() {
  name="$1"; port="$2"; uuid="$3"; sni="$4"; priv="$5"; pub="$6"
  [ -z "$sni" ] && sni="www.microsoft.com"
  file="$SB_CONF/${name}.json"
  cat >"$file" <<EOF
{
  "inbounds": [
    {
      "tag": "${name}.json",
      "type": "vless",
      "listen": "0.0.0.0",
      "listen_port": $port,
      "users": [
        { "uuid": "$uuid", "flow": "xtls-rprx-vision" }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$sni",
        "reality": {
          "enabled": true,
          "handshake": { "server": "$sni", "server_port": 443 },
          "private_key": "$priv",
          "short_id": [""]
        }
      }
    }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct" },
    { "type": "direct", "tag": "public_key_$pub" }
  ]
}
EOF
  _echo "$file"
}

_ensure_tls() {
  # self-signed for hy2; generated by core if missing
  cer="$SB_HOME/bin/tls.cer"
  key="$SB_HOME/bin/tls.key"
  if [ -f "$cer" ] && [ -f "$key" ]; then
    return 0
  fi
  _check_bin
  tmp="$SB_TMP/tls.tmp"
  "$SB_BIN" generate tls-keypair tls -m 456 >"$tmp" 2>/dev/null || {
    _err "生成 TLS 密钥对失败"
  }
  # extract without awk (Android often has no awk)
  sed -n '/BEGIN PRIVATE KEY/,/END PRIVATE KEY/p' "$tmp" >"$key"
  sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' "$tmp" >"$cer"
  rm -f "$tmp"
  [ -s "$cer" ] && [ -s "$key" ] || _err "提取 TLS 证书失败"
}

_write_hysteria2() {
  name="$1"; port="$2"; password="$3"
  _ensure_tls
  cer="$SB_HOME/bin/tls.cer"
  key="$SB_HOME/bin/tls.key"
  file="$SB_CONF/${name}.json"
  cat >"$file" <<EOF
{
  "inbounds": [
    {
      "tag": "${name}.json",
      "type": "hysteria2",
      "listen": "0.0.0.0",
      "listen_port": $port,
      "users": [ { "password": "$password" } ],
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "$cer",
        "key_path": "$key"
      }
    }
  ]
}
EOF
  _echo "$file"
}

_b64() {
  # base64 encode stdin, no wrap
  if command -v base64 >/dev/null 2>&1; then
    base64 2>/dev/null | tr -d '\n'
    return
  fi
  if command -v toybox >/dev/null 2>&1; then
    toybox base64 2>/dev/null | tr -d '\n'
    return
  fi
  # last resort: openssl
  if command -v openssl >/dev/null 2>&1; then
    openssl base64 -A 2>/dev/null
    return
  fi
  _err "需要 base64 命令"
}

_is_auto_or_empty() {
  [ -z "$1" ] || [ "$1" = "auto" ]
}

cmd_add() {
  _ensure_base_config
  proto=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
  [ "$#" -gt 0 ] && shift

  case "$proto" in
    ""|help|-h)
      _echo "用法: sb add <protocol> [args|auto]"
      _echo "协议:"
      _echo "  vmess-ws | ws          [port] [uuid] [path] [host]"
      _echo "  ss | shadowsocks       [port] [password] [method]"
      _echo "  socks                  [port] [user] [pass]"
      _echo "  http                   [port] [user] [pass]"
      _echo "  reality | vless-reality [port] [uuid] [sni]"
      _echo "  hy2 | hysteria2        [port] [password]"
      _echo "示例: sb add ws auto"
      return 0
      ;;
    ws|vmess|vmess-ws|vmess_ws)
      port="$1"; uuid="$2"; path="$3"; host="$4"
      _is_auto_or_empty "$port" && port=$(_get_port)
      _is_auto_or_empty "$uuid" && uuid=$(_uuid)
      [ "$path" = "auto" ] && path=""
      name="VMess-WS-$port"
      _write_vmess_ws "$name" "$port" "$uuid" "$path" "$host" >/dev/null
      _ok "已添加 $name"
      cmd_info "$name.json"
      if [ -x "$SB_BIN" ]; then cmd_restart; fi
      ;;
    ss|shadowsocks)
      port="$1"; pass="$2"; method="$3"
      _is_auto_or_empty "$port" && port=$(_get_port)
      _is_auto_or_empty "$pass" && pass=$(_uuid)
      _is_auto_or_empty "$method" && method="aes-128-gcm"
      name="Shadowsocks-$port"
      _write_shadowsocks "$name" "$port" "$method" "$pass" >/dev/null
      _ok "已添加 $name"
      cmd_info "$name.json"
      if [ -x "$SB_BIN" ]; then cmd_restart; fi
      ;;
    socks)
      port="$1"; user="$2"; pass="$3"
      _is_auto_or_empty "$port" && port=$(_get_port)
      _is_auto_or_empty "$user" && user="user"
      _is_auto_or_empty "$pass" && pass=$(_uuid)
      name="Socks-$port"
      _write_socks "$name" "$port" "$user" "$pass" >/dev/null
      _ok "已添加 $name"
      cmd_info "$name.json"
      if [ -x "$SB_BIN" ]; then cmd_restart; fi
      ;;
    http|http-proxy|http_proxy)
      port="$1"; user="$2"; pass="$3"
      _is_auto_or_empty "$port" && port=$(_get_port)
      _is_auto_or_empty "$user" && user="user"
      _is_auto_or_empty "$pass" && pass=$(_uuid)
      name="HTTP-$port"
      _write_http "$name" "$port" "$user" "$pass" >/dev/null
      _ok "已添加 $name"
      cmd_info "$name.json"
      if [ -x "$SB_BIN" ]; then cmd_restart; fi
      ;;
    r|reality|vless-reality|vless_reality)
      _check_bin
      port="$1"; uuid="$2"; sni="$3"
      _is_auto_or_empty "$port" && port=$(_get_port)
      _is_auto_or_empty "$uuid" && uuid=$(_uuid)
      _is_auto_or_empty "$sni" && sni="www.microsoft.com"
      kp=$("$SB_BIN" generate reality-keypair 2>/dev/null)
      priv=$(printf '%s\n' "$kp" | sed -n 's/.*[Pp]rivate[Kk]ey: *//p' | head -1 | tr -d ' \r')
      pub=$(printf '%s\n' "$kp" | sed -n 's/.*[Pp]ublic[Kk]ey: *//p' | head -1 | tr -d ' \r')
      # spaced form: "Private key: xxx"
      [ -z "$priv" ] && priv=$(printf '%s\n' "$kp" | grep -i 'private' | head -1 | sed 's/.*: *//' | tr -d ' \r')
      [ -z "$pub" ] && pub=$(printf '%s\n' "$kp" | grep -i 'public' | head -1 | sed 's/.*: *//' | tr -d ' \r')
      if [ -z "$priv" ] || [ -z "$pub" ]; then
        _err "reality-keypair 生成失败 (需要可用 core)"
      fi
      name="VLESS-REALITY-$port"
      _write_vless_reality "$name" "$port" "$uuid" "$sni" "$priv" "$pub" >/dev/null
      printf '%s\n' "$pub" >"$SB_TMP/${name}.pbk"
      _ok "已添加 $name"
      cmd_info "$name.json"
      cmd_restart
      ;;
    hy|hy2|hysteria2|hysteria*)
      port="$1"; pass="$2"
      _is_auto_or_empty "$port" && port=$(_get_port)
      _is_auto_or_empty "$pass" && pass=$(_uuid)
      name="Hysteria2-$port"
      _write_hysteria2 "$name" "$port" "$pass" >/dev/null
      _ok "已添加 $name (自签 TLS, 客户端需 allowInsecure=1)"
      cmd_info "$name.json"
      cmd_restart
      ;;
    *)
      _err "未知协议: $proto  (sb add help)"
      ;;
  esac
}

_pick_conf() {
  # $1 optional name/pattern
  q="$1"
  if [ -n "$q" ]; then
    # exact or fuzzy
    if [ -f "$SB_CONF/$q" ]; then
      _echo "$q"; return
    fi
    if [ -f "$SB_CONF/${q}.json" ]; then
      _echo "${q}.json"; return
    fi
    m=$(ls "$SB_CONF" 2>/dev/null | grep -i "$q" | head -1)
    [ -n "$m" ] && { _echo "$m"; return; }
    _err "找不到配置: $q"
  fi
  # list single auto
  c=$(ls "$SB_CONF"/*.json 2>/dev/null | wc -l | tr -d ' ')
  if [ "$c" = "1" ]; then
    basename $(ls "$SB_CONF"/*.json)
    return
  fi
  if [ "$c" = "0" ] || [ -z "$c" ]; then
    _err "没有配置, 先: sb add ws auto"
  fi
  _echo "可用配置:" >&2
  i=1
  for f in "$SB_CONF"/*.json; do
    [ -f "$f" ] || continue
    _echo "  $i) $(basename "$f")" >&2
    i=$((i + 1))
  done
  _err "请指定配置名: sb info <name>"
}

_json_get() {
  # very small field extractor: _json_get file key
  # works for flat-ish values in our generated files
  f="$1"; key="$2"
  # try grep "key": value
  sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$f" 2>/dev/null | head -1
}

_json_get_num() {
  f="$1"; key="$2"
  sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p" "$f" 2>/dev/null | head -1
}

cmd_info() {
  _ensure_dirs
  conf=$(_pick_conf "$1")
  f="$SB_CONF/$conf"
  [ -f "$f" ] || _err "文件不存在: $f"
  ip=$(_get_ip)
  type=$(_json_get "$f" type)
  [ -z "$type" ] && type=$(grep -o '"type"[[:space:]]*:[[:space:]]*"[^"]*"' "$f" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
  port=$(_json_get_num "$f" listen_port)
  uuid=$(_json_get "$f" uuid)
  password=$(_json_get "$f" password)
  method=$(_json_get "$f" method)
  path=$(_json_get "$f" path)
  host=$(_json_get "$f" Host)
  [ -z "$host" ] && host=$(_json_get "$f" host)
  sni=$(_json_get "$f" server_name)
  user=$(_json_get "$f" username)
  flow=$(_json_get "$f" flow)

  _echo "======== $conf ========"
  _echo "协议:   $type"
  _echo "地址:   $ip"
  _echo "端口:   $port"
  [ -n "$uuid" ] && _echo "UUID:   $uuid"
  [ -n "$password" ] && _echo "密码:   $password"
  [ -n "$method" ] && _echo "加密:   $method"
  [ -n "$path" ] && _echo "路径:   $path"
  [ -n "$host" ] && _echo "Host:   $host"
  [ -n "$sni" ] && _echo "SNI:    $sni"
  [ -n "$user" ] && _echo "用户:   $user"
  [ -n "$flow" ] && _echo "Flow:   $flow"

  # reality public key from sidecar or outbounds tag
  pbk=""
  side="$SB_TMP/${conf%.json}.pbk"
  [ -f "$side" ] && pbk=$(cat "$side")
  if [ -z "$pbk" ]; then
    pbk=$(grep -o 'public_key_[^"]*' "$f" 2>/dev/null | head -1 | sed 's/public_key_//')
  fi
  [ -n "$pbk" ] && _echo "公钥:   $pbk"

  url=$(cmd_url "$conf" 2>/dev/null)
  [ -n "$url" ] && _echo "链接:   $url"
  _echo "文件:   $f"
}

cmd_url() {
  _ensure_dirs
  conf=$(_pick_conf "$1")
  f="$SB_CONF/$conf"
  ip=$(_get_ip)
  type=$(_json_get "$f" type)
  [ -z "$type" ] && type=$(grep -o '"type"[[:space:]]*:[[:space:]]*"[^"]*"' "$f" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
  port=$(_json_get_num "$f" listen_port)
  uuid=$(_json_get "$f" uuid)
  password=$(_json_get "$f" password)
  method=$(_json_get "$f" method)
  path=$(_json_get "$f" path)
  host=$(_json_get "$f" Host)
  [ -z "$host" ] && host=$(_json_get "$f" host)
  sni=$(_json_get "$f" server_name)
  user=$(_json_get "$f" username)
  flow=$(_json_get "$f" flow)
  pbk=""
  side="$SB_TMP/${conf%.json}.pbk"
  [ -f "$side" ] && pbk=$(cat "$side")
  [ -z "$pbk" ] && pbk=$(grep -o 'public_key_[^"]*' "$f" 2>/dev/null | head -1 | sed 's/public_key_//')

  case "$type" in
    vmess)
      [ -z "$path" ] && path="/"
      [ -z "$host" ] && host=""
      # vmess share json
      ps="android-ws-$port"
      raw=$(printf '{"v":"2","ps":"%s","add":"%s","port":"%s","id":"%s","aid":"0","net":"ws","type":"none","host":"%s","path":"%s","tls":""}' \
        "$ps" "$ip" "$port" "$uuid" "$host" "$path")
      enc=$(printf '%s' "$raw" | _b64)
      _echo "vmess://$enc"
      ;;
    shadowsocks)
      userinfo=$(printf '%s:%s' "$method" "$password" | _b64)
      _echo "ss://${userinfo}@${ip}:${port}#android-ss-${port}"
      ;;
    socks)
      _echo "socks://$user:$password@$ip:$port#android-socks-$port"
      ;;
    http)
      _echo "http://$user:$password@$ip:$port#android-http-$port"
      ;;
    vless)
      # reality
      _echo "vless://${uuid}@${ip}:${port}?encryption=none&security=reality&flow=${flow}&type=tcp&sni=${sni}&pbk=${pbk}&fp=chrome#android-reality-${port}"
      ;;
    hysteria2)
      _echo "hysteria2://${password}@${ip}:${port}?alpn=h3&insecure=1#android-hy2-${port}"
      ;;
    *)
      _warn "该协议暂不生成 URL: $type"
      ;;
  esac
}

cmd_del() {
  conf=$(_pick_conf "$1")
  rm -f "$SB_CONF/$conf"
  rm -f "$SB_TMP/${conf%.json}.pbk"
  _ok "已删除 $conf"
  if _is_running; then
    cmd_restart
  fi
}

cmd_list() {
  _ensure_dirs
  found=0
  for f in "$SB_CONF"/*.json; do
    [ -f "$f" ] || continue
    basename "$f"
    found=1
  done
  if [ "$found" = "0" ]; then
    _warn "暂无配置"
    return 1
  fi
}

cmd_set_ip() {
  ip="$1"
  if [ -z "$ip" ] || [ "$ip" = "auto" ]; then
    unset SB_IP
    rm -f "$SB_HOME/ip.txt"
    ip=$(_get_ip)
    _ok "自动 IP: $ip"
    return
  fi
  if ! _is_ipv4 "$ip"; then
    _err "无效 IPv4: $ip"
  fi
  printf '%s\n' "$ip" >"$SB_HOME/ip.txt"
  _ok "已保存分享 IP: $ip  (文件: $SB_HOME/ip.txt)"
  _info "仅影响 info/url 显示，不改变监听地址"
}

# rewrite listen to 0.0.0.0 for old confs that used ::
cmd_fix_listen() {
  _ensure_dirs
  n=0
  for f in "$SB_CONF"/*.json; do
    [ -f "$f" ] || continue
    if grep -q '"listen"[[:space:]]*:[[:space:]]*"::"' "$f" 2>/dev/null; then
      sed 's/"listen"[[:space:]]*:[[:space:]]*"::"/"listen": "0.0.0.0"/g' "$f" >"$f.tmp" && mv -f "$f.tmp" "$f"
      n=$((n + 1))
      _ok "已修复 listen: $(basename "$f")"
    fi
  done
  if [ "$n" = "0" ]; then
    _info "没有需要修复 listen 的配置"
  else
    _info "已修复 $n 个文件，正在重启..."
    if [ -x "$SB_BIN" ]; then cmd_restart; fi
  fi
}

cmd_log() {
  f="$SB_LOG/access.log"
  [ -f "$SB_LOG/stdout.log" ] && f="$SB_LOG/stdout.log"
  if [ -f "$f" ]; then
    if command -v tail >/dev/null 2>&1; then
      tail -n 80 "$f"
    else
      cat "$f"
    fi
  else
    _warn "暂无日志"
  fi
}

cmd_test() {
  _check_bin
  _ensure_base_config
  _info "正在检查配置..."
  "$SB_BIN" check -c "$SB_CFG" -C "$SB_CONF"
}

cmd_gen_tls() {
  _check_bin
  _ensure_tls
  _ok "TLS: $SB_HOME/bin/tls.cer / tls.key"
}

cmd_help() {
  cat <<EOF
sing-box Android 服务端 $SCRIPT_VER
目录: $SB_HOME
Core: $SB_BIN
      (正式 zip 已内置 GitHub 官方 binary；安装时拷贝到此路径)

推荐: 交互菜单
  sh $SB_HOME/menu.sh

用法: sh $SB_HOME/sb.sh <命令> [参数]
  (不提供系统 PATH 命令 sb)

管理:
  start | stop | restart | status
  log | test | list
  独立脚本: start.sh / stop.sh / restart.sh

配置:
  add <protocol> [args|auto]   添加入站
  info [name]                  查看配置
  url  [name]                  分享链接
  del  [name]                  删除配置

协议 (Android 精简版, 无 Caddy/域名 TLS):
  ws / vmess-ws     VMess + WebSocket   ★默认推荐
  ss                Shadowsocks
  socks             SOCKS5
  http              HTTP 代理
  reality           VLESS-REALITY (无需域名证书)
  hy2               Hysteria2 (自签证书, insecure)

其它:
  set-ip <ipv4|auto>   设置分享链接里的地址 (写到 ip.txt)
  fix-listen           把旧配置 listen :: 改成 0.0.0.0

示例:
  sh $SB_HOME/menu.sh
  sh $SB_HOME/sb.sh add ws auto
  sh $SB_HOME/sb.sh add http auto
  sh $SB_HOME/sb.sh set-ip 192.168.1.20
  sh $SB_HOME/sb.sh fix-listen
  sh $SB_HOME/sb.sh info
  sh $SB_HOME/start.sh
EOF
}


main() {
  _ensure_dirs
  cmd="$1"
  [ -n "$cmd" ] && shift
  case "$cmd" in
    start) cmd_start "$@" ;;
    stop) cmd_stop "$@" ;;
    restart|r) cmd_restart "$@" ;;
    status|s) cmd_status "$@" ;;
    add|a) cmd_add "$@" ;;
    info|i) cmd_info "$@" ;;
    url) cmd_url "$@" ;;
    del|d|rm) cmd_del "$@" ;;
    list|ls) cmd_list "$@" ;;
    log) cmd_log "$@" ;;
    test|t) cmd_test "$@" ;;
    gen-tls) cmd_gen_tls "$@" ;;
    set-ip|ip) cmd_set_ip "$@" ;;
    fix-listen) cmd_fix_listen "$@" ;;
    help|h|-h|--help|"") cmd_help ;;
    *)
      _warn "未知命令: $cmd"
      cmd_help
      exit 1
      ;;
  esac
}

main "$@"
