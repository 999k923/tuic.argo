#!/bin/bash
# ============================================================================== 
# All-in-One TUIC & VLESS/VMess+Argo 管理脚本 (v3.2 - 完全交互式)
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

# --- 打印彩色信息 ---
print_msg() {
    case "$2" in
        "red")    printf "${C_RED}%s\n" "$1" ;;
        "green")  printf "${C_GREEN}%s\n" "$1" ;;
        "yellow") printf "${C_YELLOW}%s\n" "$1" ;;
        "blue")   printf "${C_BLUE}%s\n" "$1" ;;
        *)        printf "%s\n" "$1" ;;
    esac
}

# --- 检查并安装依赖 ---
check_and_install_dependencies() {
    print_msg "--- 检查依赖环境 ---" "blue"
    local missing=""
    local dependencies=(bash curl wget tar openssl coreutils)
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing="$missing $cmd"
        fi
    done

    if [ -n "$missing" ]; then
        print_msg "缺少依赖:$missing" "yellow"
        if command -v apk >/dev/null 2>&1; then
            print_msg "通过 apk 安装依赖..." "yellow"
            apk update && apk add --no-cache $missing
            if [ $? -ne 0 ]; then
                print_msg "apk 安装失败，请手动安装:$missing" "red"
                exit 1
            fi
        else
            print_msg "未检测到 apk，请手动安装:$missing" "red"
            exit 1
        fi
    fi
    print_msg "依赖检查完成。" "green"
}

# --- CPU 架构检测 ---
get_cpu_arch() {
    case "$(uname -m)" in
        "x86_64")   echo "amd64" ;;
        "aarch64")  echo "arm64" ;;
        *) print_msg "错误: 不支持的 CPU 架构 $(uname -m)" "red"; exit 1 ;;
    esac
}

# --- 下载文件 ---
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
    print_msg "$(basename "$dest") 下载完成并设置权限。" "green"
}

# --- 获取公网 IP ---
get_server_ip() {
    if command -v curl >/dev/null 2>&1; then curl -s https://icanhazip.com; else wget -qO- https://icanhazip.com; fi
}

# --- 读取变量 ---
load_variables() {
    if [ -f "$VARS_PATH" ]; then . "$VARS_PATH"; else return 1; fi
}

# --- 安装流程 ---
do_install() {
    print_msg "--- 节点安装向导 ---" "blue"
    print_msg "请选择您要安装的节点类型:" "yellow"
    print_msg "  1) 仅安装 TUIC"
    print_msg "  2) 仅安装 Argo 隧道 (VLESS 或 VMess)"
    print_msg "  3) 同时安装 TUIC 和 Argo 隧道"
    printf "${C_GREEN}请输入选项 [1-3]: ${C_NC}"; read -r INSTALL_CHOICE

    mkdir -p "$AGSBX_DIR"
    : > "$VARS_PATH"

    # --- 安装选项分支 ---
    if [ "$INSTALL_CHOICE" = "1" ]; then
        print_msg "您选择了: 仅安装 TUIC" "green"
        printf "${C_GREEN}请输入 TUIC 端口 (例如 443): ${C_NC}"; read -r TUIC_PORT
        echo "INSTALL_CHOICE=1" >> "$VARS_PATH"
        echo "TUIC_PORT=${TUIC_PORT}" >> "$VARS_PATH"

    elif [ "$INSTALL_CHOICE" = "2" ]; then
        print_msg "您选择了: 仅安装 Argo 隧道" "green"
        echo "INSTALL_CHOICE=2" >> "$VARS_PATH"
        printf "${C_GREEN}Argo 隧道承载 VLESS 还是 VMess? [1 for VLESS, 2 for VMess]: ${C_NC}"; read -r ARGO_PROTOCOL_CHOICE
        if [ "$ARGO_PROTOCOL_CHOICE" = "1" ]; then
            echo "ARGO_PROTOCOL='vless'" >> "$VARS_PATH"
            printf "${C_GREEN}请输入 VLESS 本地监听端口 (例如 8080): ${C_NC}"; read -r ARGO_LOCAL_PORT
        else
            echo "ARGO_PROTOCOL='vmess'" >> "$VARS_PATH"
            printf "${C_GREEN}请输入 VMess 本地监听端口 (例如 8080): ${C_NC}"; read -r ARGO_LOCAL_PORT
        fi
        echo "ARGO_LOCAL_PORT=${ARGO_LOCAL_PORT}" >> "$VARS_PATH"
        printf "${C_GREEN}请输入 Argo Tunnel 的 Token (回车使用临时隧道): ${C_NC}"; read -r ARGO_TOKEN
        if [ -n "$ARGO_TOKEN" ]; then
            printf "${C_GREEN}请输入 Argo Tunnel 对应的域名: ${C_NC}"; read -r ARGO_DOMAIN
        fi
        echo "ARGO_TOKEN='${ARGO_TOKEN}'" >> "$VARS_PATH"
        echo "ARGO_DOMAIN='${ARGO_DOMAIN}'" >> "$VARS_PATH"

    elif [ "$INSTALL_CHOICE" = "3" ]; then
        print_msg "您选择了: 同时安装 TUIC 和 Argo 隧道" "green"
        echo "INSTALL_CHOICE=3" >> "$VARS_PATH"

        printf "${C_GREEN}请输入 TUIC 端口 (例如 443): ${C_NC}"; read -r TUIC_PORT
        echo "TUIC_PORT=${TUIC_PORT}" >> "$VARS_PATH"

        printf "${C_GREEN}Argo 隧道承载 VLESS 还是 VMess? [1 for VLESS, 2 for VMess]: ${C_NC}"; read -r ARGO_PROTOCOL_CHOICE
        if [ "$ARGO_PROTOCOL_CHOICE" = "1" ]; then
            echo "ARGO_PROTOCOL='vless'" >> "$VARS_PATH"
            printf "${C_GREEN}请输入 VLESS 本地监听端口 (例如 8080): ${C_NC}"; read -r ARGO_LOCAL_PORT
        else
            echo "ARGO_PROTOCOL='vmess'" >> "$VARS_PATH"
            printf "${C_GREEN}请输入 VMess 本地监听端口 (例如 8080): ${C_NC}"; read -r ARGO_LOCAL_PORT
        fi
        echo "ARGO_LOCAL_PORT=${ARGO_LOCAL_PORT}" >> "$VARS_PATH"

        printf "${C_GREEN}请输入 Argo Tunnel 的 Token (回车使用临时隧道): ${C_NC}"; read -r ARGO_TOKEN
        if [ -n "$ARGO_TOKEN" ]; then
            printf "${C_GREEN}请输入 Argo Tunnel 对应的域名: ${C_NC}"; read -r ARGO_DOMAIN
        fi
        echo "ARGO_TOKEN='${ARGO_TOKEN}'" >> "$VARS_PATH"
        echo "ARGO_DOMAIN='${ARGO_DOMAIN}'" >> "$VARS_PATH"
    else
        print_msg "无效选项，安装已取消。" "red"
        exit 1
    fi

    load_variables
    print_msg "\n--- 正在准备依赖环境 ---" "blue"
    check_and_install_dependencies

    local cpu_arch; cpu_arch=$(get_cpu_arch)

    # --- 下载 sing-box ---
    if [ ! -f "$SINGBOX_PATH" ]; then
        local singbox_url="https://github.com/SagerNet/sing-box/releases/download/v1.9.0-beta.13/sing-box-1.9.0-beta.13-linux-${cpu_arch}.tar.gz"
        local temp_tar_path="$AGSBX_DIR/sing-box.tar.gz"
        download_file "$singbox_url" "$temp_tar_path"
        tar -xzf "$temp_tar_path" -C "$AGSBX_DIR"
        mv "$AGSBX_DIR/sing-box-1.9.0-beta.13-linux-${cpu_arch}/sing-box" "$SINGBOX_PATH"
        rm -f "$temp_tar_path"; rm -rf "$AGSBX_DIR/sing-box-1.9.0-beta.13-linux-${cpu_arch}"
    fi

    # --- 下载 cloudflared ---
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

    # --- 生成配置文件 ---
    generate_config

    # --- 启动服务 ---
    do_start

    print_msg "\n--- 安装完成，节点信息 ---" "blue"
    do_list
}

# --- 生成 sing-box 配置 ---
generate_config() {
    local argo_inbound=""
    if [ "$INSTALL_CHOICE" = "2" ] || [ "$INSTALL_CHOICE" = "3" ]; then
        if [ "$ARGO_PROTOCOL" = "vless" ]; then
            argo_inbound=$(printf '{"type": "vless", "tag": "vless-in", "listen": "127.0.0.1", "listen_port": %s, "users": [{"uuid": "%s"}], "transport": {"type": "ws", "path": "/%s-vl"}}' "$ARGO_LOCAL_PORT" "$UUID" "$UUID")
        else
            argo_inbound=$(printf '{"type": "vmess", "tag": "vmess-in", "listen": "127.0.0.1", "listen_port": %s, "users": [{"uuid": "%s", "alterId": 0}], "transport": {"type": "ws", "path": "/%s-vm"}}' "$ARGO_LOCAL_PORT" "$UUID" "$UUID")
        fi
    fi

    if [ "$INSTALL_CHOICE" = "1" ] || [ "$INSTALL_CHOICE" = "3" ]; then
        openssl ecparam -genkey -name prime256v1 -out "$KEY_PATH" >/dev/null 2>&1
        openssl req -new -x509 -days 36500 -key "$KEY_PATH" -out "$CERT_PATH" -subj "/CN=www.bing.com" >/dev/null 2>&1
    fi

    # --- 写入配置文件 ---
    if [ "$INSTALL_CHOICE" = "1" ]; then
        cat > "$CONFIG_PATH" <<EOF
{
  "log":{"level":"info","timestamp":true},
  "inbounds":[
    {"type":"tuic","tag":"tuic-in","listen":"::","listen_port":${TUIC_PORT},"users":[{"uuid":"${UUID}","password":"${UUID}"}],"congestion_control":"bbr","tls":{"enabled":true,"server_name":"www.bing.com","alpn":["h3"],"certificate_path":"${CERT_PATH}","key_path":"${KEY_PATH}"}}
  ],
  "outbounds":[{"type":"direct","tag":"direct"}]
}
EOF
    elif [ "$INSTALL_CHOICE" = "2" ]; then
        cat > "$CONFIG_PATH" <<EOF
{
  "log":{"level":"info","timestamp":true},
  "inbounds":[
    ${argo_inbound}
  ],
  "outbounds":[{"type":"direct","tag":"direct"}]
}
EOF
    else
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
    print_msg "配置文件已写入: $CONFIG_PATH" "green"
}

# --- 启动服务 ---
do_start() {
    print_msg "--- 启动服务 ---" "blue"
    load_variables || { print_msg "错误: 未找到配置文件，请先安装。" "red"; exit 1; }
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
            print_msg "临时 Argo 隧道将在几秒后建立..." "yellow"
        fi
        print_msg "cloudflared 已后台启动，日志: $AGSBX_DIR/argo.log" "green"
    fi
}

# --- 停止服务 ---
do_stop() {
    print_msg "--- 停止服务 ---" "blue"
    pkill -f "$SINGBOX_PATH" >/dev/null 2>&1
    pkill -f "$CLOUDFLARED_PATH" >/dev/null 2>&1
    print_msg "所有相关服务已停止。" "green"
}

# --- 列出节点信息 ---
do_list() {
    print_msg "--- 节点信息 ---" "blue"
    load_variables || { print_msg "错误: 未找到配置文件，请先安装。" "red"; exit 1; }

    local server_ip hostname
    server_ip=$(get_server_ip)
    hostname=$(hostname)
    print_msg "\n🎉 节点信息如下：\n" "blue"

    if [ "$INSTALL_CHOICE" = "1" ] || [ "$INSTALL_CHOICE" = "3" ]; then
        local tuic_params="congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=www.bing.com&allow_insecure=1"
        local tuic_link="tuic://${UUID}:${UUID}@${server_ip}:${TUIC_PORT}?${tuic_params}#tuic-${hostname}"
        print_msg "--- TUIC 节点 ---" "yellow"
        echo "$tuic_link"
    fi

    if [ "$INSTALL_CHOICE" = "2" ] || [ "$INSTALL_CHOICE" = "3" ]; then
        local current_argo_domain="$ARGO_DOMAIN"
        if [ -z "$ARGO_TOKEN" ]; then
            print_msg "等待临时 Argo 域名生成..." "yellow"
            sleep 5
            local temp_argo_domain
            temp_argo_domain=$(grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare\.com' "$AGSBX_DIR/argo.log" | sed 's/https:\/\///' | head -n 1)
            current_argo_domain=${temp_argo_domain:-"[请从日志中手动查找域名]"}
        fi

        if [ "$ARGO_PROTOCOL" = "vless" ]; then
            local vless_link="vless://${UUID}@${current_argo_domain}:443?encryption=none&security=tls&sni=${current_argo_domain}&fp=chrome&type=ws&host=${current_argo_domain}&path=%2f${UUID}-vl#argo-vless-${hostname}"
            print_msg "--- VLESS + Argo (TLS) 节点 ---" "yellow"
            echo "$vless_link"
        else
            local vmess_json
            vmess_json=$(printf '{"v":"2","ps":"vmess-argo-%s","add":"%s","port":"443","id":"%s","aid":"0","scy":"auto","net":"ws","type":"none","host":"%s","path":"/%s-vm","tls":"tls","sni":"%
