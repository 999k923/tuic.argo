#!/bin/bash

AGSBX_DIR="/root/agsbx"
SINGBOX_PATH="$AGSBX_DIR/sing-box"
CLOUDFLARED_PATH="$AGSBX_DIR/cloudflared"
CONFIG_PATH="$AGSBX_DIR/sb.json"
VARS_PATH="$AGSBX_DIR/variables.conf"
LOG_FILE="$AGSBX_DIR/keep_alive.log"

# 加载变量
[ -f "$VARS_PATH" ] && source "$VARS_PATH"

log(){
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

check_singbox(){
    if [ ! -f "$SINGBOX_PATH" ]; then
        log "❌ sing-box 不存在: $SINGBOX_PATH"
        return
    fi
    if [ ! -f "$CONFIG_PATH" ]; then
        log "❌ 配置文件不存在: $CONFIG_PATH"
        return
    fi
    if ! pgrep -f "$SINGBOX_PATH" >/dev/null; then
        log "🔄 sing-box 不在运行，启动中..."
        nohup "$SINGBOX_PATH" run -c "$CONFIG_PATH" >> "$LOG_FILE" 2>&1 &
        sleep 2
    fi
}

check_cloudflared(){
    if [ ! -f "$CLOUDFLARED_PATH" ]; then
        log "❌ cloudflared 不存在"
        return
    fi
    if ! pgrep -f "$CLOUDFLARED_PATH" >/dev/null; then
        log "🔄 cloudflared 不在运行，启动中..."
        nohup "$CLOUDFLARED_PATH" tunnel run >> "$LOG_FILE" 2>&1 &
        sleep 2
    fi
}

daily_restart(){
    TODAY=$(date +%Y-%m-%d)
    LAST_RESTART_FILE="$AGSBX_DIR/last_restart"

    if [ -f "$LAST_RESTART_FILE" ]; then
        LAST=$(cat "$LAST_RESTART_FILE")
    else
        LAST="none"
    fi

    if [ "$TODAY" != "$LAST" ]; then
        log "⏳ 到达每日重启时间，重启 sing-box / cloudflared"
        pkill -f "$SINGBOX_PATH"
        pkill -f "$CLOUDFLARED_PATH"
        echo "$TODAY" > "$LAST_RESTART_FILE"
        sleep 3
    fi
}

log "🚀 keep_alive 启动"

# 主循环
while true; do
    check_singbox
    check_cloudflared
    daily_restart
    sleep 10

    # 自我保活：如果父进程是 init/systemd，说明被外部杀掉，自动重启自己
    if [ "$PPID" -eq 1 ]; then
        log "⚠️ keep_alive.sh 被杀，自动重启自己"
        nohup "$0" >> "$LOG_FILE" 2>&1 &
        exit 0
    fi
done
