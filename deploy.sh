#!/bin/bash
# ==============================================================================
# All-in-One TUIC & VLESS/VMess+Argo 管理脚本 (v4.0 完整版)
# 支持 IPv4 / IPv6 自动获取，交互式安装
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
        "red")    printf "${C_RED}%s\n" "$1" ;;
        "green")  printf "${C_GREEN}%s\n" "$1" ;;
        "yellow") printf "${C_YELLOW}%s\n" "$1" ;;
        "blue")   printf "${C_BLUE}%s\n" "$1" ;;
        *)        printf "%s\n" "$1" ;;
    esac
}

check_openssl() {
    if ! command -v openssl >/dev/null 2>&1; then
        print_msg "openssl 未安装，正在安装..." "yellow"
        if [ -f /etc/alpine-release ]; then
            apk add --no-cache openssl
        elif [ -f /etc/debian_version ]; then
            apt update && apt install -y openssl
        elif [ -f /etc/redhat-release ]; then
            yum install -y openssl
        else
            print_msg "不支持的系统，请手动安装 openssl" "red"
            exit 1
        fi
    fi
}

get_cpu_arch() {
    case "$(uname -m)" in
        "x86_64") echo "amd64" ;;
        "aarch64") echo "arm64" ;;
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
    if [ $? -ne 0 ]; then
        print_msg "下载失败: $url" "red"
        exit 1
    fi
    chmod +x "$dest"
    print_msg "$(basename "$dest") 下载并设置权限成功。" "green"
}

get_server_ipv4() {
    if command -v curl >/dev/null 2>&1; then
        curl -s4 https://icanhazip.com
    else
        wget -qO- -4 https://icanhazip.com
    fi
}

get_server_ipv6() {
    if command -v curl >/dev/null 2>&1; then
        curl -s6 https://icanhazip.com
    else
        wget -qO- -6 https://icanhazip.com
    fi
}

load_variables() {
    if [ -f "$VARS_PATH" ]; then . "$VARS_PATH"; else return 1; fi
}

# --- 核心功能 ---
do_install() {
    print_msg "--- 节点安装向导 ---" "blue"
    print_msg "请选择安装类型:" "yellow"
    print_msg " 1) 仅安装 TUIC"
    print_msg " 2) 仅安装 Argo 隧道 (VLESS 或 VMess)"
    print_msg " 3) 同时安装 TUIC 和 Argo 隧道"
    read -rp "$(printf "${C_GREEN}请输入选项 [1-3]: ${C_NC}")" INSTALL_CHOICE

    mkdir -p "$AGSBX_DIR"
    : > "$VARS_PATH"

    # --- 安装选项逻辑 ---
    if [ "$INSTALL_CHOICE" = "1" ]; then
        read -rp "$(printf "${C_GREEN}请输入 TUIC 端口 (默认443): ${C_NC}")" TUIC_PORT
        TUIC_PORT=${TUIC_PORT:-443}
        echo "INSTALL_CHOICE=1" >> "$VARS_PATH"
        echo "TUIC_PORT=$TUIC_PORT" >> "$VARS_PATH"

    elif [ "$INSTALL_CHOICE" = "2" ]; then
        echo "INSTALL_CHOICE=2" >> "$VARS_PATH"
        read -rp "$(printf "${C_GREEN}Argo 隧道承载 VLESS 还是 VMess? [1 for VLESS, 2 for VMess]: ${C_NC}")" ARGO_PROTOCOL_CHOICE
        if [ "$ARGO_PROTOCOL_CHOICE" = "1" ]; then
            echo "ARGO_PROTOCOL='vless'" >> "$VARS_PATH"
        else
            echo "ARGO_PROTOCOL='vmess'" >> "$VARS_PATH"
        fi
        read -rp "$(printf "${C_GREEN}请输入本地监听端口 (默认8080): ${C_NC}")" ARGO_LOCAL_PORT
        ARGO_LOCAL_PORT=${ARGO_LOCAL_PORT:-8080}
        echo "ARGO_LOCAL_PORT=$ARGO_LOCAL_PORT" >> "$VARS_PATH"

        read -rp "$(printf "${C_GREEN}请输入 Argo Tunnel Token (可留空使用临时隧道): ${C_NC}")" ARGO_TOKEN
        echo "ARGO_TOKEN='$ARGO_TOKEN'" >> "$VARS_PATH"
        if [ -n "$ARGO_TOKEN" ]; then
            read -rp "$(printf "${C_GREEN}请输入域名: ${C_NC}")" ARGO_DOMAIN
            echo "ARGO_DOMAIN='$ARGO_DOMAIN'" >> "$VARS_PATH"
        fi

    elif [ "$INSTALL_CHOICE" = "3" ]; then
        read -rp "$(printf "${C_GREEN}请输入 TUIC 端口 (默认443): ${C_NC}")" TUIC_PORT
        TUIC_PORT=${TUIC_PORT:-443}
        echo "INSTALL_CHOICE=3" >> "$VARS_PATH"
        echo "TUIC_PORT=$TUIC_PORT" >> "$VARS_PATH"

        read -rp "$(printf "${C_GREEN}Argo 隧道承载 VLESS 还是 VMess? [1 for VLESS, 2 for VMess]: ${C_NC}")" ARGO_PROTOCOL_CHOICE
        if [ "$ARGO_PROTOCOL_CHOICE" = "1" ]; then
            echo "ARGO_PROTOCOL='vless'" >> "$VARS_PATH"
        else
            echo "ARGO_PROTOCOL='vmess'" >> "$VARS_PATH"
        fi
        read -rp "$(printf "${C_GREEN}请输入本地监听端口 (默认8080): ${C_NC}")" ARGO_LOCAL_PORT
        ARGO_LOCAL_PORT=${ARGO_LOCAL_PORT:-8080}
        echo "ARGO_LOCAL_PORT=$ARGO_LOCAL_PORT" >> "$VARS_PATH"

        read -rp "$(printf "${C_GREEN}请输入 Argo Tunnel Token (可留空使用临时隧道): ${C_NC}")" ARGO_TOKEN
        echo "ARGO_TOKEN='$ARGO_TOKEN'" >> "$VARS_PATH"
        if [ -n "$ARGO_TOKEN" ]; then
            read -rp "$(printf "${C_GREEN}请输入域名: ${C_NC}")" ARGO_DOMAIN
            echo "ARGO_DOMAIN='$ARGO_DOMAIN'" >> "$VARS_PATH"
        fi

    else
        print_msg "无效选项，安装已取消。" "red"
        exit 1
    fi

    load_variables

    print_msg "--- 准备依赖环境 ---" "blue"
    check_openssl
    cpu_arch=$(get_cpu_arch)

    # 安装 sing-box
    if [ ! -f "$SINGBOX_PATH" ]; then
        singbox_url="https://github.com/SagerNet/sing-box/releases/download/v1.9.0/sing-box-1.9.0-linux-${cpu_arch}.tar.gz"
        temp_tar="$AGSBX_DIR/sing-box.tar.gz"
        download_file "$singbox_url" "$temp_tar"
        tar -xzf "$temp_tar" -C "$AGSBX_DIR"
        mv "$AGSBX_DIR/sing-box-1.9.0-linux-${cpu_arch}/sing-box" "$SINGBOX_PATH"
        rm -f "$temp_tar" 
        rm -rf "$AGSBX_DIR/sing-box-1.9.0-linux-${cpu_arch}"
    fi

    # 安装 cloudflared
    if [ "$INSTALL_CHOICE" = "2" ] || [ "$INSTALL_CHOICE" = "3" ]; then
        if [ ! -f "$CLOUDFLARED_PATH" ]; then
            cloudflared_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cpu_arch}"
            download_file "$cloudflared_url" "$CLOUDFLARED_PATH"
        fi
    fi

    # 生成 UUID
    UUID=$($SINGBOX_PATH generate uuid)
    echo "UUID='$UUID'" >> "$VARS_PATH"
    print_msg "生成 UUID: $UUID" "yellow"

    # 生成 TLS 证书
    if [ "$INSTALL_CHOICE" = "1" ] || [ "$INSTALL_CHOICE" = "3" ]; then
        if [ ! -f "$KEY_PATH" ] || [ ! -f "$CERT_PATH" ]; then
            openssl ecparam -genkey -name prime256v1 -out "$KEY_PATH"
            openssl req -new -x509 -days 36500 -key "$KEY_PATH" -out "$CERT_PATH" -subj "/CN=www.bing.com"
            print_msg "TLS 证书生成成功" "green"
        fi
    fi

    # --- 生成配置文件 ---
    generate_config

    # 启动服务
    do_start

    print_msg "--- 安装完成，节点信息如下 ---" "blue"
    do_list
}

generate_config() {
    # TUIC inbound
    if [ "$INSTALL_CHOICE" = "1" ] || [ "$INSTALL_CHOICE" = "3" ]; then
        tuic_in=$(cat <<EOF
{"type":"tuic","tag":"tuic-in","listen":"::","listen_port":${TUIC_PORT},"users":[{"uuid":"${UUID}","password":"${UUID}"}],"congestion_control":"bbr","tls":{"enabled":true,"server_name":"www.bing.com","alpn":["h3"],"certificate_path":"${CERT_PATH}","key_path":"${KEY_PATH}"}}
EOF
)
    else
        tuic_in=""
    fi

    # Argo inbound
    if [ "$INSTALL_CHOICE" = "2" ] || [ "$INSTALL_CHOICE" = "3" ]; then
        if [ "$ARGO_PROTOCOL" = "vless" ]; then
            argo_in=$(printf '{"type":"vless","tag":"vless-in","listen":"127.0.0.1","listen_port":%s,"users":[{"uuid":"%s"}],"transport":{"type":"ws","path":"/%s-vl"}}' "$ARGO_LOCAL_PORT" "$UUID" "$UUID")
        else
            argo_in=$(printf '{"type":"vmess","tag":"vmess-in","listen":"127.0.0.1","listen_port":%s,"users":[{"uuid":"%s","alterId":0}],"transport":{"type":"ws","path":"/%s-vm"}}' "$ARGO_LOCAL_PORT" "$UUID" "$UUID")
        fi
    else
        argo_in=""
    fi

    # 输出配置
    cat > "$CONFIG_PATH" <<EOF
{
  "log":{"level":"info","timestamp":true},
  "inbounds":[
    $tuic_in
    $( [ -n "$tuic_in" ] && [ -n "$argo_in" ] && echo "," )
    $argo_in
  ],
  "outbounds":[{"type":"direct","tag":"direct"}]
}
EOF

    print_msg "配置文件已生成: $CONFIG_PATH" "green"
}

do_list() {
    print_msg "--- 节点信息 ---" "blue"
    load_variables || { print_msg "未找到配置文件，请先安装" "red"; return; }

    hostname=$(hostname)
    ipv4=$(get_server_ipv4)
    ipv6=$(get_server_ipv6)

    if [ "$INSTALL_CHOICE" = "1" ] || [ "$INSTALL_CHOICE" = "3" ]; then
        tuic_params="congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=www.bing.com&allow_insecure=1"
        echo "--- TUIC 节点 ---" 
        echo "IPv4: tuic://${UUID}:${UUID}@${ipv4}:${TUIC_PORT}?${tuic_params}#tuic-${hostname}"
        echo "IPv6: tuic://${UUID}:${UUID}@[${ipv6}]:${TUIC_PORT}?${tuic_params}#tuic-${hostname}"
    fi

    if [ "$INSTALL_CHOICE" = "2" ] || [ "$INSTALL_CHOICE" = "3" ]; then
        current_domain="$ARGO_DOMAIN"
        if [ -z "$ARGO_TOKEN" ]; then
            print_msg "等待临时 Argo 隧道生成..." "yellow"
            sleep 5
            temp_domain=$(grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare\.com' "$AGSBX_DIR/argo.log" | sed 's#https://##' | head -n1)
            current_domain=${temp_domain:-"[请查看 argo.log]"}
        fi

        if [ "$ARGO_PROTOCOL" = "vless" ]; then
            echo "--- VLESS + Argo (TLS) ---"
            echo "vless://${UUID}@${current_domain}:443?encryption=none&security=tls&sni=${current_domain}&fp=chrome&type=ws&host=${current_domain}&path=%2f${UUID}-vl#argo-vless-${hostname}"
        else
            vmess_json=$(printf '{"v":"2","ps":"vmess-argo-%s","add":"%s","port":"443","id":"%s","aid":"0","scy":"auto","net":"ws","type":"none","host":"%s","path":"/%s-vm","tls":"tls","sni":"%s"}' "$hostname" "$current_domain" "$UUID" "$current_domain" "$UUID" "$current_domain")
            vmess_base64=$(echo "$vmess_json" | tr -d '\n' | base64 -w0)
            echo "--- VMess + Argo (TLS) ---"
            echo "vmess://${vmess_base64}"
        fi
    fi
}

do_start() {
    print_msg "--- 启动服务 ---" "blue"
    load_variables || { print_msg "未找到配置文件，请先安装" "red"; return; }
    do_stop

    nohup "$SINGBOX_PATH" run -c "$CONFIG_PATH" > "$AGSBX_DIR/sing-box.log" 2>&1 &

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
        fi
    fi
    print_msg "服务已启动，日志: $AGSBX_DIR/sing-box.log / argo.log" "green"
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
    read -rp "$(printf "${C_YELLOW}确定要卸载所有文件吗? (y/n): ${C_NC}")" confirm
    if [ "$confirm" != "y" ]; then print_msg "取消卸载" "green"; return; fi
    do_stop
    rm -rf "$AGSBX_DIR"
    print_msg "卸载完成" "green"
}

show_help() {
    print_msg "All-in-One TUIC & VLESS/VMess+Argo 管理脚本" "blue"
    echo "用法: bash $0 [命令]"
    echo "可用命令: install | list | start | stop | restart | uninstall | help"
}

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
