#!/bin/bash

# ======================================================================
#            守护脚本 (在原版基础上仅增加对 Xray 的保活)
# ======================================================================

# --- sing-box (from sing.sh) ---
AGSBX_DIR="/root/agsbx"
SINGBOX_PATH="$AGSBX_DIR/sing-box"
CLOUDFLARED_PATH="$AGSBX_DIR/cloudflared"
CONFIG_PATH="$AGSBX_DIR/sb.json"
VARS_PATH="$AGSBX_DIR/variables.conf"
CONFIG_YML="$AGSBX_DIR/config.yml"

# --- xray (from x.sh) ---
XRAY_CONFIG_PATH="/etc/xray/config.json"
XRAY_SYSTEMD_SERVICE="xray"

# --- 日志文件 ---
LOG_FILE="$AGSBX_DIR/keep_alive.log"

# --- 加载变量 (仅用于 sing-box) ---
if [ -f "$VARS_PATH" ]; then
    source "$VARS_PATH"
fi

# --- 清洗变量里的单引号 (仅用于 sing-box) ---
ARGO_TOKEN="${ARGO_TOKEN//\'/}"
ARGO_DOMAIN="${ARGO_DOMAIN//\'/}"
ARGO_LOCAL_PORT="${ARGO_LOCAL_PORT//\'/}"

# --- 日志函数 (您的原版) ---
log(){
    if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt 10485760 ]; then
        > "$LOG_FILE"   # 清空日志
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# --- 检查 sing-box (您的原版，无任何改动) ---
check_singbox(){
    if [ ! -f "$SINGBOX_PATH" ]; then
        # log "❌ sing-box 不存在: $SINGBOX_PATH" # 注释掉，如果未安装则不记录日志
        return
    fi

    if [ ! -f "$CONFIG_PATH" ]; then
        # log "❌ 配置文件不存在: $CONFIG_PATH"
        return
    fi

    if ! pgrep -f "$SINGBOX_PATH" >/dev/null; then
        log "🔄 [sing-box] 不在运行，启动中..."
        nohup "$SINGBOX_PATH" run -c "$CONFIG_PATH" >> "$LOG_FILE" 2>&1 &
        sleep 2
    fi
}

# --- 检查 cloudflared (您的原版，无任何改动) ---
check_cloudflared(){
    if [ ! -f "$CLOUDFLARED_PATH" ]; then
        # log "❌ cloudflared 不存在"
        return
    fi

    # 如果是临时隧道 (没有 token)，则无法守护，跳过
    if [ -z "$ARGO_TOKEN" ]; then
        return
    fi

    if ! pgrep -f "$CLOUDFLARED_PATH" >/dev/null; then
        log "🔄 [cloudflared] 不在运行，启动中..."

        cat > "$CONFIG_YML" <<EOF
log-level: info
ingress:
  - hostname: ${ARGO_DOMAIN}
    service: http://127.0.0.1:${ARGO_LOCAL_PORT}
  - service: http_status:404
EOF

        nohup "$CLOUDFLARED_PATH" tunnel --protocol http2 --config "$CONFIG_YML" run --token "$ARGO_TOKEN" >> "$LOG_FILE" 2>&1 &
        sleep 2
    fi
}

# --- 检查 xray (节点4) ---
check_xray(){
    # 如果 xray 配置文件不存在，则认为未安装，直接跳过
    if [ ! -f "$XRAY_CONFIG_PATH" ]; then
        return
    fi

    # 使用进程检查 + nohup 启动，不依赖 systemd
    if ! pgrep -f "$XRAY_CONFIG_PATH" >/dev/null; then
        log "🔄 [xray] 不在运行，后台启动中..."
        nohup /usr/local/bin/xray run -config "$XRAY_CONFIG_PATH" >> "$LOG_FILE" 2>&1 &
        sleep 2
    fi
}


# --- 每日重启 (您的原版，稍作修改以同时重启 xray) ---
daily_restart(){
    TODAY=$(date +%Y-%m-%d)
    LAST_RESTART_FILE="$AGSBX_DIR/last_restart"

    if [ -f "$LAST_RESTART_FILE" ]; then
        LAST=$(cat "$LAST_RESTART_FILE")
    else
        LAST="none"
    fi

    if [ "$TODAY" != "$LAST" ]; then
        log "⏳ 到达每日重启时间，重启所有服务..."
        
        # 重启 sing-box 和 cloudflared (如果已安装)
        if [ -f "$SINGBOX_PATH" ]; then
            pkill -f "$SINGBOX_PATH"
            pkill -f "$CLOUDFLARED_PATH"
        fi
        
        # 【新增】重启 xray (如果已安装)
        if [ -f "$XRAY_CONFIG_PATH" ]; then
            # 先杀掉可能残留的 Xray 进程
            pkill -f "$XRAY_CONFIG_PATH" || true
            log "🔄 [xray] 每日重启，后台启动中..."
            sleep 2
        fi

        
        echo "$TODAY" > "$LAST_RESTART_FILE"
        sleep 3
    fi
}

# --- 主循环 (您的原版，仅增加调用 check_xray) ---
log "🚀 keep_alive 启动"

while true; do
    # 检查 sing-box 和 cloudflared
    check_singbox
    check_cloudflared
    
    # 【新增】检查 xray
    check_xray
    
    # 每日重启
    daily_restart
    
    # 检查间隔
    sleep 10
done
