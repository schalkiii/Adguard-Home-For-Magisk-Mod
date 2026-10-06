#!/system/bin/sh
AGH_DIR="/data/adb/agh"
YAML_FILE="$AGH_DIR/bin/AdGuardHome.yaml"
PROP_FILE="$AGH_DIR/scripts/config.prop"

# 多语言检测
locale=$(getprop persist.sys.locale)
[ -z "$locale" ] && locale="zh"
case $locale in zh*) lang=zh ;; *) lang=en ;; esac

# 读取WebUI端口
PORT=$(sed -n 's/^[[:space:]]*address: 127\.0\.0\.1:\([0-9]*\).*/\1/p' "$YAML_FILE")

# 显式打开WebUI：action.sh webui
if [ "$1" = "webui" ]; then
    if [ "$lang" = "zh" ]; then
        echo "正在打开 Web UI（端口 $PORT）..."
    else
        echo "Opening Web UI (port $PORT)..."
    fi
    am start -a android.intent.action.VIEW -d "http://127.0.0.1:$PORT"
    exit 0
fi

# 读取当前直通状态（去除可能残留的行尾字符）
bypass=$(sed -n 's/^bypass=\([01]\).*/\1/p' "$PROP_FILE" | tr -d '\r\n')
[ -z "$bypass" ] && bypass=0

# 切换直通模式
if [ "$bypass" = "1" ]; then new=0; else new=1; fi
sed -i "s/^bypass=.*/bypass=$new/" "$PROP_FILE"

if [ "$lang" = "zh" ]; then
    if [ "$bypass" = "1" ]; then
        echo "当前状态：直通模式（不劫持DNS）"
        echo "操作结果：已关闭直通，恢复DNS过滤"
        echo "注意：恢复时会刷新一次网络，WiFi将短暂断开重连"
    else
        echo "当前状态：正常过滤（劫持DNS）"
        echo "操作结果：已开启直通模式"
        echo "已撤销53端口重定向与853拦截，系统改用网络下发的DNS"
        echo "AGH进程与过滤能力保留，WebUI仍可访问：http://127.0.0.1:$PORT"
    fi
    echo "最迟5秒自动生效，无需重启"
    if pgrep -f "$AGH_DIR/scripts/iptables.sh" >/dev/null 2>&1; then
        echo "守护脚本：运行中"
    else
        echo "警告：守护脚本未运行，开关不会自动生效，请重启手机"
    fi
    echo "日志：$AGH_DIR/agh.log"
else
    if [ "$bypass" = "1" ]; then
        echo "Current: bypass mode (DNS not hijacked)"
        echo "Result: bypass disabled, DNS filtering restored"
        echo "Note: restoring refreshes the network, WiFi will briefly disconnect and reconnect"
    else
        echo "Current: normal filtering (DNS hijacked)"
        echo "Result: bypass mode enabled"
        echo "Port 53 redirections and 853 blocks removed, the system will use the DNS broadcast by the network"
        echo "The AGH process stays alive and the WebUI remains reachable: http://127.0.0.1:$PORT"
    fi
    echo "Takes effect within 5 seconds, no reboot needed"
    if pgrep -f "$AGH_DIR/scripts/iptables.sh" >/dev/null 2>&1; then
        echo "Daemon: running"
    else
        echo "Warning: daemon is not running, the switch will not take effect automatically, please reboot"
    fi
    echo "Log: $AGH_DIR/agh.log"
fi