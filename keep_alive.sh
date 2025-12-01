#!/bin/bash

AGSBX_DIR="/root/agsbx"
SINGBOX_PATH="$AGSBX_DIR/sing-box"
CLOUDFLARED_PATH="$AGSBX_DIR/cloudflared"
CONFIG_PATH="$AGSBX_DIR/sb.json"
VARS_PATH="$AGSBX_DIR/variables.conf"
LOG_FILE="$AGSBX_DIR/keep_alive.log"

# 加载变量
if [ -f "$VARS_PATH" ]; then
    source "$VARS_PATH"
fi

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

    # 自动获取 tunnel 名称
    TUNNEL_NAME=""
    TUNNELS_JSON="$HOME/.cloudflared/tunnels.json"
    if [ -f "$TUNNELS_JSON" ]; then
        if command -v jq >/dev/null 2>&1; then
            TUNNEL_NAME=$(jq -r '.[0].Name' "$TUNNELS_JSON")
        else
            log "⚠️ 未安装 jq，无法自动获取 tunnel 名称，请手动指定"
        fi
    fi

    if [ -z "$TUNNEL_NAME" ]; then
        log "⚠️ 未找到可用 tunnel 名称，cloudflared 无法启动"
        return
    fi

    if ! pgrep -f "$CLOUDFLARED_PATH" >/dev/null; then
        log "🔄 cloudflared 不在运行，启动中..."
        nohup "$CLOUDFLARED_PATH" tunnel run "$TUNNEL_NAME" >> "$LOG_FILE" 2>&1 &
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

while true; do
    check_singbox
    check_cloudflared
    daily_restart
    sleep 10
done &
