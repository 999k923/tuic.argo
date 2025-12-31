#!/usr/bin/env bash
set -e

XCONF_DIR="/etc/xray"
SYSTEMD_SERVICE="xray"

print_msg() { printf "\033[0;33m%s\033[0m\n" "$1"; }

# --- 命令判断 ---
case "$1" in
    show-uri)
        if [ ! -f "$XCONF_DIR/xray-vars.conf" ]; then
            echo "❌ 未找到已安装的变量文件，请先安装节点"
            exit 1
        fi
        source "$XCONF_DIR/xray-vars.conf"
        IP=$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')
        REMARK="reality-ipv4-instance-$(date +%Y%m%d-%H%M)"
        echo "vless://${UUID}@${IP}:${PORT}?encryption=none&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&flow=xtls-rprx-vision#${REMARK}"
        exit 0
        ;;
    start)
        print_msg "正在启动 VLESS + Vision + Reality 节点..."
        systemctl daemon-reload
        systemctl enable "$SYSTEMD_SERVICE"
        systemctl restart "$SYSTEMD_SERVICE"
        print_msg "节点已启动" green
        exit 0
        ;;    
    stop)
        print_msg "正在停止 VLESS + Vision + Reality 节点..."
        systemctl stop "$SYSTEMD_SERVICE" 2>/dev/null || true
        systemctl disable "$SYSTEMD_SERVICE" 2>/dev/null || true
        print_msg "节点已停止"
        exit 0
        ;;
    uninstall)
        print_msg "⚠️ 即将卸载 VLESS + Vision + Reality 节点..."
        bash "$0" stop
        rm -f /etc/systemd/system/$SYSTEMD_SERVICE.service
        systemctl daemon-reload
        rm -rf "$XCONF_DIR" /var/log/xray /usr/local/bin/xray
        print_msg "✅ 卸载完成"
        exit 0
        ;;
esac



# 1️⃣ 基础依赖
apt update -y
apt install -y curl unzip jq uuid-runtime openssl

# 2️⃣ 交互输入
read -rp "请输入监听端口（如 8443）: " PORT
read -rp "请输入 Reality SNI（如 www.cloudflare.com）: " SNI

if [[ -z "$PORT" || -z "$SNI" ]]; then
  echo "❌ 端口或 SNI 不能为空"
  exit 1
fi

# 3️⃣ 下载 xray
XRAY_VER=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)
curl -L -o /tmp/xray.zip \
  https://github.com/XTLS/Xray-core/releases/download/${XRAY_VER}/Xray-linux-64.zip

unzip -o /tmp/xray.zip -d /tmp/xray
install -m 755 /tmp/xray/xray /usr/local/bin/xray

# 4️⃣ 生成参数
UUID=$(uuidgen)
KEY_JSON=$(/usr/local/bin/xray x25519)
PRIVATE_KEY=$(echo "$KEY_JSON" | grep 'PrivateKey' | cut -d ':' -f2 | xargs)
PUBLIC_KEY=$(echo "$KEY_JSON" | grep 'Password'   | cut -d ':' -f2 | xargs)
SHORT_ID=$(openssl rand -hex 8)

# 5️⃣ 目录
mkdir -p /etc/xray /var/log/xray

# 6️⃣ Xray 配置
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
          "show": false,
          "dest": "${SNI}:443",
          "xver": 0,
          "serverNames": ["${SNI}"],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": ["${SHORT_ID}"]
        }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" }
  ]
}
EOF

# 7️⃣ 检查 JSON 格式
jq . /etc/xray/config.json >/dev/null 2>&1 || { echo "❌ JSON 格式错误"; exit 1; }

# 8️⃣ systemd
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

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

# 9️⃣ 输出 VLESS Reality URI
IP=$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')
REMARK="reality-ipv4-instance-$(date +%Y%m%d-%H%M)"

echo ""
echo "🎉 安装完成"
echo "---------------------------------------"
echo "vless://${UUID}@${IP}:${PORT}?encryption=none&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&flow=xtls-rprx-vision#${REMARK}"
echo "---------------------------------------"


cat >/etc/xray/xray-vars.conf <<EOF
UUID='${UUID}'
PORT='${PORT}'
SNI='${SNI}'
PUBLIC_KEY='${PUBLIC_KEY}'
SHORT_ID='${SHORT_ID}'
EOF


