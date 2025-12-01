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

log(){
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# --- 启动 sing-box ---
start_singbox(){
    if ! pgrep -f "$SINGBOX_PATH" >/dev/null; then
        log "启动 sing-box..."
        nohup "$SINGBOX_PATH" run -c "$CONFIG_PATH" >> "$LOG_FILE" 2>&1 &
        sleep 2
    fi
}

# --- 启动 cloudflared（token 模式） ---
start_cloudflared(){
    if [ -z "$ARGO_TOKEN" ]; then
        log "❌ ARGO_TOKEN 未设置，无法启动 cloudflared"
        return
    fi

    if ! pgrep -f "$CLOUDFLARED_PATH" >/dev/null; then
        log "启动 cloudflared (token 模式)..."

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

# --- 每日重启一次 ---
daily_restart(){
    TODAY=$(date +%Y-%m-%d)
    LAST_FILE="$AGSBX_DIR/last_restart"

    [[ -f "$LAST_FILE" ]] && LAST=$(cat "$LAST_FILE") || LAST="none"

    if [ "$TODAY" != "$LAST" ]; then
        log "每日重启 sing-box 和 cloudflared"
        pkill -f "$SINGBOX_PATH"
        pkill -f "$CLOUDFLARED_PATH"
        echo "$TODAY" > "$LAST_FILE"
        sleep 3
    fi
}

log "keep_alive 启动完成"

while true; do
    start_singbox
    start_cloudflared
    daily_restart
    sleep 10
done
