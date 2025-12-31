#!/bin/sh
# ======================================================================
#         一键停止并移除 All-in-One Keep-Alive 守护脚本
# ======================================================================

# --- 脚本和日志路径 (与新的 keep_alive.sh 保持一致) ---
KEEP_ALIVE_SCRIPT_PATH="/opt/vless-manager/keep_alive.sh"
LOG_DIR="/var/log/vless-manager"

echo "🛑 开始停止并移除 keep_alive 守护脚本及其开机自启..."

# --- 1. 清理 crontab (推荐的自启方式) ---
echo "1. 正在清理 crontab 中的 @reboot 任务..."
# 检查 crontab 是否存在，避免在没有 crontab 时报错
if crontab -l >/dev/null 2>&1; then
    # 过滤掉包含 keep_alive.sh 的行，然后重新写入 crontab
    crontab -l | grep -v "keep_alive.sh" | crontab -
    echo "   ✅ crontab 清理完成。"
else
    echo "   - 未发现 crontab 任务，跳过。"
fi

# --- 2. 终止正在运行的守护进程 ---
echo "2. 正在终止所有正在运行的 keep_alive.sh 进程..."
# 使用 pkill 通过脚本路径精确查找并终止进程
# -f 参数会匹配整个命令行，确保不会误杀
if pkill -f "$KEEP_ALIVE_SCRIPT_PATH"; then
    echo "   ✅ 守护进程已终止。"
else
    echo "   - 未发现正在运行的守护进程。"
fi

# --- 3. (兼容性清理) 清理旧的或自定义的 systemd 服务 ---
echo "3. 正在检查并清理可能的旧版 systemd 服务..."
if command -v systemctl >/dev/null 2>&1; then
    # 检查可能存在的服务名
    for service_name in agsbx-keepalive vless-keepalive; do
        if systemctl list-unit-files | grep -q "$service_name.service"; then
            echo "   - 发现旧版服务: $service_name，正在移除..."
            systemctl stop "$service_name" 2>/dev/null
            systemctl disable "$service_name" 2>/dev/null
            rm -f "/etc/systemd/system/$service_name.service"
            echo "   ✅ 旧版服务 $service_name 已移除。"
        fi
    done
    systemctl daemon-reload
else
    echo "   - 未安装 systemd，跳过。"
fi

# --- 4. (可选) 清理日志文件 ---
read -p "是否需要删除守护脚本的日志目录 ($LOG_DIR)？(y/n): " confirm
if [ "$confirm" = "y" ]; then
    echo "4. 正在删除日志目录..."
    rm -rf "$LOG_DIR"
    echo "   ✅ 日志目录已删除。"
fi

echo ""
echo "🎉 操作完成！所有 keep_alive 相关的守护和开机自启均已移除。"
