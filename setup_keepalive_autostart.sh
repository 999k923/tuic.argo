#!/bin/sh
# 一键设置 keep_alive.sh 开机自启 (兼容 Ubuntu / Alpine)
KEEP_ALIVE_SH="/root/agsbx/keep_alive.sh"
LOG_FILE="/root/agsbx/keep_alive_openrc.log"

if [ ! -f "$KEEP_ALIVE_SH" ]; then
    echo "❌ $KEEP_ALIVE_SH 不存在，请先确认脚本路径正确"
    exit 1
fi

# 检查系统是否有 systemd（Ubuntu）
if [ -d /etc/systemd/system ]; then
    echo "🟢 检测到 systemd，创建 systemd 服务..."
    SERVICE_FILE="/etc/systemd/system/agsbx-keepalive.service"
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Keep Alive TUIC + Argo
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash /root/agsbx/keep_alive.sh
WorkingDirectory=/root/agsbx
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

else
    echo "🟡 未检测到 systemd，使用 OpenRC 设置开机自启（Alpine）..."

    # 创建 OpenRC 服务文件
    SERVICE_FILE="/etc/init.d/agsbx-keepalive"
    cat > "$SERVICE_FILE" << EOF
#!/sbin/openrc-run

command="/bin/bash"
command_args="$KEEP_ALIVE_SH"
pidfile="/run/agsbx-keepalive.pid"
log_file="$LOG_FILE"

depend() {
    after net
}

start() {
    ebegin "Starting Keep Alive Service"
    # 后台启动脚本并记录 stdout/stderr
    start-stop-daemon --start --quiet --make-pidfile --pidfile \$pidfile --exec \$command -- \$command_args >> \$log_file 2>&1
    if [ \$? -eq 0 ]; then
        eend 0
    else
        eend 1
        echo "\$(date) ❌ 启动失败，请检查日志 \$log_file" >> \$log_file
    fi
}

stop() {
    ebegin "Stopping Keep Alive Service"
    start-stop-daemon --stop --quiet --pidfile \$pidfile
    eend \$?
}
EOF

    chmod +x "$SERVICE_FILE"

    # 添加开机自启
    rc-update add agsbx-keepalive default

    # 启动服务测试
    /etc/init.d/agsbx-keepalive start

    echo "✅ OpenRC 服务创建完成并已启动"
    echo "📄 日志文件：$LOG_FILE"
fi

echo "🎉 设置完成！请查看日志 ~/agsbx/keep_alive.log 和 $LOG_FILE 确认服务运行状态"
