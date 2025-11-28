#!/bin/bash

# ===========================
# All-in-One TUIC + VLESS/VMess + Argo
# 改进版本 (交互式安装 + 自动生成证书)
# ===========================

# --- 颜色 ---
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_NC='\033[0m'

# --- 路径 ---
HOME_DIR=$(eval echo ~)
AGSBX_DIR="$HOME_DIR/agsbx"
SINGBOX_PATH="$AGSBX_DIR/sing-box"
CLOUDFLARED_PATH="$AGSBX_DIR/cloudflared"
CONFIG_PATH="$AGSBX_DIR/sb.json"
CERT_PATH="$AGSBX_DIR/cert.pem"
KEY_PATH="$AGSBX_DIR/private.key"
VARS_PATH="$AGSBX_DIR/variables.conf"

# --- 辅助函数 ---
print_msg() { printf "${2:+$2}%s${C_NC}\n" "$1"; }
get_cpu_arch() { case "$(uname -m)" in x86_64) echo "amd64";; aarch64) echo "arm64";; *) print_msg "不支持的 CPU 架构 $(uname -m)" "$C_RED"; exit 1;; esac }
download_file() { local url="$1"; local dest="$2"; print_msg "下载 $(basename "$dest")..." "$C_YELLOW"; curl -# -Lo "$dest" "$url" || wget -q --show-progress -O "$dest" "$url"; chmod +x "$dest"; print_msg "$(basename "$dest") 下载完成" "$C_GREEN"; }
load_variables() { [ -f "$VARS_PATH" ] && . "$VARS_PATH"; }

get_server_ip() { curl -s https://icanhazip.com || wget -qO- https://icanhazip.com; }

# --- 核心安装函数 ---
do_install() {
    print_msg "--- 节点安装向导 ---" "$C_BLUE"
    print_msg "请选择节点类型: 1) TUIC 2) Argo 3) 两者" "$C_YELLOW"
    read -rp "请输入选项 [1-3]: " INSTALL_CHOICE

    mkdir -p "$AGSBX_DIR"; : > "$VARS_PATH"

    # TUIC
    if [[ "$INSTALL_CHOICE" =~ ^1|3$ ]]; then
        read -rp "请输入 TUIC 端口 (回车默认 443): " TUIC_PORT
        TUIC_PORT=${TUIC_PORT:-443}
        echo "TUIC_PORT=$TUIC_PORT" >> "$VARS_PATH"
    fi

    # Argo
    if [[ "$INSTALL_CHOICE" =~ ^2|3$ ]]; then
        read -rp "Argo 隧道承载 VLESS 或 VMess [1=VLESS,2=VMess]: " ARGO_PROTO_CHOICE
        if [[ "$ARGO_PROTO_CHOICE" == "1" ]]; then ARGO_PROTOCOL="vless"; else ARGO_PROTOCOL="vmess"; fi
        read -rp "本地监听端口 (回车默认 8080): " ARGO_LOCAL_PORT
        ARGO_LOCAL_PORT=${ARGO_LOCAL_PORT:-8080}
        read -rp "Argo Token (回车使用临时隧道): " ARGO_TOKEN
        if [ -n "$ARGO_TOKEN" ]; then read -rp "Argo 域名: " ARGO_DOMAIN; fi
        echo "ARGO_PROTOCOL='$ARGO_PROTOCOL'" >> "$VARS_PATH"
        echo "ARGO_LOCAL_PORT=$ARGO_LOCAL_PORT" >> "$VARS_PATH"
        echo "ARGO_TOKEN='$ARGO_TOKEN'" >> "$VARS_PATH"
        echo "ARGO_DOMAIN='$ARGO_DOMAIN'" >> "$VARS_PATH"
    fi

    echo "INSTALL_CHOICE=$INSTALL_CHOICE" >> "$VARS_PATH"
    load_variables

    # --- 下载依赖 ---
    mkdir -p "$AGSBX_DIR"
    CPU_ARCH=$(get_cpu_arch)

    [ ! -f "$SINGBOX_PATH" ] && {
        SINGBOX_URL="https://github.com/SagerNet/sing-box/releases/download/v1.9.0/sing-box-1.9.0-linux-$CPU_ARCH.tar.gz"
        TEMP_TAR="$AGSBX_DIR/sing-box.tar.gz"
        download_file "$SINGBOX_URL" "$TEMP_TAR"
        tar -xzf "$TEMP_TAR" -C "$AGSBX_DIR"
        mv "$AGSBX_DIR"/sing-box-1.9.0-linux-$CPU_ARCH/sing-box "$SINGBOX_PATH"
        rm -rf "$TEMP_TAR" "$AGSBX_DIR"/sing-box-1.9.0-linux-$CPU_ARCH
    }

    if [[ "$INSTALL_CHOICE" =~ ^2|3$ ]] && [ ! -f "$CLOUDFLARED_PATH" ]; then
        CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$CPU_ARCH"
        download_file "$CLOUDFLARED_URL" "$CLOUDFLARED_PATH"
    fi

    # --- 生成 UUID ---
    UUID=$($SINGBOX_PATH generate uuid)
    echo "UUID='$UUID'" >> "$VARS_PATH"
    print_msg "生成 UUID: $UUID" "$C_YELLOW"

    # --- 生成 TLS 证书 (如果 TUIC 需要 TLS) ---
    if [[ "$INSTALL_CHOICE" =~ ^1|3$ ]]; then
        if [ ! -f "$KEY_PATH" ] || [ ! -f "$CERT_PATH" ]; then
            openssl ecparam -genkey -name prime256v1 -out "$KEY_PATH"
            openssl req -new -x509 -days 36500 -key "$KEY_PATH" -out "$CERT_PATH" -subj "/CN=www.bing.com"
            print_msg "TLS 证书生成完成" "$C_GREEN"
        fi
    fi

    # --- 生成配置文件 ---
    generate_config

    # --- 启动服务 ---
    do_start

    print_msg "--- 安装完成 ---" "$C_BLUE"
    do_list
}

# --- 生成 sing-box 配置 ---
generate_config() {
    INBOUNDS=""
    # TUIC
    if [[ "$INSTALL_CHOICE" =~ ^1|3$ ]]; then
        INBOUNDS=$(cat <<EOF
{"type":"tuic","tag":"tuic-in","listen":"::","listen_port":$TUIC_PORT,"users":[{"uuid":"$UUID","password":"$UUID"}],"congestion_control":"bbr","tls":{"enabled":true,"server_name":"www.bing.com","alpn":["h3"],"certificate_path":"$CERT_PATH","key_path":"$KEY_PATH"}}
EOF
)
    fi
    # Argo
    if [[ "$INSTALL_CHOICE" =~ ^2|3$ ]]; then
        if [[ "$ARGO_PROTOCOL" == "vless" ]]; then
            ARGO_IN=$(printf '{"type":"vless","tag":"vless-in","listen":"127.0.0.1","listen_port":%s,"users":[{"uuid":"%s"}],"transport":{"type":"ws","path":"/%s-vl"}}' "$ARGO_LOCAL_PORT" "$UUID" "$UUID")
        else
            ARGO_IN=$(printf '{"type":"vmess","tag":"vmess-in","listen":"127.0.0.1","listen_port":%s,"users":[{"uuid":"%s","alterId":0}],"transport":{"type":"ws","path":"/%s-vm"}}' "$ARGO_LOCAL_PORT" "$UUID" "$UUID")
        fi
        INBOUNDS="${INBOUNDS},${ARGO_IN}"
    fi

    cat > "$CONFIG_PATH" <<EOF
{
  "log":{"level":"info","timestamp":true},
  "inbounds":[ $INBOUNDS ],
  "outbounds":[{"type":"direct","tag":"direct"}]
}
EOF
    print_msg "配置文件生成成功: $CONFIG_PATH" "$C_GREEN"
}

# --- 启动服务 ---
do_start() {
    load_variables
    do_stop

    nohup "$SINGBOX_PATH" run -c "$CONFIG_PATH" > "$AGSBX_DIR/sing-box.log" 2>&1 &
    sleep 1
    if ! pgrep -f sing-box >/dev/null; then
        print_msg "sing-box 启动失败，请检查日志" "$C_RED"
        tail -n 20 "$AGSBX_DIR/sing-box.log"
        return
    fi
    print_msg "sing-box 已后台启动" "$C_GREEN"

    # Argo
    if [[ "$INSTALL_CHOICE" =~ ^2|3$ ]]; then
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
            print_msg "临时 Argo 隧道建立中..." "$C_YELLOW"
        fi
    fi
}

# --- 停止服务 ---
do_stop() {
    pkill -f "$SINGBOX_PATH"
    pkill -f "$CLOUDFLARED_PATH"
    print_msg "已停止 sing-box 和 cloudflared" "$C_GREEN"
}

# --- 重启 ---
do_restart() {
    do_stop
    sleep 1
    do_start
}

# --- 显示节点信息 ---
do_list() {
    load_variables || { print_msg "未找到配置文件，请先安装" "$C_RED"; return; }
    SERVER_IP=$(get_server_ip)
    HOSTNAME=$(hostname)
    print_msg "--- 节点信息 ---" "$C_BLUE"

    # TUIC
    if [[ "$INSTALL_CHOICE" =~ ^1|3$ ]]; then
        TUIC_LINK="tuic://$UUID:$UUID@$SERVER_IP:$TUIC_PORT?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=www.bing.com&allow_insecure=1#tuic-$HOSTNAME"
        print_msg "--- TUIC 节点 ---" "$C_YELLOW"
        echo "$TUIC_LINK"
    fi

    # Argo
    if [[ "$INSTALL_CHOICE" =~ ^2|3$ ]]; then
        CUR_DOMAIN="$ARGO_DOMAIN"
        if [ -z "$ARGO_TOKEN" ]; then
            TEMP_DOMAIN=$(grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare\.com' "$AGSBX_DIR/argo.log" | sed 's/https:\/\///' | head -n1)
            CUR_DOMAIN=${TEMP_DOMAIN:-"[请查看 argo.log 获取域名]"}
        fi

        if [[ "$ARGO_PROTOCOL" == "vless" ]]; then
            VLESS_LINK="vless://$UUID@$CUR_DOMAIN:443?encryption=none&security=tls&sni=$CUR_DOMAIN&fp=chrome&type=ws&host=$CUR_DOMAIN&path=%2f$UUID-vl#argo-vless-$HOSTNAME"
            print_msg "--- VLESS + Argo ---" "$C_YELLOW"
            echo "$VLESS_LINK"
        else
            VMESS_JSON=$(printf '{"v":"2","ps":"vmess-argo-%s","add":"%s","port":"443","id":"%s","aid":"0","scy":"auto","net":"ws","type":"none","host":"%s","path":"/%s-vm","tls":"tls","sni":"%s"}' "$HOSTNAME" "$CUR_DOMAIN" "$UUID" "$CUR_DOMAIN" "$UUID" "$CUR_DOMAIN")
            VMESS_BASE64=$(echo "$VMESS_JSON" | tr -d '\n' | base64 -w0)
            VMESS_LINK="vmess://$VMESS_BASE64"
            print_msg "--- VMess + Argo ---" "$C_YELLOW"
            echo "$VMESS_LINK"
        fi
    fi
}

# --- 卸载 ---
do_uninstall() {
    read -rp "确定删除所有文件吗? (y/n): " confirm
    [[ "$confirm" != "y" ]] && print_msg "卸载取消" "$C_GREEN" && exit
    do_stop
    rm -rf "$AGSBX_DIR"
    print_msg "卸载完成" "$C_GREEN"
}

# --- 帮助 ---
show_help() {
    print_msg "All-in-One TUIC + VLESS/VMess + Argo 脚本" "$C_BLUE"
    echo "用法: bash $0 [install|list|start|stop|restart|uninstall|help]"
}

# --- 主入口 ---
main() {
    case "$1" in
        install) do_install ;;
        start) do_start ;;
        stop) do_stop ;;
        restart) do_restart ;;
        list) do_list ;;
        uninstall) do_uninstall ;;
        help|*) show_help ;;
    esac
}

main "$@"
