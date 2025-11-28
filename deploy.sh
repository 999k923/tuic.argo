#!/bin/bash

# ===================================================================
# All-in-One TUIC & VLESS/VMess+Argo 管理脚本 v3.5
# 主要改进：
# 1. 自动生成 TLS 证书，避免启动失败
# 2. 安装完成后自动显示节点信息
# 3. 支持 IPv6 节点显示
# ===================================================================

# --- 颜色定义 ---
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_NC='\033[0m'

# --- 常量路径 ---
HOME_DIR=$(eval echo ~)
AGSBX_DIR="$HOME_DIR/agsbx"
SINGBOX_PATH="$AGSBX_DIR/sing-box"
CLOUDFLARED_PATH="$AGSBX_DIR/cloudflared"
CONFIG_PATH="$AGSBX_DIR/sb.json"
CERT_PATH="$AGSBX_DIR/cert.pem"
KEY_PATH="$AGSBX_DIR/private.key"
VARS_PATH="$AGSBX_DIR/variables.conf"

# --- 输出信息 ---
print_msg() {
    case "$2" in
        red)    printf "${C_RED}%s\n" "$1" ;;
        green)  printf "${C_GREEN}%s\n" "$1" ;;
        yellow) printf "${C_YELLOW}%s\n" "$1" ;;
        blue)   printf "${C_BLUE}%s\n" "$1" ;;
        *)      printf "%s\n" "$1" ;;
    esac
}

# --- CPU 架构 ---
get_cpu_arch() {
    case "$(uname -m)" in
        x86_64) echo "amd64" ;;
        aarch64) echo "arm64" ;;
        *) print_msg "错误: 不支持的 CPU 架构 $(uname -m)" "red"; exit 1 ;;
    esac
}

# --- 下载工具 ---
download_file() {
    local url="$1"
    local dest="$2"
    print_msg "正在下载 $(basename "$dest")..." "yellow"
    if command -v curl >/dev/null 2>&1; then curl -# -Lo "$dest" "$url"; else wget -q --show-progress -O "$dest" "$url"; fi
    if [ $? -ne 0 ]; then print_msg "下载失败: $url" "red"; exit 1; fi
    chmod +x "$dest"
    print_msg "$(basename "$dest") 下载成功。" "green"
}

# --- 获取服务器 IPv4/IPv6 ---
get_server_ip4() { curl -s https://icanhazip.com; }
get_server_ip6() { curl -s https://icanhazip.com -6; }

# --- 读取变量 ---
load_variables() {
    if [ -f "$VARS_PATH" ]; then . "$VARS_PATH"; else return 1; fi
}

# --- 自动生成 TLS 证书 ---
prepare_tls() {
    mkdir -p "$AGSBX_DIR"
    if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
        print_msg "检测不到 TLS 证书，正在生成..." "yellow"
        openssl ecparam -genkey -name prime256v1 -out "$KEY_PATH"
        openssl req -new -x509 -days 36500 -key "$KEY_PATH" -out "$CERT_PATH" -subj "/CN=www.bing.com"
        print_msg "TLS 证书生成成功。" "green"
    fi
}

# --- 安装函数 ---
do_install() {
    print_msg "--- 节点安装向导 ---" "blue"
    print_msg "请选择要安装的节点类型:" "yellow"
    print_msg " 1) 仅安装 TUIC"
    print_msg " 2) 仅安装 Argo 隧道 (VLESS 或 VMess)"
    print_msg " 3) 同时安装 TUIC 和 Argo 隧道"
    printf "${C_GREEN}请输入选项 [1-3]: ${C_NC}"; read -r INSTALL_CHOICE

    mkdir -p "$AGSBX_DIR"
    : > "$VARS_PATH"

    # TUIC
    if [ "$INSTALL_CHOICE" = "1" ] || [ "$INSTALL_CHOICE" = "3" ]; then
        printf "${C_GREEN}请输入 TUIC 端口 (默认 443): ${C_NC}"; read -r TUIC_PORT
        TUIC_PORT=${TUIC_PORT:-443}
        echo "TUIC_PORT=${TUIC_PORT}" >> "$VARS_PATH"
    fi

    # Argo
    if [ "$INSTALL_CHOICE" = "2" ] || [ "$INSTALL_CHOICE" = "3" ]; then
        printf "${C_GREEN}Argo 隧道承载 VLESS 还是 VMess? [1=VLESS, 2=VMess]: ${C_NC}"; read -r ARGO_PROTOCOL_CHOICE
        if [ "$ARGO_PROTOCOL_CHOICE" = "1" ]; then ARGO_PROTOCOL="vless"; else ARGO_PROTOCOL="vmess"; fi
        echo "ARGO_PROTOCOL='${ARGO_PROTOCOL}'" >> "$VARS_PATH"
        printf "${C_GREEN}请输入 Argo 本地监听端口 (默认 8080): ${C_NC}"; read -r ARGO_LOCAL_PORT
        ARGO_LOCAL_PORT=${ARGO_LOCAL_PORT:-8080}
        echo "ARGO_LOCAL_PORT=${ARGO_LOCAL_PORT}" >> "$VARS_PATH"
        printf "${C_GREEN}请输入 Argo Tunnel Token (回车使用临时隧道): ${C_NC}"; read -r ARGO_TOKEN
        if [ -n "$ARGO_TOKEN" ]; then
            printf "${C_GREEN}请输入 Argo Tunnel 域名: ${C_NC}"; read -r ARGO_DOMAIN
        fi
        echo "ARGO_TOKEN='${ARGO_TOKEN}'" >> "$VARS_PATH"
        echo "ARGO_DOMAIN='${ARGO_DOMAIN}'" >> "$VARS_PATH"
    fi

    load_variables

    print_msg "--- 准备依赖环境 ---" "blue"
    cpu_arch=$(get_cpu_arch)

    # 下载 sing-box
    if [ ! -f "$SINGBOX_PATH" ]; then
        singbox_url="https://github.com/SagerNet/sing-box/releases/download/v1.9.0/sing-box-1.9.0-linux-${cpu_arch}.tar.gz"
        temp_tar="$AGSBX_DIR/sing-box.tar.gz"
        download_file "$singbox_url" "$temp_tar"
        tar -xzf "$temp_tar" -C "$AGSBX_DIR"
        mv "$AGSBX_DIR/sing-box-1.9.0-linux-${cpu_arch}/sing-box" "$SINGBOX_PATH"
        rm -f "$temp_tar"; rm -rf "$AGSBX_DIR/sing-box-1.9.0-linux-${cpu_arch}"
    fi

    # 下载 cloudflared
    if [ "$INSTALL_CHOICE" = "2" ] || [ "$INSTALL_CHOICE" = "3" ]; then
        if [ ! -f "$CLOUDFLARED_PATH" ]; then
            cloudflared_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cpu_arch}"
            download_file "$cloudflared_url" "$CLOUDFLARED_PATH"
        fi
    fi

    # 生成 UUID
    UUID=$($SINGBOX_PATH generate uuid)
    echo "UUID='${UUID}'" >> "$VARS_PATH"
    print_msg "生成 UUID: $UUID" "yellow"

    # 生成配置文件
    prepare_tls
    cat > "$CONFIG_PATH" <<EOF
{
    "log": {"level": "info", "timestamp": true},
    "inbounds": [
        $( [ "$INSTALL_CHOICE" = "1" ] || [ "$INSTALL_CHOICE" = "3" ] && echo "{\"type\":\"tuic\",\"tag\":\"tuic-in\",\"listen\":\"::\",\"listen_port\":${TUIC_PORT},\"users\":[{\"uuid\":\"${UUID}\",\"password\":\"${UUID}\"}],\"congestion_control\":\"bbr\",\"tls\":{\"enabled\":true,\"server_name\":\"www.bing.com\",\"alpn\":[\"h3\"],\"certificate_path\":\"${CERT_PATH}\",\"key_path\":\"${KEY_PATH}\"}}" )
        $( [ "$INSTALL_CHOICE" = "2" ] || [ "$INSTALL_CHOICE" = "3" ] && echo ",{\"type\":\"$ARGO_PROTOCOL\",\"tag\":\"argo-in\",\"listen\":\"127.0.0.1\",\"listen_port\":${ARGO_LOCAL_PORT},\"users\":[{\"uuid\":\"${UUID}\"}],\"transport\":{\"type\":\"ws\",\"path\":\"/${UUID}-${ARGO_PROTOCOL:0:2}\"}}" )
    ],
    "outbounds": [{"type":"direct","tag":"direct"}]
}
EOF

    print_msg "配置文件已生成: $CONFIG_PATH" "green"
    do_start
}

# --- 启动 ---
do_start() {
    print_msg "--- 启动服务 ---" "blue"
    load_variables
    do_stop
    prepare_tls

    nohup "$SINGBOX_PATH" run -c "$CONFIG_PATH" > "$AGSBX_DIR/sing-box.log" 2>&1 &
    sleep 1
    if ! ps aux | grep -q "[s]ing-box"; then
        print_msg "⚠️ sing-box 启动失败，请查看日志: $AGSBX_DIR/sing-box.log" "red"
        exit 1
    fi
    print_msg "sing-box 已后台启动，日志: $AGSBX_DIR/sing-box.log" "green"

    # Argo
    if [ "$INSTALL_CHOICE" = "2" ] || [ "$INSTALL_CHOICE" = "3" ]; then
        if [ -n "$ARGO_TOKEN" ]; then
            cat > "$AGSBX_DIR/config.yml" <<EOF
log-level: info
ingress:
  - hostname: ${ARGO_DOMAIN}
    service: http://127.0.0.1:${ARGO_LOCAL_PORT}
  - service: http_status:404
EOF
            nohup "$CLOUDFLARED_PATH" tunnel --config "$AGSBX_DIR/config.yml" run --token "$ARGO_TOKEN" > "$AGSBX_DIR/argo.log" 2>&1 &
        else
            nohup "$CLOUDFLARED_PATH" tunnel --url "http://127.0.0.1:${ARGO_LOCAL_PORT}" > "$AGSBX_DIR/argo.log" 2>&1 &
            print_msg "临时隧道将在几秒后建立..." "yellow"
        fi
        print_msg "cloudflared 已后台启动，日志: $AGSBX_DIR/argo.log" "green"
    fi

    print_msg "\n--- 节点信息 ---" "blue"
    do_list
}

# --- 停止 ---
do_stop() {
    pkill -f "$SINGBOX_PATH"
    pkill -f "$CLOUDFLARED_PATH"
    print_msg "已停止 sing-box 和 cloudflared。" "green"
}

# --- 节点信息 ---
do_list() {
    load_variables || { print_msg "未找到配置，请先安装。" "red"; return; }
    local ip4 ip6
    ip4=$(get_server_ip4)
    ip6=$(get_server_ip6)

    if [ "$INSTALL_CHOICE" = "1" ] || [ "$INSTALL_CHOICE" = "3" ]; then
        local tuic_params="congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=www.bing.com&allow_insecure=1"
        local tuic_link="tuic://${UUID}:${UUID}@${ip4}:${TUIC_PORT}?${tuic_params}#tuic-ipv4"
        print_msg "--- TUIC IPv4 节点 ---" "yellow"
        echo "$tuic_link"
        [ -n "$ip6" ] && echo "tuic://${UUID}:${UUID}@[${ip6}]:${TUIC_PORT}?${tuic_params}#tuic-ipv6"
    fi

    if [ "$INSTALL_CHOICE" = "2" ] || [ "$INSTALL_CHOICE" = "3" ]; then
        local domain=${ARGO_DOMAIN:-临时域名未生成}
        if [ "$ARGO_PROTOCOL" = "vless" ]; then
            local vless_link="vless://${UUID}@${domain}:443?encryption=none&security=tls&sni=${domain}&fp=chrome&type=ws&host=${domain}&path=%2f${UUID}-vl#argo-vless"
            print_msg "--- VLESS + Argo 节点 ---" "yellow"
            echo "$vless_link"
        else
            local vmess_json; vmess_json=$(printf '{"v":"2","ps":"vmess-argo","add":"%s","port":"443","id":"%s","aid":"0","net":"ws","type":"none","host":"%s","path":"/%s-vm","tls":"tls","sni":"%s"}' "$domain" "$UUID" "$domain" "$UUID" "$domain")
            local vmess_base64; vmess_base64=$(echo "$vmess_json" | tr -d '\n' | base64 -w0)
            local vmess_link="vmess://${vmess_base64}"
            print_msg "--- VMess + Argo 节点 ---" "yellow"
            echo "$vmess_link"
        fi
    fi
}

# --- 卸载 ---
do_uninstall() {
    do_stop
    rm -rf "$AGSBX_DIR"
    print_msg "已卸载所有文件。" "green"
}

# --- 重启 ---
do_restart() {
    do_stop
    sleep 1
    do_start
}

# --- 帮助 ---
show_help() {
    print_msg "All-in-One TUIC & VLESS/VMess+Argo 管理脚本 v3.5" "blue"
    echo "用法: bash $0 [命令]"
    print_msg "可用命令:" "yellow"
    echo " install    - 安装节点"
    echo " list       - 显示节点信息"
    echo " start      - 启动服务"
    echo " stop       - 停止服务"
    echo " restart    - 重启服务"
    echo " uninstall  - 卸载"
    echo " help       - 显示帮助"
}

# --- 主入口 ---
main() {
    case "$1" in
        install) do_install ;;
        list)    do_list ;;
        start)   do_start ;;
        stop)    do_stop ;;
        restart) do_restart ;;
        uninstall) do_uninstall ;;
        help|*) show_help ;;
    esac
}

main "$@"
