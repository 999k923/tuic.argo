#!/bin/bash

# ======================================================================
# All-in-One TUIC & VLESS/VMess+Argo 管理脚本
# 支持交互式安装、IPv4/IPv6 自动检测、节点备注带 Emoji+国家+IP类型
# ======================================================================

# --- 颜色 ---
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_NC='\033[0m'

# --- 常量 ---
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
    print_msg "正在下载 $(basename "$dest")..." yellow
    if command -v curl >/dev/null 2>&1; then
        curl -# -Lo "$dest" "$url"
    else
        wget -q --show-progress -O "$dest" "$url"
    fi
    if [ $? -ne 0 ]; then print_msg "下载失败: $url" red; exit 1; fi
    chmod +x "$dest"
    print_msg "$(basename "$dest") 下载并设置权限成功。" green
}

load_variables() {
    [ -f "$VARS_PATH" ] && . "$VARS_PATH"
}

# --- 获取 IPv4/IPv6 ---
get_server_ip() {
    local ipv4
    if command -v curl >/dev/null 2>&1; then
        ipv4=$(curl -4 -s https://icanhazip.com)
    else
        ipv4=$(wget -4 -qO- https://icanhazip.com)
    fi
    echo "$ipv4"
}

get_server_ipv6() {
    [ -n "$SERVER_IPV6" ] && echo "$SERVER_IPV6" && return
    local iface ipv6
    for iface in $(ls /sys/class/net/ | grep -v lo); do
        ipv6=$(ip -6 addr show dev "$iface" | grep inet6 | grep -v '::1' | grep -v 'fe80' | awk '{print $2}' | cut -d/ -f1 | head -n1)
        [ -n "$ipv6" ] && echo "$ipv6" && return
    done
    if command -v curl >/dev/null 2>&1; then
        ipv6=$(curl -6 -s https://icanhazip.com)
    else
        ipv6=$(wget -6 -qO- https://icanhazip.com)
    fi
    echo "$ipv6"
}

# --- 核心安装 ---
do_install() {
    print_msg "--- 节点安装向导 ---" blue
    print_msg "请选择您要安装的类型:" yellow
    print_msg "  1) 仅安装 TUIC"
    print_msg "  2) 仅安装 Argo 隧道 (VLESS 或 VMess)"
    print_msg "  3) 同时安装 TUIC 和 Argo 隧道"
    read -rp "$(printf "${C_GREEN}请输入选项 [1-3]: ${C_NC}")" INSTALL_CHOICE

    mkdir -p "$AGSBX_DIR"
    : > "$VARS_PATH"

    [[ "$INSTALL_CHOICE" =~ ^[1-3]$ ]] || { print_msg "无效选项，安装已取消。" red; exit 1; }
    echo "INSTALL_CHOICE=$INSTALL_CHOICE" >> "$VARS_PATH"

    # TUIC 配置
    if [[ "$INSTALL_CHOICE" =~ ^(1|3)$ ]]; then
        read -rp "$(printf "${C_GREEN}请输入 TUIC 端口 (默认 443): ${C_NC}")" TUIC_PORT
        TUIC_PORT=${TUIC_PORT:-443}
        echo "TUIC_PORT=${TUIC_PORT}" >> "$VARS_PATH"
    fi

    # Argo 配置
    if [[ "$INSTALL_CHOICE" =~ ^(2|3)$ ]]; then
        read -rp "$(printf "${C_GREEN}Argo 隧道协议 [1=VLESS,2=VMess]: ${C_NC}")" ARGO_PROTOCOL_CHOICE
        if [ "$ARGO_PROTOCOL_CHOICE" = "1" ]; then
            ARGO_PROTOCOL='vless'
            read -rp "$(printf "${C_GREEN}请输入本地监听端口 (默认 8080): ${C_NC}")" ARGO_LOCAL_PORT
        else
            ARGO_PROTOCOL='vmess'
            read -rp "$(printf "${C_GREEN}请输入本地监听端口 (默认 8080): ${C_NC}")" ARGO_LOCAL_PORT
        fi
        ARGO_LOCAL_PORT=${ARGO_LOCAL_PORT:-8080}
        read -rp "$(printf "${C_GREEN}请输入 Argo Tunnel Token (留空使用临时隧道): ${C_NC}")" ARGO_TOKEN
        [ -n "$ARGO_TOKEN" ] && read -rp "$(printf "${C_GREEN}请输入 Argo Tunnel 对应域名: ${C_NC}")" ARGO_DOMAIN
        echo "ARGO_PROTOCOL='$ARGO_PROTOCOL'" >> "$VARS_PATH"
        echo "ARGO_LOCAL_PORT=${ARGO_LOCAL_PORT}" >> "$VARS_PATH"
        echo "ARGO_TOKEN='${ARGO_TOKEN}'" >> "$VARS_PATH"
        echo "ARGO_DOMAIN='${ARGO_DOMAIN}'" >> "$VARS_PATH"
    fi

    # 可选手动指定 IPv6
    read -rp "$(printf "${C_GREEN}如果是 NAT IPv6，请输入公网 IPv6，否则直接回车自动获取: ${C_NC}")" SERVER_IPV6
    [ -n "$SERVER_IPV6" ] && echo "SERVER_IPV6='${SERVER_IPV6}'" >> "$VARS_PATH"

    load_variables

    print_msg "--- 准备依赖 ---" blue
    cpu_arch=$(get_cpu_arch)

    # 下载 sing-box
    if [ ! -f "$SINGBOX_PATH" ]; then
        SINGBOX_URL="https://github.com/SagerNet/sing-box/releases/download/v1.9.0/sing-box-1.9.0-linux-${cpu_arch}.tar.gz"
        TMP_TAR="$AGSBX_DIR/sing-box.tar.gz"
        download_file "$SINGBOX_URL" "$TMP_TAR"
        tar -xzf "$TMP_TAR" -C "$AGSBX_DIR"
        mv "$AGSBX_DIR/sing-box-1.9.0-linux-${cpu_arch}/sing-box" "$SINGBOX_PATH"
        rm -rf "$TMP_TAR" "$AGSBX_DIR/sing-box-1.9.0-linux-${cpu_arch}"
    fi

    # 下载 cloudflared
    if [[ "$INSTALL_CHOICE" =~ ^(2|3)$ ]] && [ ! -f "$CLOUDFLARED_PATH" ]; then
        CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cpu_arch}"
        download_file "$CLOUDFLARED_URL" "$CLOUDFLARED_PATH"
    fi

    # TLS 证书
    if [[ "$INSTALL_CHOICE" =~ ^(1|3)$ ]]; then
        command -v openssl >/dev/null 2>&1 || { print_msg "请安装 openssl" red; exit 1; }
        openssl ecparam -genkey -name prime256v1 -out "$KEY_PATH" >/dev/null 2>&1
        openssl req -new -x509 -days 36500 -key "$KEY_PATH" -out "$CERT_PATH" -subj "/CN=www.bing.com" >/dev/null 2>&1
    fi

    # 生成 UUID
    UUID=$($SINGBOX_PATH generate uuid)
    echo "UUID='${UUID}'" >> "$VARS_PATH"
    print_msg "生成 UUID: $UUID" yellow

    # 生成配置
    do_generate_config

    # 启动
    do_start
    print_msg "--- 安装完成，节点信息 ---" blue
    do_list
}

do_generate_config() {
    load_variables
    local argo_inbound=""
    if [[ "$INSTALL_CHOICE" =~ ^(2|3)$ ]]; then
        if [ "$ARGO_PROTOCOL" = "vless" ]; then
            argo_inbound=$(printf '{"type":"vless","tag":"vless-in","listen":"127.0.0.1","listen_port":%s,"users":[{"uuid":"%s"}],"transport":{"type":"ws","path":"/%s-vl"}}' "$ARGO_LOCAL_PORT" "$UUID" "$UUID")
        else
            argo_inbound=$(printf '{"type":"vmess","tag":"vmess-in","listen":"127.0.0.1","listen_port":%s,"users":[{"uuid":"%s","alterId":0}],"transport":{"type":"ws","path":"/%s-vm"}}' "$ARGO_LOCAL_PORT" "$UUID" "$UUID")
        fi
    fi

    # 生成配置
    if [ "$INSTALL_CHOICE" = "1" ]; then
        cat > "$CONFIG_PATH" <<EOF
{
  "log":{"level":"info","timestamp":true},
  "inbounds":[{"type":"tuic","tag":"tuic-in","listen":"::","listen_port":${TUIC_PORT},"users":[{"uuid":"${UUID}","password":"${UUID}"}],"congestion_control":"bbr","tls":{"enabled":true,"server_name":"www.bing.com","alpn":["h3"],"certificate_path":"${CERT_PATH}","key_path":"${KEY_PATH}"}}],
  "outbounds":[{"type":"direct","tag":"direct"}]
}
EOF
    elif [ "$INSTALL_CHOICE" = "2" ]; then
        cat > "$CONFIG_PATH" <<EOF
{
  "log":{"level":"info","timestamp":true},
  "inbounds":[${argo_inbound}],
  "outbounds":[{"type":"direct","tag":"direct"}]
}
EOF
    elif [ "$INSTALL_CHOICE" = "3" ]; then
        cat > "$CONFIG_PATH" <<EOF
{
  "log":{"level":"info","timestamp":true},
  "inbounds":[
    {"type":"tuic","tag":"tuic-in","listen":"::","listen_port":${TUIC_PORT},"users":[{"uuid":"${UUID}","password":"${UUID}"}],"congestion_control":"bbr","tls":{"enabled":true,"server_name":"www.bing.com","alpn":["h3"],"certificate_path":"${CERT_PATH}","key_path":"${KEY_PATH}"}},
    ${argo_inbound}
  ],
  "outbounds":[{"type":"direct","tag":"direct"}]
}
EOF
    fi
    print_msg "配置文件已生成: $CONFIG_PATH" green
}

# --- 启停 ---
do_start() {
    load_variables
    do_stop

    nohup "$SINGBOX_PATH" run -c "$CONFIG_PATH" > "$AGSBX_DIR/sing-box.log" 2>&1 &

    if [[ "$INSTALL_CHOICE" =~ ^(2|3)$ ]]; then
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
        fi
    fi

    print_msg "服务已启动" green
}

do_stop() {
    pkill -f "$SINGBOX_PATH"
    pkill -f "$CLOUDFLARED_PATH"
    print_msg "服务已停止" green
}

# --- 节点列表，带 Emoji + 协议 + 国家 + IP类型 ---
do_list() {
    load_variables || { print_msg "请先安装" red; return; }

    server_ip=$(get_server_ip)
    server_ipv6=$(get_server_ipv6)
    hostname=$(hostname)

    get_country() {
        local ip="$1"
        curl -s "https://ipapi.co/${ip}/country/" 2>/dev/null || echo "🌍"
    }

    country4=$(get_country "$server_ip")
    country6=$(get_country "$server_ipv6")

    # TUIC
    if [[ "$INSTALL_CHOICE" =~ ^(1|3)$ ]]; then
        tuic_params="congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=www.bing.com&allow_insecure=1"
        print_msg "--- TUIC ---" yellow
        echo "tuic://${UUID}:${UUID}@${server_ip}:${TUIC_PORT}?${tuic_params}#🌐 TUIC ${country4} IPv4"
        echo "tuic://${UUID}:${UUID}@[${server_ipv6}]:${TUIC_PORT}?${tuic_params}#🌐 TUIC ${country6} IPv6"
    fi

    # Argo
    if [[ "$INSTALL_CHOICE" =~ ^(2|3)$ ]]; then
        [ -z "$ARGO_TOKEN" ] && print_msg "等待临时 Argo 域名..." yellow
        if [ "$ARGO_PROTOCOL" = "vless" ]; then
            echo "--- VLESS + Argo (TLS) ---" yellow
            echo "vless://${UUID}@${ARGO_DOMAIN}:443?encryption=none&security=tls&sni=${ARGO_DOMAIN}&fp=chrome&type=ws&host=${ARGO_DOMAIN}&path=%2f${UUID}-vl#⛓️ VLESS ${country4} IPv4"
        else
            vmess_json=$(printf '{"v":"2","ps":"vmess-argo-%s","add":"%s","port":"443","id":"%s","aid":"0","scy":"auto","net":"ws","type":"none","host":"%s","path":"/%s-vm","tls":"tls","sni":"%s"}' "$hostname" "$ARGO_DOMAIN" "$UUID" "$ARGO_DOMAIN" "$UUID" "$ARGO_DOMAIN")
            vmess_base64=$(echo "$vmess_json" | tr -d '\n' | base64 -w0)
            echo "--- VMess + Argo (TLS) ---" yellow
            echo "vmess://${vmess_base64}#⛓️ VMess ${country4} IPv4"
        fi
    fi
}

do_restart() { do_stop; sleep 1; do_start; }

do_uninstall() {
    read -rp "$(printf "${C_YELLOW}确认卸载？将删除所有文件 (y/n): ${C_NC}")" confirm
    [ "$confirm" != "y" ] && print_msg "取消卸载" green && exit 0
    do_stop
    rm -rf "$AGSBX_DIR"
    print_msg "卸载完成" green
}

show_help() {
    print_msg "All-in-One TUIC & VLESS/VMess+Argo 管理脚本" blue
    echo "用法: bash $0 [命令]"
    echo "命令: install | list | start | stop | restart | uninstall | help"
}

# --- 主入口 ---
case "$1" in
    install) do_install ;;
    list)    do_list ;;
    start)   do_start ;;
    stop)    do_stop ;;
    restart) do_restart ;;
    uninstall) do_uninstall ;;
    help|*) show_help ;;
esac
