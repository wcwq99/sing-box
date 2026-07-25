#!/system/bin/sh
# Magisk module install hook
# Core binary is BUNDLED in zip (downloaded from GitHub at pack time).
# Install copies it to /data/adb/sing-box/bin/sing-box — no network on device.

SKIPUNZIP=0

ui_print "- 正在安装 sing-box Android 服务端模块"
ui_print "- 模块 id: sing-box-server (arm64/armv7a 共用, 只装一个)"
ui_print "- 固定目录: /data/adb/sing-box"

mkdir -p /data/adb/sing-box/bin \
  /data/adb/sing-box/conf \
  /data/adb/sing-box/log \
  /data/adb/sing-box/tmp

# 清理历史重复模块目录 (曾误装双包 / 不同 id 导致面具显示两个)
for d in \
  /data/adb/modules/sing-box-server-armv8a \
  /data/adb/modules/sing-box-server-v7a \
  /data/adb/modules/sing-box-server-arm64 \
  /data/adb/modules/sing-box-server-armv7a \
  /data/adb/modules/sing-box-android \
  /data/adb/modules/sing-box-android-server \
  /data/adb/modules_update/sing-box-server-armv8a \
  /data/adb/modules_update/sing-box-server-v7a \
  /data/adb/modules_update/sing-box-server-arm64 \
  /data/adb/modules_update/sing-box-server-armv7a
do
  if [ -d "$d" ]; then
    ui_print "- 清理旧模块目录: $d"
    rm -rf "$d"
  fi
done

# 删除旧版注入的 PATH 命令 sb / sb-*
for f in sb sb-start sb-stop sb-restart; do
  rm -f "$MODPATH/system/bin/$f" 2>/dev/null
  rm -f /data/adb/modules/sing-box-server/system/bin/$f 2>/dev/null
done
rm -rf "$MODPATH/system" 2>/dev/null

# management scripts (ASCII names only)
for f in sb.sh start.sh stop.sh restart.sh menu.sh; do
  if [ -f "$MODPATH/sb/$f" ]; then
    cp -f "$MODPATH/sb/$f" /data/adb/sing-box/$f
    chmod 755 /data/adb/sing-box/$f
  fi
done
# strip Windows CRLF if any (prevents: syntax error: 'in / : not found)
for f in /data/adb/sing-box/*.sh; do
  [ -f "$f" ] || continue
  if grep -q $'\r' "$f" 2>/dev/null; then
    tr -d '\r' <"$f" >"$f.lf" && mv -f "$f.lf" "$f"
    chmod 755 "$f"
  fi
done
# remove legacy Chinese menu alias
rm -f /data/adb/sing-box/菜单.sh 2>/dev/null
chmod 755 "$MODPATH/service.sh" 2>/dev/null

# bundled core
CORE_SRC=""
if [ -f "$MODPATH/sb/bin/sing-box" ]; then
  CORE_SRC="$MODPATH/sb/bin/sing-box"
elif [ -f "$MODPATH/bin/sing-box" ]; then
  CORE_SRC="$MODPATH/bin/sing-box"
fi

if [ -n "$CORE_SRC" ]; then
  cp -f "$CORE_SRC" /data/adb/sing-box/bin/sing-box
  chmod 755 /data/adb/sing-box/bin/sing-box
  ui_print "- 已安装 core: /data/adb/sing-box/bin/sing-box"
  if [ -f "$MODPATH/sb/core.version" ]; then
    cp -f "$MODPATH/sb/core.version" /data/adb/sing-box/core.version
    ui_print "- $(head -n 3 /data/adb/sing-box/core.version | tr '\n' ' ')"
  fi
else
  ui_print "- [WARN] zip 未内置 core"
  ui_print "- 请手动放置: /data/adb/sing-box/bin/sing-box"
fi

if [ ! -f /data/adb/sing-box/config.json ]; then
  cat >/data/adb/sing-box/config.json <<'EOF'
{
  "log": {
    "level": "info",
    "timestamp": true,
    "output": "/data/adb/sing-box/log/access.log"
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
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "default_domain_resolver": "dns-google"
  }
}
EOF
fi

ui_print "- 安装完成"
ui_print "- 菜单: sh /data/adb/sing-box/menu.sh"
ui_print "- 启动: sh /data/adb/sing-box/start.sh"
