#!/usr/bin/env bash

# ======================================================================
#     Docker 版 Xray 节点脚本 (xdocker.sh)
#     经典方案: VLESS-TCP-XTLS-Vision-REALITY
#     结构与 x.sh 保持一致
# ======================================================================

XCONF_DIR="/etc/xray"
XRAY_BIN="/usr/local/bin/xray"
XRAY_CONFIG="${XCONF_DIR}/config.json"
XRAY_PID_FILE="${XCONF_DIR}/xray.pid"
VARS_PATH="${XCONF_DIR}/xray-vars.conf"
DOCKER_MODE="${DOCKER_MODE:-0}"

# --- 颜色 ---
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_NC='\033[0m'

print_msg() {
    case "$2" in
        red)    printf "${C_RED}%s${C_NC}\n" "$1";;
        green)  printf "${C_GREEN}%s${C_NC}\n" "$1";;
        yellow) printf "${C_YELLOW}%s${C_NC}\n" "$1";;
        blue)   printf "${C_BLUE}%s${C_NC}\n" "$1";;
        *)      printf "%s\n" "$1";;
    esac
}

require_env() {
    local var_name="$1"
    if [ -z "${!var_name}" ]; then
        print_msg "缺少必要环境变量: ${var_name}" red
        exit 1
    fi
}

is_docker_mode() {
    [ "$DOCKER_MODE" = "1" ]
}

load_variables() {
    [ -f "$VARS_PATH" ] && . "$VARS_PATH"
}

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

    # === 扩展区 ===

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

    jq . "$XRAY_CONFIG" >/dev/null 2>&1 || { print_msg "JSON 格式错误" red; exit 1; }
    print_msg "配置文件已生成: $XRAY_CONFIG" green
}

# --- 服务管理 ---
start_xray() {
    if [ ! -f "$XRAY_CONFIG" ]; then
        print_msg "未找到配置文件，请先安装节点" red
        exit 1
    fi
    pkill -f "${XRAY_BIN} run -config ${XRAY_CONFIG}" 2>/dev/null || true
    nohup "${XRAY_BIN}" run -config "${XRAY_CONFIG}" > /var/log/xray/xray.out 2>&1 &
    echo $! > "$XRAY_PID_FILE"
    print_msg "节点已启动" green
}

stop_xray() {
    if [ -f "$XRAY_PID_FILE" ]; then
        kill "$(cat "$XRAY_PID_FILE")" 2>/dev/null || true
        rm -f "$XRAY_PID_FILE"
    fi
    pkill -f "${XRAY_BIN} run -config ${XRAY_CONFIG}" 2>/dev/null || true
    print_msg "节点已停止" green
}

do_list() {
    if [ ! -f "$VARS_PATH" ]; then
        print_msg "未找到配置文件，请先安装。" red
        return
    fi

    load_variables
    local ip
    ip=$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')

    if is_selected 4; then
        print_msg "--- VLESS-TCP-XTLS-Vision-REALITY ---" yellow
        echo "vless://${UUID}@${ip}:${PORT4}?encryption=none&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&flow=xtls-rprx-vision#reality-${ip}"
    fi
}

# --- 命令判断 ---
case "$1" in
    show-uri)
        do_list
        exit 0
        ;;
    start)
        print_msg "正在启动 Xray 节点..." green
        start_xray
        exit 0
        ;;
    stop)
        print_msg "正在停止 Xray 节点..." yellow
        stop_xray
        exit 0
        ;;
    uninstall)
        if [ -z "$2" ] || [ "$2" != "force" ]; then
            read -rp "$(printf "${C_YELLOW}确认卸载 Xray 节点？(y/n): ${C_NC}")" confirm
            [ "$confirm" != "y" ] && print_msg "取消卸载" green && exit 0
        fi
        print_msg "正在卸载 Xray 节点..." yellow
        bash "$0" stop >/dev/null 2>&1
        rm -rf "$XCONF_DIR" /var/log/xray "$XRAY_BIN"
        print_msg "卸载完成" green
        exit 0
        ;;
esac

# Docker 模式下如已存在配置则跳过重装
if is_docker_mode && [ -x "$XRAY_BIN" ] && [ -f "$XRAY_CONFIG" ] && [ -f "$VARS_PATH" ]; then
    load_variables
    INSTALL_CHOICE="${INSTALL_CHOICE:-4}"
    print_msg "检测到已有配置，跳过重新安装，直接启动服务。" yellow
    start_xray
    do_list
    exit 0
fi

# --- 安装流程 ---

# 1. 基础依赖
print_msg "正在安装基础依赖..." yellow
if command -v apt >/dev/null 2>&1; then
    apt update -y
    apt install -y curl unzip jq uuid-runtime openssl
elif command -v yum >/dev/null 2>&1; then
    yum install -y curl unzip jq uuid-runtime openssl
else
    print_msg "不支持的包管理器" red
    exit 1
fi

# 2. 交互输入
if is_docker_mode; then
    require_env "XRAY_PORT"
    require_env "XRAY_SNI"
    PORT4="$XRAY_PORT"
    SNI="$XRAY_SNI"
    INSTALL_CHOICE="4"
else
    INSTALL_CHOICE="4"
    read -rp "请输入监听端口（如 8443）: " PORT4
    read -rp "请输入 Reality SNI（默认 gateway.icloud.com）: " SNI
    SNI=${SNI:-gateway.icloud.com}
fi

if [[ -z "$PORT4" || -z "$SNI" ]]; then
    print_msg "端口或 SNI 不能为空" red
    exit 1
fi

mkdir -p "$XCONF_DIR" /var/log/xray

# 3. 下载 xray
print_msg "正在下载最新版 Xray-core..." yellow
XRAY_VER=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)
case "$(uname -m)" in
    x86_64) ARCH="64";;
    aarch64) ARCH="arm64-v8a";;
    *) print_msg "不支持的 CPU 架构: $(uname -m)" red; exit 1;;
esac
curl -L -o /tmp/xray.zip \
    "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VER}/Xray-linux-${ARCH}.zip"
unzip -o /tmp/xray.zip -d /tmp/xray
install -m 755 /tmp/xray/xray "$XRAY_BIN"
rm -rf /tmp/xray /tmp/xray.zip

# 4. 生成参数
print_msg "正在生成 Reality 参数..." yellow
UUID=$(uuidgen)
KEYS=$($XRAY_BIN x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep 'PrivateKey' | awk -F': ' '{print $2}' | tr -d '"')
PUBLIC_KEY=$(echo "$KEYS" | grep 'Password' | awk -F': ' '{print $2}' | tr -d '"')
SHORT_ID=$(openssl rand -hex 8)

# 5. 生成配置
do_generate_config

# 6. 启动服务
start_xray

# 7. 输出 URI + 保存变量
cat >"$VARS_PATH" <<EOF
INSTALL_CHOICE='4'
UUID='${UUID}'
PORT4='${PORT4}'
SNI='${SNI}'
PUBLIC_KEY='${PUBLIC_KEY}'
SHORT_ID='${SHORT_ID}'
EOF

echo ""
print_msg "安装完成" green
echo "---------------------------------------"
do_list
echo "---------------------------------------"
