#!/bin/bash
# ======================================================================
# agsbx-watchdog.sh - sing-box & cloudflared 保活脚本 (兼容 Alpine & Ubuntu)
# ======================================================================

AGSBX_DIR="$HOME/agsbx"
SINGBOX_PATH="$AGSBX_DIR/sing-box"
CLOUDFLARED_PATH="$AGSBX_DIR/cloudflared"
CONFIG_PATH="$AGSBX_DIR/sb.json"
VARS_PATH="$AGSBX_DIR/variables.conf"
LOG_FILE="$AGSBX_DIR/watchdog.log"

print_msg() {
    local msg="$1"
    echo "$(date '+%F %T') $msg" | tee -a "$LOG_FILE"
}

is_running() {
    local cmd="$1"
    pgrep -f "$cmd" >/dev/null 2>&1
}

start_services() {
    # 加载变量
    [ -f "$VARS_PATH" ] && . "$VARS_PATH"

    # 启动 sing-box
    if ! is_running "$SINGBOX_PATH"; then
        nohup "$SINGBOX_PATH" run -c "$CONFIG_PATH" >> "$LOG_FILE" 2>&1 &
        print_msg "sing-box 已启动"
    fi

    # 启动 cloudflared
    if [[ "$INSTALL_CHOICE" =~ ^(2|3)$ ]]; then
        if ! is_running "$CLOUDFLARED_PATH"; then
            if [ -n "$ARGO_TOKEN" ]; then
                cat > "$AGSBX_DIR/config.yml" <<EOF
log-level: info
ingress:
  - hostname: ${ARGO_DOMAIN}
    service: http://127.0.0.1:${ARGO_LOCAL_PORT}
  - service: http_status:404
EOF
                nohup "$CLOUDFLARED_PATH" tunnel --config "$AGSBX_DIR/config.yml" run --token "$ARGO_TOKEN" >> "$LOG_FILE" 2>&1 &
            else
                nohup "$CLOUDFLARED_PATH" tunnel --url "http://127.0.0.1:${ARGO_LOCAL_PORT}" >> "$LOG_FILE" 2>&1 &
            fi
            print_msg "cloudflared 已启动"
        fi
    fi
}

# 检测系统类型
detect_os() {
    if [ -f /etc/alpine-release ]; then
        OS_TYPE="alpine"
    elif [ -f /etc/lsb-release ] || [ -f /etc/os-release ]; then
        OS_TYPE="ubuntu"
    else
        OS_TYPE="unknown"
    fi
    echo "$OS_TYPE"
}

# 设置开机自启
setup_autostart() {
    os=$(detect_os)
    if [ "$os" = "ubuntu" ]; then
        SERVICE_FILE="/etc/systemd/system/agsbx-watchdog.service"
        sudo tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=Sing-box & Cloudflared Watchdog
After=network.target

[Service]
Type=simple
User=$USER
ExecStart=$HOME/agsbx-watchdog.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        sudo systemctl daemon-reload
        sudo systemctl enable agsbx-watchdog
        sudo systemctl start agsbx-watchdog
        print_msg "systemd 服务已创建并启动"
    elif [ "$os" = "alpine" ]; then
        INIT_FILE="/etc/init.d/agsbx-watchdog"
        sudo tee "$INIT_FILE" >/dev/null <<'EOF'
#!/sbin/openrc-run
description="Sing-box & Cloudflared Watchdog"

command="$HOME/agsbx-watchdog.sh"
command_background="yes"
pidfile="/run/agsbx-watchdog.pid"
name="agsbx-watchdog"
EOF
        sudo chmod +x "$INIT_FILE"
        sudo rc-update add agsbx-watchdog default
        sudo rc-service agsbx-watchdog start
        print_msg "OpenRC 服务已创建并启动"
    else
        print_msg "未知系统类型，无法自动配置开机启动" red
    fi
}

# 主循环
start_watchdog() {
    print_msg "启动 watchdog 保活进程..."
    while true; do
        start_services
        sleep 10
    done
}

# 启动保活并设置开机自启
setup_autostart
start_watchdog
