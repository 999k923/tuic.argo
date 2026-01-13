#!/bin/bash

# ======================================================================
# All-in-One TUIC & VLESS/VMess+Argo 管理脚本 (sing.sh)
# 支持交互式安装、IPv4/IPv6 自动检测、Cloudflare 证书自动化
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
        ipv4=$(curl -4 -s https://icanhazip.com  )
    else
        ipv4=$(wget -4 -qO- https://icanhazip.com  )
    fi
    echo "$ipv4"
}

get_server_ipv6() {
    [ -n "$SERVER_IPV6" ] && echo "$SERVER_IPV6" && return
    if command -v curl >/dev/null 2>&1; then
        ipv6=$(curl -6 -s ip.sb)
    else
        ipv6=$(wget -6 -qO- ip.sb)
    fi
    if [ -n "$ipv6" ]; then
        echo "$ipv6"
        return
    fi
    local iface
    for iface in $(ls /sys/class/net/ | grep -v lo); do
        ipv6=$(ip -6 addr show dev "$iface" | grep inet6 \
            | grep -v '::1' \
            | grep -v 'fe80' \
            | grep -v '^fd' \
            | awk '{print $2}' \
            | cut -d/ -f1 \
            | head -n1)
        if [ -n "$ipv6" ]; then
            echo "$ipv6"
            return
        fi
    done
    echo "Unable to retrieve IPv6 address"
}

# 检查选项是否被选中
is_selected() {
    local choice=$1
    [[ ",$INSTALL_CHOICE," =~ ,$choice, ]]
}

# --- 证书申请逻辑 ---
install_acme() {
    # 1. 补齐隐性依赖 (perl, socat, cron)
    print_msg "正在检查并补齐证书申请依赖..." yellow
    local deps=("perl" "socat")
    if command -v apt >/dev/null 2>&1; then
        sudo apt update -y >/dev/null 2>&1
        for dep in "${deps[@]}"; do
            if ! command -v "$dep" >/dev/null 2>&1; then
                sudo apt install -y "$dep" >/dev/null 2>&1
            fi
        done
        if ! command -v crontab >/dev/null 2>&1; then
            sudo apt install -y cron >/dev/null 2>&1
        fi
    elif command -v yum >/dev/null 2>&1; then
        for dep in "${deps[@]}"; do
            if ! command -v "$dep" >/dev/null 2>&1; then
                sudo yum install -y "$dep" >/dev/null 2>&1
            fi
        done
        if ! command -v crontab >/dev/null 2>&1; then
            sudo yum install -y cronie >/dev/null 2>&1
        fi
    fi

    # 2. 启动并启用 cron 服务
    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl enable cron >/dev/null 2>&1 || sudo systemctl enable cronie >/dev/null 2>&1
        sudo systemctl start cron >/dev/null 2>&1 || sudo systemctl start cronie >/dev/null 2>&1
    fi

    # 3. crontab 兜底
    if ! crontab -l >/dev/null 2>&1; then
        print_msg "crontab 不可用，创建空 crontab 作为兜底..." yellow
        (crontab -l 2>/dev/null; echo "") | crontab -
    fi

    # 4. 安装 acme.sh
    if [ ! -x "$HOME/.acme.sh/acme.sh" ]; then
        print_msg "正在安装 acme.sh (手动下载 tar.gz)..." yellow
        mkdir -p "$HOME/.acme.sh"
        cd "$HOME/.acme.sh" || exit

        # 下载并解压
        curl -L https://github.com/acmesh-official/acme.sh/archive/master.tar.gz -o master.tar.gz
        tar -xzf master.tar.gz --strip-components=1

        # 如果已经存在 acme.sh ，用升级方式安装
        if [ -f "./acme.sh" ]; then
            chmod +x ./acme.sh
            ./acme.sh --upgrade --auto-upgrade
        else
            ./acme.sh --install --force
        fi

        [ -f "$HOME/.bashrc" ] && source "$HOME/.bashrc"
        print_msg "acme.sh 安装完成" green
    fi
}


issue_cf_cert() {
    install_acme

    # 安全加固：在写入敏感信息前设置权限
    touch "$VARS_PATH"
    chmod 600 "$VARS_PATH"

    # 输入 Cloudflare 邮箱
    if [ -z "$CF_EMAIL" ]; then
        read -rp "$(printf "${C_GREEN}请输入 Cloudflare 账户邮箱: ${C_NC}")" CF_EMAIL
        echo "CF_EMAIL='${CF_EMAIL}'" >> "$VARS_PATH"
    fi

    # 输入 Cloudflare Global API Key
    if [ -z "$CF_API_KEY" ]; then
        read -rp "$(printf "${C_GREEN}请输入 Cloudflare Global API Key: ${C_NC}")" CF_API_KEY
        echo "CF_API_KEY='${CF_API_KEY}'" >> "$VARS_PATH"
    fi

    export CF_Email="$CF_EMAIL"
    export CF_Key="$CF_API_KEY"

    # 输入 AnyTLS 域名
    if [ -z "$ANYTLS_DOMAIN" ]; then
        read -rp "$(printf "${C_GREEN}请输入 AnyTLS 域名: ${C_NC}")" ANYTLS_DOMAIN
        echo "ANYTLS_DOMAIN='${ANYTLS_DOMAIN}'" >> "$VARS_PATH"
    fi

    print_msg "正在通过 Cloudflare DNS 申请或验证证书..." yellow
    # 尝试申请证书，并捕获退出码
    "$HOME/.acme.sh/acme.sh" --issue \
        --dns dns_cf \
        -d "${ANYTLS_DOMAIN}" \
        --keylength ec-256 \
        --server letsencrypt
    
    ACME_STATUS=$? # 保存 acme.sh 的退出码

    # 如果退出码是 0 (新申请成功) 或 2 (跳过)，都继续执行安装证书
    if [ "$ACME_STATUS" -eq 0 ] || [ "$ACME_STATUS" -eq 2 ]; then
        print_msg "acme.sh 执行完毕 (状态码: $ACME_STATUS)，开始安装证书到目标路径..." yellow
        "$HOME/.acme.sh/acme.sh" --install-cert \
            -d "${ANYTLS_DOMAIN}" \
            --ecc \
            --key-file "$KEY_PATH" \
            --fullchain-file "$CERT_PATH"
            
        # 最后检查一次文件是否存在，确保万无一失
        if [ -f "$CERT_PATH" ] && [ -f "$KEY_PATH" ]; then
            print_msg "Cloudflare 证书已就绪: $CERT_PATH" green
        else
            print_msg "错误：证书文件未能成功安装到目标路径。" red
            exit 1
        fi
    else
        # 如果是其他错误码，则认为是真正的失败
        print_msg "证书申请失败，acme.sh 返回错误码: $ACME_STATUS" red
        print_msg "请检查邮箱、API Key 和域名是否正确，或查看 acme.sh 日志。" red
        exit 1
    fi
}

# --- 1. 在脚本开头或合适位置添加优选逻辑 ---
CF_DOMAINS=(
    "cf.090227.xyz"
    "cf.877774.xyz"
    "cf.130519.xyz"
    "cf.008500.xyz"
    "store.ubi.com"
    "saas.sin.fan"
    "cdns.doon.eu.org"
)

select_random_cf_domain() {
    # 使用 >&2 将提示信息输出到屏幕，而不影响函数返回值
    print_msg "正在优选 Cloudflare 域名，请稍候..." yellow >&2
    local available=()
    for domain in "${CF_DOMAINS[@]}"; do
        if curl -s --max-time 2 -o /dev/null "https://$domain" 2>/dev/null; then
            available+=("$domain" )
        fi
    done
    if [ ${#available[@]} -gt 0 ]; then
        echo "${available[$((RANDOM % ${#available[@]}))]}"
    else
        echo "${CF_DOMAINS[0]}"
    fi
}



# --- 核心安装 ---
do_install() {
    print_msg "--- 节点安装向导 ---" blue
    print_msg "请选择您要安装的节点类型 (支持多选，如输入 1,2 或 1,2,3):" yellow
    print_msg "  1) 安装 TUIC"
    print_msg "  2) 安装 Argo 隧道 (VLESS 或 VMess)"
    print_msg "  3) 安装 AnyTLS (使用 CF 证书)"
    read -rp "$(printf "${C_GREEN}请输入选项: ${C_NC}")" INSTALL_CHOICE
    
    INSTALL_CHOICE=$(echo "$INSTALL_CHOICE" | tr -d ' ' | tr '，' ',')

    if [[ ! "$INSTALL_CHOICE" =~ ^[123](,[123])*$ ]]; then
        print_msg "无效选项，请输入 1, 2, 3 中的一个或多个（用逗号分隔）。" red
        exit 1
    fi
    
    # 调用实际的安装逻辑
    execute_installation "$INSTALL_CHOICE"
}

# 新增：被 manage.sh 调用的安装函数
install_from_manager() {
    local choices="$1"
    print_msg "接收到管理脚本指令，开始非交互式安装..." yellow
    execute_installation "$choices"
}

# 实际的安装执行逻辑
execute_installation() {
    local INSTALL_CHOICE="$1"
    
    mkdir -p "$AGSBX_DIR"
    # 预设权限
    touch "$VARS_PATH"
    chmod 600 "$VARS_PATH"
    echo "INSTALL_CHOICE='$INSTALL_CHOICE'" > "$VARS_PATH"

    # TUIC 配置
    if is_selected 1; then
        read -rp "$(printf "${C_GREEN}请输入 TUIC 端口 (默认 443): ${C_NC}")" TUIC_PORT
        TUIC_PORT=${TUIC_PORT:-443}
        echo "TUIC_PORT=${TUIC_PORT}" >> "$VARS_PATH"
    fi

   # --- 2. 修改 Argo 配置部分 ---
if is_selected 2; then
    # 执行域名优选并保存
    SELECTED_CF_DOMAIN=$(select_random_cf_domain)
    
    read -rp "$(printf "${C_GREEN}Argo 隧道承载 VLESS 还是 VMess? [1=VLESS,2=VMess]: ${C_NC}")" ARGO_PROTOCOL_CHOICE
    if [[ "$ARGO_PROTOCOL_CHOICE" = "1" ]]; then
        ARGO_PROTOCOL='vless'
        read -rp "$(printf "${C_GREEN}请输入 VLESS 本地监听端口 (如果用临时隧道直接回车): ${C_NC}")" ARGO_LOCAL_PORT
    else
        ARGO_PROTOCOL='vmess'
        read -rp "$(printf "${C_GREEN}请输入 VMess 本地监听端口 (如果用临时隧道直接回车): ${C_NC}")" ARGO_LOCAL_PORT
    fi
    ARGO_LOCAL_PORT=${ARGO_LOCAL_PORT:-8080}
    read -rp "$(printf "${C_GREEN}请输入 Argo Tunnel Token (如果用临时隧道直接回车): ${C_NC}")" ARGO_TOKEN
    [ -n "$ARGO_TOKEN" ] && read -rp "$(printf "${C_GREEN}请输入 Argo Tunnel 对应域名: ${C_NC}")" ARGO_DOMAIN

    echo "ARGO_PROTOCOL='$ARGO_PROTOCOL'" >> "$VARS_PATH"
    echo "ARGO_LOCAL_PORT=${ARGO_LOCAL_PORT}" >> "$VARS_PATH"
    echo "ARGO_TOKEN='${ARGO_TOKEN}'" >> "$VARS_PATH"
    echo "ARGO_DOMAIN='${ARGO_DOMAIN}'" >> "$VARS_PATH"
    # 将优选域名也存入变量文件
    echo "SELECTED_CF_DOMAIN='${SELECTED_CF_DOMAIN}'" >> "$VARS_PATH"
fi

    # AnyTLS 配置
    if is_selected 3; then
        read -rp "$(printf "${C_GREEN}请输入 AnyTLS 监听端口 (默认 443): ${C_NC}")" ANYTLS_PORT
        ANYTLS_PORT=${ANYTLS_PORT:-443}
        echo "ANYTLS_PORT=${ANYTLS_PORT}" >> "$VARS_PATH"
    fi

    # 手动指定 IPv6（可选）
    read -rp "$(printf "${C_GREEN}如果你是 NAT IPv6，请输入公网 IPv6，否则直接回车自动获取: ${C_NC}")" SERVER_IPV6
    [ -n "$SERVER_IPV6" ] && echo "SERVER_IPV6='${SERVER_IPV6}'" >> "$VARS_PATH"

    load_variables

    print_msg "\n--- 准备依赖 ---" blue
    cpu_arch=$(get_cpu_arch)

    # 下载 sing-box
    if [ ! -f "$SINGBOX_PATH" ]; then
        # sing-box 1.12.14 最新 GitHub release
        SINGBOX_VERSION="1.12.14"
        SINGBOX_URL="https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/sing-box-${SINGBOX_VERSION}-linux-${cpu_arch}.tar.gz"
    
        TMP_TAR="$AGSBX_DIR/sing-box.tar.gz"
        echo "[INFO] 下载 sing-box v${SINGBOX_VERSION} -> $TMP_TAR"
        download_file "$SINGBOX_URL" "$TMP_TAR"

        tar -xzf "$TMP_TAR" -C "$AGSBX_DIR"
        mv "$AGSBX_DIR/sing-box-${SINGBOX_VERSION}-linux-${cpu_arch}/sing-box" "$SINGBOX_PATH"
    
    # 清理
    rm -rf "$TMP_TAR" "$AGSBX_DIR/sing-box-${SINGBOX_VERSION}-linux-${cpu_arch}"
    fi


    # 下载 cloudflared
    if is_selected 2 && [ ! -f "$CLOUDFLARED_PATH" ]; then
        CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cpu_arch}"
        download_file "$CLOUDFLARED_URL" "$CLOUDFLARED_PATH"
    fi

    # TLS 证书处理
    if is_selected 3; then
        issue_cf_cert
    elif is_selected 1; then
        if ! command -v openssl >/dev/null 2>&1; then
            print_msg "⚠️ openssl 未安装  ，请先安装 openssl" red
            exit 1
        fi
        print_msg "正在生成 TUIC 自签名证书..." yellow
        openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
            -keyout "$KEY_PATH" -out "$CERT_PATH" \
            -subj "/CN=www.bing.com" -days 36500 >/dev/null 2>&1
        print_msg "已生成 TUIC 自签名证书。" yellow
    fi

    # 生成 UUID
    UUID=$($SINGBOX_PATH generate uuid)
    echo "UUID='${UUID}'" >> "$VARS_PATH"
    print_msg "生成 UUID: $UUID" yellow

    # 生成 sing-box 配置
    do_generate_config

    # 启动服务
    do_start
    print_msg "\n--- 安装完成，获取节点信息 ---" blue
    do_list
}

do_generate_config() {
    load_variables
    local inbounds=()

    # TUIC Inbound
    if is_selected 1; then
        inbounds+=("$(printf '{"type":"tuic","tag":"tuic-in","listen":"::","listen_port":%s,"users":[{"uuid":"%s","password":"%s"}],"congestion_control":"bbr","tls":{"enabled":true,"server_name":"www.bing.com","alpn":["h3"],"certificate_path":"%s","key_path":"%s"}}' "$TUIC_PORT" "$UUID" "$UUID" "$CERT_PATH" "$KEY_PATH")")
    fi

    # Argo Inbound
    if is_selected 2; then
        if [ "$ARGO_PROTOCOL" = "vless" ]; then
            inbounds+=("$(printf '{"type":"vless","tag":"vless-in","listen":"127.0.0.1","listen_port":%s,"users":[{"uuid":"%s"}],"transport":{"type":"ws","path":"/%s-vl"}}' "$ARGO_LOCAL_PORT" "$UUID" "$UUID")")
        else
            inbounds+=("$(printf '{"type":"vmess","tag":"vmess-in","listen":"127.0.0.1","listen_port":%s,"users":[{"uuid":"%s","alterId":0}],"transport":{"type":"ws","path":"/%s-vm"}}' "$ARGO_LOCAL_PORT" "$UUID" "$UUID")")
        fi
    fi

    # AnyTLS（标准配置，保留变量 + 随机 password + padding）
    if is_selected 3; then
        # 生成每次运行随机密码，16 位字母数字
        ANYTLS_PASS=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c16)

        # 写入变量文件，确保 do_list 可以读取
        echo "ANYTLS_PASS='${ANYTLS_PASS}'" >> "$VARS_PATH"

        # padding_scheme 数组（示例，可根据需求修改）
        inbounds+=("$(printf '{
          "type":"anytls",
          "tag":"anytls-sb",
          "listen":"::",
          "listen_port":%s,
          "users":[{"name":"useranytls","password":"%s"}],
          "padding_scheme": [
            "stop=9",
            "0=20-40",
            "1=120-380",
            "2=360-480,c,520-960,c,480-980,c,520-1100",
            "3=12-16,480-960",
            "4=520-1100",
            "5=520-1100",
            "6=520-1100",
            "7=520-1100",
            "8=600-1200"
          ],
          "tls":{
            "enabled": true,
            "server_name": "%s",
            "certificate_path": "%s",
            "key_path": "%s",
            "alpn": ["h2", "http/1.1"]
          }
        }' "$ANYTLS_PORT" "$ANYTLS_PASS" "$ANYTLS_DOMAIN" "$CERT_PATH" "$KEY_PATH")")
    fi

    # 拼接 inbounds
    local inbounds_json=$(IFS=,; echo "${inbounds[*]}")

    cat > "$CONFIG_PATH" <<EOF
{
  "log": {"level": "info", "timestamp": true},
  "inbounds": [${inbounds_json}],
  "outbounds": [{"type": "direct", "tag": "direct"}]
}
EOF
    print_msg "配置文件已生成: $CONFIG_PATH" green
}

do_start() {
    load_variables
    if pgrep -f "$SINGBOX_PATH" >/dev/null 2>&1 || pgrep -f "$CLOUDFLARED_PATH" >/dev/null 2>&1; then
        do_stop
    fi
    nohup "$SINGBOX_PATH" run -c "$CONFIG_PATH" > "$AGSBX_DIR/sing-box.log" 2>&1 &
    if is_selected 2; then
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

do_list() {
    if [ ! -f "$VARS_PATH" ]; then
        print_msg "未找到配置文件，请先安装。" red
        return
    fi

    source "$VARS_PATH"

    server_ip=$(get_server_ip)
    server_ipv6=$(get_server_ipv6)
    hostname=$(hostname)

    if is_selected 1; then
        tuic_params="congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=www.bing.com&allow_insecure=1"
        print_msg "--- TUIC IPv4 ---" yellow
        echo "tuic://${UUID}:${UUID}@${server_ip}:${TUIC_PORT}?${tuic_params}#tuic-ipv4-${hostname}"
        print_msg "--- TUIC IPv6 ---" yellow
        echo "tuic://${UUID}:${UUID}@[${server_ipv6}]:${TUIC_PORT}?${tuic_params}#tuic-ipv6-${hostname}"
    fi

    # --- 3. 修改节点输出部分 ---
if is_selected 2; then
    # 确保读取了优选域名，如果没有则使用默认
    [ -z "$SELECTED_CF_DOMAIN" ] && SELECTED_CF_DOMAIN="cdns.doon.eu.org"
    
    current_argo_domain="$ARGO_DOMAIN"
    if [ -z "$ARGO_TOKEN" ]; then
        print_msg "等待临时 Argo 域名..." yellow
        for i in {1..10}; do
            current_argo_domain=$(grep -oE 'https://[a-zA-Z0-9.-]+\.trycloudflare\.com' "$AGSBX_DIR/argo.log" | head -n1 | sed 's/https:\/\///'   )
            [ -n "$current_argo_domain" ] && break
            sleep 2
        done
    fi
    if [ -n "$current_argo_domain" ]; then
        if [ "$ARGO_PROTOCOL" = "vless" ]; then
            echo "--- VLESS + Argo (TLS) ---" yellow
            # 使用 ${SELECTED_CF_DOMAIN} 替换了原有的 cdns.doon.eu.org
            echo "vless://${UUID}@${SELECTED_CF_DOMAIN}:443?encryption=none&security=tls&sni=${current_argo_domain}&fp=chrome&type=ws&host=${current_argo_domain}&path=%2f${UUID}-vl#argo-vless-${hostname}"
        else
            # 使用 ${SELECTED_CF_DOMAIN} 替换了原有的 cdns.doon.eu.org
            vmess_json=$(printf '{"v":"2","ps":"vmess-argo-%s","add":"%s","port":"443","id":"%s","aid":"0","scy":"auto","net":"ws","type":"none","host":"%s","path":"/%s-vm","tls":"tls","sni":"%s"}' "$hostname" "$SELECTED_CF_DOMAIN" "$UUID" "$current_argo_domain" "$UUID" "$current_argo_domain")
            vmess_base64=$(echo "$vmess_json" | tr -d '\n' | base64 -w0)
            echo "--- VMess + Argo (TLS) ---" yellow
            echo "vmess://${vmess_base64}"
        fi
    else
        print_msg "未能获取到 Argo 域名，请检查 $AGSBX_DIR/argo.log" red
    fi
fi

    if is_selected 3; then
        print_msg "--- AnyTLS ---" yellow
        # 使用从 VARS_PATH 读取的 ANYTLS_PASS
        echo "anytls://${ANYTLS_PASS}@${server_ip}:${ANYTLS_PORT}?sni=${ANYTLS_DOMAIN}#anytls-${hostname}"
        echo "anytls://${ANYTLS_PASS}@[${server_ipv6}]:${ANYTLS_PORT}?sni=${ANYTLS_DOMAIN}#anytls-${hostname}"
    fi

}

do_restart() { do_stop; sleep 1; do_start; }

do_uninstall() {
    # 如果是从 manage.sh 调用，则不询问
    if [ "$1" != "force" ]; then
        read -rp "$(printf "${C_YELLOW}确认卸载？将删除所有文件 (y/n): ${C_NC}")" confirm
        [ "$confirm" != "y" ] && print_msg "取消卸载" green && exit 0
    fi
    do_stop
    rm -rf "$AGSBX_DIR"
    print_msg "卸载完成" green
}

show_help() {
    print_msg "All-in-One TUIC & VLESS/VMess+Argo 管理脚本 (sing.sh)" blue
    echo "用法: bash $0 [命令]"
    echo "命令: install | list | start | stop | restart | uninstall | help"
}

# --- 主逻辑 ---
case "$1" in
    install) 
        do_install 
        ;;
    install_from_manager) 
        install_from_manager "$2" 
        ;;
    list)    
        do_list 
        ;;
    start)   
        do_start 
        ;;
    stop)    
        do_stop 
        ;;
    restart) 
        do_restart 
        ;;
    uninstall) 
        # 允许 manage.sh 强制卸载
        do_uninstall "$2"
        ;;
    help|*) 
        show_help 
        ;;
esac
