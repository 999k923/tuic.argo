#!/bin/bash

# ======================================================================
# All-in-One TUIC5 / VLESS-WS-Argo 一键脚本（增强版 + IPv6 NAT 修复）
# 增强内容：
# - IPv6 NAT 场景下自动纠正 IPv6
# - list 输出备注（国家 + 协议类型 + IPv4/IPv6）
# - 完整 TUIC5 + Argo + TLS + Systemd
# ======================================================================

# -----------------------------
#   颜色
# -----------------------------
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_NC='\033[0m'

# -----------------------------
#   路径
# -----------------------------
HOME_DIR=$(eval echo ~)
AGSBX_DIR="$HOME_DIR/agsbx"
SINGBOX_PATH="$AGSBX_DIR/sing-box"
CLOUDFLARED_PATH="$AGSBX_DIR/cloudflared"
CONFIG_PATH="$AGSBX_DIR/sb.json"
CERT_PATH="$AGSBX_DIR/cert.pem"
KEY_PATH="$AGSBX_DIR/private.key"
VARS_PATH="$AGSBX_DIR/variables.conf"

# -----------------------------
#   公共函数
# -----------------------------
print_msg() {
    case "$2" in
        red)    printf "${C_RED}%s${C_NC}\n" "$1";;
        green)  printf "${C_GREEN}%s${C_NC}\n" "$1";;
        yellow) printf "${C_YELLOW}%s${C_NC}\n" "$1";;
        blue)   printf "${C_BLUE}%s${C_NC}\n" "$1";;
        *)      printf "%s\n" "$1";;
    esac
}

get_cpu_arch() {
    case "$(uname -m)" in
        x86_64) echo "amd64";;
        aarch64) echo "arm64";;
        *) print_msg "❌ 不支持的 CPU 架构 $(uname -m)" red; exit 1;;
    esac
}

download_file() {
    local url="$1"
    local dest="$2"
    print_msg "正在下载 $(basename "$dest")..." yellow
    if command -v curl >/dev/null; then
        curl -# -Lo "$dest" "$url"
    else
        wget -q --show-progress -O "$dest" "$url"
    fi
    chmod +x "$dest"
    print_msg "$(basename "$dest") 下载成功" green
}

load_variables() {
    [ -f "$VARS_PATH" ] && . "$VARS_PATH"
}

# -----------------------------
#   获取 IPv4 / IPv6
# -----------------------------
get_server_ipv4() {
    curl -4 -s https://icanhazip.com || wget -4 -qO- https://icanhazip.com
}

# 🚀 **NAT IPv6 场景修复：优先真实网卡 IPv6，否则回落出口 IPv6**
get_server_ipv6() {
    [ -n "$SERVER_IPV6" ] && echo "$SERVER_IPV6" && return

    local iface ipv6
    for iface in $(ls /sys/class/net | grep -v lo); do
        ipv6=$(ip -6 addr show dev "$iface" \
            | grep inet6 \
            | grep -v fe80 \
            | grep -v ::1 \
            | awk '{print $2}' | cut -d/ -f1 | head -n1)

        if [[ "$ipv6" =~ ":" ]]; then
            echo "$ipv6"
            return
        fi
    done

    # 出口 IPv6（NAT VPS 会走这里）
    curl -6 -s https://icanhazip.com || wget -6 -qO- https://icanhazip.com
}

# -----------------------------
#   安装
# -----------------------------
do_install() {
    print_msg "====== 安装向导 ======" blue

    print_msg "请选择安装类型：" yellow
    echo "1) TUIC5"
    echo "2) Argo（VLESS）"
    echo "3) TUIC5 + Argo"
    read -rp "输入选择[1-3]: " INSTALL_CHOICE

    mkdir -p "$AGSBX_DIR"
    : > "$VARS_PATH"

    echo "INSTALL_CHOICE=$INSTALL_CHOICE" >> "$VARS_PATH"

    # TUIC
    if [[ "$INSTALL_CHOICE" == "1" || "$INSTALL_CHOICE" == "3" ]]; then
        read -rp "请输入 TUIC 端口 (默认443): " TUIC_PORT
        TUIC_PORT=${TUIC_PORT:-443}
        echo "TUIC_PORT=$TUIC_PORT" >> "$VARS_PATH"
    fi

    # Argo
    if [[ "$INSTALL_CHOICE" == "2" || "$INSTALL_CHOICE" == "3" ]]; then
        read -rp "请输入 Argo 本地端口 (默认8080): " ARGO_LOCAL_PORT
        ARGO_LOCAL_PORT=${ARGO_LOCAL_PORT:-8080}

        read -rp "请输入 Argo Token（留空临时隧道）: " ARGO_TOKEN
        [ -n "$ARGO_TOKEN" ] && read -rp "请输入 Argo 绑定域名: " ARGO_DOMAIN

        echo "ARGO_LOCAL_PORT=$ARGO_LOCAL_PORT" >> "$VARS_PATH"
        echo "ARGO_TOKEN='$ARGO_TOKEN'" >> "$VARS_PATH"
        echo "ARGO_DOMAIN='$ARGO_DOMAIN'" >> "$VARS_PATH"
    fi

    # IPv6 NAT 修复
    read -rp "如果你是 NAT IPv6，请输入真实 IPv6（否则回车自动获取）: " SERVER_IPV6
    [ -n "$SERVER_IPV6" ] && echo "SERVER_IPV6='$SERVER_IPV6'" >> "$VARS_PATH"

    load_variables

    # 下载
    arch=$(get_cpu_arch)

    if [ ! -f "$SINGBOX_PATH" ]; then
        url="https://github.com/SagerNet/sing-box/releases/download/v1.9.0/sing-box-1.9.0-linux-${arch}.tar.gz"
        tmp="$AGSBX_DIR/sb.tar.gz"
        download_file "$url" "$tmp"
        tar -xzf "$tmp" -C "$AGSBX_DIR"
        mv "$AGSBX_DIR"/sing-box-*/sing-box "$SINGBOX_PATH"
        rm -rf "$tmp" "$AGSBX_DIR"/sing-box-*
    fi

    if [[ "$INSTALL_CHOICE" =~ [23] && ! -f "$CLOUDFLARED_PATH" ]]; then
        download_file "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}" "$CLOUDFLARED_PATH"
    fi

    # TLS
    if ! command -v openssl >/dev/null; then
        print_msg "❌ 缺少 openssl，请安装后重试" red
        exit 1
    fi
    openssl ecparam -genkey -name prime256v1 -out "$KEY_PATH" >/dev/null
    openssl req -new -x509 -days 36500 -key "$KEY_PATH" -out "$CERT_PATH" -subj "/CN=www.bing.com" >/dev/null

    # UUID
    UUID=$("$SINGBOX_PATH" generate uuid)
    echo "UUID='$UUID'" >> "$VARS_PATH"

    do_generate_config
    do_start
    do_list
}

# -----------------------------
#   生成配置
# -----------------------------
do_generate_config() {
    load_variables

    if [[ "$INSTALL_CHOICE" == "1" ]]; then
        cat > "$CONFIG_PATH" <<EOF
{
  "log":{"level":"info"},
  "inbounds":[{
    "type":"tuic",
    "tag":"tuic-in",
    "listen":"::",
    "listen_port":$TUIC_PORT,
    "users":[{"uuid":"$UUID","password":"$UUID"}],
    "congestion_control":"bbr",
    "tls":{
      "enabled":true,
      "server_name":"www.bing.com",
      "certificate_path":"$CERT_PATH",
      "key_path":"$KEY_PATH",
      "alpn":["h3"]
    }
  }],
  "outbounds":[{"type":"direct"}]
}
EOF
    fi

    if [[ "$INSTALL_CHOICE" == "2" || "$INSTALL_CHOICE" == "3" ]]; then
        inbound_argo=$(printf '{"type":"vless","listen":"127.0.0.1","listen_port":%s,"users":[{"uuid":"%s"}],"transport":{"type":"ws","path":"/%s-vl"}}' "$ARGO_LOCAL_PORT" "$UUID" "$UUID")

        if [[ "$INSTALL_CHOICE" == "2" ]]; then
            tuic_part=""
        else
            tuic_part=$(cat <<EOF
{
  "type":"tuic",
  "listen":"::",
  "listen_port":$TUIC_PORT,
  "users":[{"uuid":"$UUID","password":"$UUID"}],
  "congestion_control":"bbr",
  "tls":{
    "enabled":true,
    "certificate_path":"$CERT_PATH",
    "key_path":"$KEY_PATH",
    "server_name":"www.bing.com"
  }
},
EOF
)
        fi

        cat > "$CONFIG_PATH" <<EOF
{
  "log":{"level":"info"},
  "inbounds":[
    $tuic_part
    $inbound_argo
  ],
  "outbounds":[{"type":"direct"}]
}
EOF
    fi
}

# -----------------------------
#   启停
# -----------------------------
do_start() {
    do_stop
    nohup "$SINGBOX_PATH" run -c "$CONFIG_PATH" > "$AGSBX_DIR/sing-box.log" 2>&1 &

    load_variables
    if [ -n "$ARGO_LOCAL_PORT" ]; then
        if [ -n "$ARGO_TOKEN" ]; then
            cat > "$AGSBX_DIR/config.yml" <<EOF
ingress:
  - hostname: $ARGO_DOMAIN
    service: http://127.0.0.1:$ARGO_LOCAL_PORT
  - service: http_status:404
EOF
            nohup "$CLOUDFLARED_PATH" tunnel --config "$AGSBX_DIR/config.yml" run --token "$ARGO_TOKEN" > "$AGSBX_DIR/argo.log" &
        else
            nohup "$CLOUDFLARED_PATH" tunnel --url "http://127.0.0.1:$ARGO_LOCAL_PORT" > "$AGSBX_DIR/argo.log" &
        fi
    fi

    print_msg "服务已启动" green
}

do_stop() {
    pkill -f "$SINGBOX_PATH" >/dev/null 2>&1
    pkill -f "$CLOUDFLARED_PATH" >/dev/null 2>&1
}

# -----------------------------
#   节点信息
# -----------------------------
do_list() {
    load_variables

    ipv4=$(get_server_ipv4)
    ipv6=$(get_server_ipv6)
    country=$(curl -s https://ipapi.co/country_name/ || echo "Unknown")
    host=$(hostname)

    print_msg "====== 节点信息 ======" blue

    if [[ "$INSTALL_CHOICE" =~ [13] ]]; then
        params="congestion_control=bbr&alpn=h3&sni=www.bing.com&allow_insecure=1"
        echo -e "\n▶ TUIC (IPv4) [$country / IPv4]"
        echo "tuic://$UUID:$UUID@$ipv4:$TUIC_PORT?$params#tuic-$host"

        echo -e "\n▶ TUIC (IPv6) [$country / IPv6]"
        echo "tuic://$UUID:$UUID@[$ipv6]:$TUIC_PORT?$params#tuic-$host"
    fi

    if [[ "$INSTALL_CHOICE" =~ [23] ]]; then
        domain="$ARGO_DOMAIN"
        echo -e "\n▶ Argo VLESS [$country / CDN]"
        echo "vless://$UUID@$domain:443?encryption=none&security=tls&type=ws&host=$domain&path=/$UUID-vl&sni=$domain#argo-$host"
    fi
}

# -----------------------------
#   卸载
# -----------------------------
do_uninstall() {
    read -rp "确认卸载？(y/n): " x
    [[ "$x" != "y" ]] && exit
    do_stop
    rm -rf "$AGSBX_DIR"
    print_msg "已卸载" green
}

# -----------------------------
#   主入口
# -----------------------------
case "$1" in
    install) do_install ;;
    list) do_list ;;
    start) do_start ;;
    stop) do_stop ;;
    restart) do_stop; sleep 1; do_start ;;
    uninstall) do_uninstall ;;
    *) echo "用法: bash $0 {install|list|start|stop|restart|uninstall}" ;;
esac
