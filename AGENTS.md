# AGENTS.md

## 定位
Magisk / KernelSU 模块：把本机 DNS 流量用 iptables 重定向到 AdGuardHome 做广告过滤与防 DNS 劫持，附带 App 广告目录锁定清理、代理模块 DNS 兼容、WebUI 上游转发。

## 运行方式
- 无构建、无测试、无包管理器：纯 shell 脚本 + 一份 AGH YAML 配置
- **打包必须用 `python tools/pack_module.py`**（Windows 或 WSL 均可，WSL 下会额外跑 mksh 校验）
  - 不要用 PowerShell 的 `Compress-Archive`：它不转 LF、不写 Unix 权限位、也不做校验
  - 脚本会自动完成：文本文件转 LF → 写入 0755 权限 → 打包 → CRC/条目/行尾/mksh 语法/二进制 SHA256 校验
  - 在 WSL 内运行可获得完整 mksh 语法校验（`sh -n` 会误报，bash 通过也不代表设备能跑）
- 设备路径：脚本 `/data/adb/agh/scripts/`、配置 `/data/adb/agh/bin/AdGuardHome.yaml`、日志 `/data/adb/agh/agh.log`
- 常用入口：`action.sh`（切换 bypass）、`scripts/config.prop`（`bypass` / `redir_port` / `PROXY_URL`）

## 技术栈
- Android `sh` 是 **mksh**：支持数组、`<<<`、`<(...)`；**dash 不支持**，所以 `sh -n` 校验会误报，请用 `bash -n`
- `iptables` / `ip6tables`、`settings put`、`am broadcast`
- `bin/AdGuardHome.yaml`：AGH 配置，上游为本地 smartdns `127.0.0.1:1451`

## 目录与约定
- `Adguardhome/scripts/*.sh` 全部会被 `chattr +i` 锁定；改动后调试前先 `chattr -i`
- **行尾：仓库内统一 LF**（`core.autocrlf=true`，工作区显示 CRLF 属正常，不要"修正"成 CRLF）
- **shell 脚本只能用 mksh 兼容语法**（设备 `/system/bin/sh` 是 mksh）：禁止 `< <(...)` 进程替换、`local` 出现在函数外、`f(){...}` 紧凑函数写法（mksh 会把 `{` 当命令）。校验一律用 `mksh -n`
- 规则写入用 `-A` 追加，清理必须循环删到不存在；单条 `-D` 会残留
- `fallback_dns` **只能用 443 DoH**，不能加 `tls://…:853`：模块自己 DROP 出向 853，会把自己打死
- 端口分工：WebUI 固定 `3000`；DNS 重定向端口每次冷启动随机化并写回 `config.prop`
- `bin/AdGuardHome` 是上游魔改核心，不入库（`.gitignore`），发版前需从 `liuzq2002/AdguardHome-Mod` release 取 `linux_arm64` 包

## 当前状态（2026-10-06）
- `bypass` 直通模式已落地（撤销 53 重定向与 853 拦截 + 停止强制关私人 DNS），供必须使用指定 DNS 的 WiFi 使用
- `action.sh` 已由"打开 WebUI"改为"切换 bypass"，打开 Web UI 需手动访问 `127.0.0.1:3000`

## 待办
- 仓库不含 `AdGuardHome` 二进制（`bin/` 下只有 yaml 与过滤列表缓存），打包需从`liuzq2002/AdguardHome-Mod` 取 arm64 魔改核心
- 模块脚本尚未适配魔改核心的 NFQUEUE 规则接口（`AGH_SNI` 链 + `sni_filter` 配置段），SNI 阻断与强力模式目前不生效