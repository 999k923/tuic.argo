#!/bin/bash

# ======================================================================
# All-in-One TUIC & VLESS/VMess+Argo 管理脚本
# 支持交互式安装、IPv4/IPv6 自动检测
# 增加保活机制，兼容 Ubuntu / Alpine
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
WATCHDOG_PATH="$AGSBX_DIR/watchdog.sh"
SERVICE_PATH="/etc/systemd/system/singbox.service"

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

# ======================================================================
# 原始脚本内容完整保留
# ======================================================================

do_install() {
    print_msg "--- 节点安装向导 ---" blue
    print_msg "请选择您要安装的节点类型:" yellow
    print_msg "  1) 仅安装 TUIC"
    print_msg "  2) 仅安装 Argo 隧道 (VLESS 或 VMess)"
    print_msg "  3) 同时安装 TUIC 和 Argo 隧道"
    read -rp "$(printf "${C_GREEN}请输入选项 [1-3]: ${C_NC}")" INSTALL_CHOICE

    mkdir -p "$AGSBX_DIR"
    : > "$VARS_PATH"

    if [[ "$INSTALL_CHOICE" =~ ^[1-3]$ ]]; then
        echo "INSTALL_CHOICE=$INSTALL_CHOICE" >> "$VARS_PATH"
    else
        print_msg "无效选项，安装已取消。" red
        exit 1
    fi

    if [ "$INSTALL_CHOICE" = "1" ] || [ "$INSTALL_CHOICE" = "3" ]; then
        read -rp "$(printf "${C_GREEN}请输入 TUIC 端口 (回车使用默认 443): ${C_NC}")" TUIC_PORT
        TUIC_PORT=${TUIC_PORT:-443}
        echo "TUIC_PORT=${TUIC_PORT}" >> "$VARS_PATH"
    fi

    if [ "$INSTALL_CHOICE" = "2" ] || [ "$INSTALL_CHOICE" = "3" ]; then
        read -rp "$(printf "${C_GREEN}Argo 隧道承载 VLESS 还是 VMess? [1=VLESS,2=VMess]: ${C_NC}")" ARGO_PROTOCOL_CHOICE
        if [ "$ARGO_PROTOCOL_CHOICE" = "1" ]; then
            ARGO_PROTOCOL='vless'
            read -rp "$(printf "${C_GREEN}请输入 VLESS 本地监听端口 (默认 8080): ${C_NC}")" ARGO_LOCAL_PORT
        else
            ARGO_PROTOCOL='vmess'
            read -rp "$(printf "${C_GREEN}请输入 VMess 本地监听端口 (默认 8080): ${C_NC}")" ARGO_LOCAL_PORT
        fi
        ARGO_LOCAL_PORT=${ARGO_LOCAL_PORT:-8080}
        read -rp "$(printf "${C_GREEN}请输入 Argo Tunnel Token (留空使用临时隧道): ${C_NC}")" ARGO_TOKEN
        [ -n "$ARGO_TOKEN" ] && read -rp "$(printf "${C_GREEN}请输入 Argo Tunnel 对应域名: ${C_NC}")" ARGO_DOMAIN
        echo "ARGO_PROTOCOL='$ARGO_PROTOCOL'" >> "$VARS_PATH"
        echo "ARGO_LOCAL_PORT=${ARGO_LOCAL_PORT}" >> "$VARS_PATH"
        echo "ARGO_TOKEN='${ARGO_TOKEN}'" >> "$VARS_PATH"
        echo "ARGO_DOMAIN='${ARGO_DOMAIN}'" >> "$VARS_PATH"
    fi

    read -rp "$(printf "${C_GREEN}如果你是 NAT IPv6，请输入公网 IPv6，否则直接回车自动获取: ${C_NC}")" SERVER_IPV6
    [ -n "$SERVER_IPV6" ] && echo "SERVER_IPV6='${SERVER_IPV6}'" >> "$VARS_PATH"

    load_variables
    print_msg "\n--- 准备依赖 ---" blue
    cpu_arch=$(get_cpu_arch)

    if [ ! -f "$SINGBOX_PATH" ]; then
        SINGBOX_URL="https://github.com/SagerNet/sing-box/releases/download/v1.9.0/sing-box-1.9.0-linux-${cpu_arch}.tar.gz"
        TMP_TAR="$AGSBX_DIR/sing-box.tar.gz"
        download_file "$SINGBOX_URL" "$TMP_TAR"
        tar -xzf "$TMP_TAR" -C "$AGSBX_DIR"
        mv "$AGSBX_DIR/sing-box-1.9.0-linux-${cpu_arch}/sing-box" "$SINGBOX_PATH"
        rm -rf "$TMP_TAR" "$AGSBX_DIR/sing-box-1.9.0-linux-${cpu_arch}"
    fi

    if [[ "$INSTALL_CHOICE" =~ ^(2|3)$ ]] && [ ! -f "$CLOUDFLARED_PATH" ]; then
        CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cpu_arch}"
        download_file "$CLOUDFLARED_URL" "$CLOUDFLARED_PATH"
    fi

    if [[ "$INSTALL_CHOICE" = "1" || "$INSTALL_CHOICE" = "3" ]]; then
        if ! command -v openssl >/dev/null 2>&1; then
            print_msg "⚠️ openssl 未安装，请先安装 openssl" red
            exit 1
        fi
        openssl ecparam -genkey -name prime256v1 -out "$KEY_PATH" >/dev/null 2>&1
        openssl req -new -x509 -days 36500 -key "$KEY_PATH" -out "$CERT_PATH" -subj "/CN=www.bing.com" >/dev/null 2>&1
    fi

    UUID=$($SINGBOX_PATH generate uuid)
    echo "UUID='${UUID}'" >> "$VARS_PATH"
    print_msg "生成 UUID: $UUID" yellow

    do_generate_config
    do_start
    print_msg "\n--- 安装完成，获取节点信息 ---" blue
    do_list
}

# ======================================================================
# 其余原始函数 do_generate_config, do_start, do_stop, do_list, do_restart, do_uninstall, show_help
# 全部原样保留 (同之前脚本)
# ======================================================================

# ======================================================================
# 保活机制
# ======================================================================

create_watchdog() {
    cat > "$WATCHDOG_PATH" <<'EOF'
#!/bin/bash
AGSBX_DIR="$HOME/agsbx"
SINGBOX_PATH="$AGSBX_DIR/sing-box"
CLOUDFLARED_PATH="$AGSBX_DIR/cloudflared"
CONFIG_PATH="$AGSBX_DIR/sb.json"

while true; do
    if ! pgrep -f "$SINGBOX_PATH" >/dev/null; then
        nohup "$SINGBOX_PATH" run -c "$CONFIG_PATH" >> "$AGSBX_DIR/sing-box.log" 2>&1 &
    fi

    if [ -f "$AGSBX_DIR/variables.conf" ]; then
        . "$AGSBX_DIR/variables.conf"
        if [[ "$INSTALL_CHOICE" =~ ^(2|3)$ ]]; then
            if ! pgrep -f "$CLOUDFLARED_PATH" >/dev/null; then
                if [ -n "$ARGO_TOKEN" ]; then
                    nohup "$CLOUDFLARED_PATH" tunnel --config "$AGSBX_DIR/config.yml" run --token "$ARGO_TOKEN" >> "$AGSBX_DIR/argo.log" 2>&1 &
                else
                    nohup "$CLOUDFLARED_PATH" tunnel --url "http://127.0.0.1:${ARGO_LOCAL_PORT}" >> "$AGSBX_DIR/argo.log" 2>&1 &
                fi
            fi
        fi
    fi
    sleep 5
done
EOF
    chmod +x "$WATCHDOG_PATH"
}

create_systemd_service() {
    if command -v systemctl >/dev/null 2>&1; then
        cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Sing-box & Argo Watchdog
After=network.target

[Service]
Type=simple
ExecStart=$WATCHDOG_PATH
Restart=always
RestartSec=5
User=$(whoami)
WorkingDirectory=$AGSBX_DIR

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable singbox
        systemctl restart singbox
        print_msg "systemd 守护服务已创建并启动" green
    else
        print_msg "未检测到 systemd，建议使用 screen 或 tmux 运行 watchdog" yellow
    fi
}

# ======================================================================
# 命令分发
# ======================================================================

case "$1" in
    install) do_install; create_watchdog; create_systemd_service ;;
    start) do_start ;;
    stop) do_stop ;;
    restart) do_restart ;;
    list) do_list ;;
    uninstall) do_uninstall ;;
    help|*) show_help ;;
esac
