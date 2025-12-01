#!/bin/bash

# ======================================================================
# All-in-One TUIC & VLESS/VMess+Argo 管理脚本 + systemd 守护保活
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

SYSTEMD_SINGBOX="/etc/systemd/system/singbox.service"
SYSTEMD_ARGO="/etc/systemd/system/argo.service"

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
    curl -# -Lo "$dest" "$url" || wget -q --show-progress -O "$dest" "$url"
    [ $? -ne 0 ] && print_msg "下载失败: $url" red && exit 1
    chmod +x "$dest"
    print_msg "$(basename "$dest") 下载并设置权限成功。" green
}

load_variables() {
    [ -f "$VARS_PATH" ] && . "$VARS_PATH"
}

# --- 获取 IP ---
get_server_ip() { curl -4 -s https://icanhazip.com || wget -4 -qO- https://icanhazip.com; }
get_server_ipv6() {
    [ -n "$SERVER_IPV6" ] && echo "$SERVER_IPV6" && return
    ipv6=$(ip -6 addr | grep 'global' | awk '{print $2}' | cut -d/ -f1 | head -n1)
    [ -z "$ipv6" ] && ipv6=$(curl -6 -s https://icanhazip.com)
    echo "$ipv6"
}

# ======================================================================
# ★★★ 新增：systemd 服务生成 ★★★
# ======================================================================

create_systemd_services() {
    print_msg "正在创建 systemd 守护服务..." blue

    # --- sing-box ---
    cat > "$SYSTEMD_SINGBOX" <<EOF
[Unit]
Description=Sing-box Service
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=$SINGBOX_PATH run -c $CONFIG_PATH
Restart=always
RestartSec=2
User=root
LimitNOFILE=200000

[Install]
WantedBy=multi-user.target
EOF

    # --- Argo ---
    if [[ "$INSTALL_CHOICE" =~ ^(2|3)$ ]]; then
cat > "$SYSTEMD_ARGO" <<EOF
[Unit]
Description=Cloudflared Argo Tunnel
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=$CLOUDFLARED_PATH tunnel --config $AGSBX_DIR/config.yml run
Restart=always
RestartSec=2
User=root
LimitNOFILE=200000

[Install]
WantedBy=multi-user.target
EOF
    fi

    systemctl daemon-reload
    systemctl enable singbox >/dev/null 2>&1

    [[ "$INSTALL_CHOICE" =~ ^(2|3)$ ]] && systemctl enable argo >/dev/null 2>&1

    print_msg "systemd 服务已创建并设置为开机自启！" green
}

# ======================================================================
# ★★★ 安装流程 ★★★
# ======================================================================

do_install() {
    print_msg "--- 节点安装向导 ---" blue
    print_msg "请选择安装类型:" yellow
    echo "1) 仅 TUIC"
    echo "2) 仅 Argo (VLESS/VMess)"
    echo "3) TUIC + Argo"
    read -rp "$(printf "${C_GREEN}请输入选项 [1-3]: ${C_NC}")" INSTALL_CHOICE

    mkdir -p "$AGSBX_DIR"
    : > "$VARS_PATH"

    echo "INSTALL_CHOICE=$INSTALL_CHOICE" >> "$VARS_PATH"

    # TUIC
    if [[ "$INSTALL_CHOICE" =~ ^(1|3)$ ]]; then
        read -rp "TUIC 端口(默认443): " TUIC_PORT
        TUIC_PORT=${TUIC_PORT:-443}
        echo "TUIC_PORT=$TUIC_PORT" >> "$VARS_PATH"
    fi

    # Argo
    if [[ "$INSTALL_CHOICE" =~ ^(2|3)$ ]]; then
        read -rp "选择 Argo 承载协议 (1=VLESS,2=VMess): " ARGO_PROTOCOL_CHOICE
        [ "$ARGO_PROTOCOL_CHOICE" = "1" ] && ARGO_PROTOCOL=vless || ARGO_PROTOCOL=vmess
        read -rp "本地监听端口(默认8080): " ARGO_LOCAL_PORT
        ARGO_LOCAL_PORT=${ARGO_LOCAL_PORT:-8080}

        read -rp "Argo TOKEN (留空=临时隧道): " ARGO_TOKEN
        [ -n "$ARGO_TOKEN" ] && read -rp "Argo 域名: " ARGO_DOMAIN

        echo "ARGO_PROTOCOL='$ARGO_PROTOCOL'" >> "$VARS_PATH"
        echo "ARGO_LOCAL_PORT=$ARGO_LOCAL_PORT" >> "$VARS_PATH"
        echo "ARGO_TOKEN='$ARGO_TOKEN'" >> "$VARS_PATH"
        echo "ARGO_DOMAIN='$ARGO_DOMAIN'" >> "$VARS_PATH"
    fi

    read -rp "若你是NAT IPv6，请输入公网 IPv6： " SERVER_IPV6
    [ -n "$SERVER_IPV6" ] && echo "SERVER_IPV6='$SERVER_IPV6'" >> "$VARS_PATH"

    load_variables

    # --- 下载程序 ---
    arch=$(get_cpu_arch)

    if [ ! -f "$SINGBOX_PATH" ]; then
        url="https://github.com/SagerNet/sing-box/releases/latest/download/sing-box-linux-$arch.tar.gz"
        tarball="$AGSBX_DIR/sb.tar.gz"
        download_file "$url" "$tarball"
        tar -xf "$tarball" -C "$AGSBX_DIR"
        mv "$AGSBX_DIR"/sing-box*/sing-box "$SINGBOX_PATH"
        rm -rf "$tarball" "$AGSBX_DIR"/sing-box*
    fi

    if [[ "$INSTALL_CHOICE" =~ ^(2|3)$ ]] && [ ! -f "$CLOUDFLARED_PATH" ]; then
        url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$arch"
        download_file "$url" "$CLOUDFLARED_PATH"
    fi

    # --- TLS ---
    if [[ "$INSTALL_CHOICE" =~ ^(1|3)$ ]]; then
        openssl ecparam -genkey -name prime256v1 -out "$KEY_PATH"
        openssl req -new -x509 -days 36500 -key "$KEY_PATH" -out "$CERT_PATH" -subj "/CN=www.bing.com"
    fi

    UUID=$($SINGBOX_PATH generate uuid)
    echo "UUID='$UUID'" >> "$VARS_PATH"

    do_generate_config
    create_systemd_services

    systemctl restart singbox
    [[ "$INSTALL_CHOICE" =~ ^(2|3)$ ]] && systemctl restart argo

    print_msg "安装完成！" green
    do_list
}

# ======================================================================
# ★★★ 配置生成 ★★★
# ======================================================================

do_generate_config() {
    load_variables

    argo_inbound=""
    if [[ "$INSTALL_CHOICE" =~ ^(2|3)$ ]]; then
        if [ "$ARGO_PROTOCOL" = "vless" ]; then
argo_inbound=$(cat <<EOF
{
"type":"vless",
"listen":"127.0.0.1",
"listen_port":$ARGO_LOCAL_PORT,
"users":[{"uuid":"$UUID"}],
"transport":{"type":"ws","path":"/$UUID-vl"}
}
EOF
)
        else
argo_inbound=$(cat <<EOF
{
"type":"vmess",
"listen":"127.0.0.1",
"listen_port":$ARGO_LOCAL_PORT,
"users":[{"uuid":"$UUID","alterId":0}],
"transport":{"type":"ws","path":"/$UUID-vm"}
}
EOF
)
        fi
    fi

    # 配置写入
    if [ "$INSTALL_CHOICE" = "1" ]; then
cat > "$CONFIG_PATH" <<EOF
{
"log":{"level":"info"},
"inbounds":[
  {
    "type":"tuic",
    "listen":"::",
    "listen_port":$TUIC_PORT,
    "users":[{"uuid":"$UUID","password":"$UUID"}],
    "congestion_control":"bbr",
    "tls":{"enabled":true,"server_name":"www.bing.com","alpn":["h3"],"certificate_path":"$CERT_PATH","key_path":"$KEY_PATH"}
  }
],
"outbounds":[{"type":"direct"}]
}
EOF

    elif [ "$INSTALL_CHOICE" = "2" ]; then
cat > "$CONFIG_PATH" <<EOF
{
"log":{"level":"info"},
"inbounds":[
  $argo_inbound
],
"outbounds":[{"type":"direct"}]
}
EOF

    elif [ "$INSTALL_CHOICE" = "3" ]; then
cat > "$CONFIG_PATH" <<EOF
{
"log":{"level":"info"},
"inbounds":[
  {
    "type":"tuic",
    "listen":"::",
    "listen_port":$TUIC_PORT,
    "users":[{"uuid":"$UUID","password":"$UUID"}],
    "congestion_control":"bbr",
    "tls":{"enabled":true,"server_name":"www.bing.com","alpn":["h3"],"certificate_path":"$CERT_PATH","key_path":"$KEY_PATH"}
  },
  $argo_inbound
],
"outbounds":[{"type":"direct"}]
}
EOF
    fi
}

# ======================================================================
# ★★★ 控制 ★★★
# ======================================================================
do_start() { systemctl restart singbox; [[ "$INSTALL_CHOICE" =~ ^(2|3)$ ]] && systemctl restart argo; }
do_stop() { systemctl stop singbox; systemctl stop argo; }
do_restart() { do_start; }

do_uninstall() {
    echo -n "确认卸载？ (y/n): "
    read confirm
    [[ "$confirm" != "y" ]] && exit 0

    systemctl disable singbox --now
    systemctl disable argo --now

    rm -f $SYSTEMD_SINGBOX
    rm -f $SYSTEMD_ARGO

    systemctl daemon-reload

    rm -rf "$AGSBX_DIR"
    print_msg "卸载完成！" green
}

# ======================================================================
# ★★★ 显示节点 ★★★
# ======================================================================

do_list() {
    load_variables
    ip4=$(get_server_ip)
    ip6=$(get_server_ipv6)
    host=$(hostname)

    [[ "$INSTALL_CHOICE" =~ ^(1|3)$ ]] && {
        tuic_param="congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=www.bing.com&allow_insecure=1"

        print_msg "=== TUIC IPv4 ===" yellow
        echo "tuic://${UUID}:${UUID}@${ip4}:${TUIC_PORT}?${tuic_param}#tuic-ipv4-${host}"

        print_msg "=== TUIC IPv6 ===" yellow
        echo "tuic://${UUID}:${UUID}@[${ip6}]:${TUIC_PORT}?${tuic_param}#tuic-ipv6-${host}"
    }

    [[ "$INSTALL_CHOICE" =~ ^(2|3)$ ]] && {
        print_msg "--- Argo 节点 ---" yellow
        echo "域名: $ARGO_DOMAIN"

        if [ "$ARGO_PROTOCOL" = "vless" ]; then
            echo "vless://${UUID}@${ARGO_DOMAIN}:443?encryption=none&security=tls&sni=${ARGO_DOMAIN}&host=${ARGO_DOMAIN}&type=ws&path=%2f${UUID}-vl#argo-vless-${host}"
        else
            vmess_json="{\"v\":\"2\",\"ps\":\"argo-vmess-$host\",\"add\":\"$ARGO_DOMAIN\",\"port\":\"443\",\"id\":\"$UUID\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$ARGO_DOMAIN\",\"tls\":\"tls\",\"sni\":\"$ARGO_DOMAIN\",\"path\":\"/$UUID-vm\"}"
            vmess_base64=$(echo "$vmess_json" | base64 -w0)
            echo "vmess://${vmess_base64}"
        fi
    }
}

show_help() {
    echo "用法: bash $0 [ install | start | stop | restart | list | uninstall ]"
}

# ======================================================================
# ★★★ 主入口 ★★★
# ======================================================================

case "$1" in
    install) do_install ;;
    list)    do_list ;;
    start)   do_start ;;
    stop)    do_stop ;;
    restart) do_restart ;;
    uninstall) do_uninstall ;;
    *)       show_help ;;
esac
