#!/usr/bin/env bash
set -e

# ======================================================================
#     All-in-One Reality 节点脚本 (x.sh)
#     结构与 sing.sh 保持一致，便于扩展更多选项
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

ensure_deps() {
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
        print_msg "❌ 不支持的包管理器，请手动安装 curl, unzip, jq, uuidgen, openssl" red
        exit 1
    fi
}

get_public_ip() {
    curl -s https://api.ipify.org || hostname -I | awk '{print $1}'
}

load_variables() {
    [ -f "$VARS_PATH" ] && . "$VARS_PATH"
}

# 检查选项是否被选中
is_selected() {
    local choice=$1
    [[ ",$INSTALL_CHOICE," =~ ,$choice, ]]
}

# --- 核心功能 ---
show_uri() {
    if [ ! -f "$VARS_PATH" ]; then
        print_msg "❌ 未找到已安装的变量文件，请先安装节点" red
        exit 1
    fi

    load_variables
    local ip remark
    ip=$(get_public_ip)
    remark="reality-ipv4-instance-$(date +%Y%m%d-%H%M)"
    echo "vless://${UUID}@${ip}:${PORT}?encryption=none&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&flow=xtls-rprx-vision#${remark}"
}

do_start() {
    print_msg "正在启动 VLESS + Vision + Reality 节点..." green
    if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload
        systemctl enable "$SYSTEMD_SERVICE"
        systemctl restart "$SYSTEMD_SERVICE"
    elif command -v rc-service >/dev/null 2>&1; then
        rc-update add xray default 2>/dev/null || true
        rc-service xray restart
    else
        print_msg "❌ 未检测到 systemd 或 OpenRC，无法启动服务" red
        exit 1
    fi
    print_msg "✅ 节点已启动" green
}

do_stop() {
    print_msg "正在停止 VLESS + Vision + Reality 节点..." yellow
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop "$SYSTEMD_SERVICE" 2>/dev/null || true
        systemctl disable "$SYSTEMD_SERVICE" 2>/dev/null || true
    fi
    if command -v rc-service >/dev/null 2>&1; then
        rc-service xray stop 2>/dev/null || true
        rc-update del xray default 2>/dev/null || true
    fi
    print_msg "✅ 节点已停止" green
}

do_uninstall() {
    if [ -z "$1" ] || [ "$1" != "force" ]; then
        read -rp "$(printf "${C_YELLOW}⚠️ 确认卸载 VLESS + Vision + Reality 节点？(y/n): ${C_NC}")" confirm
        [ "$confirm" != "y" ] && print_msg "取消卸载" green && exit 0
    fi

    print_msg "⚠️ 即将卸载 VLESS + Vision + Reality 节点..." yellow
    do_stop
    rm -f "/etc/systemd/system/${SYSTEMD_SERVICE}.service"
    rm -f /etc/init.d/xray
    if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload
    fi
    rm -rf "$XCONF_DIR" /var/log/xray /usr/local/bin/xray
    print_msg "✅ 卸载完成" green
}

# --- 安装流程 ---
execute_installation() {
    local xray_ver arch keys private_key public_key short_id

    ensure_deps

    read -rp "请输入监听端口（如 8443）: " PORT
    read -rp "请输入 Reality SNI（如 microsoft.com，cloudflare.com，bing.com，speed.cloudflare.com，apple.com）: " SNI

    if [[ -z "$PORT" || -z "$SNI" ]]; then
        print_msg "❌ 端口或 SNI 不能为空" red
        exit 1
    fi

    print_msg "正在下载最新版 Xray-core..." yellow
    xray_ver=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)
    case "$(uname -m)" in
        x86_64) arch="64";;
        aarch64) arch="arm64-v8a";;
        *) print_msg "❌ 不支持的 CPU 架构: $(uname -m)" red; exit 1;;
    esac
    curl -L -o /tmp/xray.zip \
        "https://github.com/XTLS/Xray-core/releases/download/${xray_ver}/Xray-linux-${arch}.zip"

    unzip -o /tmp/xray.zip -d /tmp/xray
    install -m 755 /tmp/xray/xray /usr/local/bin/xray
    rm -rf /tmp/xray /tmp/xray.zip

    print_msg "正在生成 Reality 参数..." yellow
    UUID=$(uuidgen)
    keys=$(/usr/local/bin/xray x25519)
    private_key=$(echo "$keys" | grep 'PrivateKey' | awk -F': ' '{print $2}' | tr -d '"' | tr -d ' ')
    public_key=$(echo "$keys" | grep 'Password' | awk -F': ' '{print $2}' | tr -d '"' | tr -d ' ')
    short_id=$(openssl rand -hex 8)

    print_msg "正在写入配置文件 (官方 VLESS + Reality + Vision)..." yellow
    mkdir -p /etc/xray /var/log/xray

    cat >/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "${SNI}:443",
          "serverNames": [
            "${SNI}"
          ],
          "privateKey": "${private_key}",
          "shortIds": [
            "${short_id}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ],
        "routeOnly": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}
EOF

    jq . /etc/xray/config.json >/dev/null 2>&1 || { print_msg "❌ JSON 格式错误" red; exit 1; }

    print_msg "正在设置服务..." yellow
    if command -v systemctl >/dev/null 2>&1; then
        cat >/etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable xray
        systemctl restart xray
    elif command -v rc-service >/dev/null 2>&1; then
        cat >/etc/init.d/xray <<'EOF'
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
EOF
        chmod +x /etc/init.d/xray
        rc-update add xray default
        rc-service xray restart
    else
        print_msg "❌ 未检测到 systemd 或 OpenRC，无法创建服务" red
        exit 1
    fi

    print_msg "🎉 安装完成" green
    echo "---------------------------------------"
    local ip remark
    ip=$(get_public_ip)
    remark="reality-ipv4-instance-$(date +%Y%m%d-%H%M)"
    echo "vless://${UUID}@${ip}:${PORT}?encryption=none&security=reality&sni=${SNI}&fp=chrome&pbk=${public_key}&sid=${short_id}&flow=xtls-rprx-vision#${remark}"
    echo "---------------------------------------"

    cat >"$VARS_PATH" <<EOF
UUID='${UUID}'
PORT='${PORT}'
SNI='${SNI}'
PUBLIC_KEY='${public_key}'
SHORT_ID='${short_id}'
EOF
}

do_install() {
    print_msg "--- Reality 节点安装向导 ---" blue
    print_msg "请选择您要安装的节点类型 (支持多选，如输入 1):" yellow
    print_msg "  1) 安装 VLESS + Vision + Reality"
    read -rp "$(printf "${C_GREEN}请输入选项: ${C_NC}")" INSTALL_CHOICE

    INSTALL_CHOICE=$(echo "$INSTALL_CHOICE" | tr -d ' ' | tr '，' ',')

    if [[ ! "$INSTALL_CHOICE" =~ ^1(,1)*$ ]]; then
        print_msg "无效选项，请输入 1（用逗号分隔）。" red
        exit 1
    fi

    if is_selected 1; then
        execute_installation
    fi
}

install_from_manager() {
    local choices="$1"
    print_msg "接收到管理脚本指令，开始非交互式安装..." yellow
    INSTALL_CHOICE="$choices"

    if is_selected 1; then
        execute_installation
    fi
}

show_help() {
    print_msg "Reality 节点管理脚本" blue
    echo "用法: bash $0 [命令]"
    echo ""
    echo "核心命令:"
    echo "  install               - 显示交互式菜单，安装节点"
    echo "  install_from_manager  - 被 manage.sh 调用的安装方式"
    echo "  show-uri              - 输出分享链接"
    echo "  start                 - 启动服务"
    echo "  stop                  - 停止服务"
    echo "  uninstall             - 卸载服务"
    echo "  help                  - 显示此帮助信息"
}

# --- 主逻辑 ---
case "$1" in
    install)              do_install ;;
    install_from_manager) install_from_manager "$2" ;;
    show-uri)             show_uri ;;
    start)                do_start ;;
    stop)                 do_stop ;;
    uninstall)            do_uninstall "$2" ;;
    help|-h|--help)       show_help ;;
    "")                   do_install ;;
    *)                    show_help ;;
esac
