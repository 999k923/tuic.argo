#!/bin/bash

# ==============================================================================
# All-in-One TUIC & VLESS/VMess + Argo 管理脚本 (v3.4)
# 交互式安装，自动写入变量，支持 list/start/stop/restart/uninstall
# ==============================================================================

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
print_msg() {
    local msg="$1"
    local color="$2"
    case "$color" in
        red) printf "${C_RED}%s\n${C_NC}" "$msg" ;;
        green) printf "${C_GREEN}%s\n${C_NC}" "$msg" ;;
        yellow) printf "${C_YELLOW}%s\n${C_NC}" "$msg" ;;
        blue) printf "${C_BLUE}%s\n${C_NC}" "$msg" ;;
        *) echo "$msg" ;;
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
    print_msg "$(basename "$dest") 下载成功" "green"
}

get_server_ip() {
    if command -v curl >/dev/null 2>&1; then curl -s https://icanhazip.com; else wget -qO- https://icanhazip.com; fi
}

load_variables() {
    if [ -f "$VARS_PATH" ]; then
        . "$VARS_PATH"
    else
        return 1
    fi
}

# --- 核心函数 ---
do_install() {
    print_msg "--- 节点安装向导 ---" "blue"
    print_msg "请选择您要安装的节点类型:" "yellow"
    print_msg " 1) 仅安装 TUIC"
    print_msg " 2) 仅安装 Argo 隧道 (VLESS 或 VMess)"
    print_msg " 3) 同时安装 TUIC 和 Argo 隧道"
    read -rp "请输入选项 [1-3]: " INSTALL_CHOICE
    if [[ ! "$INSTALL_CHOICE" =~ ^[1-3]$ ]]; then
        print_msg "无效选项，安装取消。" "red"; exit 1
    fi

    mkdir -p "$AGSBX_DIR"
    : > "$VARS_PATH"
    echo "INSTALL_CHOICE=$INSTALL_CHOICE" >> "$VARS_PATH"

    # TUIC
    if [[ "$INSTALL_CHOICE" = "1" || "$INSTALL_CHOICE" = "3" ]]; then
        read -rp "请输入 TUIC 端口 (回车使用默认 443): " TUIC_PORT
        TUIC_PORT=${TUIC_PORT:-443}
        echo "TUIC_PORT=$TUIC_PORT" >> "$VARS_PATH"
    fi

    # Argo
    if [[ "$INSTALL_CHOICE" = "2" || "$INSTALL_CHOICE" = "3" ]]; then
        read -rp "Argo 隧道承载 VLESS 还是 VMess? [1 for VLESS, 2 for VMess]: " ARGO_PROTOCOL_CHOICE
        if [[ "$ARGO_PROTOCOL_CHOICE" = "1" ]]; then ARGO_PROTOCOL='vless'; else ARGO_PROTOCOL='vmess'; fi
        echo "ARGO_PROTOCOL='$ARGO_PROTOCOL'" >> "$VARS_PATH"

        read -rp "请输入 Argo 本地监听端口 (例如 8080): " ARGO_LOCAL_PORT
        echo "ARGO_LOCAL_PORT=$ARGO_LOCAL_PORT" >> "$VARS_PATH"

        read -rp "请输入 Argo Tunnel 的 Token (回车使用临时隧道): " ARGO_TOKEN
        echo "ARGO_TOKEN='$ARGO_TOKEN'" >> "$VARS_PATH"

        if [[ -n "$ARGO_TOKEN" ]]; then
            read -rp "请输入 Argo Tunnel 对应的域名: " ARGO_DOMAIN
            echo "ARGO_DOMAIN='$ARGO_DOMAIN'" >> "$VARS_PATH"
        else
            ARGO_DOMAIN=""
            echo "ARGO_DOMAIN=''" >> "$VARS_PATH"
        fi
    fi

    load_variables

    print_msg "\n--- 正在准备依赖环境 ---" "blue"
    local cpu_arch; cpu_arch=$(get_cpu_arch)

    # sing-box
    if [ ! -f "$SINGBOX_PATH" ]; then
        local sb_url="https://github.com/SagerNet/sing-box/releases/download/v1.9.0/sing-box-1.9.0-linux-${cpu_arch}.tar.gz"
        local temp_tar="$AGSBX_DIR/sing-box.tar.gz"
        download_file "$sb_url" "$temp_tar"
        tar -xzf "$temp_tar" -C "$AGSBX_DIR"
        mv "$AGSBX_DIR/sing-box-1.9.0-linux-${cpu_arch}/sing-box" "$SINGBOX_PATH"
        rm -rf "$temp_tar" "$AGSBX_DIR/sing-box-1.9.0-linux-${cpu_arch}"
    fi

    # cloudflared
    if [[ "$INSTALL_CHOICE" = "2" || "$INSTALL_CHOICE" = "3" ]]; then
        if [ ! -f "$CLOUDFLARED_PATH" ]; then
            local cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cpu_arch}"
            download_file "$cf_url" "$CLOUDFLARED_PATH"
        fi
    fi

    # 生成 UUID
    UUID=$($SINGBOX_PATH generate uuid)
    echo "UUID='$UUID'" >> "$VARS_PATH"
    print_msg "生成 UUID: $UUID" "yellow"

    # --- 生成配置 ---
    if [[ "$INSTALL_CHOICE" = "1" ]]; then
        openssl ecparam -genkey -name prime256v1 -out "$KEY_PATH" >/dev/null 2>&1
        openssl req -new -x509 -days 36500 -key "$KEY_PATH" -out "$CERT_PATH" -subj "/CN=www.bing.com" >/dev/null 2>&1
        cat > "$CONFIG_PATH" <<EOF
{
    "log":{"level":"info","timestamp":true},
    "inbounds":[{"type":"tuic","tag":"tuic-in","listen":"::","listen_port":$TUIC_PORT,"users":[{"uuid":"$UUID","password":"$UUID"}],"congestion_control":"bbr","tls":{"enabled":true,"server_name":"www.bing.com","alpn":["h3"],"certificate_path":"$CERT_PATH","key_path":"$KEY_PATH"}}],
    "outbounds":[{"type":"direct","tag":"direct"}]
}
EOF
    elif [[ "$INSTALL_CHOICE" = "2" ]]; then
        if [[ "$ARGO_PROTOCOL" = "vless" ]]; then
            argo_inbound="{\"type\":\"vless\",\"tag\":\"vless-in\",\"listen\":\"127.0.0.1\",\"listen_port\":$ARGO_LOCAL_PORT,\"users\":[{\"uuid\":\"$UUID\"}],\"transport\":{\"type\":\"ws\",\"path\":\"/$UUID-vl\"}}"
        else
            argo_inbound="{\"type\":\"vmess\",\"tag\":\"vmess-in\",\"listen\":\"127.0.0.1\",\"listen_port\":$ARGO_LOCAL_PORT,\"users\":[{\"uuid\":\"$UUID\",\"alterId\":0}],\"transport\":{\"type\":\"ws\",\"path\":\"/$UUID-vm\"}}"
        fi
        cat > "$CONFIG_PATH" <<EOF
{
    "log":{"level":"info","timestamp":true},
    "inbounds":[ $argo_inbound ],
    "outbounds":[{"type":"direct","tag":"direct"}]
}
EOF
    elif [[ "$INSTALL_CHOICE" = "3" ]]; then
        openssl ecparam -genkey -name prime256v1 -out "$KEY_PATH" >/dev/null 2>&1
        openssl req -new -x509 -days 36500 -key "$KEY_PATH" -out "$CERT_PATH" -subj "/CN=www.bing.com" >/dev/null 2>&1
        if [[ "$ARGO_PROTOCOL" = "vless" ]]; then
            argo_inbound="{\"type\":\"vless\",\"tag\":\"vless-in\",\"listen\":\"127.0.0.1\",\"listen_port\":$ARGO_LOCAL_PORT,\"users\":[{\"uuid\":\"$UUID\"}],\"transport\":{\"type\":\"ws\",\"path\":\"/$UUID-vl\"}}"
        else
            argo_inbound="{\"type\":\"vmess\",\"tag\":\"vmess-in\",\"listen\":\"127.0.0.1\",\"listen_port\":$ARGO_LOCAL_PORT,\"users\":[{\"uuid\":\"$UUID\",\"alterId\":0}],\"transport\":{\"type\":\"ws\",\"path\":\"/$UUID-vm\"}}"
        fi
        cat > "$CONFIG_PATH" <<EOF
{
    "log":{"level":"info","timestamp":true},
    "inbounds":[
        {"type":"tuic","tag":"tuic-in","listen":"::","listen_port":$TUIC_PORT,"users":[{"uuid":"$UUID","password":"$UUID"}],"congestion_control":"bbr","tls":{"enabled":true,"server_name":"www.bing.com","alpn":["h3"],"certificate_path":"$CERT_PATH","key_path":"$KEY_PATH"}},
        $argo_inbound
    ],
    "outbounds":[{"type":"direct","tag":"direct"}]
}
EOF
    fi

    print_msg "配置文件已生成: $CONFIG_PATH" "green"

    do_start
    print_msg "\n--- 安装完成，节点信息 ---" "blue"
    do_list
}

do_list() {
    print_msg "--- 节点信息 ---" "blue"
    if ! load_variables; then print_msg "错误: 未找到配置文件，请先执行 install" "red"; exit 1; fi

    local server_ip; server_ip=$(get_server_ip)
    local hostname; hostname=$(hostname)

    if [[ "$INSTALL_CHOICE" = "1" || "$INSTALL_CHOICE" = "3" ]]; then
        local tuic_params="congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=www.bing.com&allow_insecure=1"
        local tuic_link="tuic://${UUID}:${UUID}@${server_ip}:${TUIC_PORT}?${tuic_params}#tuic-${hostname}"
        print_msg "--- TUIC 节点 ---" "yellow"
        echo "$tuic_link"
    fi

    if [[ "$INSTALL_CHOICE" = "2" || "$INSTALL_CHOICE" = "3" ]]; then
        local current_argo_domain="$ARGO_DOMAIN"
        if [[ -z "$ARGO_TOKEN" ]]; then
            print_msg "等待临时 Argo 域名生成..." "yellow"
            sleep 5
            local temp_argo_domain=$(grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare\.com' "$AGSBX_DIR/argo.log" | sed 's#https://##' | head -n1)
            current_argo_domain=${temp_argo_domain:-'[请从日志中手动查找域名]'}
        fi

        if [[ "$ARGO_PROTOCOL" = "vless" ]]; then
            local vless_link="vless://${UUID}@${current_argo_domain}:443?encryption=none&security=tls&sni=${current_argo_domain}&fp=chrome&type=ws&host=${current_argo_domain}&path=%2f${UUID}-vl#argo-vless-${hostname}"
            print_msg "--- VLESS + Argo (TLS) 节点 ---" "yellow"
            echo "$vless_link"
        else
            local vmess_json
            vmess_json=$(printf '{"v":"2","ps":"vmess-argo-%s","add":"%s","port":"443","id":"%s","aid":"0","scy":"auto","net":"ws","type":"none","host":"%s","path":"/%s-vm","tls":"tls","sni":"%s"}' "$hostname" "$current_argo_domain" "$UUID" "$current_argo_domain" "$UUID" "$current_argo_domain")
            local vmess_base64
            vmess_base64=$(echo "$vmess_json" | tr -d '\n' | base64 -w0)
            local vmess_link="vmess://${vmess_base64}"
            print_msg "--- VMess + Argo (TLS) 节点 ---" "yellow"
            echo "$vmess_link"
        fi
    fi
}

do_start() {
    print_msg "--- 启动服务 ---" "blue"
    if ! load_variables; then print_msg "错误: 未找到配置文件，请先执行 install" "red"; exit 1; fi
    do_stop

    nohup "$SINGBOX_PATH" run -c "$CONFIG_PATH" > "$AGSBX_DIR/sing-box.log" 2>&1 &
    print_msg "sing-box 已后台启动，日志: $AGSBX_DIR/sing-box.log" "green"

    if [[ "$INSTALL_CHOICE" = "2" || "$INSTALL_CHOICE" = "3" ]]; then
        if [[ -n "$ARGO_TOKEN" ]]; then
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
            print_msg "临时隧道启动中，日志: $AGSBX_DIR/argo.log" "yellow"
        fi
        print_msg "cloudflared 已后台启动" "green"
    fi
}

do_stop() {
    print_msg "--- 停止服务 ---" "blue"
    pkill -f "$SINGBOX_PATH"
    pkill -f "$CLOUDFLARED_PATH"
    print_msg "所有服务已停止" "green"
}

do_restart() {
    print_msg "--- 重启服务 ---" "blue"
    do_stop
    sleep 1
    do_start
}

do_uninstall() {
    print_msg "--- 卸载 ---" "red"
    read -rp "警告: 这将删除所有文件，确定吗? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then print_msg "卸载已取消" "green"; exit 0; fi
    do_stop
    rm -rf "$AGSBX_DIR"
    print_msg "卸载完成" "green"
}

show_help() {
    print_msg "All-in-One TUIC & VLESS/VMess + Argo 管理脚本" "blue"
    echo "用法: bash $0 [命令]"
    echo "可用命令: install | list | start | stop | restart | uninstall | help"
}

# --- 主入口 ---
main() {
    case "$1" in
        install) do_install ;;
        list) do_list ;;
        start) do_start ;;
        stop) do_stop ;;
        restart) do_restart ;;
        uninstall) do_uninstall ;;
        help|*) show_help ;;
    esac
}

main "$@"
