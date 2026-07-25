#!/system/bin/sh
# 交互菜单（参考 233boy/sing-box 主菜单风格）
# 用法: sh /data/adb/sing-box/menu.sh

SB_HOME="${SB_HOME:-/data/adb/sing-box}"
SB_SH="$SB_HOME/sb.sh"
SCRIPT_VER="v1.0.2-android"

# 优先本机路径
if [ ! -f "$SB_SH" ]; then
  HERE=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
  [ -f "$HERE/sb.sh" ] && SB_SH="$HERE/sb.sh" && SB_HOME="$HERE"
fi

_echo() { printf '%s\n' "$*"; }
_err() { _echo "[ERR] $*" >&2; }
_green() { printf '\033[92m%s\033[0m\n' "$*"; }
_yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
_red() { printf '\033[31m%s\033[0m\n' "$*"; }

_run() {
  if [ -f "$SB_SH" ]; then
    /system/bin/sh "$SB_SH" "$@"
  else
    _err "找不到 sb.sh: $SB_SH"
    return 1
  fi
}

_pause() {
  _echo
  printf '按 Enter 返回菜单, 或 Ctrl+C 退出...'
  # shellcheck disable=SC2034
  read _line
  _echo
}

_status_line() {
  if [ -x "$SB_HOME/bin/sing-box" ]; then
    ver=$("$SB_HOME/bin/sing-box" version 2>/dev/null | head -1)
    [ -z "$ver" ] && ver="sing-box installed"
  else
    ver="core missing"
  fi
  pid=""
  [ -f "$SB_HOME/tmp/sing-box.pid" ] && pid=$(cat "$SB_HOME/tmp/sing-box.pid" 2>/dev/null)
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    st="running (pid=$pid)"
  else
    st="stopped"
  fi
  n=$(ls "$SB_HOME/conf"/*.json 2>/dev/null | wc -l | tr -d ' ')
  [ -z "$n" ] && n=0
  _echo "core: $ver"
  _echo "状态: $st"
  _echo "配置: ${n} 个"
  _echo "目录: $SB_HOME"
}

_menu_add() {
  _echo
  _echo "请选择协议:"
  _echo "  1) VMess-WS          ★推荐"
  _echo "  2) Shadowsocks"
  _echo "  3) SOCKS5"
  _echo "  4) HTTP"
  _echo "  5) VLESS-REALITY"
  _echo "  6) Hysteria2        (自签/insecure)"
  _echo "  0) 返回"
  printf '请选择 [0-6]: '
  read p
  case "$p" in
    1)
      printf '端口 (回车=auto): '; read port
      [ -z "$port" ] && port=auto
      _run add ws "$port" auto
      ;;
    2)
      printf '端口 (回车=auto): '; read port
      [ -z "$port" ] && port=auto
      _run add ss "$port" auto
      ;;
    3)
      printf '端口 (回车=auto): '; read port
      [ -z "$port" ] && port=auto
      _run add socks "$port" auto
      ;;
    4)
      printf '端口 (回车=auto): '; read port
      [ -z "$port" ] && port=auto
      _run add http "$port" auto
      ;;
    5)
      printf '端口 (回车=auto): '; read port
      [ -z "$port" ] && port=auto
      _run add reality "$port" auto
      ;;
    6)
      printf '端口 (回车=auto): '; read port
      [ -z "$port" ] && port=auto
      _run add hy2 "$port" auto
      ;;
    0|"") return ;;
    *) _err "无效选择" ;;
  esac
}

_menu_manage() {
  _echo
  _echo "运行管理:"
  _echo "  1) 启动"
  _echo "  2) 停止"
  _echo "  3) 重启"
  _echo "  4) 状态"
  _echo "  0) 返回"
  printf '请选择 [0-4]: '
  read m
  case "$m" in
    1) [ -f "$SB_HOME/start.sh" ] && /system/bin/sh "$SB_HOME/start.sh" || _run start ;;
    2) [ -f "$SB_HOME/stop.sh" ] && /system/bin/sh "$SB_HOME/stop.sh" || _run stop ;;
    3) [ -f "$SB_HOME/restart.sh" ] && /system/bin/sh "$SB_HOME/restart.sh" || _run restart ;;
    4) _run status ;;
    0|"") return ;;
    *) _err "无效选择" ;;
  esac
}

_menu_info() {
  _echo
  _run list
  _echo
  printf '输入配置名 (回车=自动/唯一项): '
  read name
  if [ -n "$name" ]; then
    _run info "$name"
    _echo
    _run url "$name"
  else
    _run info
    _echo
    _run url
  fi
}

_menu_del() {
  _echo
  _run list
  _echo
  printf '输入要删除的配置名: '
  read name
  [ -z "$name" ] && { _err "未输入名称"; return; }
  printf '确认删除 %s ? 输入 y: ' "$name"
  read y
  case "$y" in
    y|Y|yes|YES) _run del "$name" ;;
    *) _echo "已取消" ;;
  esac
}

_menu_help() {
  cat <<EOF

------------- 帮助 -------------
固定目录: $SB_HOME
管理脚本: $SB_SH
菜单脚本: $SB_HOME/menu.sh

常用直接命令 (无需菜单):
  sh $SB_HOME/menu.sh
  sh $SB_HOME/start.sh
  sh $SB_HOME/stop.sh
  sh $SB_HOME/restart.sh
  sh $SB_SH add ws auto
  sh $SB_SH add http auto
  sh $SB_SH info
  sh $SB_SH url
  sh $SB_SH list
  sh $SB_SH del <name>
  sh $SB_SH status
  sh $SB_SH log

协议说明:
  VMess-WS     无域名证书, Android 推荐
  HTTP/SOCKS   基础代理
  REALITY      无需域名证书
  HY2          自签证书, 客户端需 insecure

注意:
  - 不提供 Caddy / 自动 TLS / 伪装站
  - 不提供系统 PATH 命令 sb
  - 面具模块 id 固定为 sing-box-server (arm64/armv7a 二选一)

EOF
}

# -------- main loop --------
while :; do
  _echo
  _echo "------------- sing-box Android $SCRIPT_VER -------------"
  _status_line
  _echo "-----------------------------------------------"
  _echo "  1) 添加配置"
  _echo "  2) 查看配置 / 分享链接"
  _echo "  3) 删除配置"
  _echo "  4) 运行管理 (启动/停止/重启)"
  _echo "  5) 查看日志"
  _echo "  6) 测试配置"
  _echo "  7) 列出配置"
  _echo "  8) 帮助"
  _echo "  0) 退出"
  _echo "-----------------------------------------------"
  printf '请选择 [0-8]: '
  read choice
  case "$choice" in
    1) _menu_add; _pause ;;
    2) _menu_info; _pause ;;
    3) _menu_del; _pause ;;
    4) _menu_manage; _pause ;;
    5) _run log; _pause ;;
    6) _run test; _pause ;;
    7) _run list; _pause ;;
    8) _menu_help; _pause ;;
    0|q|Q|"") _echo "bye"; exit 0 ;;
    *) _err "无效选择: $choice"; _pause ;;
  esac
done
