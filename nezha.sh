#!/usr/bin/env bash

set -euo pipefail

C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_NC='\033[0m'

print_msg() {
    case "$2" in
        red)    printf "${C_RED}%s\n" "$1";;
        green)  printf "${C_GREEN}%s\n" "$1";;
        yellow) printf "${C_YELLOW}%s\n" "$1";;
        blue)   printf "${C_BLUE}%s\n" "$1";;
        *)      printf "%s\n" "$1";;
    esac
}

get_cpu_arch() {
    case "$(uname -m)" in
        x86_64) echo "amd64";;
        aarch64) echo "arm64";;
        *) print_msg "错误: 不支持的 CPU 架构 $(uname -m)" red; exit 1;;
    esac
}

download_file() {
    local url="$1"
    local dest="$2"
    if [ -x "$dest" ]; then
        return 0
    fi
    print_msg "正在下载 $(basename "$dest")..." yellow
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$dest" "$url"
    else
        wget -q -O "$dest" "$url"
    fi
    chmod +x "$dest"
    print_msg "$(basename "$dest") 下载完成。" green
}

is_tls_port() {
    local p="$1"
    case "$p" in
        443|8443|2096|2087|2083|2053) return 0 ;;
        *) return 1 ;;
    esac
}

install_nezha_v1() {
    if [ -z "${NEZHA_SERVER:-}" ] || [ -z "${NEZHA_KEY:-}" ]; then
        print_msg "[Nezha] 未配置 NEZHA_SERVER/NEZHA_KEY，跳过安装。" yellow
        return 0
    fi

    if [ -n "${NEZHA_PORT:-}" ]; then
        print_msg "[Nezha] 检测到 NEZHA_PORT（V0 参数），已忽略，仅运行 V1。" yellow
    fi

    local arch
    arch="$(get_cpu_arch)"
    local base_url="https://${arch}.ssss.nyc.mn"

    local nezha_dir="$HOME/agsbx"
    mkdir -p "$nezha_dir"

    local uuid_file="${nezha_dir}/uuid.txt"
    local uuid
    if [ -f "$uuid_file" ]; then
        uuid=$(cat "$uuid_file")
    else
        uuid=$(cat /proc/sys/kernel/random/uuid)
        echo "$uuid" > "$uuid_file"
    fi

    local nezha_bin="${nezha_dir}/nezha-agent"
    local nezha_cfg="${nezha_dir}/nezha.yaml"
    local nezha_log="${nezha_dir}/nezha.log"

    local port=""
    if [[ "$NEZHA_SERVER" == *:* ]]; then
        port="${NEZHA_SERVER##*:}"
    fi

    local tls="false"
    if [ -n "$port" ] && is_tls_port "$port"; then
        tls="true"
    fi

    download_file "${base_url}/v1" "$nezha_bin"

    cat > "$nezha_cfg" <<EOF
client_secret: ${NEZHA_KEY}
debug: false
disable_auto_update: true
disable_command_execute: false
disable_force_update: true
disable_nat: false
disable_send_query: false
gpu: false
insecure_tls: false
ip_report_period: 1800
report_delay: 4
server: ${NEZHA_SERVER}
skip_connection_count: false
skip_procs_count: false
temperature: false
tls: ${tls}
use_gitee_to_upgrade: false
use_ipv6_country_code: false
uuid: ${uuid}
EOF

    print_msg "[Nezha] 启动 V1 agent（tls=${tls}）..." blue
    nohup "$nezha_bin" -c "$nezha_cfg" >"$nezha_log" 2>&1 &
    local nezha_pid=$!
    sleep 1

    if ! kill -0 "$nezha_pid" 2>/dev/null; then
        print_msg "[Nezha] 启动失败，最近日志：" red
        tail -n 80 "$nezha_log" || true
        return 0
    fi

    print_msg "[Nezha] 已启动 PID: $nezha_pid" green
}

install_nezha_v1
