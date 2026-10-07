# Adguard Home For Android
<a href="https://deepwiki.com/liuzq2002/Adguard-Home-For-Magisk-Mod"><img src="https://deepwiki.com/badge.svg" alt="Ask DeepWiki"></a>

 **简体中文** | [English](README.en.md)
- 通过重定向过滤 DNS 请求实现去广告，并带有模块系统的 Root 管理器通用
- 本项目自己定制了一个魔改核心，现在已开源并可以点此链接进行访问[点击跳转](https://github.com/liuzq2002/AdguardHome-Mod)
- 本项目永久开源免费无捐赠及其变种，不以是否捐赠来区分版本
- 达到了开箱即用的易用性、操作失误自动恢复，刷入模块后按照教程稍微排查一下即可使用（无需配置规则）
- 内置了GOODBYEADS的拦截规则并在此基础上增加了自定义规则
- 改包与Hosts共存或者去掉其他限制造成的问题别来找我（因为都是为了确保模块能够正常运行所设下的限制，去掉限制代表你能够自行解决问题那不要来找我）
- 本项目旨在取代传统Hosts以带来更好的现代化体验——“零”广告侧漏、高性能、强隐蔽性
- 发布了独立的管理器应用，需要的可以下载[点击跳转](https://github.com/liuzq2002/adguard-home-manager-mod)
- 已经兼容了Box、Clash代理模块，其余的暂不兼容
- 不看教程不要来找我反馈，点此链接直接跳转到教程：[点击跳转](https://github.com/liuzq2002/Adguard-Home-For-Magisk-Mod/tree/main?tab=readme-ov-file#-%E6%95%99%E7%A8%8B%E4%B8%8D%E7%9C%8B%E7%9A%84%E8%AF%9D%E5%87%BA%E4%BA%8B%E5%88%AB%E5%88%B0%E5%A4%84%E6%89%BE%E6%88%91%E9%97%AE%E9%A2%98)

## 模块架构设计图
```mermaid
graph TD
    subgraph 独立管理器[独立管理器 - adguard-home-manager-mod]
        M1[Flutter 应用<br>arm64-v8a] --> M2[自动读取 YAML<br>获取 WebUI 端口 3000]
        M2 --> M3[使用 root/root 凭证<br>连接 AGH API]
        M3 --> M4[首页：全部保护开关<br>暂停时长选择]
        M3 --> M5[日志·统计·DNS配置]
        M3 --> M6[订阅链接 PROXY_URL<br>写入 config.prop]
        M1 --> M7[通知栏快捷磁贴开关]
        M1 --> M8[开机自启动 MainActivity]
    end

    subgraph 安装流程[安装流程 - customize.sh]
        I1[开始安装] --> I2[检测Hosts模块冲突]
        I2 --> I3[停止旧进程·备份配置]
        I3 --> I4[解压文件·设置权限]
        I4 --> I5[锁定脚本 chattr +i]
        I5 --> I6[安装完成，提示重启]
    end

    subgraph 启动主流程[启动主流程 - service.sh]
        S1[service.sh 执行] --> S2[解锁脚本防篡改]
        S2 --> S3{检测到Hosts模块?}
        S3 -->|有| S4[禁用模块并退出]
        S3 -->|无| S5{AGH进程是否已运行?}
        S5 -->|是（软重启）| S6[跳过初始化]
        S5 -->|否（冷启动）| S7[DNS端口随机化·同步config.prop]
        S7 --> S8[启动AGH]
        S8 --> S9{启动验证成功?}
        S9 -->|是| S10[记录启动成功]
        S9 -->|否| S11[exec $0 自重启]
        S11 --> S1
        S10 --> S12[启动守护脚本组]
        S6 --> S12
    end

    subgraph 守护脚本组[守护脚本组 - 各自独立5秒循环]
        DIR[<b>各自独立 每5秒循环</b>]

        D1["iptables.sh"]
            D1 --> D1A[每轮重载 config.prop<br>取得 bypass 与 redir_port]
        D1A --> D1Z{bypass = 1 ?}
        D1Z -->|是| D1H[clear_block：逐条循环删除<br>全部劫持规则与DoT拦截<br>AGH 进程保留·WebUI 仍可访问]
        D1H --> D1G
        D1Z -->|否| D1B{检测 need_restart<br>（pgrep AGH）}
        D1B -->|进程丢失| D1C[start_agh：写日志·启动AGH]
        D1B -->|进程正常| D1D[继续]
        D1C --> D1E[block_active：检测规则完整性]
        D1D --> D1E
        D1E -->|规则缺失| D1F[rebuild_rules：先循环清理<br>再重建规则·刷新网络]
        D1E -->|规则正常| D1G[sleep 5 回到循环]
        D1F --> D1G
        D1G --> D1

        D2["NoAdsService.sh"]
        D2 --> D2A[收集广告目录路径]
        D2A --> D2B[检查锁定状态]
        D2B -->|未锁定| D2C[删除目录·重建并锁定]
        D2B -->|已锁定| D2D[跳过]
        D2C --> D2E[强制关闭私人DNS<br>bypass=1 时跳过]
        D2D --> D2E
        D2E --> D2F[sleep 5 回到循环]
        D2F --> D2

        D3["ProxyConfig.sh"]
        D3 --> D3A[每轮重载 config.prop]
        D3A --> D3B[遍历代理配置文件]
        D3B --> D3C[修改YAML DNS指向AGH<br>bypass=1 时还原为原始DNS]
        D3C --> D3D[重启代理服务·刷新网络]
        D3D --> D3E[sleep 5 回到循环]
        D3E --> D3

        D4["ModuleMOD.sh"]
        D4 --> D4A[检测系统语言]
        D4A --> D4B{语言是否变化?}
        D4B -->|是| D4C[更新 module.prop 描述]
        D4B -->|否| D4D[跳过]
        D4C --> D4E[sleep 5 回到循环]
        D4D --> D4E
        D4E --> D4
    end

    subgraph 卸载流程[卸载流程 - uninstall.sh]
        U1[开始卸载] --> U2[遍历 /proc 停止所有 AGH 及脚本进程]
        U2 --> U3[ProxyConfig --clean 还原代理配置]
        U3 --> U4[清理 iptables 规则]
        U4 --> U5[解锁 chattr 并删除残留文件]
        U5 --> U6[删除 AGH 残留目录]
        U6 --> U7[卸载完成，无残留]
    end

    %% 垂直顺序：管理器 → 安装 → 启动 → 守护 → 卸载
    独立管理器 -.->|可选工具，读取/写入配置| 安装流程
    安装流程 --> 启动主流程
    启动主流程 --> 守护脚本组
    守护脚本组 --> 卸载流程

    style S5 fill:#f9f,stroke:#333
    style S6 fill:#bbf,stroke:#333
    style S7 fill:#bbf,stroke:#333
    style S11 fill:#faa,stroke:#333
    style D1 fill:#e1f5e1,stroke:#333
    style D2 fill:#e1f0f5,stroke:#333
    style D3 fill:#f5e1e1,stroke:#333
    style D4 fill:#f5f0e1,stroke:#333
    style DIR fill:#fff,stroke:#fff
    style M1 fill:#e8d5f5,stroke:#333
    style M7 fill:#d5f5e8,stroke:#333
    style M8 fill:#d5f5e8,stroke:#333
```

## ⚠️ 风险提示，不看请别怪我没提醒
- 更新到2026.03.31版本的切记不要降级刷入到更早之前的版本，不然卸载模块时会有残留
- 模块会导致优惠券无法正常领取，如无法正常领取这并非误杀
- 部分软件的看广告领金币无法正常领取，如无法使用这并非误杀
- 模块不可以与同类模块同时使用，更详细的请看教程那一栏
- 模块默认会劫持全部 DNS 流量并强制关闭私人 DNS，接入需要指定 DNS 的 WiFi 前请先按「直通模式」关闭劫持
- 模块无法拦截广告与内容为同一域名的，比如QQ、微信、支付宝等部分广告
## 💡 模块相比于其他的方案有哪些优点？
### 相比于非AdguardHome DNS实现方案有哪些优点？
1. AdguardHome经过多年维护都还有高危CVE漏洞，其他竞品方案只会更差（实力不如Adguard公司技术深厚）
2. 性能和功耗上未必好得过由Go语言编写的AdguardHome，项目越小盯的人越少越不容易发现深层次漏洞（更何况AdguardHome为全球开源大项目）
### 相比于私人DNS有哪些优点？
1. 私人dns需要不断的向服务器进行访问，一旦服务器超负荷或过载以及服务器连不上的话就会导致断网
2. 由于私人dns需要向服务器进行访问，所以存在很大的网络延迟问题（因为需要向服务器请求过滤以后再返回到你的设备上）
3. 私人DNS由于数据都交由服务器处理，存在的数据泄露的隐患（因为私人DNS的置信度不高）
4. 数据都在本地处理，隐私保障性更高
### 相比于Hosts有哪些优点？
1. 数据都是加密传输，并且经过Doh
2. 防止DNS劫持，防止网页被劫持的风险
3. 不容易被检测，因为Hosts返回本地回环地址本身就是特征
4. 不需要刷入元模块，隐藏性更好
### 相比于李跳跳等无障碍跳过软件有哪些优点？
1. 不用担心会掉后台，不用担心杀后台会导致无障碍失效等问题
2. 不会因为无障碍而导致手机掉帧卡顿，因为无障碍跳过软件是实时扫描页面元素
3. 轻量化运行不用担心耗电过快的问题
4. 模块不存在应用包名被检测的问题
### 相比于Lsposed模块去广告有哪些优点？
1. 不容易被检测到，因为Lsposed去广告插件需要Hook函数注入应用
2. 本模块虽屏蔽精度不高，相比于此类插件屏蔽的广啊（因为此类模块只能屏蔽一个或十几个应用）
3. 无需担心应用检测包名的问题
### 相比于VPN代理去广告有哪些优点？
1. 无需担心应用检测到开启VPN代理
2. 不用担心会掉后台的问题
3. 无需担心应用检测包名的问题
## 📖 教程，不看的话出事别到处找我问题
- 一定要关闭或卸载其他广告拦截模块、无障碍跳过软件、VPN代理去广告、浏览器自带广告拦截等等
- 遇到广告拦截不掉的话清除该应用的全部数据后重试
- 如果你使用的是Magisk框架，点击模块旁边的操作按钮即可**切换直通模式**（不会打开 Web UI），想打开 Web UI 请直接访问 `http://127.0.0.1:3000`
- Web UI 地址固定为 `http://127.0.0.1:3000`（DNS 重定向端口为随机端口，无需关心）
- 如果你有自己修改代理模块配置文件的癖好请不要用本模块，谢谢
- 代理模块和代理软件不是同一个，是两个不同的概念
- 代理软件教程：使用Chash Meta导致无法正常过滤的，可以去Chash Meta设置-网络中关闭系统代理
- 代理模块教程：订阅链接只能填一个且在/data/adb/agh/scripts/config.prop中填入你的机场订阅保存重启即可自动兼容代理模块，剩下的交给模块自行处理就行
- 上游 DNS 教程：模块默认把查询交给本地 smartdns（`127.0.0.1:1451`），需要自行部署 smartdns 并监听该端口；未部署时会自动改用内置的 `fallback_dns` 解析（仍为 DoH，但失去 smartdns 的分流与加速能力）
- 中国科学大学测速网：[点击跳转](https://test.ustc.edu.cn)
- 测试广告拦截是否正常（达到96%或以上是正常）：[点击跳转](https://paileactivist.github.io/toolz/adblock.html)
## 📶 直通模式（必须使用指定 DNS 的 WiFi）
有些公共WiFi（认证热点、校园网、企业内网等）会通过 DHCP 广播指定的 DNS，或要求设备的 DNS 指向特定服务器才能完成认证。此时模块的 DNS 重定向会与之冲突，表现为解析异常、认证页打不开。
- 开启方式（二选一）：
  - 点击模块旁边的**操作按钮**，按钮即为直通模式开关，每次点击在`关闭/开启`之间切换，并打印当前状态
  - 用编辑器打开 `/data/adb/agh/scripts/config.prop`，把 `bypass=0` 改为 `bypass=1`
  - 两种方式都最迟 5 秒生效，无需重启
- 生效范围：撤销全部 53 端口重定向与 853（DoT）拦截，并停止强制关闭私人 DNS；系统随即改用网络下发的 DNS
- AGH 进程与过滤能力保留，Web UI 仍可访问（`http://127.0.0.1:3000`），但不劫持任何 DNS 流量
- 使用代理模块时，开启期间会自动还原代理配置中被改写的 DNS，避免代理失去上游
- 关闭方式：再点一次操作按钮，或把 `bypass` 改回 `0`；守护脚本会重建规则并刷新网络（会短暂断开 WiFi）
- 注意：在 Web UI 里关闭「保护」开关不会撤销 DNS 劫持，二者互不等价，切换网络时请改`bypass`
- 查看当前状态：日志 `/data/adb/agh/agh.log` 会记录每次模式切换
- 卸载模块后私人 DNS 不会自动恢复原设置，需要时请自行在系统设置里调整
- 操作按钮的输出里如果出现「守护脚本未运行」，说明模块守护进程已退出，此时开关不会自动生效，请重启手机
## 💬 获取联系方式
- 聊天闲聊群：[点击链接加入群聊](https://qun.qq.com/universal-share/share?ac=1&authKey=l2FNOfui75SDr9n8qTfNjibiF1aTpQ%2B0cmJrw7iKnj%2B95dyExNG5LrdCJu5%2FEKrQ&busi_data=eyJncm91cENvZGUiOiI3NDY2NDA0NjQiLCJ0b2tlbiI6ImhOUWgzVTFPYnRUcEw1ZEJ1TnhkOGI4b0ZQSFV6cmtuVkludk5EcDR4WTFXSU5PelVmdnZoUHIwOGEreHVnNEYiLCJ1aW4iOiIzMzEzODI0NTc1In0%3D&data=8QbRVdmvcvuIPhoaZYMQRNm8tdG9QvQ_d6dLJvGEW_XEOWLbexxs8SgTRPfW51Tpe7IGWAu3PpizEpFa9oO1LQ&svctype=4&tempid=h5_group_info)
- 反馈测试组：[点击链接加入群聊](https://qun.qq.com/universal-share/share?ac=1&authKey=CnRMCNMYpq8urYWFDHU1Hr8cDAdDaVGHc6NQ4cyNJlYsaf2AGI14CAmwadmXpPjk&busi_data=eyJncm91cENvZGUiOiIyMTY3MDQ4MzI2IiwidG9rZW4iOiJTcjF1NENkZC9uNzMyMW52cnJITmdQRURQR25LOXkrWlV2d3BNbTNpdTl1dHk4M1ZVSUFYZDMwdGhaSU1JTE1sIiwidWluIjoiMzMxMzgyNDU3NSJ9&data=qW-Iwd_M-T4oba0swGdorSGKcUbyHUIRmYV8nVcUVA320bVl97MIQsLZpfxDc9zWSCZSVB2nsKmK-oLu96JB6Q&svctype=4&tempid=h5_group_info)
- 绮梦社区友情链接：[点击链接进入官网](https://vlink.cc/ceromis)
## 🙏 鸣谢项目名单
- [AdguardHome_magisk](https://github.com/410154425/AdGuardHome_magisk)
- [akashaProxy](https://github.com/ModuleList/akashaProxy)
- [box_for_magisk](https://github.com/taamarin/box_for_magisk)
- [AdGuardHomeForMagisk](https://github.com/twoone-3/AdGuardHomeForMagisk)
