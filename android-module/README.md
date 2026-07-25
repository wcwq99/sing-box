# sing-box Android Server Module

面向 **Android 6+** 的轻量代理 **服务端** Magisk 模块（也可纯 root 手动部署）。

## 原项目 / Credits

本模块是 **[233boy/sing-box](https://github.com/233boy/sing-box)** 一键脚本思路在 Android 上的精简移植：

| 项目 | 链接 | 说明 |
|------|------|------|
| **原脚本项目** | https://github.com/233boy/sing-box | 菜单 / 多 conf / `add·info·url` 设计参考来源 |
| **原作者文档** | https://233boy.com/sing-box/sing-box-script/ | 上游使用文档 |
| **Core 上游** | https://github.com/SagerNet/sing-box | 打包时下载官方 `android-arm64` / `android-arm` binary |

> 脚本逻辑已针对 Android Magisk / `/system/bin/sh` **重写**，不是原版 Linux 脚本直接拷贝。  
> 请尊重上游：[233boy/sing-box](https://github.com/233boy/sing-box)（GPL-3.0）、[SagerNet/sing-box](https://github.com/SagerNet/sing-box)。

## Core 从哪来？

| 阶段 | 行为 |
|------|------|
| **打包时（电脑/CI）** | 从 GitHub `SagerNet/sing-box` Release 下载官方 **`android-arm64` / `android-arm`**（bionic） |
| **zip 内** | 已带上 `sb/bin/sing-box`（**随包分发**） |
| **手机安装时** | 只拷贝包内二进制到 `/data/adb/sing-box/bin/sing-box`，**不联网下载** |

> ⚠️ **必须用 `android-*` 资源**。`linux-arm64` / `linux-armv7` 依赖 glibc（`/lib/ld-linux-aarch64.so.1`），在 Android 上会直接报 `No such file or directory`，无法启动。

产物：

- `dist/sing-box-android-arm64.zip` ← **64 位**，GitHub `android-arm64`
- `dist/sing-box-android-armv7a.zip` ← **32 位**，GitHub `android-arm`

```bash
# Linux / macOS / Git Bash
cd android-module
./build-release.sh              # 拉 latest core
./build-release.sh v1.12.0      # 钉死 core 版本

# Windows PowerShell
.\build-release.ps1
.\build-release.ps1 -CoreVer v1.12.0
```

> 源码树里的 `pack.ps1` / `pack.sh` 只打**无 core** 脚本包（调试用）。正式发布请用 `build-release.*`。

## 设计取舍

| 保留 | 删除 |
|------|------|
| 固定目录 `/data/adb/sing-box` | systemd / OpenRC |
| 正式 zip **内置** GitHub core | Caddy / 自动 TLS / 伪装站 |
| `add / info / url / start / stop / restart / status` | BBR |
| **VMess-WS**（必保） | 所有域名证书 `*-TLS` 链路 |
| SS / SOCKS / HTTP / VLESS-REALITY | import / 复杂 change full |
| 可选 HY2（自签 + insecure） | TUIC / 脚本自更新整套 |

## 目录结构

```
/data/adb/sing-box/
  bin/sing-box      # 安装时从 zip 拷入（GitHub 官方构建）
  bin/tls.cer|key   # HY2 自签（首次 add 时自动生成）
  conf/*.json       # 各入站配置（-C 加载）
  config.json       # 主配置 log/dns/outbounds
  log/              # 日志
  tmp/              # pid / pbk 缓存
  sb.sh             # 管理脚本
  menu.sh           # 交互菜单
  start.sh          # 启动
  stop.sh           # 暂停/停止
  restart.sh        # 重启
  core.version      # 打包时写入的 core 来源信息
```

## 安装

### 方式 A：Magisk 刷入（推荐）

1. 电脑执行 `./build-release.sh` / `.\build-release.ps1` 得到两个 zip  
2. 按 CPU 选包：`arm64`（**64 位**）或 `armv7a`（**32 位**）  
3. Magisk → 模块 → 从本地安装 → 重启  
4. 无需再 push core，直接：

```bash
sh /data/adb/sing-box/menu.sh
# 或
sh /data/adb/sing-box/start.sh
```

> **只装一个 ABI 包**（64 或 32，二选一）。两个 zip 的 Magisk `id` 相同（`sing-box-server`），后装会覆盖前装；若面具里仍见两个，卸载旧模块或重装即可。

### 方式 B：无 Magisk，纯 root

```bash
su
mkdir -p /data/adb/sing-box/{bin,conf,log,tmp}
# 解压对应 abi zip，把 sb/* 和 sb/bin/sing-box 拷入
chmod 755 /data/adb/sing-box/*.sh /data/adb/sing-box/bin/sing-box
sh /data/adb/sing-box/menu.sh
```

## 使用

### 交互菜单（推荐，风格参考源项目主菜单）

```bash
sh /data/adb/sing-box/menu.sh
```

菜单项：添加配置 / 查看配置与链接 / 删除 / 启动停止重启 / 日志 / 测试 / 列表 / 帮助

协议（添加菜单）：VMess-WS / Shadowsocks / SOCKS5 / **HTTP** / VLESS-REALITY / Hysteria2

### 命令行

```bash
H=/data/adb/sing-box
sh $H/sb.sh add ws auto          # VMess + WebSocket（推荐）
sh $H/sb.sh add ss auto
sh $H/sb.sh add http auto
sh $H/sb.sh add reality auto
sh $H/sb.sh info
sh $H/sb.sh url
sh $H/sb.sh status
sh $H/sb.sh log
```

### 启动 / 暂停 / 重启

```bash
sh /data/adb/sing-box/start.sh
sh /data/adb/sing-box/stop.sh
sh /data/adb/sing-box/restart.sh
```

> **不提供** 系统 PATH 命令 `sb` / `sb-start` 等。

开机自启由模块 `service.sh` 处理（检测到 binary 才启动）。

## Core 选择注意

- 正式包内 core = GitHub 官方 **`android-arm64`**（64 位包）/ **`android-arm`**（32 位包），打包时下载并打进 zip
- 若错误刷入了 `linux-*` core，执行会报 `No such file or directory`（缺 glibc loader），用正确 android core 覆盖：
  `/data/adb/sing-box/bin/sing-box`
- `sb.sh` / `menu.sh` 只做配置与进程管理，不绑死某一 core 小版本  
- 建议 core ≥ 1.8（REALITY / HY2 等按 core 能力启用）

## 网络与权限

- 服务端监听 `::`（IPv4/IPv6），请在路由器/热点侧做好端口转发或公网映射  
- 部分 ROM 需关闭省电限制 / 允许后台  
- 不依赖 iptables/TProxy；本模块只做 **入站代理服务端**，不是本地 VPN 客户端  

## 明确不做的事

- 不装 Caddy、不申请 Let’s Encrypt  
- 不启用 BBR、不改系统内核参数  
- 不提供 VMess-WS-TLS / VLESS-WS-TLS 等域名证书协议  
- **手机端安装过程不下载 core**（core 只在打包机/CI 从 GitHub 拉取）

## 与原版 233boy 脚本关系

逻辑参考 [233boy/sing-box](https://github.com/233boy/sing-box) 的 `add / info / url` 与多 conf 目录设计，但实现重写为：

- `/system/bin/sh` 可运行（避免 bash 数组 / systemctl）
- 无 jq 依赖（生成模板 + 简易字段解析）
- 固定 Android 路径与 pid 守护
- **不做** 原版的 Caddy / 自动 TLS / 域名证书协议 / BBR / 系统 PATH 命令

## License

- 本目录脚本随仓库协议（上游 [233boy/sing-box](https://github.com/233boy/sing-box) 为 **GPL-3.0**）
- 内置 / 下载的 core 遵循 [SagerNet/sing-box](https://github.com/SagerNet/sing-box) 自身许可证
