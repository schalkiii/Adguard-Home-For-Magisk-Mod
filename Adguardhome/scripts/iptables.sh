#!/system/bin/sh
AGH_DIR="/data/adb/agh"
. "$AGH_DIR/scripts/config.prop"
MAIN_LOG="$AGH_DIR/agh.log"

# 防止重复启动
[ $(pgrep -f "$0" | wc -l) -gt 1 ] && exit

# 检测Adguardhome是否存活
agh_running() {
    for p in /proc/[0-9]*; do
        c=
        IFS= read -r c < "$p/cmdline"
        case "$c" in
        "$AGH_DIR/bin/AdGuardHome"*) return 0 ;;
        esac
    done
    return 1
}

# 启动AdGuardHome
start_agh() {
    {
        case "$(getprop persist.sys.locale)" in
            zh*) echo "$(date '+%F %T') AdGuardHome 进程丢失，正在重启..." ;;
            *)   echo "$(date '+%F %T') AdGuardHome process lost, restarting..." ;;
        esac
    } >> "$MAIN_LOG"
    export SSL_CERT_DIR="/system/etc/security/cacerts/"
    "$AGH_DIR/bin/AdGuardHome" --no-check-update &
}

# 检测劫持规则是否仍然存在（任一命中即认为仍处于劫持状态）
# 只以 53 端口重定向为准：filter 里的 DROP 属于旧版残留，清掉它们时不能反过来当作"劫持生效"
block_active() {
    iptables -w 2 -t nat -C ADGUARD -p udp --dport 53 -j REDIRECT --to-ports "$redir_port" 2>/dev/null && return 0
    iptables -w 2 -t nat -C ADGUARD -p tcp --dport 53 -j REDIRECT --to-ports "$redir_port" 2>/dev/null && return 0
    ip6tables -w 2 -t nat -C ADGUARD -p udp --dport 53 -j REDIRECT --to-ports "$redir_port" 2>/dev/null && return 0
    ip6tables -w 2 -t nat -C ADGUARD -p tcp --dport 53 -j REDIRECT --to-ports "$redir_port" 2>/dev/null && return 0
    return 1
}

# 清除全部劫持规则
# 规则写入用的是追加，历史上可能已堆积多条，因此逐条循环删除直到不存在
clear_block() {
    while iptables -w 2 -t nat -C OUTPUT -j ADGUARD 2>/dev/null; do
        iptables -w 2 -t nat -D OUTPUT -j ADGUARD || break
    done
    iptables -w 2 -t nat -F ADGUARD 2>/dev/null
    iptables -w 2 -t nat -X ADGUARD 2>/dev/null
    while ip6tables -w 2 -t nat -C OUTPUT -j ADGUARD 2>/dev/null; do
        ip6tables -w 2 -t nat -D OUTPUT -j ADGUARD || break
    done
    ip6tables -w 2 -t nat -F ADGUARD 2>/dev/null
    ip6tables -w 2 -t nat -X ADGUARD 2>/dev/null
    # 旧版本会 DROP 出向 853 与 IPv6:53，本版改为放行 853、IPv6 走重定向，
    # 不清掉这些残留的话升级后 DoT 和 IPv6 解析仍然被闷死
    while iptables -w 2 -C OUTPUT -p tcp --dport 853 -j DROP 2>/dev/null; do
        iptables -w 2 -D OUTPUT -p tcp --dport 853 -j DROP || break
    done
    while iptables -w 2 -C OUTPUT -p udp --dport 853 -j DROP 2>/dev/null; do
        iptables -w 2 -D OUTPUT -p udp --dport 853 -j DROP || break
    done
    while ip6tables -w 2 -C OUTPUT -p tcp --dport 853 -j DROP 2>/dev/null; do
        ip6tables -w 2 -D OUTPUT -p tcp --dport 853 -j DROP || break
    done
    while ip6tables -w 2 -C OUTPUT -p udp --dport 853 -j DROP 2>/dev/null; do
        ip6tables -w 2 -D OUTPUT -p udp --dport 853 -j DROP || break
    done
    while ip6tables -w 2 -C OUTPUT -p udp --dport 53 -j DROP 2>/dev/null; do
        ip6tables -w 2 -D OUTPUT -p udp --dport 53 -j DROP || break
    done
    while ip6tables -w 2 -C OUTPUT -p tcp --dport 53 -j DROP 2>/dev/null; do
        ip6tables -w 2 -D OUTPUT -p tcp --dport 53 -j DROP || break
    done
}

# 本机上游解析器的 socket 属主匹配串，由 config.prop 的 upstream_uid/upstream_gid 生成
# 留空表示不豁免。owner 匹配只比对进程主组，App 的 3004 属附加组，不会被放行
owner_match=""
# 部分内核不带 xt_owner，创建失败后置 0 并不再要求该规则，避免守护循环反复重建刷网络
owner_supported=1

build_owner_match() {
    owner_match=""
    # 与 redir_port 同样做容错，编辑器存成带\r 或非数字时直接视为未配置
    upstream_uid="${upstream_uid%%[!0-9]*}"
    upstream_gid="${upstream_gid%%[!0-9]*}"
    [ -z "$upstream_gid" ] && return
    [ -z "$upstream_uid" ] && upstream_uid=0
    owner_match="-m owner --uid-owner $upstream_uid --gid-owner $upstream_gid"
}

# 建立上游豁免规则：v4/v6 的 ADGUARD 链首各插一条 RETURN，
# 解析器自己发出的 53 查询直接出去，不再被重定向回 AGH 形成回环
# IPv6 不支持 nat 表时那条静默失败，不影响 IPv4 一路
add_exempt_rules() {
    iptables -w 2 -t nat -I ADGUARD 1 $owner_match -j RETURN 2>/dev/null || return 1
    ip6tables -w 2 -t nat -I ADGUARD 1 $owner_match -j RETURN 2>/dev/null
    return 0
}

# 豁免规则是否存在（配置清空后需重启或等待规则重建才生效，故不反向检测）
# 只查 IPv4：v6 规则在内核不支持 IPv6 nat 时本就不存在，查它会每轮误判成缺失
exempt_active() {
    iptables -w 2 -t nat -C ADGUARD $owner_match -j RETURN 2>/dev/null
}

# 重建iptables规则
rebuild_rules() {
    clear_block
    iptables -w 2 -t nat -N ADGUARD
    iptables -w 2 -t nat -I OUTPUT -j ADGUARD
    # IPv6 的 53 也重定向进 AGH，不再整条 DROP：闷掉之后 IPv6 DNS 客户端只会等超时
    ip6tables -w 2 -t nat -N ADGUARD 2>/dev/null
    ip6tables -w 2 -t nat -I OUTPUT -j ADGUARD 2>/dev/null
    # 上游豁免要在 REDIRECT 之前建立，插到链首
    if [ -n "$owner_match" ] && [ "$owner_supported" = "1" ]; then
        if ! add_exempt_rules; then
            owner_supported=0
            echo "$(date '+%F %T') 内核不支持 owner 匹配，已放弃上游解析器豁免；解析器请勿使用 53 端口上游。" >> "$MAIN_LOG"
        fi
    fi
    iptables -w 2 -t nat -A ADGUARD -p udp --dport 53 -j REDIRECT --to-ports "$redir_port"
    iptables -w 2 -t nat -A ADGUARD -p tcp --dport 53 -j REDIRECT --to-ports "$redir_port"
    ip6tables -w 2 -t nat -A ADGUARD -p udp --dport 53 -j REDIRECT --to-ports "$redir_port" 2>/dev/null
    ip6tables -w 2 -t nat -A ADGUARD -p tcp --dport 53 -j REDIRECT --to-ports "$redir_port" 2>/dev/null
    # 853（DoT/DoQ）不再设卡：静默 DROP 会让不回退的客户端直接没网，
    # 重定向又过不了 TLS 证书校验，拦不住还添堵，所以干脆放行

# 刷新网络（开关飞行模式）
    for s in 1 0; do
        settings put global airplane_mode_on $s
        am broadcast -a android.intent.action.AIRPLANE_MODE
    done
}

# 规则守护循环
bypass_state=0
while true; do
    . "$AGH_DIR/scripts/config.prop"
    # config.prop 若被带\r 的编辑器保存，直接使用会导致规则创建失败，这里做容错
    redir_port="${redir_port%%[!0-9]*}"
    [ -z "$redir_port" ] && redir_port=5591
    case "$bypass" in 1*) bypass=1 ;; *) bypass=0 ;; esac
    build_owner_match

    # 直通模式：撤销全部劫持规则，系统改用网络下发的 DNS
    # AGH 进程保持运行，WebUI 仍可访问，此分支不拉起也不重建规则
    if [ "$bypass" = "1" ]; then
        block_active && clear_block
        [ "$bypass_state" = "1" ] || echo "$(date '+%F %T') 直通模式已开启，DNS 劫持规则已撤销。" >> "$MAIN_LOG"
        bypass_state=1
        sleep 5
        continue
    fi
    [ "$bypass_state" = "1" ] && echo "$(date '+%F %T') 直通模式已关闭，恢复 DNS 过滤。" >> "$MAIN_LOG"
    bypass_state=0

    need_restart=0
    agh_running || need_restart=1
    need_fix=0
    block_active || need_fix=1
    # 豁免链可能被其他模块清空，而劫持规则仍在别处命中，需单独确认豁免没丢
    if [ -n "$owner_match" ] && [ "$owner_supported" = "1" ]; then
        exempt_active || need_fix=1
    fi
    [ $need_restart -eq 1 ] && start_agh
    [ $need_restart -eq 1 ] || [ $need_fix -eq 1 ] && rebuild_rules
    sleep 5
done &