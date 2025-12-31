#!/bin/bash

# ======================================================================
#            All-in-One Keep-Alive & Watchdog Script
#         同时守护 sing-box (sing.sh) 和 xray (x.sh)
# ======================================================================

# --- sing-box (sing.sh) 相关路径 ---
AGSBX_DIR="/root/agsbx"
SINGBOX_PATH="$AGSBX_DIR/sing-box"
SINGBOX_CONFIG_PATH="$AGSBX_DIR/sb.json"
CLOUDFLARED_PATH="$AGSBX_DIR/cloudflared"
SING_VARS_PATH="$AGSBX_DIR/variables.conf"
CLOUDFLARED_CONFIG_YML="$AGSBX_DIR/config.yml"

# --- xray (x.sh) 相关路径 ---
XRAY_DIR="/etc/xray"
XRAY_PATH="/usr/local/bin/xray"
XRAY_CONFIG_PATH="$XRAY_DIR/config.json"

# --- 公共路径 ---
LOG_DIR="/var/log/vless-manager"
LOG_FILE="$LOG_DIR/keep_alive.log"
LAST_RESTART_FILE="$LOG_DIR/last_restart"

# --- 创建日志目录 ---
mkdir -p "$LOG_DIR"

# --- 加载 sing.sh 的变量 ---
if [ -f "$SING_VARS_PATH" ]; then
    source "$SING_VARS_PATH"
fi

# --- 清洗变量里的单引号 (如果存在) ---
ARGO_TOKEN="${ARGO_TOKEN//\'/}"
ARGO_DOMAIN="${ARGO_DOMAIN//\'/}"
ARGO_LOCAL_PORT="${ARGO_LOCAL_PORT//\'/}"

# --- 日志函数 ---
log(){
    # 日志文件大于 10MB 时自动清空
    if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt 10485760 ]; then
        > "$LOG_FILE"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Log file rotated." >> "$LOG_FILE"
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# --- 检查和守护 sing-box ---
check_singbox(){
    # 如果 sing-box 配置文件不存在，则认为未安装，直接跳过
    if [ ! -f "$SINGBOX_CONFIG_PATH" ]; then
        return
    fi

    if ! pgrep -f "$SINGBOX_PATH" >/dev/null; then
        log "🔄 [sing-box] Process not running, attempting to restart..."
        nohup "$SINGBOX_PATH" run -c "$SINGBOX_CONFIG_PATH" >> "$LOG_FILE" 2>&1 &
        sleep 2 # 等待启动
        if pgrep -f "$SINGBOX_PATH" >/dev/null; then
            log "✅ [sing-box] Restarted successfully."
        else
            log "❌ [sing-box] Failed to restart."
        fi
    fi
}

# --- 检查和守护 cloudflared (Argo Tunnel) ---
check_cloudflared(){
    # 如果 sing-box 未安装，或者没有选择安装 Argo (is_selected 2)，则跳过
    # 我们通过检查 ARGO_LOCAL_PORT 是否有值来判断
    if [ ! -f "$SINGBOX_CONFIG_PATH" ] || [ -z "$ARGO_LOCAL_PORT" ]; then
        return
    fi

    # 如果是临时隧道 (没有 token)，则无法守护，跳过
    if [ -z "$ARGO_TOKEN" ]; then
        return
    fi

    if ! pgrep -f "$CLOUDFLARED_PATH" >/dev/null; then
        log "🔄 [cloudflared] Process not running, attempting to restart..."
        
        # 确保配置文件存在
        cat > "$CLOUDFLARED_CONFIG_YML" <<EOF
log-level: info
ingress:
  - hostname: ${ARGO_DOMAIN}
    service: http://127.0.0.1:${ARGO_LOCAL_PORT}
  - service: http_status:404
EOF
        nohup "$CLOUDFLARED_PATH" tunnel --config "$CLOUDFLARED_CONFIG_YML" run --token "$ARGO_TOKEN" >> "$LOG_FILE" 2>&1 &
        sleep 2
        if pgrep -f "$CLOUDFLARED_PATH" >/dev/null; then
            log "✅ [cloudflared] Restarted successfully."
        else
            log "❌ [cloudflared] Failed to restart."
        fi
    fi
}

# --- 检查和守护 xray ---
check_xray( ){
    # 如果 xray 配置文件不存在，则认为未安装，直接跳过
    if [ ! -f "$XRAY_CONFIG_PATH" ]; then
        return
    fi

    # xray 是通过 systemd 管理的，所以我们检查 systemd 服务状态
    if ! systemctl is-active --quiet xray; then
        log "🔄 [xray] Service is not active, attempting to restart via systemctl..."
        systemctl restart xray
        sleep 2
        if systemctl is-active --quiet xray; then
            log "✅ [xray] Service restarted successfully via systemctl."
        else
            log "❌ [xray] Failed to restart service via systemctl."
        fi
    fi
}

# --- 每日重启任务 ---
daily_restart(){
    TODAY=$(date +%Y-%m-%d)

    if [ -f "$LAST_RESTART_FILE" ]; then
        LAST=$(cat "$LAST_RESTART_FILE")
    else
        LAST="none"
    fi

    if [ "$TODAY" != "$LAST" ]; then
        log "⏳ Daily restart triggered. Restarting all services..."
        
        # 重启 sing-box 和 cloudflared (如果已安装)
        if [ -f "$SINGBOX_CONFIG_PATH" ]; then
            pkill -f "$SINGBOX_PATH"
            pkill -f "$CLOUDFLARED_PATH"
        fi
        
        # 重启 xray (如果已安装)
        if [ -f "$XRAY_CONFIG_PATH" ]; then
            systemctl restart xray
        fi
        
        echo "$TODAY" > "$LAST_RESTART_FILE"
        log "✅ Daily restart completed."
        sleep 3 # 等待进程完全关闭
    fi
}

# --- 主循环 ---
log "🚀 Keep-alive script started. Monitoring services..."

while true; do
    # 每日重启检查优先
    daily_restart

    # 检查各个服务进程
    check_singbox
    check_cloudflared
    check_xray
    
    # 每 30 秒检查一次
    sleep 30
done
