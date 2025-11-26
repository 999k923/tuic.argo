#!/bin/sh

# ==============================================================================
# All-in-One TUIC & VLESS/VMess+Argo 管理脚本 (v2.1 - 修复 Argo 路径转发)
#
# 功能:
#   - install:   提供菜单选择安装 TUIC, VLESS/VMess+Argo, 或两者
#   - list:      显示已配置的节点信息
#   - start:     根据安装内容启动后台服务
#   - stop:      停止所有后台服务
#   - restart:   重启后台服务
#   - uninstall: 卸载并清理所有文件
#   - help:      显示此帮助菜单
#
# 使用:
#   首次安装: bash <(curl -Ls [URL]) install
#   后续管理: bash deploy.sh [command]
# ==============================================================================

# --- 颜色定义 ---
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_NC='\033[0m'

# --- 脚本常量 ---
HOME_DIR=$(eval echo ~)
AGSBX_DIR="$HOME_DIR/agsbx"
SINGBOX_PATH="$AGSBX_DIR/sing-box"
CLOUDFLARED_PATH="$AGSBX_DIR/cloudflared"
CONFIG_PATH="$AGSBX_DIR/sb.json"
CERT_PATH="$AGSBX_DIR/cert.pem"
KEY_PATH="$AGSBX_DIR/private.key"
VARS_PATH="$AGSBX_DIR/variables.conf"

# --- 辅助函数 ---

print_msg() {
    case "$2" in
        "red")    printf "${C_RED}%s${C_NC}\n" "$1" ;;
        "green")  printf "${C_GREEN}%s${C_NC}\n" "$1" ;;
        "yellow") printf "${C_YELLOW}%s${C_NC}\n" "$1" ;;
        "blue")   printf "${C_BLUE}%s${C_NC}\n" "$1" ;;
        *)        printf "%s\n" "$1" ;;
    esac
}

get_cpu_arch() {
    case "$(uname -m)" in
        "x86_64")   echo "amd64" ;;
        "aarch64")  echo "arm64" ;;
        *) print_msg "错误: 不支持的 CPU 架构 $(uname -m)" "red"; exit 1 ;;
    esac
}

download_file() {
    local url="$1"
    local dest="$2"
    print_msg "正在下载 $(basename "$dest")..." "yellow"
    if command -v curl >/dev/null 2>&1; then curl -# -Lo "$dest" "$url"; else wget -q --show-progress -O "$dest" "$url"; fi
    if [ $? -ne 0 ]; then print_msg "下载失败: $url" "red"; exit 1; fi
    chmod +x "$dest"
    print_msg "$(basename "$dest") 下载并设置权限成功。" "green"
}

get_server_ip() {
    if command -v curl >/dev/null 2>&1; then curl -s https://icanhazip.com; else wget -qO- https://icanhazip.com; fi
}

load_variables(  ) {
    if [ -f "$VARS_PATH" ]; then . "$VARS_PATH"; else return 1; fi
}

# --- 核心功能函数 ---

do_install() {
    print_msg "--- 节点安装向导 ---" "blue"
    print_msg "请选择您要安装的节点类型:" "yellow"
    print_msg "  1) 仅安装 TUIC"
    print_msg "  2) 仅安装 Argo 隧道 (VLESS 或 VMess)"
    print_msg "  3) 同时安装 TUIC 和 Argo 隧道"
    printf "${C_GREEN}请输入选项 [1-3]: ${C_NC}"; read -r INSTALL_CHOICE

    # 清理旧变量并准备新配置
    mkdir -p "$AGSBX_DIR"
    : > "$VARS_PATH" # 清空变量文件
    
    # 根据选择获取输入
    case "$INSTALL_CHOICE" in
        1) # 仅 TUIC
            print_msg "您选择了: 仅安装 TUIC" "green"
            printf "${C_GREEN}请输入 TUIC 端口 (例如 443): ${C_NC}"; read -r TUIC_PORT
            echo "INSTALL_TUIC=true" >> "$VARS_PATH"
            echo "TUIC_PORT=${TUIC_PORT}" >> "$VARS_PATH"
            ;;
        2) # 仅 Argo
            print_msg "您选择了: 仅安装 Argo 隧道" "green"
            echo "INSTALL_ARGO=true" >> "$VARS_PATH"
            ;;
        3) # 两者都安装
            print_msg "您选择了: 同时安装两者" "green"
            printf "${C_GREEN}请输入 TUIC 端口 (例如 443): ${C_NC}"; read -r TUIC_PORT
            echo "INSTALL_TUIC=true" >> "$VARS_PATH"
            echo "INSTALL_ARGO=true" >> "$VARS_PATH"
            echo "TUIC_PORT=${TUIC_PORT}" >> "$VARS_PATH"
            ;;
        *)
            print_msg "无效的选项，安装已取消。" "red"; exit 1 ;;
    esac

    if grep -q "INSTALL_ARGO=true" "$VARS_PATH"; then
        print_msg "\n--- 配置 Argo 隧道 ---" "blue"
        printf "${C_GREEN}Argo 隧道承载 VLESS 还是 VMess? [1 for VLESS, 2 for VMess]: ${C_NC}"; read -r ARGO_PROTOCOL_CHOICE
        if [ "$ARGO_PROTOCOL_CHOICE" = "1" ]; then
            echo "ARGO_PROTOCOL='vless'" >> "$VARS_PATH"
            printf "${C_GREEN}请输入 VLESS 本地监听端口 (例如 8080): ${C_NC}"; read -r ARGO_LOCAL_PORT
        else
            echo "ARGO_PROTOCOL='vmess'" >> "$VARS_PATH"
            printf "${C_GREEN}请输入 VMess 本地监听端口 (例如 8080): ${C_NC}"; read -r ARGO_LOCAL_PORT
        fi
        echo "ARGO_LOCAL_PORT=${ARGO_LOCAL_PORT}" >> "$VARS_PATH"

        printf "${C_GREEN}请输入 Argo Tunnel 的 Token (若使用临时隧道，请直接回车): ${C_NC}"; read -r ARGO_TOKEN
        if [ -n "$ARGO_TOKEN" ]; then
            printf "${C_GREEN}请输入 Argo Tunnel 对应的域名: ${C_NC}"; read -r ARGO_DOMAIN
        fi
        echo "ARGO_TOKEN='${ARGO_TOKEN}'" >> "$VARS_PATH"
        echo "ARGO_DOMAIN='${ARGO_DOMAIN}'" >> "$VARS_PATH"
    fi

    load_variables

    print_msg "\n--- 正在准备依赖环境 ---" "blue"
    local cpu_arch; cpu_arch=$(get_cpu_arch)
    if [ "$INSTALL_TUIC" = "true" ] || [ "$INSTALL_ARGO" = "true" ]; then
        if [ ! -f "$SINGBOX_PATH" ]; then
            local singbox_url="https://github.com/SagerNet/sing-box/releases/download/v1.9.0-beta.13/sing-box-1.9.0-beta.13-linux-${cpu_arch}.tar.gz"
            local temp_tar_path="$AGSBX_DIR/sing-box.tar.gz"
            download_file "$singbox_url" "$temp_tar_path"
            tar -xzf "$temp_tar_path" -C "$AGSBX_DIR"
            mv "$AGSBX_DIR/sing-box-1.9.0-beta.13-linux-${cpu_arch}/sing-box" "$SINGBOX_PATH"
            rm -f "$temp_tar_path"; rm -rf "$AGSBX_DIR/sing-box-1.9.0-beta.13-linux-${cpu_arch}"
        fi
    fi
    if [ "$INSTALL_ARGO" = "true" ]; then
        if [ ! -f "$CLOUDFLARED_PATH" ]; then
            local cloudflared_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cpu_arch}"
            download_file "$cloudflared_url" "$CLOUDFLARED_PATH"
        fi
    fi

    print_msg "\n--- 正在生成配置文件 ---" "blue"
    local UUID; UUID=$($SINGBOX_PATH generate uuid  )
    echo "UUID='${UUID}'" >> "$VARS_PATH"
    print_msg "生成的 UUID: $UUID" "yellow"

    if [ "$INSTALL_TUIC" = "true" ]; then
        if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
            openssl ecparam -genkey -name prime256v1 -out "$KEY_PATH" >/dev/null 2>&1
            openssl req -new -x509 -days 36500 -key "$KEY_PATH" -out "$CERT_PATH" -subj "/CN=www.bing.com" >/dev/null 2>&1
        fi
    fi

    local inbounds=""
    if [ "$INSTALL_TUIC" = "true" ]; then
        inbounds=$(printf '{"type": "tuic", "tag": "tuic-in", "listen": "::", "listen_port": %s, "users": [{"uuid": "%s", "password": "%s"}], "congestion_control": "bbr", "tls": {"enabled": true, "server_name": "www.bing.com", "alpn": ["h3"], "certificate_path": "%s", "key_path": "%s"}}' "$TUIC_PORT" "$UUID" "$UUID" "$CERT_PATH" "$KEY_PATH")
    fi
    
    if [ "$INSTALL_ARGO" = "true" ]; then
        if [ -n "$inbounds" ]; then inbounds="$inbounds,"; fi
        
        if [ "$ARGO_PROTOCOL" = "vless" ]; then
            inbounds="$inbounds$(printf '{"type": "vless", "tag": "vless-in", "listen": "127.0.0.1", "listen_port": %s, "users": [{"uuid": "%s", "flow": "xtls-rprx-vision"}], "transport": {"type": "ws", "path": "/%s-vl"}}' "$ARGO_LOCAL_PORT" "$UUID" "$UUID")"
        else
            inbounds="$inbounds$(printf '{"type": "vmess", "tag": "vmess-in", "listen": "127.0.0.1", "listen_port": %s, "users": [{"uuid": "%s", "alterId": 0}], "transport": {"type": "ws", "path": "/%s-vm"}}' "$ARGO_LOCAL_PORT" "$UUID" "$UUID")"
        fi
    fi

    cat > "$CONFIG_PATH" <<EOF
{
    "log": {"level": "info", "timestamp": true},
    "inbounds": [ ${inbounds} ],
    "outbounds": [{"type": "direct", "tag": "direct"}]
}
EOF
    print_msg "配置文件创建成功。" "green"
    do_start
}

do_list() {
    print_msg "--- 显示节点信息 ---" "blue"
    if ! load_variables; then print_msg "错误: 未找到配置文件。请先执行 'install' 命令。" "red"; exit 1; fi

    local server_ip; server_ip=$(get_server_ip)
    local hostname; hostname=$(hostname)
    print_msg "\n🎉 节点信息如下：\n" "blue"

    if [ "$INSTALL_TUIC" = "true" ]; then
        local tuic_params="congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=www.bing.com&allow_insecure=1"
        local tuic_link="tuic://${UUID}:${UUID}@${server_ip}:${TUIC_PORT}?${tuic_params}#tuic-${hostname}"
        print_msg "--- TUIC 节点 ---" "yellow"
        echo "$tuic_link"
    fi

    if [ "$INSTALL_ARGO" = "true" ]; then
        local current_argo_domain="$ARGO_DOMAIN"
        if [ -z "$ARGO_TOKEN" ]; then
            print_msg "正在等待临时 Argo 域名生成..." "yellow"; sleep 5
            local temp_argo_domain; temp_argo_domain=$(grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare\.com' "$AGSBX_DIR/argo.log" | sed 's/https:\/\///' | head -n 1  )
            if [ -z "$temp_argo_domain" ]; then
                print_msg "无法自动获取临时 Argo 域名，请检查日志: $AGSBX_DIR/argo.log" "red"
                current_argo_domain="[请从日志中手动查找域名]"
            else
                current_argo_domain=$temp_argo_domain
            fi
        fi

        if [ "$ARGO_PROTOCOL" = "vless" ]; then
            local vless_link="vless://${UUID}@${current_argo_domain}:443?encryption=none&security=tls&sni=${current_argo_domain}&fp=chrome&type=ws&host=${current_argo_domain}&path=%2f${UUID}-vl#argo-vless-${hostname}"
            print_msg "\n--- VLESS + Argo (TLS) 节点 ---" "yellow"
            echo "$vless_link"
        else
            local vmess_json; vmess_json=$(printf '{"v":"2","ps":"vmess-argo-%s","add":"%s","port":"443","id":"%s","aid":"0","scy":"auto","net":"ws","type":"none","host":"%s","path":"/%s-vm","tls":"tls","sni":"%s"}' "$hostname" "$current_argo_domain" "$UUID" "$current_argo_domain" "$UUID" "$current_argo_domain")
            local vmess_base64; vmess_base64=$(echo "$vmess_json" | tr -d '\n' | base64 -w0)
            local vmess_link="vmess://${vmess_base64}"
            print_msg "\n--- VMess + Argo (TLS) 节点 ---" "yellow"
            echo "$vmess_link"
        fi
    fi
}

do_start() {
    print_msg "--- 启动服务 ---" "blue"
    if ! load_variables; then print_msg "错误: 未找到配置文件。请先执行 'install' 命令。" "red"; exit 1; fi
    do_stop # 先停止，避免重复启动
    
    if [ "$INSTALL_TUIC" = "true" ] || [ "$INSTALL_ARGO" = "true" ]; then
        nohup "$SINGBOX_PATH" run -c "$CONFIG_PATH" > "$AGSBX_DIR/sing-box.log" 2>&1 &
        print_msg "sing-box 服务已在后台启动。" "green"
    fi
    
    if [ "$INSTALL_ARGO" = "true" ]; then
        if [ -n "$ARGO_TOKEN" ]; then
            # 对于固定 Token，使用 --url 参数同样有效，且更简单
            nohup "$CLOUDFLARED_PATH" tunnel --no-autoupdate --url "http://127.0.0.1:${ARGO_LOCAL_PORT}" run --token "$ARGO_TOKEN" > "$AGSBX_DIR/argo.log" 2>&1 &
        else
            # 对于临时隧道
            nohup "$CLOUDFLARED_PATH" tunnel --url "http://127.0.0.1:${ARGO_LOCAL_PORT}" > "$AGSBX_DIR/argo.log" 2>&1 &
            print_msg "临时隧道将在几秒后建立..." "yellow"
        fi
        print_msg "cloudflared 服务已在后台启动 。" "green"
    fi
}

do_stop() {
    print_msg "--- 停止服务 ---" "blue"
    pkill -f "$SINGBOX_PATH"
    pkill -f "$CLOUDFLARED_PATH"
    print_msg "所有相关服务已停止。" "green"
}

do_restart() {
    print_msg "--- 重启服务 ---" "blue"
    do_stop; sleep 1; do_start
}

do_uninstall() {
    print_msg "--- 开始卸载 ---" "red"
    printf "${C_YELLOW}警告: 这将删除所有相关文件和配置。确定吗? (y/n): ${C_NC}"; read -r confirmation
    if [ "$confirmation" != "y" ]; then print_msg "卸载已取消。" "green"; exit 0; fi
    do_stop
    rm -rf "$AGSBX_DIR"
    if [ -f "deploy.sh" ]; then rm -f "deploy.sh"; fi
    print_msg "卸载完成。" "green"
}

show_help() {
    print_msg "All-in-One TUIC & VLESS/VMess+Argo 管理脚本" "blue"
    echo "----------------------------------------"
    print_msg "用法: bash $0 [命令]"
    echo
    print_msg "可用命令:" "yellow"
    print_msg "  install    - 显示安装菜单，可选择安装 TUIC, VLESS/VMess+Argo, 或两者"
    print_msg "  list       - 显示已配置的节点信息"
    print_msg "  start      - 根据安装内容启动后台服务"
    print_msg "  stop       - 停止所有后台服务"
    print_msg "  restart    - 重启后台服务"
    print_msg "  uninstall  - 卸载并清理所有文件"
    print_msg "  help       - 显示此帮助菜单"
    echo
}

# --- 脚本主入口 ---
main() {
    # 如果脚本是通过 curl 执行的，自动设为 install
    if [ ! -t 0 ]; then
        do_install
    elif [ -z "$1" ]; then
        show_help
    else
        case "$1" in
            install)   do_install ;;
            list)      do_list ;;
            start)     do_start ;;
            stop)      do_stop ;;
            restart)   do_restart ;;
            uninstall) do_uninstall ;;
            help|*)    show_help ;;
        esac
    fi
}

main "$@"
