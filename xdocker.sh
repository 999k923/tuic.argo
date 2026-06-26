#!/usr/bin/env bash
set -e

XCONF_DIR="/etc/xray"
XRAY_BIN="/usr/local/bin/xray"
XRAY_CONFIG="${XCONF_DIR}/config.json"
XRAY_PID_FILE="${XCONF_DIR}/xray.pid"
DOCKER_MODE="${DOCKER_MODE:-0}"

print_msg() {
    # 统一颜色定义
    case "$2" in
        red)    printf "\033[0;31m%s\033[0m\n" "$1";;
        green)  printf "\033[0;32m%s\033[0m\n" "$1";;
        yellow) printf "\033[0;33m%s\033[0m\n" "$1";;
        *)      printf "\033[0;33m%s\033[0m\n" "$1";;
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

start_xray() {
    if [ ! -f "$XRAY_CONFIG" ]; then
        print_msg "❌ 未找到配置文件，请先安装节点" red
        exit 1
    fi
    pkill -f "${XRAY_BIN} run -config ${XRAY_CONFIG}" 2>/dev/null || true
    nohup "${XRAY_BIN}" run -config "${XRAY_CONFIG}" > /var/log/xray/xray.out 2>&1 &
    echo $! > "$XRAY_PID_FILE"
    print_msg "✅ 节点已启动" green
}

stop_xray() {
    if [ -f "$XRAY_PID_FILE" ]; then
        kill "$(cat "$XRAY_PID_FILE")" 2>/dev/null || true
        rm -f "$XRAY_PID_FILE"
    fi
    pkill -f "${XRAY_BIN} run -config ${XRAY_CONFIG}" 2>/dev/null || true
    print_msg "✅ 节点已停止" green
}

# --- 命令判断 ---
case "$1" in
    show-uri)
        if [ ! -f "$XCONF_DIR/xray-vars.conf" ]; then
            echo "❌ 未找到已安装的变量文件，请先安装节点"
            exit 1
        fi
        source "$XCONF_DIR/xray-vars.conf"
        IP=$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}' )
        REMARK="reality-ipv4-instance-$(date +%Y%m%d-%H%M)"
        echo "vless://${UUID}@${IP}:${PORT}?encryption=none&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&flow=xtls-rprx-vision&type=xhttp&path=%2f${UUID}-xh#${REMARK}"
        exit 0
        ;;
    start)
        print_msg "正在启动 VLESS + XHTTP + Vision + Reality 节点..." green
        start_xray
        exit 0
        ;;
    stop)
        print_msg "正在停止 VLESS + XHTTP + Vision + Reality 节点..." yellow
        stop_xray
        exit 0
        ;;
    uninstall)
        # 如果是直接运行 x.sh uninstall，则询问
        if [ -z "$2" ] || [ "$2" != "force" ]; then
            read -rp "$(printf "\033[0;33m⚠️ 确认卸载 VLESS + XHTTP + Vision + Reality 节点？(y/n): \033[0m")" confirm
            [ "$confirm" != "y" ] && print_msg "取消卸载" green && exit 0
        fi
        
        print_msg "⚠️ 即将卸载 VLESS + XHTTP + Vision + Reality 节点..." yellow
        # 调用自身的 stop 命令
        bash "$0" stop >/dev/null 2>&1
        rm -rf "$XCONF_DIR" /var/log/xray "$XRAY_BIN"
        print_msg "✅ 卸载完成" green
        exit 0
        ;;
esac

# Docker 模式下如已存在配置则跳过重装
if is_docker_mode && [ -x "$XRAY_BIN" ] && [ -f "$XRAY_CONFIG" ] && [ -f "$XCONF_DIR/xray-vars.conf" ]; then
    print_msg "检测到已有配置，跳过重新安装，直接启动服务。" yellow
    start_xray
    exit 0
fi

# --- 从这里开始是安装流程 ---

# 1️⃣ 基础依赖
print_msg "正在安装基础依赖..." yellow
if command -v apt >/dev/null 2>&1; then
    apt update -y
    apt install -y curl unzip jq uuid-runtime openssl
elif command -v yum >/dev/null 2>&1; then
    yum install -y curl unzip jq uuid-runtime openssl
else
    print_msg "❌ 不支持的包管理器，请手动安装 curl, unzip, jq, uuid-runtime, openssl" red
    exit 1
fi


# 2️⃣ 交互输入
if is_docker_mode; then
    require_env "XRAY_PORT"
    require_env "XRAY_SNI"
    PORT="$XRAY_PORT"
    SNI="$XRAY_SNI"
else
    read -rp "请输入监听端口（如 8443）: " PORT
    read -rp "请输入 Reality SNI（如 microsoft.com，cloudflare.com，speed.cloudflare.com，apple.com，节点不同尝试换其他的试试）: " SNI
fi

if [[ -z "$PORT" || -z "$SNI" ]]; then
  print_msg "❌ 端口或 SNI 不能为空" red
  exit 1
fi

# 3️⃣ 下载 xray
print_msg "正在下载最新版 Xray-core..." yellow
XRAY_VER=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name )
case "$(uname -m)" in
    x86_64) ARCH="64";;
    aarch64) ARCH="arm64-v8a";;
    *) print_msg "❌ 不支持的 CPU 架构: $(uname -m)" red; exit 1;;
esac
curl -L -o /tmp/xray.zip \
  "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VER}/Xray-linux-${ARCH}.zip"

unzip -o /tmp/xray.zip -d /tmp/xray
install -m 755 /tmp/xray/xray /usr/local/bin/xray
rm -rf /tmp/xray /tmp/xray.zip

# 4️⃣ 生成参数
print_msg "正在生成 Reality 参数..." yellow
UUID=$(uuidgen)
KEYS=$(/usr/local/bin/xray x25519)
# 使用更健壮的 awk 命令来提取，同时保留您正确的 grep 逻辑
PRIVATE_KEY=$(echo "$KEYS" | grep 'PrivateKey' | awk -F': ' '{print $2}' | tr -d '"')
PUBLIC_KEY=$(echo "$KEYS" | grep 'Password' | awk -F': ' '{print $2}' | tr -d '"')
SHORT_ID=$(openssl rand -hex 8)


# 5️⃣ 目录和配置
print_msg "正在写入配置文件 (VLESS + XHTTP + Reality + Vision + Enc)..." yellow
mkdir -p /etc/xray /var/log/xray

cat >"${XRAY_CONFIG}" <<EOF
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
        "network": "xhttp",
        "xhttpSettings": {
          "path": "/${UUID}-xh",
          "mode": "auto",
          "xPaddingBytes": "100-1000"
        },
        "security": "reality",
        "realitySettings": {
          "dest": "${SNI}:443",
          "serverNames": [
            "${SNI}"
          ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [
            "${SHORT_ID}"
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



# 7️⃣ 检查 JSON 格式
jq . "${XRAY_CONFIG}" >/dev/null 2>&1 || { print_msg "❌ JSON 格式错误" red; exit 1; }

# 8️⃣ 启动服务
start_xray

# 🔟 输出 VLESS Reality URI
IP=$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}' )
REMARK="xhttp-reality-ipv4-$(date +%Y%m%d-%H%M)"

echo ""
print_msg "🎉 安装完成" green
echo "---------------------------------------"
echo "vless://${UUID}@${IP}:${PORT}?encryption=none&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&flow=xtls-rprx-vision&type=xhttp&path=%2f${UUID}-xh#${REMARK}"
echo "---------------------------------------"

# 11. 保存变量
cat >/etc/xray/xray-vars.conf <<EOF
UUID='${UUID}'
PORT='${PORT}'
SNI='${SNI}'
PUBLIC_KEY='${PUBLIC_KEY}'
SHORT_ID='${SHORT_ID}'
EOF
