#!/usr/bin/env bash

# ======================================================================
#     管道版 Xray 节点脚本 (xapline.sh)
#     经典方案: VLESS-TCP-XTLS-Vision-REALITY
#     结构与 x.sh 保持一致
# ======================================================================

XCONF_DIR="/etc/xray"
SYSTEMD_SERVICE="xray"
VARS_PATH="${XCONF_DIR}/xray-vars.conf"
XRAY_CONFIG="${XCONF_DIR}/config.json"
XRAY_BIN="/usr/local/bin/xray"

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
        INSTALL_CHOICE="${INSTALL_CHOICE:-4}"
        do_list
        exit 0
        ;;
    start)
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
        exit 0
        ;;
    stop)
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
        exit 0
        ;;
    uninstall)
        if [ -z "$2" ] || [ "$2" != "force" ]; then
            read -rp "$(printf "${C_YELLOW}确认卸载 Xray 节点？(y/n): ${C_NC}")" confirm
            [ "$confirm" != "y" ] && print_msg "取消卸载" green && exit 0
        fi
        print_msg "正在卸载 Xray 节点..." yellow
        bash "$0" stop >/dev/null 2>&1
        rm -f /etc/systemd/system/$SYSTEMD_SERVICE.service
        rm -f /etc/init.d/xray
        command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload
        rm -rf "$XCONF_DIR" /var/log/xray "$XRAY_BIN"
        print_msg "卸载完成" green
        exit 0
        ;;
esac

# --- 安装流程 ---

# 1. 基础依赖
print_msg "正在安装基础依赖..." yellow
if command -v apk >/dev/null 2>&1; then
    apk update
    apk add --no-cache curl unzip jq util-linux openssl
elif command -v apt >/dev/null 2>&1; then
    apt update -y
    apt install -y curl unzip jq uuid-runtime openssl
elif command -v yum >/dev/null 2>&1; then
    yum install -y curl unzip jq util-linux openssl
else
    print_msg "不支持的包管理器" red
    exit 1
fi

# 2. 交互输入
INSTALL_CHOICE="4"
read -rp "请输入监听端口（如 8443）: " PORT4
read -rp "请输入 Reality SNI（默认 gateway.icloud.com）: " SNI
SNI=${SNI:-gateway.icloud.com}

if [[ -z "$PORT4" || -z "$SNI" ]]; then
    print_msg "端口或 SNI 不能为空" red
    exit 1
fi

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
PRIVATE_KEY=$(echo "$KEYS" | grep 'PrivateKey' | awk -F': ' '{print $2}' | tr -d '"' | tr -d ' ')
PUBLIC_KEY=$(echo "$KEYS" | grep 'Password' | awk -F': ' '{print $2}' | tr -d '"' | tr -d ' ')
SHORT_ID=$(openssl rand -hex 8)

# 5. 生成配置
mkdir -p "$XCONF_DIR" /var/log/xray
do_generate_config

# 6. 服务设置
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
    systemctl daemon-reload
    systemctl enable xray
    systemctl restart xray
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
    rc-update add xray default
    rc-service xray restart
else
    print_msg "未检测到 systemd 或 OpenRC" red
    exit 1
fi

# 7. 保存变量 + 输出 URI
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
