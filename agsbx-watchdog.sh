#!/bin/bash

# ===============================
# 通用 watchdog 脚本：TUIC + Argo
# ===============================

AGSBX="$HOME/agsbx"

# TUIC (sing-box)
SINGBOX="$AGSBX/sing-box"
CONFIG="$AGSBX/sb.json"
LOG="$AGSBX/sing-box.log"

# Argo 隧道 (cloudflared)
CLOUDFLARED="$AGSBX/cloudflared"
ARGO_CONFIG="$AGSBX/config.yml"
ARGO_LOG="$AGSBX/argo.log"

# 循环检测函数
check_and_start() {
    local name="$1"
    local cmd="$2"
    local log="$3"

    if [ -x "$cmd" ]; then
        if ! pgrep -f "$cmd" >/dev/null; then
            echo "$(date) : $name not running, starting..." >> "$log"
            nohup "$cmd" >> "$log" 2>&1 &
        fi
    fi
}

# 主循环
while true; do
    # TUIC 保活
    check_and_start "sing-box" "$SINGBOX run -c $CONFIG" "$LOG"

    # Argo 隧道保活
    check_and_start "cloudflared" "$CLOUDFLARED tunnel --config $ARGO_CONFIG run" "$ARGO_LOG"

    sleep 5
done
