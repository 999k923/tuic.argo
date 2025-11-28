#!/usr/bin/env bash
# All-in-One TUIC & VLESS/VMess + Argo 管理脚本
# 说明: 单文件脚本，支持交互安装/管理 sing-box + cloudflared
# 作者: ChatGPT (生成)
# 2025-11-27
set -euo pipefail
IFS=$'\n\t'

# ----------------------------
# 颜色
# ----------------------------
C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'; C_NC='\033[0m'

print_msg() {
  local msg="$1"; local color="${2:-}"
  case "$color" in
    red) printf "${C_RED}%s${C_NC}\n" "$msg" ;;
    green) printf "${C_GREEN}%s${C_NC}\n" "$msg" ;;
    yellow) printf "${C_YELLOW}%s${C_NC}\n" "$msg" ;;
    blue) printf "${C_BLUE}%s${C_NC}\n" "$msg" ;;
    *) printf "%s\n" "$msg" ;;
  esac
}

# ----------------------------
# 环境变量 & 路径
# ----------------------------
HOME_DIR=$(eval echo ~)
AGSBX_DIR="$HOME_DIR/agsbx"
SINGBOX_PATH="$AGSBX_DIR/sing-box"
CLOUDFLARED_PATH="$AGSBX_DIR/cloudflared"
CONFIG_PATH="$AGSBX_DIR/sb.json"
CERT_PATH="$AGSBX_DIR/cert.pem"
KEY_PATH="$AGSBX_DIR/private.key"
VARS_PATH="$AGSBX_DIR/variables.conf"
SYSTEMD_DIR="/etc/systemd/system"

# ----------------------------
# 小工具
# ----------------------------
get_cpu_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) print_msg "错误: 不支持的 CPU 架构 $(uname -m)" "red"; exit 1 ;;
  esac
}

download_file() {
    URL="$1"
    OUTPUT="$2"

    echo -e "\n>>> 检测 GitHub IPv4 连接..."
    if curl -4 --connect-timeout 4 -s https://github.com >/dev/null; then
        echo "✅ IPv4 可访问 GitHub，优先使用 IPv4 下载"
        PROTO="-4"
    else
        echo "⚠ IPv4 无法访问 GitHub"
        PROTO=""
    fi

    echo -e "\n>>> 开始下载: $URL"
    if curl $PROTO -L --retry 3 --retry-delay 2 -o "$OUTPUT" "$URL"; then
        echo "✅ 下载成功: $OUTPUT"
        return 0
    fi

    echo "❌ 下载失败，尝试使用镜像源..."

    MIRRORS=(
        "https://ghproxy.net/"
        "https://mirror.ghproxy.com/"
        "https://download.fastgit.org/"
    )

    for MIRROR in "${MIRRORS[@]}"; do
        echo "→ 镜像: $MIRROR"
        if curl $PROTO -L --retry 3 --retry-delay 2 -o "$OUTPUT" "${MIRROR}${URL}"; then
            echo "✅ 镜像下载成功: $OUTPUT"
            return 0
        fi
    done

    echo "❌ 所有镜像下载失败，请检查网络"
    return 1
}


# 读取/保存 variables.conf
load_variables() {
  if [ -f "$VARS_PATH" ]; then
    # shellcheck disable=SC1090
    . "$VARS_PATH"
    return 0
  fi
  return 1
}
save_var() {
  local key="$1"; local val="$2"
  mkdir -p "$AGSBX_DIR"
  # quote value safely
  printf '%s=%q\n' "$key" "$val" >> "$VARS_PATH"
}

# ----------------------------
# 依赖安装（尝试）
# ----------------------------
install_prereqs() {
  print_msg "检测并安装基础依赖（curl/wget/tar/openssl/ca-certificates）..." "blue"
  if command -v apk >/dev/null 2>&1; then
    apk update
    apk add --no-cache curl wget tar openssl ca-certificates bash || true
  elif command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get update || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget tar openssl ca-certificates bash || true
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl wget tar openssl ca-certificates bash || true
  else
    print_msg "未检测到常见包管理器，请确保 curl/wget/tar/openssl 已安装。" "yellow"
  fi
}

# ----------------------------
# sing-box 安装
# ----------------------------
install_singbox() {
  if [ -x "$SINGBOX_PATH" ]; then
    print_msg "sing-box 已存在，跳过下载。" "yellow"; return 0
  fi
  local arch; arch=$(get_cpu_arch)
  # 选择一个稳定版本号：可以按需修改
  local ver="1.9.0"
  local tarname="sing-box-${ver}-linux-${arch}.tar.gz"
  local url="https://github.com/SagerNet/sing-box/releases/download/v${ver}/${tarname}"
  local tmp="$AGSBX_DIR/${tarname}"
  download_file "$url" "$tmp" || {
    print_msg "sing-box 官方包下载失败 (尝试备用 v1.9.0-beta.13)..." "yellow"
    tmp="$AGSBX_DIR/sing-box-beta.tar.gz"
    url="https://github.com/SagerNet/sing-box/releases/download/v1.9.0-beta.13/sing-box-1.9.0-beta.13-linux-${arch}.tar.gz"
    download_file "$url" "$tmp" || { print_msg "sing-box 下载备用也失败，请手动处理。" "red"; return 1; }
  }
  mkdir -p "$AGSBX_DIR"
  tar -xzf "$tmp" -C "$AGSBX_DIR" || { print_msg "解压 sing-box 失败。" "red"; return 1; }
  # 在解压目录寻找可执行文件
  local found
  found=$(find "$AGSBX_DIR" -maxdepth 2 -type f -name 'sing-box' | head -n1 || true)
  if [ -n "$found" ]; then
    mv "$found" "$SINGBOX_PATH" 2>/dev/null || cp "$found" "$SINGBOX_PATH"
    chmod +x "$SINGBOX_PATH"
    print_msg "sing-box 安装成功：$SINGBOX_PATH" "green"
    rm -f "$tmp"
    # 清理解压残余目录（保守）
    find "$AGSBX_DIR" -maxdepth 1 -type d -name 'sing-box*' -exec rm -rf {} \; || true
    return 0
  else
    print_msg "未在解压结果中找到 sing-box 可执行文件，请检查 tar 包结构。" "red"
    return 1
  fi
}

# ----------------------------
# cloudflared 安装
# ----------------------------
install_cloudflared() {
  if [ -x "$CLOUDFLARED_PATH" ]; then
    print_msg "cloudflared 已存在，跳过下载。" "yellow"; return 0
  fi
  local arch; arch=$(get_cpu_arch)
  local url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}"
  download_file "$url" "$CLOUDFLARED_PATH" || { print_msg "cloudflared 下载失败，请手动检查网络或版本。" "red"; return 1; }
  chmod +x "$CLOUDFLARED_PATH"
  print_msg "cloudflared 安装成功：$CLOUDFLARED_PATH" "green"
}

# ----------------------------
# 生成/启动/停止/管理
# ----------------------------
generate_uuid() {
  if [ -x "$SINGBOX_PATH" ]; then
    # try sing-box generate uuid
    if "$SINGBOX_PATH" generate uuid >/dev/null 2>&1; then
      "$SINGBOX_PATH" generate uuid
      return 0
    fi
  fi
  # fallback to openssl
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 16
  else
    # fallback random
    head -c16 /dev/urandom | od -An -tx1 | tr -d ' \n'
  fi
}

create_tls_cert() {
  mkdir -p "$AGSBX_DIR"
  if [ -f "$CERT_PATH" ] && [ -f "$KEY_PATH" ]; then
    print_msg "证书已存在，跳过生成。" "yellow"; return 0
  fi
  print_msg "生成自签名 TLS 证书..." "yellow"
  openssl ecparam -genkey -name prime256v1 -out "$KEY_PATH" >/dev/null 2>&1 || openssl genrsa -out "$KEY_PATH" 2048 >/dev/null 2>&1
  openssl req -new -x509 -days 36500 -key "$KEY_PATH" -out "$CERT_PATH" -subj "/CN=www.bing.com" >/dev/null 2>&1 || true
  print_msg "证书生成完成。" "green"
}

create_config_and_save_vars() {
  mkdir -p "$AGSBX_DIR"
  local UUID
  UUID=$(generate_uuid)
  save_var "UUID" "$UUID"
  print_msg "生成 UUID: $UUID" "yellow"

  # ----------------------------
  # 检测 VPS 是否有 IPv6
  # ----------------------------
  local LISTEN_ADDR="0.0.0.0"
  if command -v ip >/dev/null 2>&1; then
    if ip -6 addr show scope global | grep -q inet6; then
      LISTEN_ADDR="::"
      print_msg "检测到 IPv6，TUIC 将监听 IPv6 (dual-stack 支持 IPv4)" "green"
    else
      print_msg "未检测到 IPv6，TUIC 仅监听 IPv4" "yellow"
    fi
  fi

  # ----------------------------
  # TUIC 配置
  # ----------------------------
  local tuic_inbounds=""
  if [ "$INSTALL_CHOICE" = "1" ] || [ "$INSTALL_CHOICE" = "3" ]; then
    create_tls_cert
    tuic_inbounds=$(cat <<EOF
    {
      "type":"tuic",
      "tag":"tuic-in",
      "listen":"${LISTEN_ADDR}",
      "listen_port":${TUIC_PORT},
      "users":[{"uuid":"${UUID}","password":"${UUID}"}],
      "congestion_control":"bbr",
      "tls":{"enabled":true,"server_name":"www.bing.com","alpn":["h3"],"certificate_path":"${CERT_PATH}","key_path":"${KEY_PATH}"}
    }
EOF
)
  fi

  # ----------------------------
  # Argo 配置
  # ----------------------------
  local argo_inbound=""
  if [ "$INSTALL_CHOICE" = "2" ] || [ "$INSTALL_CHOICE" = "3" ]; then
    if [ "${ARGO_PROTOCOL:-vless}" = "vless" ]; then
      argo_inbound=$(printf '{"type":"vless","tag":"vless-in","listen":"127.0.0.1","listen_port":%s,"users":[{"uuid":"%s"}],"transport":{"type":"ws","path":"/%s-vl"}}' "$ARGO_LOCAL_PORT" "$UUID" "$UUID")
    else
      argo_inbound=$(printf '{"type":"vmess","tag":"vmess-in","listen":"127.0.0.1","listen_port":%s,"users":[{"uuid":"%s","alterId":0}],"transport":{"type":"ws","path":"/%s-vm"}}' "$ARGO_LOCAL_PORT" "$UUID" "$UUID")
    fi
  fi

  # ----------------------------
  # 写入配置文件
  # ----------------------------
  if [ "$INSTALL_CHOICE" = "1" ]; then
    cat > "$CONFIG_PATH" <<EOF
{
  "log":{"level":"info","timestamp":true},
  "inbounds":[
    $tuic_inbounds
  ],
  "outbounds":[{"type":"direct","tag":"direct"}]
}
EOF
  elif [ "$INSTALL_CHOICE" = "2" ]; then
    cat > "$CONFIG_PATH" <<EOF
{
  "log":{"level":"info","timestamp":true},
  "inbounds":[
    $argo_inbound
  ],
  "outbounds":[{"type":"direct","tag":"direct"}]
}
EOF
  elif [ "$INSTALL_CHOICE" = "3" ]; then
    cat > "$CONFIG_PATH" <<EOF
{
  "log":{"level":"info","timestamp":true},
  "inbounds":[
    $tuic_inbounds,
    $argo_inbound
  ],
  "outbounds":[{"type":"direct","tag":"direct"}]
}
EOF
  fi

  print_msg "配置文件已写入: $CONFIG_PATH" "green"

  # ----------------------------
  # 保存变量
  # ----------------------------
  save_var "INSTALL_CHOICE" "$INSTALL_CHOICE"
  [ -n "${TUIC_PORT:-}" ] && save_var "TUIC_PORT" "$TUIC_PORT"
  [ -n "${ARGO_PROTOCOL:-}" ] && save_var "ARGO_PROTOCOL" "$ARGO_PROTOCOL"
  [ -n "${ARGO_LOCAL_PORT:-}" ] && save_var "ARGO_LOCAL_PORT" "$ARGO_LOCAL_PORT"
  [ -n "${ARGO_TOKEN:-}" ] && save_var "ARGO_TOKEN" "$ARGO_TOKEN"
  [ -n "${ARGO_DOMAIN:-}" ] && save_var "ARGO_DOMAIN" "$ARGO_DOMAIN"
}



# ----------------------------
# systemd unit helpers (optional)
# ----------------------------
create_systemd_service() {
  local svc_name="$1"; local exec_cmd="$2"; local desc="$3"
  if [ -d "$SYSTEMD_DIR" ]; then
    cat > "${SYSTEMD_DIR}/${svc_name}.service" <<EOF
[Unit]
Description=${desc}
After=network.target

[Service]
Type=simple
ExecStart=${exec_cmd}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload || true
    systemctl enable "${svc_name}.service" || true
    print_msg "已创建并启用 systemd 服务: ${svc_name}.service" "green"
  else
    print_msg "未检测到 systemd (或无权限)，跳过创建 systemd 服务。" "yellow"
  fi
}

# ----------------------------
# 服务控制
# ----------------------------
do_start() {
    print_msg "--- 启动服务 ---" cyan

    # 停止已有进程
    do_stop

    # 启动 sing-box
    print_msg "启动 sing-box..." green
    nohup "$SINGBOX_PATH" run -c "$CONFIG_PATH" \
        > /root/agsbx/sing-box.log 2>&1 &

    sleep 1

    # 检查 sing-box 是否启动成功
    if pgrep -f "sing-box run -c $CONFIG_PATH" >/dev/null 2>&1; then
        print_msg "✅ sing-box 已成功后台启动" green
    else
        print_msg "⚠ sing-box 启动失败，请查看日志 /root/agsbx/sing-box.log" red
        exit 1
    fi

    # 如果存在 cloudflared 配置，则启动 Argo
    if [[ -f "$VARS_PATH" ]]; then
        print_msg "启动 Argo Tunnel..." green
        nohup "$CLOUDFLARED_PATH" tunnel run \
            --token "$(grep ARGO_TOKEN "$VARS_PATH" | cut -d= -f2)" \
            > /root/agsbx/cloudflared.log 2>&1 &

        sleep 1

        if pgrep -f "cloudflared tunnel run" >/dev/null 2>&1; then
            print_msg "🌐 Argo Tunnel 已启动" green
        else
            print_msg "⚠ Argo 启动失败，请查看日志 /root/agsbx/cloudflared.log" red
        fi
    fi
}


do_stop() {
  print_msg "--- 停止服务 ---" "blue"

  # 只杀死通过本脚本启动的 sing-box，而不是所有 sing-box
  pkill -f "sing-box run -c /root/agsbx/sb.json" 2>/dev/null || true
  
  # 只杀死 cloudflared tunnel run
  pkill -f "cloudflared tunnel run" 2>/dev/null || true

  print_msg "已停止 sing-box 和 cloudflared。" "green"
}


do_restart() {
  print_msg "--- 重启服务 ---" "blue"
  do_stop
  sleep 1
  do_start
}

do_list() {
  print_msg "--- 节点信息 ---" "blue"
  if ! load_variables; then print_msg "错误: 未找到变量文件，请先执行 'install'。" "red"; exit 1; fi
  local server_ip
  if command -v curl >/dev/null 2>&1; then server_ip=$(curl -s https://icanhazip.com || true); fi
  server_ip=${server_ip:-$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")}
  local hostname; hostname=$(hostname)

  if [ "${INSTALL_CHOICE}" = "1" ] || [ "${INSTALL_CHOICE}" = "3" ]; then
    local tuic_params="congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=www.bing.com&allow_insecure=1"
    local tuic_link="tuic://${UUID}:${UUID}@${server_ip}:${TUIC_PORT}?${tuic_params}#tuic-${hostname}"
    print_msg "--- TUIC 节点 ---" "yellow"
    echo "$tuic_link"
  fi

  if [ "${INSTALL_CHOICE}" = "2" ] || [ "${INSTALL_CHOICE}" = "3" ]; then
    local current_argo_domain="$ARGO_DOMAIN"
    if [ -z "${ARGO_TOKEN:-}" ]; then
      # try to grab temporary domain from argo.log
      sleep 2
      if [ -f "$AGSBX_DIR/argo.log" ]; then
        local tmpd
        tmpd=$(grep -oE 'https?://[a-zA-Z0-9.-]+\.trycloudflare\.com' "$AGSBX_DIR/argo.log" | sed 's!https\?://!!' | head -n1 || true)
        [ -n "$tmpd" ] && current_argo_domain="$tmpd"
      fi
    fi
    if [ "${ARGO_PROTOCOL:-vless}" = "vless" ]; then
      local vless_link="vless://${UUID}@${current_argo_domain}:443?encryption=none&security=tls&sni=${current_argo_domain}&fp=chrome&type=ws&host=${current_argo_domain}&path=%2f${UUID}-vl#argo-vless-${hostname}"
      print_msg "\n--- VLESS + Argo (TLS) 节点 ---" "yellow"
      echo "$vless_link"
    else
      local vmess_json; vmess_json=$(printf '{"v":"2","ps":"vmess-argo-%s","add":"%s","port":"443","id":"%s","aid":"0","scy":"auto","net":"ws","type":"none","host":"%s","path":"/%s-vm","tls":"tls","sni":"%s"}' "$hostname" "$current_argo_domain" "$UUID" "$current_argo_domain" "$UUID" "$current_argo_domain")
      local vmess_base64; vmess_base64=$(printf "%s" "$vmess_json" | tr -d '\n' | base64 -w0 || printf "%s" "$vmess_json" | base64)
      local vmess_link="vmess://${vmess_base64}"
      print_msg "\n--- VMess + Argo (TLS) 节点 ---" "yellow"
      echo "$vmess_link"
    fi
  fi
}

do_uninstall() {
  print_msg "--- 卸载 ---" "red"
  read -r -p "警告: 这将删除 $AGSBX_DIR 并停止服务。确认继续? (y/n): " yn
  if [ "${yn}" != "y" ]; then print_msg "卸载已取消。" "green"; return 0; fi
  do_stop
  rm -rf "$AGSBX_DIR"
  if [ -f "./deploy.sh" ]; then rm -f ./deploy.sh || true; fi
  if [ -d "$SYSTEMD_DIR" ]; then
    rm -f "${SYSTEMD_DIR}/agsbx-singbox.service" || true
    systemctl daemon-reload || true
  fi
  print_msg "卸载完成。" "green"
}

# ----------------------------
# 安装交互
# ----------------------------
do_install() {
  print_msg "--- 节点安装向导 ---" "blue"
  install_prereqs
  mkdir -p "$AGSBX_DIR"
  : > "$VARS_PATH"

  print_msg "请选择要安装的节点类型:" "yellow"
  print_msg "  1) 仅安装 TUIC"
  print_msg "  2) 仅安装 Argo 隧道 (VLESS 或 VMess)"
  print_msg "  3) 同时安装 TUIC 和 Argo 隧道"
  read -r -p "请输入选项 [1-3]: " INSTALL_CHOICE

  if [ "$INSTALL_CHOICE" != "1" ] && [ "$INSTALL_CHOICE" != "2" ] && [ "$INSTALL_CHOICE" != "3" ]; then
    print_msg "无效选项，退出安装。" "red"; exit 1
  fi

  if [ "$INSTALL_CHOICE" = "1" ] || [ "$INSTALL_CHOICE" = "3" ]; then
    read -r -p "请输入 TUIC 端口 (回车使用默认 443): " TUIC_PORT
    TUIC_PORT=${TUIC_PORT:-443}
    save_var "TUIC_PORT" "$TUIC_PORT"
  fi

  if [ "$INSTALL_CHOICE" = "2" ] || [ "$INSTALL_CHOICE" = "3" ]; then
    print_msg "Argo 隧道承载协议选择: 1) VLESS  2) VMess" "yellow"
    read -r -p "请选择 [1-2] (默认 1): " ARGO_PROTO_CHOICE
    if [ "$ARGO_PROTO_CHOICE" = "2" ]; then ARGO_PROTOCOL="vmess"; else ARGO_PROTOCOL="vless"; fi
    read -r -p "请输入 Argo 本地监听端口 (例如 8080, 回车默认 8080): " ARGO_LOCAL_PORT
    ARGO_LOCAL_PORT=${ARGO_LOCAL_PORT:-8080}
    read -r -p "请输入 Argo Tunnel Token (回车使用临时隧道): " ARGO_TOKEN
    if [ -n "$ARGO_TOKEN" ]; then
      read -r -p "请输入 Argo Tunnel 对应的域名 (例: tunnel.example.com): " ARGO_DOMAIN
    else
      ARGO_DOMAIN=""
    fi
    save_var "ARGO_PROTOCOL" "$ARGO_PROTOCOL"
    save_var "ARGO_LOCAL_PORT" "$ARGO_LOCAL_PORT"
    save_var "ARGO_TOKEN" "$ARGO_TOKEN"
    save_var "ARGO_DOMAIN" "$ARGO_DOMAIN"
  fi

  save_var "INSTALL_CHOICE" "$INSTALL_CHOICE"
  # 安装二进制
  install_singbox
  if [ "$INSTALL_CHOICE" = "2" ] || [ "$INSTALL_CHOICE" = "3" ]; then
    install_cloudflared
  fi

  # 生成配置文件
  TUIC_PORT=${TUIC_PORT:-}
  ARGO_LOCAL_PORT=${ARGO_LOCAL_PORT:-}
  ARGO_PROTOCOL=${ARGO_PROTOCOL:-}
  ARGO_TOKEN=${ARGO_TOKEN:-}
  ARGO_DOMAIN=${ARGO_DOMAIN:-}
  create_config_and_save_vars

  # 启动
  do_start

  print_msg "\n--- 安装完成，节点信息如下 ---" "blue"
  do_list
}

# ----------------------------
# 运行入口 - 菜单
# ----------------------------
show_help() {
  cat <<EOF
Usage: bash $0 [command]
Commands:
  install      - 交互式安装（TUIC / Argo / 两者）
  list         - 显示节点信息
  start        - 启动服务
  stop         - 停止服务
  restart      - 重启服务
  uninstall    - 卸载并清理所有文件
  help         - 显示本帮助
EOF
}

main() {
  if [ $# -eq 0 ]; then show_help; exit 0; fi
  case "$1" in
    install) do_install ;;
    list) do_list ;;
    start) do_start ;;
    stop) do_stop ;;
    restart) do_restart ;;
    uninstall) do_uninstall ;;
    help|*) show_help ;;
  esac
}

main "$@"
