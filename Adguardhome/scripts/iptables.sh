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
block_active() {
    iptables -w 2 -t nat -C ADGUARD -p udp --dport 53 -j REDIRECT --to-ports "$redir_port" 2>/dev/null && return 0
    iptables -w 2 -t nat -C ADGUARD -p tcp --dport 53 -j REDIRECT --to-ports "$redir_port" 2>/dev/null && return 0
    iptables -w 2 -C OUTPUT -p tcp --dport 853 -j DROP 2>/dev/null && return 0
    iptables -w 2 -C OUTPUT -p udp --dport 853 -j DROP 2>/dev/null && return 0
    ip6tables -w 2 -C OUTPUT -p tcp --dport 853 -j DROP 2>/dev/null && return 0
    ip6tables -w 2 -C OUTPUT -p udp --dport 853 -j DROP 2>/dev/null && return 0
    ip6tables -w 2 -C OUTPUT -p udp --dport 53 -j DROP 2>/dev/null && return 0
    ip6tables -w 2 -C OUTPUT -p tcp --dport 53 -j DROP 2>/dev/null && return 0
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

# 重建iptables规则
rebuild_rules() {
    clear_block
    iptables -w 2 -t nat -N ADGUARD
    iptables -w 2 -t nat -I OUTPUT -j ADGUARD
    iptables -w 2 -t nat -A ADGUARD -p udp --dport 53 -j REDIRECT --to-ports "$redir_port"
    iptables -w 2 -t nat -A ADGUARD -p tcp --dport 53 -j REDIRECT --to-ports "$redir_port"
    iptables -w 2 -A OUTPUT -p tcp --dport 853 -j DROP
    iptables -w 2 -A OUTPUT -p udp --dport 853 -j DROP
    ip6tables -w 2 -A OUTPUT -p tcp --dport 853 -j DROP
    ip6tables -w 2 -A OUTPUT -p udp --dport 853 -j DROP
    ip6tables -w 2 -A OUTPUT -p udp --dport 53 -j DROP
    ip6tables -w 2 -A OUTPUT -p tcp --dport 53 -j DROP

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
    [ $need_restart -eq 1 ] && start_agh
    [ $need_restart -eq 1 ] || [ $need_fix -eq 1 ] && rebuild_rules
    sleep 5
done &