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
- 常用入口：`action.sh`（切换 bypass）、`scripts/config.prop`（`bypass` / `redir_port` / `upstream_uid` + `upstream_gid` / `PROXY_URL`）

## 技术栈
- Android `sh` 是 **mksh**：支持数组、`<<<`、`<(...)`；**dash 不支持**，所以 `sh -n` 校验会误报，请用 `bash -n`
- `iptables` / `ip6tables`、`settings put`、`am broadcast`；上游豁免依赖 `xt_owner`（`-m owner`），部分内核不带该模块，脚本会自动降级并在 `agh.log` 留痕
- `bin/AdGuardHome.yaml`：AGH 配置，上游为本地 smartdns `127.0.0.1:1451`

## 目录与约定
- `Adguardhome/scripts/*.sh` 全部会被 `chattr +i` 锁定；改动后调试前先 `chattr -i`
- **行尾：仓库内统一 LF**（`core.autocrlf=true`，工作区显示 CRLF 属正常，不要"修正"成 CRLF）
- **shell 脚本只能用 mksh 兼容语法**（设备 `/system/bin/sh` 是 mksh）：禁止 `< <(...)` 进程替换、`local` 出现在函数外、`f(){...}` 紧凑函数写法（mksh 会把 `{` 当命令）。校验一律用 `mksh -n`
- 规则写入用 `-A` 追加，清理必须循环删到不存在；单条 `-D` 会残留
- `fallback_dns` 目前配的是 443 DoH；本机已不再拦 853，`tls://…:853` 这类 DoT 上游现在也能用（此前禁用是因为模块自己 DROP 出向 853，会把自己打死）
- IPv4 与 IPv6 各有一条 nat `ADGUARD` 链（同名、分属不同表），链首都用 `-I ADGUARD 1 -m owner --uid-owner .. --gid-owner .. -j RETURN` 豁免本机上游解析器，必须排在 REDIRECT 之前；删掉它会与解析器形成解析回环
- 豁免只允许 uid+gid 组合这种窄匹配，不要放宽成单 gid 或任意 root，否则等于放弃过滤
- IPv6 的 53 改成重定向后，AGH 必须监听 `::1`（`bin/AdGuardHome.yaml` 的 `dns.bind_hosts`），否则查询被弹到 ::1 却无人应答
- 853（DoT/DoQ）不再下任何规则：重定向过来的 DoT 过不了 TLS 证书校验，整条 DROP 又会让不回退的客户端表现为没网。内置 DoT 的 App 因此可以绕过 AGH，系统级私人 DNS 由脚本强制关闭来兜底
- 内核没有 IPv6 nat 表时（HyperOS 实测如此）v6 无法重定向：必须退回 filter 链 `AGUARD6` 拦掉本机出向 53（链内先 `-m owner` 放行解析器，再 DROP），绝不允许"既不重定向也不拦截"——那样 IPv6 DNS 会整块绕过 AGH，表现为解析量骤降、过滤失效
- `owner` 匹配只比对进程主组，App 的 3004（aid_inet）属附加组，因此豁免不会削弱对 App 的劫持与过滤
- 端口分工：WebUI 固定 `3000`；DNS 重定向端口每次冷启动随机化并写回 `config.prop`
- `bin/AdGuardHome` 是上游魔改核心，不入库（`.gitignore`），发版前需从 `liuzq2002/AdguardHome-Mod` release 取 `linux_arm64` 包

## 当前状态（2026-10-12）
- `bypass` 直通模式已落地（撤销 IPv4/IPv6 的 53 重定向 + 停止强制关私人 DNS），供必须使用指定 DNS 的 WiFi 使用
- `action.sh` 已由"打开 WebUI"改为"切换 bypass"，打开 Web UI 需手动访问 `127.0.0.1:3000`
- 上游解析器回环已修复：按 `upstream_uid`/`upstream_gid`（默认 `0`/`3004`，即 SmartDNS 模块 `chpst -u 0:3004` 的启动身份）在 v4/v6 两条 ADGUARD 链首放行，smartdns 的 `-b`/`-fallback` 明文上游不再被弹回 AGH
- 拦截策略调整：853 完全放行（原先整条 DROP 会把不回退的客户端闷死），IPv6 的 53 由 DROP 改为重定向，AGH 随之监听 `::1`
- 20261012 修掉上述改动的副作用：设备内核没有 IPv6 nat 表时 v6 重定向建不上，曾导致 IPv6 DNS 既不劫持也不拦截、整块绕过 AGH（用户实测解析量骤降）。现在这种情况退回 filter 链 `AGUARD6` 拦截 v6:53，链内保留解析器豁免

## 待办
- 仓库不含 `AdGuardHome` 二进制（`bin/` 下只有 yaml 与过滤列表缓存），打包需从`liuzq2002/AdguardHome-Mod` 取 arm64 魔改核心
- 模块脚本尚未适配魔改核心的 NFQUEUE 规则接口（`AGH_SNI` 链 + `sni_filter` 配置段），SNI 阻断与强力模式目前不生效
- `block_active` 仍是"任一命中即视为劫持中"的或语义：判定已收敛到 v4/v6 的 53 重定向（旧版 DROP 残留不再参与），但若其他模块只清空 v4 链而 v6 链还在，守护循环依旧不重建，IPv4 侧会静默失去劫持。可改成逐条要求（未验证，待定）