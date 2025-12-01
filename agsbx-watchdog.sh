#!/bin/bash

# 节点可执行路径
SINGBOX="$HOME/agsbx/sing-box"
CONFIG="$HOME/agsbx/sb.json"
LOG="$HOME/agsbx/sing-box.log"

# 循环检测
while true; do
    if ! pgrep -f "$SINGBOX" >/dev/null; then
        echo "$(date) : sing-box not running, starting..." >> "$LOG"
        nohup "$SINGBOX" run -c "$CONFIG" >> "$LOG" 2>&1 &
    fi
    sleep 5
done
