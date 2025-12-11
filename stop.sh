#!/bin/sh
# 一键停止 keep_alive 开机自启 + 保活 (兼容 Ubuntu / Alpine)

SERVICE_NAME="agsbx-keepalive"
KEEP_ALIVE_SH="/root/agsbx/keep_alive.sh"
PID_FILE="/run/agsbx-keepalive.pid"

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

# --- OpenRC (Alpine) ---
if [ -f /etc/init.d/$SERVICE_NAME ]; then
    echo "🛑 检测到 OpenRC 服务，正在停止..."
    /etc/init.d/$SERVICE_NAME stop
    rc-update del $SERVICE_NAME default
    rm -f /etc/init.d/$SERVICE_NAME
    echo "🟢 OpenRC 服务已完全移除"
fi

# --- rc.local ---
if [ -f /etc/rc.local ]; then
    echo "🛑 清理 rc.local ..."
    sed -i "/keep_alive.sh/d" /etc/rc.local
fi

# --- crontab ---
echo "🛑 清理 crontab @reboot ..."
crontab -l 2>/dev/null | grep -v "keep_alive.sh" | crontab - 2>/dev/null

# --- kill running process ---
echo "🛑 终止正在运行的 keep_alive.sh ..."
# 优先用 PID 文件杀
if [ -f "$PID_FILE" ]; then
    kill "$(cat $PID_FILE)" 2>/dev/null
    rm -f "$PID_FILE"
fi
# 再补杀防止遗漏
pkill -f "$KEEP_ALIVE_SH" 2>/dev/null

echo "🎉 操作完成！所有开机自启 & 保活已完全移除。"
