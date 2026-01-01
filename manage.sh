#!/usr/bin/env bash
# ======================================================================
#            All-in-One Proxy Manager (manage.sh)
#         统一管理 sing.sh (TUIC/Argo) 和 x.sh (Reality)
# ======================================================================

# --- 颜色 ---
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_NC='\033[0m'

# --- 常量 ---
MANAGER_DIR=$(dirname "$(readlink -f "$0")")
SING_SCRIPT_PATH="${MANAGER_DIR}/sing.sh"
XRAY_SCRIPT_PATH="${MANAGER_DIR}/x.sh"
STATUS_FILE="${MANAGER_DIR}/install_status.conf"

# --- 辅助函数 ---
print_msg() {
    case "$2" in
        red)    printf "${C_RED}%s\n" "$1";;
        green)  printf "${C_GREEN}%s\n" "$1";;
        yellow) printf "${C_YELLOW}%s\n" "$1";;
        blue)   printf "${C_BLUE}%s\n" "$1";;
        *)      printf "%s\n" "$1";;
    esac
}

# 检查 sing.sh 是否被安装过
is_sing_installed() {
    [ -f "$STATUS_FILE" ] && grep -q "SING_INSTALLED=true" "$STATUS_FILE"
}

# 检查 x.sh 是否被安装过
is_xray_installed() {
    [ -f "$STATUS_FILE" ] && grep -q "XRAY_INSTALLED=true" "$STATUS_FILE"
}

# --- 核心功能 ---
do_install() {
    print_msg "--- 节点统一安装向导 ---" blue
    print_msg "请选择您要安装的节点类型 (支持多选，如输入 1,4 或 1,2,4):" yellow
    print_msg "--- sing-box (sing.sh) ---"
    print_msg "  1) 安装 TUIC"
    print_msg "  2) 安装 Argo 隧道 (VLESS 或 VMess)"
    print_msg "  3) 安装 AnyTLS (使用 CF 证书)"
    print_msg "--- Xray (x.sh) ---"
    print_msg "  4) 安装 VLESS + Vision + Reality"
    read -rp "$(printf "${C_GREEN}请输入选项: ${C_NC}")" INSTALL_CHOICE

    INSTALL_CHOICE=$(echo "$INSTALL_CHOICE" | tr -d ' ' | tr '，' ',')

    # 分离选项给 sing.sh 和 x.sh
    SING_CHOICES=$(echo "$INSTALL_CHOICE" | tr ',' '\n' | grep -E '^[1-3]$' | tr '\n' ',' | sed 's/,$//')
    XRAY_CHOICES=$(echo "$INSTALL_CHOICE" | tr ',' '\n' | grep -E '^4$' | tr '\n' ',' | sed 's/,$//')

    if [ -z "$SING_CHOICES" ] && [ -z "$XRAY_CHOICES" ]; then
        print_msg "无效选项，请输入 1, 2, 3, 4 中的一个或多个（用逗号分隔）。" red
        exit 1
    fi

    # 执行 sing.sh 安装
    if [ -n "$SING_CHOICES" ]; then
        print_msg "\n--- 即将调用 sing.sh 进行安装 (选项: ${SING_CHOICES}) ---" blue
        bash "$SING_SCRIPT_PATH" install_from_manager "${SING_CHOICES}"
        if [ $? -eq 0 ]; then
            echo "SING_INSTALLED=true" >> "$STATUS_FILE"
            print_msg "sing.sh 安装部分完成。" green
        else
            print_msg "sing.sh 安装失败。" red
        fi
    fi

    # 执行 x.sh 安装
    if [ -n "$XRAY_CHOICES" ]; then
        print_msg "\n--- 即将调用 x.sh 进行安装 ---" blue
        bash "$XRAY_SCRIPT_PATH"
        if [ $? -eq 0 ]; then
            echo "XRAY_INSTALLED=true" >> "$STATUS_FILE"
            print_msg "x.sh 安装部分完成。" green
        else
            print_msg "x.sh 安装失败。" red
        fi
    fi

    print_msg "\n🎉 所有选择的安装任务已执行完毕。" green
}

do_list() {
    print_msg "--- 显示所有已安装节点信息 ---" blue
    if is_sing_installed; then
        print_msg "\n--- sing.sh (TUIC/Argo) 节点信息 ---" yellow
        bash "$SING_SCRIPT_PATH" list
    fi
    if is_xray_installed; then
        print_msg "\n--- x.sh (Reality) 节点信息 ---" yellow
        bash "$XRAY_SCRIPT_PATH" show-uri
    fi
    if ! is_sing_installed && ! is_xray_installed; then
        print_msg "未发现任何已安装的节点。请先执行安装。" red
    fi
}

do_start() {
    print_msg "--- 启动所有已安装服务 ---" blue
    if is_sing_installed; then bash "$SING_SCRIPT_PATH" start; fi
    if is_xray_installed; then bash "$XRAY_SCRIPT_PATH" start; fi
}

do_stop() {
    print_msg "--- 停止所有已安装服务 ---" blue
    if is_sing_installed; then bash "$SING_SCRIPT_PATH" stop; fi
    if is_xray_installed; then bash "$XRAY_SCRIPT_PATH" stop; fi
}

do_restart() {
    print_msg "--- 重启所有已安装服务 ---" blue
    if is_sing_installed; then bash "$SING_SCRIPT_PATH" restart; fi
    if is_xray_installed; then bash "$XRAY_SCRIPT_PATH" restart; fi
}

do_uninstall() {
    read -rp "$(printf "${C_YELLOW}⚠️ 确认卸载所有节点？将删除所有相关文件 (y/n): ${C_NC}")" confirm
    [ "$confirm" != "y" ] && print_msg "取消卸载" green && exit 0
    
    print_msg "--- 卸载所有节点 ---" blue
    if is_sing_installed; then bash "$SING_SCRIPT_PATH" uninstall; fi
    if is_xray_installed; then bash "$XRAY_SCRIPT_PATH" uninstall; fi
    
    rm -f "$STATUS_FILE"
    print_msg "✅ 所有节点卸载完成。" green
}

show_help() {
    print_msg "All-in-One Proxy Manager" blue
    echo "用法: bash $0 [命令]"
    echo ""
    echo "核心命令:"
    echo "  install    - 显示交互式菜单，安装一个或多个节点方案"
    echo "  list       - 显示所有已安装节点的分享链接"
    echo "  start      - 启动所有已安装的节点服务"
    echo "  stop       - 停止所有已安装的节点服务"
    echo "  restart    - 重启所有已安装的节点服务"
    echo "  uninstall  - 卸载所有通过此脚本安装的节点和文件"
    echo "  help       - 显示此帮助信息"
}

# --- 主逻辑 ---
# 确保脚本存在
if [ ! -f "$SING_SCRIPT_PATH" ] || [ ! -f "$XRAY_SCRIPT_PATH" ]; then
    print_msg "错误: sing.sh 或 x.sh 脚本未在同一目录下找到。" red
    exit 1
fi

case "$1" in
    install)   do_install ;;
    list)      do_list ;;
    start)     do_start ;;
    stop)      do_stop ;;
    restart)   do_restart ;;
    uninstall) do_uninstall ;;
    help|*)    show_help ;;
esac
