#!/bin/sh
# 一键设置 keep_alive.sh 开机自启 (兼容 Ubuntu / Alpine)
KEEP_ALIVE_SH="/root/agsbx/keep_alive.sh"

if [ ! -f "$KEEP_ALIVE_SH" ]; then
    echo "❌ $KEEP_ALIVE_SH 不存在，请先确认脚本路径正确"
    exit 1
fi

# 检查系统是否有 systemd
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
    echo "🟡 未检测到 systemd，使用 rc.local / crontab 设置开机自启..."

    # rc.local 方式
    if [ ! -f /etc/rc.local ]; then
        echo -e "#!/bin/sh\nexit 0" > /etc/rc.local
        chmod +x /etc/rc.local
    fi
    grep -q "$KEEP_ALIVE_SH" /etc/rc.local || sed -i "1i $KEEP_ALIVE_SH &" /etc/rc.local

    # crontab @reboot 方式
    (crontab -l 2>/dev/null | grep -q "keep_alive.sh") || \
        (crontab -l 2>/dev/null; echo "@reboot $KEEP_ALIVE_SH") | crontab -

    echo "✅ rc.local / crontab 设置完成，下次开机自动启动 keep_alive.sh"
fi

echo "🎉 设置完成！请查看日志 ~/agsbx/keep_alive.log 确认服务运行状态"
