#!/usr/bin/env bash
set -e

# 目录和变量定义
XCONF_DIR="/etc/xray"
SYSTEMD_SERVICE="xray"

print_msg() {
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
        REMARK="reality-ipv4-$(date +%Y%m%d-%H%M)"
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
            print_msg "❌ 未检测到支持的服务管理器" red
            exit 1
        fi
        print_msg "✅ 节点已启动" green
        exit 0
        ;;
    stop)
        print_msg "正在停止节点..." yellow
        if command -v systemctl >/dev/null 2>&1; then
            systemctl stop "$SYSTEMD_SERVICE" 2>/dev/null || true
        fi
        if command -v rc-service >/dev/null 2>&1; then
            rc-service xray stop 2>/dev/null || true
        fi
        print_msg "✅ 节点已停止" green
        exit 0
        ;;
    uninstall)
        if [ -z "$2" ] || [ "$2" != "force" ]; then
            read -rp "$(printf "\033[0;33m⚠️ 确认卸载？(y/n): \033[0m")" confirm
            [ "$confirm" != "y" ] && exit 0
        fi
        bash "$0" stop >/dev/null 2>&1
        rm -f /etc/systemd/system/$SYSTEMD_SERVICE.service /etc/init.d/xray
        [ -x "$(command -v systemctl)" ] && systemctl daemon-reload
        rm -rf "$XCONF_DIR" /var/log/xray /usr/local/bin/xray
        print_msg "✅ 卸载完成" green
        exit 0
        ;;
esac

# --- 安装流程 ---
print_msg "正在安装基础依赖..." yellow
if command -v apk >/dev/null 2>&1; then
    apk update && apk add --no-cache curl unzip jq util-linux openssl
elif command -v apt >/dev/null 2>&1; then
    apt update -y && apt install -y curl unzip jq uuid-runtime openssl
elif command -v yum >/dev/null 2>&1; then
    yum install -y curl unzip jq util-linux openssl
fi

# 交互输入
read -rp "请输入监听端口（如 8443）: " PORT
read -rp "请输入 Reality SNI（如 microsoft.com, speed.cloudflare.com）: " SNI
[[ -z "$PORT" || -z "$SNI" ]] && { print_msg "❌ 不能为空" red; exit 1; }

# 下载 Xray
print_msg "正在下载 Xray-core..." yellow
XRAY_VER=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name )
ARCH_RAW=$(uname -m)
case "$ARCH_RAW" in
    x86_64) ARCH="64";;
    aarch64) ARCH="arm64-v8a";;
    *) print_msg "❌ 不支持的架构: $ARCH_RAW" red; exit 1;;
esac
curl -L -o /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VER}/Xray-linux-${ARCH}.zip"
unzip -o /tmp/xray.zip -d /tmp/xray
install -m 755 /tmp/xray/xray /usr/local/bin/xray
rm -rf /tmp/xray /tmp/xray.zip

# 生成参数
print_msg "正在生成 Reality 参数..." yellow
UUID=$(uuidgen)
KEYS=$(/usr/local/bin/xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep 'PrivateKey' | awk -F': ' '{print $2}' | tr -d '"')
PUBLIC_KEY=$(echo "$KEYS" | grep 'Password' | awk -F': ' '{print $2}' | tr -d '"')
SHORT_ID=$(openssl rand -hex 8)

# 写入配置 (完全采用配置 1 的标准模式)
print_msg "正在写入配置文件..." yellow
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
      "listen": "0.0.0.0",
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
          "serverNames": ["${SNI}"],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": ["${SHORT_ID}"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
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

# 校验 JSON
jq . /etc/xray/config.json >/dev/null 2>&1 || { print_msg "❌ JSON 格式错误" red; exit 1; }

# 设置服务
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
depend() { need net; }
EOF
    chmod +x /etc/init.d/xray
    rc-update add xray default
    rc-service xray restart
fi

# 输出结果
IP=$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}' )
REMARK="reality-ipv4-$(date +%Y%m%d-%H%M)"
echo ""
print_msg "🎉 安装完成" green
echo "---------------------------------------"
echo "vless://${UUID}@${IP}:${PORT}?encryption=none&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&flow=xtls-rprx-vision#${REMARK}"
echo "---------------------------------------"

# 保存变量
cat >/etc/xray/xray-vars.conf <<EOF
UUID='${UUID}'
PORT='${PORT}'
SNI='${SNI}'
PUBLIC_KEY='${PUBLIC_KEY}'
SHORT_ID='${SHORT_ID}'
EOF

# 创建快捷别名
if [ -f ~/.bashrc ]; then
    if ! grep -q "alias jiedian=" ~/.bashrc; then
        echo "alias jiedian='bash $(realpath "$0")'" >> ~/.bashrc
        print_msg "✅ 已创建快捷别名: jiedian (请重新连接终端或运行 source ~/.bashrc 生效)" yellow
    fi
fi
