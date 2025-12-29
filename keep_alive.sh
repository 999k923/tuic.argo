#!/bin/bash

AGSBX_DIR="/root/agsbx"
SINGBOX_PATH="$AGSBX_DIR/sing-box"
CLOUDFLARED_PATH="$AGSBX_DIR/cloudflared"
CONFIG_PATH="$AGSBX_DIR/sb.json"
VARS_PATH="$AGSBX_DIR/variables.conf"
LOG_FILE="$AGSBX_DIR/keep_alive.log"
CONFIG_YML="$AGSBX_DIR/config.yml"

# --- 加载变量 ---
if [ -f "$VARS_PATH" ]; then
    source "$VARS_PATH"
fi

# --- 清洗变量里的单引号 ---
ARGO_TOKEN="${ARGO_TOKEN//\'/}"
ARGO_DOMAIN="${ARGO_DOMAIN//\'/}"
ARGO_LOCAL_PORT="${ARGO_LOCAL_PORT//\'/}"

log(){
    if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt 10485760 ]; then
        > "$LOG_FILE"   # 清空日志
    fi
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

    if [ -z "$ARGO_TOKEN" ]; then
        log "❌ ARGO_TOKEN 未设置，无法启动 cloudflared"
        return
    fi

    if ! pgrep -f "$CLOUDFLARED_PATH" >/dev/null; then
        log "🔄 cloudflared 不在运行，启动中..."

        cat > "$CONFIG_YML" <<EOF
log-level: info
ingress:
  - hostname: ${ARGO_DOMAIN}
    service: http://127.0.0.1:${ARGO_LOCAL_PORT}
  - service: http_status:404
EOF

        nohup "$CLOUDFLARED_PATH" tunnel --config "$CONFIG_YML" run --token "$ARGO_TOKEN" >> "$LOG_FILE" 2>&1 &
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
done
