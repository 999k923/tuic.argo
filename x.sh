#!/bin/bash

# ======================================================================
#     All-in-One Xray 节点脚本 (x.sh)
#     经典方案: VLESS-TCP-XTLS-Vision-REALITY
#     结构与 sing.sh 保持一致，便于扩展更多 Xray 协议
# ======================================================================

# --- 颜色 ---
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_NC='\033[0m'

# --- 常量 ---
XCONF_DIR="/etc/xray"
SYSTEMD_SERVICE="xray"
VARS_PATH="${XCONF_DIR}/xray-vars.conf"
XRAY_BIN="/usr/local/bin/xray"
XRAY_CONFIG="${XCONF_DIR}/config.json"

# --- 辅助函数 ---
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
        x86_64) echo "64";;
        aarch64) echo "arm64-v8a";;
        *) print_msg "错误: 不支持的 CPU 架构 $(uname -m)" red; exit 1;;
    esac
}

download_xray() {
    print_msg "正在下载最新版 Xray-core..." yellow
    local xray_ver arch
    xray_ver=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)
    arch=$(get_cpu_arch)
    curl -L -o /tmp/xray.zip \
        "https://github.com/XTLS/Xray-core/releases/download/${xray_ver}/Xray-linux-${arch}.zip"
    unzip -o /tmp/xray.zip -d /tmp/xray
    install -m 755 /tmp/xray/xray "$XRAY_BIN"
    rm -rf /tmp/xray /tmp/xray.zip
    print_msg "Xray ${xray_ver} 安装完成" green
}

ensure_deps() {
    print_msg "正在检查并安装基础依赖..." yellow
    if command -v apt >/dev/null 2>&1; then
        apt update -y >/dev/null 2>&1
        apt install -y curl unzip jq uuid-runtime openssl >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
        yum install -y curl unzip jq util-linux openssl >/dev/null 2>&1
    elif command -v apk >/dev/null 2>&1; then
        apk update >/dev/null 2>&1
        apk add --no-cache curl unzip jq util-linux openssl >/dev/null 2>&1
    else
        print_msg "不支持的包管理器，请手动安装 curl, unzip, jq, uuidgen, openssl" red
        exit 1
    fi
}

get_public_ip() {
    curl -4 -s https://api.ipify.org || hostname -I | awk '{print $1}'
}

load_variables() {
    [ -f "$VARS_PATH" ] && . "$VARS_PATH"
}

set_variable() {
    local key="$1"
    local value="$2"
    if [ -f "$VARS_PATH" ] && grep -q "^${key}=" "$VARS_PATH"; then
        sed -i "s/^${key}=.*/${key}='${value}'/" "$VARS_PATH"
    else
        echo "${key}='${value}'" >> "$VARS_PATH"
    fi
}

# 检查选项是否被选中
is_selected() {
    local choice=$1
    [[ ",$INSTALL_CHOICE," =~ ,$choice, ]]
}

# --- 配置生成 ---
do_generate_config() {
    load_variables

    local inbounds=()
    local outbound_json='{"protocol":"freedom","tag":"direct"}'

    # 选项4: VLESS-TCP-XTLS-Vision-REALITY
    if is_selected 4; then
        inbounds+=("$(printf '{
      "port": %s,
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "%s", "flow": "xtls-rprx-vision"}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "%s:443",
          "serverNames": ["%s"],
          "privateKey": "%s",
          "shortIds": ["%s"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "routeOnly": true
      }
    }' "$PORT4" "$UUID" "$SNI" "$SNI" "$PRIVATE_KEY" "$SHORT_ID")")
    fi

    # === 扩展区: 在这里添加新的 Xray 协议 ===
    # 示例: 选项6 - 新协议
    # if is_selected 6; then
    #     inbounds+=("...")
    # fi

    # 拼接 inbounds
    local inbounds_json
    inbounds_json=$(IFS=,; echo "${inbounds[*]}")

    cat > "$XRAY_CONFIG" <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [${inbounds_json}],
  "outbounds": [${outbound_json}]
}
EOF

    # 验证 JSON
    if ! jq . "$XRAY_CONFIG" >/dev/null 2>&1; then
        print_msg "JSON 配置格式错误" red
        exit 1
    fi
    print_msg "配置文件已生成: $XRAY_CONFIG" green
}

# --- 服务管理 ---
do_start() {
    load_variables
    print_msg "正在启动 Xray 节点..." green
    if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload
        systemctl enable "$SYSTEMD_SERVICE"
        systemctl restart "$SYSTEMD_SERVICE"
    elif command -v rc-service >/dev/null 2>&1; then
        rc-update add xray default 2>/dev/null || true
        rc-service xray restart
    else
        print_msg "未检测到 systemd 或 OpenRC" red
        exit 1
    fi
    print_msg "节点已启动" green
}

do_stop() {
    print_msg "正在停止 Xray 节点..." yellow
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop "$SYSTEMD_SERVICE" 2>/dev/null || true
        systemctl disable "$SYSTEMD_SERVICE" 2>/dev/null || true
    fi
    if command -v rc-service >/dev/null 2>&1; then
        rc-service xray stop 2>/dev/null || true
        rc-update del xray default 2>/dev/null || true
    fi
    print_msg "节点已停止" green
}

do_restart() {
    do_stop; sleep 1; do_start
}

do_list() {
    if [ ! -f "$VARS_PATH" ]; then
        print_msg "未找到配置文件，请先安装。" red
        return
    fi

    load_variables
    local ip
    ip=$(get_public_ip)

    if is_selected 4; then
        print_msg "--- VLESS-TCP-XTLS-Vision-REALITY ---" yellow
        echo "vless://${UUID}@${ip}:${PORT4}?encryption=none&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&flow=xtls-rprx-vision#reality-${ip}"
    fi
}

do_uninstall() {
    if [ "$1" != "force" ]; then
        read -rp "$(printf "${C_YELLOW}确认卸载 Xray 节点？(y/n): ${C_NC}")" confirm
        [ "$confirm" != "y" ] && print_msg "取消卸载" green && exit 0
    fi

    print_msg "正在卸载 Xray 节点..." yellow
    do_stop
    rm -f "/etc/systemd/system/${SYSTEMD_SERVICE}.service"
    rm -f /etc/init.d/xray
    if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload
    fi
    rm -rf "$XCONF_DIR" /var/log/xray "$XRAY_BIN"
    print_msg "卸载完成" green
}

set_ip_preference() {
    local preference="$1"
    local strategy

    if [ ! -f "$VARS_PATH" ] || [ ! -f "$XRAY_CONFIG" ]; then
        print_msg "未找到已安装的配置文件，请先安装节点" red
        exit 1
    fi

    case "$preference" in
        ipv4) strategy="UseIPv4" ;;
        ipv6) strategy="UseIPv6" ;;
        *) print_msg "无效参数，请使用 ipv4 或 ipv6" red; exit 1 ;;
    esac

    if ! command -v jq >/dev/null 2>&1; then
        print_msg "缺少 jq，无法修改配置" red
        exit 1
    fi

    jq --arg strategy "$strategy" \
        '(.outbounds[] | select(.tag=="direct" and .protocol=="freedom")).domainStrategy=$strategy' \
        "$XRAY_CONFIG" > "$XRAY_CONFIG.tmp"
    mv "$XRAY_CONFIG.tmp" "$XRAY_CONFIG"

    set_variable "OUTBOUND_IP_PREFERENCE" "$preference"
    do_restart
    print_msg "出口 IP 优先级已更新为: $preference" green
}

# --- 安装流程 ---
execute_installation() {
    local INSTALL_CHOICE="$1"

    ensure_deps
    mkdir -p "$XCONF_DIR" /var/log/xray
    touch "$VARS_PATH"
    chmod 600 "$VARS_PATH"
    echo "INSTALL_CHOICE='$INSTALL_CHOICE'" > "$VARS_PATH"

    # 选项4: Reality 参数
    if is_selected 4; then
        read -rp "$(printf "${C_GREEN}请输入 Reality 监听端口 (默认 8443): ${C_NC}")" PORT4
        PORT4=${PORT4:-8443}
        echo "PORT4='${PORT4}'" >> "$VARS_PATH"

        read -rp "$(printf "${C_GREEN}请输入 Reality SNI (默认 gateway.icloud.com): ${C_NC}")" SNI
        SNI=${SNI:-gateway.icloud.com}
        echo "SNI='${SNI}'" >> "$VARS_PATH"
    fi

    # === 扩展区: 新协议的参数输入 ===
    # if is_selected 6; then
    #     read -rp "..." PORT6
    #     ...
    # fi

    load_variables

    # 下载 Xray
    if [ ! -f "$XRAY_BIN" ]; then
        download_xray
    fi

    # 生成 Reality 密钥对
    if is_selected 4; then
        UUID=$(uuidgen)
        echo "UUID='${UUID}'" >> "$VARS_PATH"
        print_msg "生成 UUID: $UUID" yellow

        local keys
        keys=$($XRAY_BIN x25519)
        PRIVATE_KEY=$(echo "$keys" | grep 'PrivateKey' | awk -F': ' '{print $2}' | tr -d '"' | tr -d ' ')
        PUBLIC_KEY=$(echo "$keys" | grep 'Password' | awk -F': ' '{print $2}' | tr -d '"' | tr -d ' ')
        SHORT_ID=$(openssl rand -hex 8)

        echo "PRIVATE_KEY='${PRIVATE_KEY}'" >> "$VARS_PATH"
        echo "PUBLIC_KEY='${PUBLIC_KEY}'" >> "$VARS_PATH"
        echo "SHORT_ID='${SHORT_ID}'" >> "$VARS_PATH"

        print_msg "Reality 密钥对已生成" yellow
    fi

    # 生成配置
    do_generate_config

    # 创建 systemd/openrc 服务
    print_msg "正在设置服务..." yellow
    if command -v systemctl >/dev/null 2>&1; then
        cat >/etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStart=${XRAY_BIN} run -config ${XRAY_CONFIG}
Restart=on-failure
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
    elif command -v rc-service >/dev/null 2>&1; then
        cat >/etc/init.d/xray <<'RCEOF'
#!/sbin/openrc-run

name="xray"
description="Xray Service"
command="/usr/local/bin/xray"
command_args="run -config /etc/xray/config.json"
pidfile="/run/xray.pid"
command_background=true

depend() {
    need net
}
RCEOF
        chmod +x /etc/init.d/xray
    fi

    # 启动
    do_start

    # 输出节点信息
    print_msg "\n--- 安装完成，获取节点信息 ---" blue
    do_list
}

do_install() {
    print_msg "--- Xray 节点安装向导 ---" blue
    print_msg "请选择您要安装的节点类型 (支持多选，如输入 4):" yellow
    print_msg "  4) 安装 VLESS-TCP-XTLS-Vision-REALITY"
    # === 扩展区 ===
    # print_msg "  6) 安装 新协议名"
    read -rp "$(printf "${C_GREEN}请输入选项: ${C_NC}")" INSTALL_CHOICE

    INSTALL_CHOICE=$(echo "$INSTALL_CHOICE" | tr -d ' ' | tr '，' ',')

    if [[ ! "$INSTALL_CHOICE" =~ ^[4](,[4])*$ ]]; then
        print_msg "无效选项，当前仅支持选项4。" red
        exit 1
    fi

    execute_installation "$INSTALL_CHOICE"
}

install_from_manager() {
    local choices="$1"
    print_msg "接收到管理脚本指令，开始非交互式安装..." yellow
    execute_installation "$choices"
}

show_help() {
    print_msg "Xray 节点管理脚本 (VLESS-TCP-XTLS-Vision-REALITY)" blue
    echo "用法: bash $0 [命令]"
    echo ""
    echo "命令:"
    echo "  install               - 交互式安装节点"
    echo "  install_from_manager  - 被 manage.sh 调用的安装方式"
    echo "  list                  - 输出分享链接"
    echo "  start                 - 启动服务"
    echo "  stop                  - 停止服务"
    echo "  restart               - 重启服务"
    echo "  set-ip-preference     - 设置出口优先 IPv4 或 IPv6"
    echo "  uninstall             - 卸载服务"
    echo "  help                  - 显示此帮助信息"
}

# --- 主逻辑 ---
case "$1" in
    install)              do_install ;;
    install_from_manager) install_from_manager "$2" ;;
    list|show-uri)       do_list ;;
    start)                do_start ;;
    stop)                 do_stop ;;
    restart)              do_restart ;;
    set-ip-preference)    set_ip_preference "$2" ;;
    uninstall)            do_uninstall "$2" ;;
    help|-h|--help)       show_help ;;
    "")                   do_install ;;
    *)                    show_help ;;
esac
