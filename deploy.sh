#!/bin/bash

# ============================================================================== 
# All-in-One TUIC & VLESS/VMess+Argo 管理脚本 (v4.0 改进版)
# 支持 IPv4/IPv6 自动检测
# ==============================================================================

# --- 颜色定义 ---
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
        red)    printf "${C_RED}%s\n" "$1" ;;
        green)  printf "${C_GREEN}%s\n" "$1" ;;
        yellow) printf "${C_YELLOW}%s\n" "$1" ;;
        blue)   printf "${C_BLUE}%s\n" "$1" ;;
        *)      printf "%s\n" "$1" ;;
    esac
}

get_cpu_arch() {
    case "$(uname -m)" in
        x86_64) echo "amd64" ;;
        aarch64) echo "arm64" ;;
        *) print_msg "错误: 不支持的 CPU 架构 $(uname -m)" "red"; exit 1 ;;
    esac
}

download_file() {
    local url="$1"
    local dest="$2"
    print_msg "正在下载 $(basename "$dest")..." "yellow"
    if command -v curl >/dev/null 2>&1; then
        curl -# -Lo "$dest" "$url"
    else
        wget -q --show-progress -O "$dest" "$url"
    fi
    if [ $? -ne 0 ]; then print_msg "下载失败: $url" "red"; exit 1; fi
    chmod +x "$dest"
    print_msg "$(basename "$dest") 下载并设置权限成功。" "green"
}

get_server_ip() {
    if command -v curl >/dev/null 2>&1; then
        curl -4 -s https://icanhazip.com
    else
        wget -4 -qO- https://icanhazip.com
    fi
}

get_server_ipv6() {
    local ip6
    if command -v curl >/dev/null 2>&1; then
        ip6=$(curl -6 -s https://icanhazip.com)
    else
        ip6=$(wget -6 -qO- https://icanhazip.com)
    fi
    echo "$ip6"
}

load_variables() {
    [ -f "$VARS_PATH" ] && . "$VARS_PATH"
}

# --- 核心函数 ---
do_install() {
    print_msg "--- 节点安装向导 ---" "blue"
    print_msg "请选择安装类型:" "yellow"
    print_msg "  1) 仅 TUIC"
    print_msg "  2) 仅 Argo 隧道 (VLESS/VMess)"
    print_msg "  3) 同时安装 TUIC 和 Argo"
    read -rp "请输入选项 [1-3]: " INSTALL_CHOICE

    mkdir -p "$AGSBX_DIR"
    : > "$VARS_PATH"

    # --- 根据选择交互输入 ---
    if [ "$INSTALL_CHOICE" = "1" ] || [ "$INSTALL_CHOICE" = "3" ]; then
        read -rp "请输入 TUIC 端口 (默认 443): " TUIC_PORT
        TUIC_PORT=${TUIC_PORT:-443}
        echo "TUIC_PORT=${TUIC_PORT}" >> "$VARS_PATH"
    fi

    if [ "$INSTALL_CHOICE" = "2" ] || [ "$INSTALL_CHOICE" = "3" ]; then
        read -rp "Argo 隧道承载 VLESS 还是 VMess? [1=VLESS, 2=VMess]: " ARGO_PROTOCOL_CHOICE
        if [ "$ARGO_PROTOCOL_CHOICE" = "1" ]; then
            ARGO_PROTOCOL='vless'
            read -rp "请输入 VLESS 本地端口 (默认 8080): " ARGO_LOCAL_PORT
        else
            ARGO_PROTOCOL='vmess'
            read -rp "请输入 VMess 本地端口 (默认 8080): " ARGO_LOCAL_PORT
        fi
        ARGO_LOCAL_PORT=${ARGO_LOCAL_PORT:-8080}
        read -rp "请输入 Argo Tunnel Token (回车使用临时隧道): " ARGO_TOKEN
        if [ -n "$ARGO_TOKEN" ]; then
            read -rp "请输入 Argo 域名: " ARGO_DOMAIN
        fi
        echo "ARGO_PROTOCOL='$ARGO_PROTOCOL'" >> "$VARS_PATH"
        echo "ARGO_LOCAL_PORT=${ARGO_LOCAL_PORT}" >> "$VARS_PATH"
        echo "ARGO_TOKEN='${ARGO_TOKEN}'" >> "$VARS_PATH"
        echo "ARGO_DOMAIN='${ARGO_DOMAIN}'" >> "$VARS_PATH"
    fi

    echo "INSTALL_CHOICE=${INSTALL_CHOICE}" >> "$VARS_PATH"
    load_variables

    # --- 安装依赖 ---
    local cpu_arch; cpu_arch=$(get_cpu_arch)
    if [ ! -f "$SINGBOX_PATH" ]; then
        local singbox_url="https://github.com/SagerNet/sing-box/releases/download/v1.9.0/sing-box-1.9.0-linux-${cpu_arch}.tar.gz"
        local temp_tar="$AGSBX_DIR/sing-box.tar.gz"
        download_file "$singbox_url" "$temp_tar"
        tar -xzf "$temp_tar" -C "$AGSBX_DIR"
        mv "$AGSBX_DIR/sing-box-1.9.0-linux-${cpu_arch}/sing-box" "$SINGBOX_PATH"
        rm -rf "$temp_tar" "$AGSBX_DIR/sing-box-1.9.0-linux-${cpu_arch}"
    fi

    if [ "$INSTALL_CHOICE" = "2" ] || [ "$INSTALL_CHOICE" = "3" ]; then
        if [ ! -f "$CLOUDFLARED_PATH" ]; then
            local cloudflared_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cpu_arch}"
            download_file "$cloudflared_url" "$CLOUDFLARED_PATH"
        fi
    fi

    # --- 生成 UUID ---
    local UUID; UUID=$($SINGBOX_PATH generate uuid)
    echo "UUID='${UUID}'" >> "$VARS_PATH"
    print_msg "生成 UUID: $UUID" "yellow"

    # --- TLS 证书 ---
    if [ "$INSTALL_CHOICE" = "1" ] || [ "$INSTALL_CHOICE" = "3" ]; then
        if ! command -v openssl >/dev/null 2>&1; then
            print_msg "警告: 未安装 openssl，无法生成 TLS 证书" "red"
        else
            openssl ecparam -genkey -name prime256v1 -out "$KEY_PATH"
            openssl req -new -x509 -days 36500 -key "$KEY_PATH" -out "$CERT_PATH" -subj "/CN=www.bing.com"
            print_msg "TLS 证书生成成功" "green"
        fi
    fi

    # --- 生成 sing-box 配置 ---
    local argo_inbound=""
    if [ "$INSTALL_CHOICE" = "2" ] || [ "$INSTALL_CHOICE" = "3" ]; then
        if [ "$ARGO_PROTOCOL" = "vless" ]; then
            argo_inbound=$(printf '{"type": "vless", "tag": "vless-in", "listen": "127.0.0.1", "listen_port": %s, "users": [{"uuid": "%s"}], "transport": {"type": "ws", "path": "/%s-vl"}}' "$ARGO_LOCAL_PORT" "$UUID" "$UUID")
        else
            argo_inbound=$(printf '{"type": "vmess", "tag": "vmess-in", "listen": "127.0.0.1", "listen_port": %s, "users": [{"uuid": "%s","alterId":0}], "transport":{"type":"ws","path":"/%s-vm"}}' "$ARGO_LOCAL_PORT" "$UUID" "$UUID")
        fi
    fi

    cat > "$CONFIG_PATH" <<EOF
{
    "log":{"level":"info","timestamp":true},
    "inbounds":[
        $( [ "$INSTALL_CHOICE" = "1" ] || [ "$INSTALL_CHOICE" = "3" ] && echo '{"type":"tuic","tag":"tuic-in","listen":"::","listen_port":'"$TUIC_PORT"',"users":[{"uuid":"'"$UUID"'","password":"'"$UUID"'"}],"congestion_control":"bbr","tls":{"enabled":true,"server_name":"www.bing.com","alpn":["h3"],"certificate_path":"'"$CERT_PATH"'","key_path":"'"$KEY_PATH"'"}}' ),
        $argo_inbound
    ],
    "outbounds":[{"type":"direct","tag":"direct"}]
}
EOF
    print_msg "配置文件已生成: $CONFIG_PATH" "green"
    do_start
    do_list
}

# --- 显示节点信息 ---
do_list() {
    load_variables || { print_msg "未找到变量文件，请先安装" "red"; exit 1; }
    local ipv4 ipv6 hostname
    ipv4=$(get_server_ip)
    ipv6=$(get_server_ipv6)
    hostname=$(hostname)

    print_msg "--- 节点信息 ---" "blue"

    if [ "$INSTALL_CHOICE" = "1" ] || [ "$INSTALL_CHOICE" = "3" ]; then
        local tuic_params="congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=www.bing.com&allow_insecure=1"
        print_msg "--- TUIC IPv4 ---" "yellow"
        echo "tuic://${UUID}:${UUID}@${ipv4}:${TUIC_PORT}?${tuic_params}#tuic-${hostname}-ipv4"
        if [ -n "$ipv6" ]; then
            print_msg "--- TUIC IPv6 ---" "yellow"
            echo "tuic://${UUID}:${UUID}@[${ipv6}]:${TUIC_PORT}?${tuic_params}#tuic-${hostname}-ipv6"
        fi
    fi

    if [ "$INSTALL_CHOICE" = "2" ] || [ "$INSTALL_CHOICE" = "3" ]; then
        local domain=${ARGO_DOMAIN:-"[请检查 Argo 域名]"}
        if [ "$ARGO_PROTOCOL" = "vless" ]; then
            echo "vless://${UUID}@${domain}:443?encryption=none&security=tls&sni=${domain}&fp=chrome&type=ws&host=${domain}&path=%2f${UUID}-vl#argo-vless-${hostname}"
        else
            local vmess_json; vmess_json=$(printf '{"v":"2","ps":"vmess-argo-%s","add":"%s","port":"443","id":"%s","aid":"0","scy":"auto","net":"ws","type":"none","host":"%s","path":"/%s-vm","tls":"tls","sni":"%s"}' "$hostname" "$domain" "$UUID" "$domain" "$UUID" "$domain")
            local vmess_base64; vmess_base64=$(echo "$vmess_json" | tr -d '\n' | base64 -w0)
            echo "vmess://${vmess_base64}"
        fi
    fi
}

do_start() {
    load_variables || { print_msg "未找到变量文件，请先安装" "red"; exit 1; }
    do_stop
    nohup "$SINGBOX_PATH" run -c "$CONFIG_PATH" > "$AGSBX_DIR/sing-box.log" 2>&1 &
    print_msg "sing-box 已后台启动，日志: $AGSBX_DIR/sing-box.log" "green"

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
            print_msg "临时隧道启动中，log: $AGSBX_DIR/argo.log" "yellow"
        fi
        print_msg "cloudflared 已后台启动。" "green"
    fi
}

do_stop() {
    pkill -f "$SINGBOX_PATH"
    pkill -f "$CLOUDFLARED_PATH"
    print_msg "已停止 sing-box 和 cloudflared" "green"
}

do_restart() {
    do_stop
    sleep 1
    do_start
}

do_uninstall() {
    read -rp "⚠️ 确定要删除所有文件和配置吗? (y/n): " confirm
    [ "$confirm" != "y" ] && { print_msg "取消卸载" "green"; exit 0; }
    do_stop
    rm -rf "$AGSBX_DIR"
    print_msg "卸载完成" "green"
}

show_help() {
    print_msg "All-in-One TUIC & VLESS/VMess+Argo 管理脚本 (IPv6 改进版)" "blue"
    echo "用法: bash $0 [命令]"
    echo "可用命令: install | list | start | stop | restart | uninstall | help"
}

main() {
    case "$1" in
        install)   do_install ;;
        list)      do_list ;;
        start)     do_start ;;
        stop)      do_stop ;;
        restart)   do_restart ;;
        uninstall) do_uninstall ;;
        help|*)    show_help ;;
    esac
}

main "$@"
