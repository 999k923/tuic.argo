#!/bin/sh
# 一键停止 keep_alive 开机自启 + 保活

SERVICE_NAME="agsbx-keepalive"
KEEP_ALIVE_SH="/root/agsbx/keep_alive.sh"

echo "🛑 开始停止 keep_alive 保活与开机自启..."

# --- systemd ---
if [ -d /etc/systemd/system ]; then
    if systemctl list-unit-files | grep -q "$SERVICE_NAME"; then
        echo "🛑 检测到 systemd 服务，正在停止..."
        systemctl stop $SERVICE_NAME 2>/dev/null
        systemctl disable $SERVICE_NAME 2>/dev/null
        rm -f /etc/systemd/system/$SERVICE_NAME.service
        systemctl daemon-reload
        echo "🟢 systemd 已完全移除"
    fi
fi

# --- rc.local ---
if [ -f /etc/rc.local ]; then
    echo "🛑 清理 rc.local ..."
    sed -i '/keep_alive.sh/d' /etc/rc.local
fi

# --- crontab ---
echo "🛑 清理 crontab @reboot ..."
crontab -l 2>/dev/null | grep -v "keep_alive.sh" | crontab - 2>/dev/null

# --- kill running process ---
echo "🛑 终止正在运行的 keep_alive.sh ..."
pkill -f keep_alive.sh 2>/dev/null

echo "🎉 操作完成！所有开机自启 & 保活已完全移除。"
