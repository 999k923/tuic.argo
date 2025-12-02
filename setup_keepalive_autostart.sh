#!/bin/sh
# ===============================
# 一键设置 keep_alive.sh 开机自启并保活
# 兼容 Ubuntu(systemd) / Alpine(crond)
# ===============================

KEEP_ALIVE_SH="/root/agsbx/keep_alive.sh"
LOG_FILE="/root/agsbx/keep_alive.log"
DAEMON_SH="/root/agsbx/keep_alive_daemon.sh"

# -------------------------------
# 检查 keep_alive.sh 是否存在
# -------------------------------
if [ ! -f "$KEEP_ALIVE_SH" ]; then
    echo "❌ $KEEP_ALIVE_SH 不存在，请先确认脚本路径正确"
    exit 1
fi

# -------------------------------
# Ubuntu / systemd 系统
# -------------------------------
if [ -d /etc/systemd/system ]; then
    echo "🟢 检测到 systemd，创建 systemd 服务..."
    SERVICE_FILE="/etc/systemd/system/agsbx-keepalive.service"
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Keep Alive TUIC + Argo
After=network.target

[Service]
Type=simple
ExecStart=/bin/sh $KEEP_ALIVE_SH
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable agsbx-keepalive
    systemctl restart agsbx-keepalive
    echo "✅ systemd 服务创建完成并已启动"

# -------------------------------
# Alpine / 非 systemd 系统
# -------------------------------
else
    echo "🟡 未检测到 systemd，使用 crontab + 守护脚本保活..."

    # 检查 crond 是否安装
    if ! command -v crond >/dev/null 2>&1; then
        echo "⚠️ crond 未安装，请先安装 cronie 或 busybox-cron"
        exit 1
    fi

    # 确保 crond 启动
    if ! pgrep crond >/dev/null 2>&1; then
        echo "🚀 启动 crond..."
        crond
    fi

    # -------------------------------
    # 创建守护脚本
    # -------------------------------
    cat > "$DAEMON_SH" << 'EOF'
#!/bin/sh
KEEP_ALIVE_SH="/root/agsbx/keep_alive.sh"
LOG_FILE="/root/agsbx/keep_alive.log"

# 避免重复运行守护脚本
if [ -f /tmp/keep_alive_daemon.pid ]; then
    PID=$(cat /tmp/keep_alive_daemon.pid)
    if kill -0 "$PID" >/dev/null 2>&1; then
        exit 0
    fi
fi
echo $$ > /tmp/keep_alive_daemon.pid

# 守护循环
while true; do
    if ! pgrep -f "$KEEP_ALIVE_SH" >/dev/null; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] keep_alive.sh 不存在运行中，启动中..." >> "$LOG_FILE"
        /bin/sh "$KEEP_ALIVE_SH" >> "$LOG_FILE" 2>&1 &
    fi
    sleep 5
done
EOF
    chmod +x "$DAEMON_SH"

    # -------------------------------
    # crontab 定时启动守护脚本
    # -------------------------------
    (crontab -l 2>/dev/null | grep -q "keep_alive_daemon.sh") || \
        (crontab -l 2>/dev/null; echo "@reboot $DAEMON_SH &") | crontab -

    # 每分钟确保守护脚本运行
    (crontab -l 2>/dev/null | grep -q "keep_alive_daemon.sh") || \
        (crontab -l 2>/dev/null; echo "* * * * * $DAEMON_SH &") | crontab -

    echo "✅ crontab + 守护循环设置完成，下次开机自动启动并保活 keep_alive.sh"
fi

# -------------------------------
# 立即启动一次 keep_alive.sh
# -------------------------------
echo "🚀 启动 keep_alive.sh..."
$KEEP_ALIVE_SH &

echo "🎉 设置完成！请查看日志 $LOG_FILE 确认服务运行状态"
