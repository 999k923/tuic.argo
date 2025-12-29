#!/bin/bash
set -e

# ==========================================================
# agsbx v2
# TUIC | Argo(VLESS/VMess WS) | VLESS AnyTLS
# ==========================================================

# ---------- 颜色 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

msg() {
  case "$2" in
    red) echo -e "${RED}$1${NC}" ;;
    green) echo -e "${GREEN}$1${NC}" ;;
    yellow) echo -e "${YELLOW}$1${NC}" ;;
    blue) echo -e "${BLUE}$1${NC}" ;;
    *) echo "$1" ;;
  esac
}

# ---------- 路径 ----------
BASE="$HOME/agsbx"
SINGBOX="$BASE/sing-box"
CLOUDFLARED="$BASE/cloudflared"
CONF="$BASE/sb.json"
VARS="$BASE/vars.conf"
CERT="$BASE/cert.pem"
KEY="$BASE/key.pem"

mkdir -p "$BASE"

# ---------- 工具 ----------
arch() {
  case "$(uname -m)" in
    x86_64) echo amd64 ;;
    aarch64) echo arm64 ;;
    *) msg "不支持的架构" red; exit 1 ;;
  esac
}

pub4() { curl -4 -s icanhazip.com || true; }
pub6() { curl -6 -s ip.sb || true; }

download() {
  curl -L -o "$2" "$1"
  chmod +x "$2"
}

load_vars() {
  [ -f "$VARS" ] && source "$VARS"
}

gen_cert() {
  openssl ecparam -genkey -name prime256v1 -out "$KEY" >/dev/null
  openssl req -new -x509 -days 36500 -key "$KEY" -out "$CERT" \
    -subj "/CN=www.bing.com" >/dev/null
}

# ---------- 安装 ----------
install() {
  : > "$VARS"

  msg "选择安装模式：" blue
  echo "1) TUIC"
  echo "2) Argo (VLESS / VMess WS)"
  echo "3) TUIC + Argo"
  echo "4) VLESS + AnyTLS（推荐）"
  read -rp "> " MODE

  [[ "$MODE" =~ ^[1-4]$ ]] || exit 1
  echo "MODE=$MODE" >> "$VARS"

  CPU=$(arch)

  # sing-box
  if [ ! -f "$SINGBOX" ]; then
    url="https://github.com/SagerNet/sing-box/releases/download/v1.9.0/sing-box-1.9.0-linux-$CPU.tar.gz"
    curl -L "$url" | tar xz -C "$BASE"
    mv "$BASE"/sing-box-*/sing-box "$SINGBOX"
  fi

  UUID=$($SINGBOX generate uuid)
  echo "UUID=$UUID" >> "$VARS"

  # TUIC
  if [[ "$MODE" =~ ^(1|3)$ ]]; then
    read -rp "TUIC 端口 [443]: " TUIC_PORT
    TUIC_PORT=${TUIC_PORT:-443}
    echo "TUIC_PORT=$TUIC_PORT" >> "$VARS"
    gen_cert
  fi

  # Argo
  if [[ "$MODE" =~ ^(2|3)$ ]]; then
    read -rp "1=VLESS 2=VMess: " A
    ARGO_PROTO=$([ "$A" = "2" ] && echo vmess || echo vless)
    read -rp "本地端口 [8080]: " ARGO_PORT
    ARGO_PORT=${ARGO_PORT:-8080}
    read -rp "Argo Token (可空): " ARGO_TOKEN
    read -rp "Argo 域名: " ARGO_DOMAIN

    echo "ARGO_PROTO=$ARGO_PROTO" >> "$VARS"
    echo "ARGO_PORT=$ARGO_PORT" >> "$VARS"
    echo "ARGO_TOKEN='$ARGO_TOKEN'" >> "$VARS"
    echo "ARGO_DOMAIN='$ARGO_DOMAIN'" >> "$VARS"

    [ -f "$CLOUDFLARED" ] || download \
      "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$CPU" \
      "$CLOUDFLARED"
  fi

  # AnyTLS
  if [ "$MODE" = "4" ]; then
    read -rp "AnyTLS 端口 [443]: " ANYTLS_PORT
    ANYTLS_PORT=${ANYTLS_PORT:-443}
    read -rp "AnyTLS 域名: " ANYTLS_DOMAIN
    echo "ANYTLS_PORT=$ANYTLS_PORT" >> "$VARS"
    echo "ANYTLS_DOMAIN='$ANYTLS_DOMAIN'" >> "$VARS"
    gen_cert
  fi

  gen_config
  start
  list
}

# ---------- 生成配置 ----------
gen_config() {
  load_vars

  INB=""

  if [[ "$MODE" =~ ^(1|3)$ ]]; then
    INB+='{
      "type":"tuic","listen":"::","listen_port":'"$TUIC_PORT"',
      "users":[{"uuid":"'"$UUID"'","password":"'"$UUID"'"}],
      "tls":{"enabled":true,"certificate_path":"'"$CERT"'","key_path":"'"$KEY"'","alpn":["h3"]}
    },'
  fi

  if [[ "$MODE" =~ ^(2|3)$ ]]; then
    if [ "$ARGO_PROTO" = "vless" ]; then
      INB+='{
        "type":"vless","listen":"127.0.0.1","listen_port":'"$ARGO_PORT"',
        "users":[{"uuid":"'"$UUID"'"}],
        "transport":{"type":"ws","path":"/'"$UUID"'"}
      },'
    else
      INB+='{
        "type":"vmess","listen":"127.0.0.1","listen_port":'"$ARGO_PORT"',
        "users":[{"uuid":"'"$UUID"'","alterId":0}],
        "transport":{"type":"ws","path":"/'"$UUID"'"}
      },'
    fi
  fi

  if [ "$MODE" = "4" ]; then
    INB+='{
      "type":"vless","listen":"::","listen_port":'"$ANYTLS_PORT"',
      "users":[{"uuid":"'"$UUID"'"}],
      "tls":{
        "enabled":true,
        "server_name":"'"$ANYTLS_DOMAIN"'",
        "alpn":["h2","http/1.1"],
        "certificate_path":"'"$CERT"'",
        "key_path":"'"$KEY"'"
      }
    },'
  fi

  INB="[${INB%,}]"

  cat > "$CONF" <<EOF
{
  "log":{"level":"info"},
  "inbounds":$INB,
  "outbounds":[{"type":"direct"}]
}
EOF
}

# ---------- 启停 ----------
start() {
  pkill -f sing-box || true
  pkill -f cloudflared || true
  nohup "$SINGBOX" run -c "$CONF" >"$BASE/sb.log" 2>&1 &

  load_vars
  if [[ "$MODE" =~ ^(2|3)$ ]]; then
    if [ -n "$ARGO_TOKEN" ]; then
      cat > "$BASE/argo.yml" <<EOF
ingress:
  - hostname: $ARGO_DOMAIN
    service: http://127.0.0.1:$ARGO_PORT
  - service: http_status:404
EOF
      nohup "$CLOUDFLARED" tunnel --config "$BASE/argo.yml" run --token "$ARGO_TOKEN" >"$BASE/argo.log" 2>&1 &
    else
      nohup "$CLOUDFLARED" tunnel --url http://127.0.0.1:$ARGO_PORT >"$BASE/argo.log" 2>&1 &
    fi
  fi
}

stop() {
  pkill -f sing-box || true
  pkill -f cloudflared || true
}

# ---------- 节点 ----------
list() {
  load_vars
  H=$(hostname)
  IP4=$(pub4)
  IP6=$(pub6)

  if [[ "$MODE" =~ ^(1|3)$ ]]; then
    echo "tuic://${UUID}:${UUID}@${IP4}:${TUIC_PORT}?alpn=h3#tuic-${H}"
  fi

  if [[ "$MODE" =~ ^(2|3)$ ]]; then
    echo "vless://${UUID}@cdns.doon.eu.org:443?type=ws&host=${ARGO_DOMAIN}&path=/${UUID}&security=tls&sni=${ARGO_DOMAIN}#argo-${H}"
  fi

  if [ "$MODE" = "4" ]; then
    echo "vless://${UUID}@${IP4}:${ANYTLS_PORT}?security=tls&sni=${ANYTLS_DOMAIN}&alpn=h2,http/1.1&fp=chrome#anytls-${H}"
  fi
}

case "$1" in
  install) install ;;
  start) start ;;
  stop) stop ;;
  restart) stop; start ;;
  list) list ;;
  *) echo "install | start | stop | restart | list" ;;
esac
