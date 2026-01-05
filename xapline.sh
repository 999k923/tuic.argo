#!/usr/bin/env bash
set -e

XCONF_DIR="/etc/xray"
SYSTEMD_SERVICE="xray"

print_msg() {
    # 统一颜色定义
    case "$2" in
        red)    printf "\033[0;31m%s\033[0m\n" "$1";;
        green)  printf "\033[0;32m%s\033[0m\n" "$1";;
        yellow) printf "\033[0;33m%s\033[0m\n" "$1";;
        *)      printf "\033[0;33m%s\033[0m\n" "$1";;
    esac
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
        echo "vless://${UUID}@${IP}:${PORT}?encryption=none&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&flow=xtls-rprx-vision#${REMARK}"
        exit 0
        ;;
    start)
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
        exit 0
        ;;
    stop)
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
        exit 0
        ;;
    uninstall)
        # 如果是直接运行 x.sh uninstall，则询问
        if [ -z "$2" ] || [ "$2" != "force" ]; then
            read -rp "$(printf "\033[0;33m⚠️ 确认卸载 VLESS + Vision + Reality 节点？(y/n): \033[0m")" confirm
            [ "$confirm" != "y" ] && print_msg "取消卸载" green && exit 0
        fi
        
        print_msg "⚠️ 即将卸载 VLESS + Vision + Reality 节点..." yellow
        # 调用自身的 stop 命令
        bash "$0" stop >/dev/null 2>&1
        rm -f /etc/systemd/system/$SYSTEMD_SERVICE.service
        rm -f /etc/init.d/xray
        if command -v systemctl >/dev/null 2>&1; then
            systemctl daemon-reload
        fi
        rm -rf "$XCONF_DIR" /var/log/xray /usr/local/bin/xray
        print_msg "✅ 卸载完成" green
        exit 0
        ;;
esac

# --- 从这里开始是安装流程 ---

# 1️⃣ 基础依赖
print_msg "正在安装基础依赖..." yellow
if command -v apk >/dev/null 2>&1; then
    # Alpine Linux
    apk update
    apk add --no-cache curl unzip jq util-linux openssl
elif command -v apt >/dev/null 2>&1; then
    # Debian / Ubuntu
    apt update -y
    apt install -y curl unzip jq uuid-runtime openssl
elif command -v yum >/dev/null 2>&1; then
    # CentOS / Rocky / Alma
    yum install -y curl unzip jq util-linux openssl
else
    print_msg "❌ 不支持的包管理器，请手动安装 curl, unzip, jq, uuidgen, openssl" red
    exit 1
fi


# 2️⃣ 交互输入
read -rp "请输入监听端口（如 8443）: " PORT
read -rp "请输入 Reality SNI（如 microsoft.com，cloudflare.com，bing.com，speed.cloudflare.com，apple.com）: " SNI

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
PRIVATE_KEY=$(echo "$KEYS" | grep 'PrivateKey' | awk -F': ' '{print $2}' | tr -d '"' | tr -d ' ')
PUBLIC_KEY=$(echo "$KEYS" | grep 'Password' | awk -F': ' '{print $2}' | tr -d '"' | tr -d ' ')
SHORT_ID=$(openssl rand -hex 8)


# 5️⃣ 目录和配置
print_msg "正在写入配置文件 (官方 VLESS + Reality + Vision)..." yellow
mkdir -p /etc/xray /var/log/xray

cat >/etc/xray/config.json <<EOF
{
   "log": {
    "loglevel": "debug",
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
jq . /etc/xray/config.json >/dev/null 2>&1 || { print_msg "❌ JSON 格式错误" red; exit 1; }

# 8️⃣ 服务设置 (systemd / OpenRC 兼容)
print_msg "正在设置服务..." yellow

if command -v systemctl >/dev/null 2>&1; then
    # ===== systemd =====
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
    # ===== Alpine OpenRC =====
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

# 9️⃣ 启动服务 (调用自身的 start 命令以确保逻辑一致)
# bash "$0" start  # 上面已经直接处理了启动，这里不再重复调用

# 🔟 输出 VLESS Reality URI
IP=$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}' )
REMARK="reality-ipv4-instance-$(date +%Y%m%d-%H%M)"

echo ""
print_msg "🎉 安装完成" green
echo "---------------------------------------"
echo "vless://${UUID}@${IP}:${PORT}?encryption=none&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&flow=xtls-rprx-vision#${REMARK}"
echo "---------------------------------------"

# 11. 保存变量
cat >/etc/xray/xray-vars.conf <<EOF
UUID='${UUID}'
PORT='${PORT}'
SNI='${SNI}'
PUBLIC_KEY='${PUBLIC_KEY}'
SHORT_ID='${SHORT_ID}'
EOF
