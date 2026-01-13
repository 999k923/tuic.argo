#!/usr/bin/env bash
# ======================================================================
#        Docker Proxy Manager (managedocker.sh)
#   使用环境变量选择节点与端口，非交互式安装
# ======================================================================

set -euo pipefail

C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_NC='\033[0m'

MANAGER_DIR=$(dirname "$(readlink -f "$0")")
SING_SCRIPT_PATH="${MANAGER_DIR}/singdocker.sh"
XRAY_SCRIPT_PATH="${MANAGER_DIR}/xdocker.sh"
STATUS_FILE="${MANAGER_DIR}/install_status_docker.conf"
DOCKER_MODE="${DOCKER_MODE:-1}"

touch "$STATUS_FILE" 2>/dev/null

print_msg() {
    case "$2" in
        red)    printf "${C_RED}%s\n" "$1";;
        green)  printf "${C_GREEN}%s\n" "$1";;
        yellow) printf "${C_YELLOW}%s\n" "$1";;
        blue)   printf "${C_BLUE}%s\n" "$1";;
        *)      printf "%s\n" "$1";;
    esac
}

is_true() {
    local value="${1:-}"
    case "${value,,}" in
        true|1|1true|1ture|yes|y) return 0 ;;
        *) return 1 ;;
    esac
}

is_sing_installed() {
    [ -f "$STATUS_FILE" ] && grep -q "SING_INSTALLED=true" "$STATUS_FILE"
}

is_xray_installed() {
    [ -f "$STATUS_FILE" ] && grep -q "XRAY_INSTALLED=true" "$STATUS_FILE"
}

ensure_scripts_exist() {
    if [ ! -f "$SING_SCRIPT_PATH" ] || [ ! -f "$XRAY_SCRIPT_PATH" ]; then
        print_msg "错误: singdocker.sh 或 xdocker.sh 脚本未在同一目录下找到。" red
        exit 1
    fi
}

apply_port_env() {
    if [ -n "${PORT1:-}" ]; then export TUIC_PORT="$PORT1"; fi
    if [ -n "${PORT2:-}" ]; then export ARGO_LOCAL_PORT="$PORT2"; fi
    if [ -n "${PORT3:-}" ]; then export ANYTLS_PORT="$PORT3"; fi
    if [ -n "${PORT4:-}" ]; then export XRAY_PORT="$PORT4"; fi

    if is_true "${NODE1:-}" && [ -z "${TUIC_PORT:-}" ]; then
        export TUIC_PORT="443"
    fi
    if is_true "${NODE2:-}" && [ -z "${ARGO_LOCAL_PORT:-}" ]; then
        export ARGO_LOCAL_PORT="8080"
    fi
    if is_true "${NODE3:-}" && [ -z "${ANYTLS_PORT:-}" ]; then
        export ANYTLS_PORT="443"
    fi
    if is_true "${NODE4:-}" && [ -z "${XRAY_PORT:-}" ]; then
        export XRAY_PORT="8443"
    fi
}

validate_env() {
    if is_true "${NODE3:-}"; then
        if [ -z "${CF_EMAIL:-}" ] || [ -z "${CF_API_KEY:-}" ] || [ -z "${ANYTLS_DOMAIN:-}" ]; then
            print_msg "启用 AnyTLS 时必须设置 CF_EMAIL、CF_API_KEY、ANYTLS_DOMAIN。" red
            exit 1
        fi
    fi

    if is_true "${NODE4:-}" && [ -z "${XRAY_SNI:-}" ]; then
        print_msg "启用 Reality 节点时必须设置 XRAY_SNI。" red
        exit 1
    fi
}

build_sing_choices() {
    local choices=()
    if is_true "${NODE1:-}"; then choices+=("1"); fi
    if is_true "${NODE2:-}"; then choices+=("2"); fi
    if is_true "${NODE3:-}"; then choices+=("3"); fi
    if [ ${#choices[@]} -eq 0 ]; then
        echo ""
        return
    fi
    (IFS=,; echo "${choices[*]}")
}

do_install() {
    ensure_scripts_exist
    export DOCKER_MODE=1

    apply_port_env
    validate_env

    local sing_choices
    sing_choices=$(build_sing_choices)

    if [ -n "$sing_choices" ]; then
        print_msg "--- 即将调用 singdocker.sh 进行安装 (选项: ${sing_choices}) ---" blue
        bash "$SING_SCRIPT_PATH" install_from_manager "$sing_choices"
        grep -q "SING_INSTALLED=true" "$STATUS_FILE" || echo "SING_INSTALLED=true" >> "$STATUS_FILE"
    fi

    if is_true "${NODE4:-}"; then
        print_msg "--- 即将调用 xdocker.sh 进行安装 ---" blue
        bash "$XRAY_SCRIPT_PATH"
        grep -q "XRAY_INSTALLED=true" "$STATUS_FILE" || echo "XRAY_INSTALLED=true" >> "$STATUS_FILE"
    fi

    if [ -z "$sing_choices" ] && ! is_true "${NODE4:-}"; then
        print_msg "未选择任何节点，请设置 NODE1/NODE2/NODE3/NODE4。" red
        exit 1
    fi

    print_msg "\n--- 安装完成，输出节点信息 ---" blue
    do_list
}

do_list() {
    if is_sing_installed; then
        print_msg "\n--- singdocker.sh (TUIC/Argo/AnyTLS) 节点信息 ---" yellow
        bash "$SING_SCRIPT_PATH" list
    fi
    if is_xray_installed; then
        print_msg "\n--- xdocker.sh (Reality) 节点信息 ---" yellow
        bash "$XRAY_SCRIPT_PATH" show-uri
    fi
    if ! is_sing_installed && ! is_xray_installed; then
        print_msg "未发现任何已安装的节点。请先执行安装。" red
    fi
}

do_start() {
    if is_sing_installed; then bash "$SING_SCRIPT_PATH" start; fi
    if is_xray_installed; then bash "$XRAY_SCRIPT_PATH" start; fi
}

do_stop() {
    if is_sing_installed; then bash "$SING_SCRIPT_PATH" stop; fi
    if is_xray_installed; then bash "$XRAY_SCRIPT_PATH" stop; fi
}

show_help() {
    print_msg "Docker Proxy Manager" blue
    echo "用法: bash $0 [命令]"
    echo ""
    echo "核心命令:"
    echo "  install    - 根据环境变量安装节点"
    echo "  list       - 显示所有已安装节点的分享链接"
    echo "  start      - 启动所有已安装的节点服务"
    echo "  stop       - 停止所有已安装的节点服务"
    echo "  run        - 安装并启动服务 (适合容器 ENTRYPOINT)"
    echo "  help       - 显示此帮助信息"
}

case "${1:-}" in
    install)   do_install ;;
    list)      do_list ;;
    start)     do_start ;;
    stop)      do_stop ;;
    run)       do_install; do_start; tail -f /dev/null ;;
    help|*)    show_help ;;
esac
