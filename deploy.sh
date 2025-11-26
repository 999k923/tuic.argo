#!/bin/sh

# ==============================================================================
# All-in-One 节点管理脚本 (v6.3 - 终极稳定版)
#
# 更新:
#   - 彻底重构下载和解压逻辑，使用绝对路径，避免 `mv` 错误。
#   - 增加严格的步骤检查，确保每一步成功后再继续。
#   - 增强下载命令，使其在遇到 HTTP 错误时能直接失败。
# ==============================================================================

# --- 颜色定义 ---
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_NC='\033[0m'

# --- 脚本常量 ---
SCRIPT_URL="https://cdn.jsdelivr.net/gh/999k923/tuic.argo@main/deploy.sh"
HOME_DIR=$(eval echo ~ )
AGSBX_DIR="$HOME_DIR/agsbx"
SINGBOX_PATH="$AGSBX_DIR/sing-box"
CLOUDFLARED_PATH="$AGSBX_DIR/cloudflared"
CONFIG_PATH="$AGSBX_DIR/sb.json"
CERT_PATH="$AGSBX_DIR/cert.pem"
KEY_PATH="$AGSBX_DIR/private.key"
VARS_PATH="$AGSBX_DIR/variables.conf"

# --- 辅助函数 ---

print_msg() {
    case "$2" in
        "red")    printf "${C_RED}%s${C_NC}\n" "$1" ;;
        "green")  printf "${C_GREEN}%s${C_NC}\n" "$1" ;;
        "yellow") printf "${C_YELLOW}%s${C_NC}\n" "$1" ;;
        "blue")   printf "${C_BLUE}%s${C_NC}\n" "$1" ;;
        *)        printf "%s\n" "$1" ;;
    esac
}

get_cpu_arch() {
    case "$(uname -m)" in
        "x86_64")   echo "amd64" ;;
        "aarch64")  echo "arm64" ;;
        *) print_msg "错误: 不支持的 CPU 架构 $(uname -m)" "red"; exit 1 ;;
    esac
}

# 增强的下载函数，带 HTTP 错误检查
download_and_verify() {
    local url="$1"
    local dest="$2"
    local is_tarball="$3"

    # 优先尝试加速代理
    local proxy_url="https://kgithub.com/${url}"
    print_msg "正在通过加速代理下载 $(basename "$dest" )..." "yellow"
    
    if command -v curl >/dev/null 2>&1; then
        curl -# -fLo "$dest" "$proxy_url"
    else
        wget --show-progress --fail -qO "$dest" "$proxy_url"
    fi

    # 检查下载是否成功，如果不成功或文件无效，则切换到官方链接
    if [ $? -ne 0 ] || ([ "$is_tarball" = "true" ] && ! tar -t -f "$dest" > /dev/null 2>&1); then
        print_msg "代理下载失败或文件无效，正在切换到官方链接重试..." "red"
        if command -v curl >/dev/null 2>&1; then
            curl -# -fLo "$dest" "$url"
        else
            wget --show-progress --fail -qO "$dest" "$url"
        fi
    fi

    # 最终检查
    if [ $? -ne 0 ] || [ ! -s "$dest" ]; then
        print_msg "下载失败: $url" "red"; exit 1
    fi
    
    print_msg "$(basename "$dest") 下载成功。" "green"
}

get_server_ip() {
    if command -v curl >/dev/null 2>&1; then curl -s https://icanhazip.com; else wget -qO- https://icanhazip.com; fi
}

load_variables( ) {
    if [ -f "$VARS_PATH" ]; then . "$VARS_PATH"; else return 1; fi
}

# --- 核心功能函数 ---

do_install() {
    local choice="$1"
    mkdir -p "$AGSBX_DIR"
    : > "$VARS_PATH"
    
    case "$choice" in
        1) 
            echo "INSTALL_TUIC=true" >> "$VARS_PATH"
            print_msg "\n--- 配置 TUIC 节点 ---" "blue"
            printf "${C_GREEN}请输入 TUIC 端口 (例如 443): ${C_NC}"; read -r TUIC_PORT
            echo "TUIC_PORT=${TUIC_PORT}" >> "$VARS_PATH"
            ;;
        2) 
            echo "INSTALL_ARGO=true" >> "$VARS_PATH"
            ;;
        3) 
            echo "INSTALL_TUIC=true" >> "$VARS_PATH"; echo "INSTALL_ARGO=true" >> "$VARS_PATH"
            print_msg "\n--- 配置 TUIC 节点 ---" "blue"
            printf "${C_GREEN}请输入 TUIC 端口 (例如 443): ${C_NC}"; read -r TUIC_PORT
            echo "TUIC_PORT=${TUIC_PORT}" >> "$VARS_PATH"
            ;;
    esac

    # 确保 load_variables 之前，文件里有内容
    if [ "$(grep -c "INSTALL_ARGO=true" "$VARS_PATH")" -gt 0 ]; then
        print_msg "\n--- 配置 Argo 隧道节点 ---" "blue"
        printf "${C_GREEN}Argo 节点使用 VLESS 还是 VMess? [1 for VLESS, 2 for VMess]: ${C_NC}"; read -r ARGO_PROTOCOL_CHOICE
        if [ "$ARGO_PROTOCOL_CHOICE" = "1" ]; then echo "ARGO_PROTOCOL='vless'" >> "$VARS_PATH"; else echo "ARGO_PROTOCOL='vmess'" >> "$VARS_PATH"; fi
        printf "${C_GREEN}请输入 Argo 节点本地监听端口 (例如 8080): ${C_NC}"; read -r ARGO_PORT
        printf "${C_GREEN}请输入 Argo Tunnel 的 Token (若使用临时隧道，请直接回车): ${C_NC}"; read -r ARGO_TOKEN
        if [ -n "$ARGO_TOKEN" ]; then printf "${C_GREEN}请输入 Argo Tunnel 对应的域名: ${C_NC}"; read -r ARGO_DOMAIN; fi
        printf "${C_GREEN}请输入 Argo 优选地址/IP (直接回车使用默认: www.visa.com.sg): ${C_NC}"; read -r ARGO_PREF_ADDR
        if [ -z "$ARGO_PREF_ADDR" ]; then ARGO_PREF_ADDR="www.visa.com.sg"; fi
        echo "ARGO_PORT=${ARGO_PORT}" >> "$VARS_PATH"; echo "ARGO_TOKEN='${ARGO_TOKEN}'" >> "$VARS_PATH"
        echo "ARGO_DOMAIN='${ARGO_DOMAIN}'" >> "$VARS_PATH"; echo "ARGO_PREF_ADDR='${ARGO_PREF_ADDR}'" >> "$VARS_PATH"
    fi

    load_variables

    print_msg "\n--- 正在准备依赖环境 ---" "blue"
    local cpu_arch; cpu_arch=$(get_cpu_arch)
    if [ "$INSTALL_TUIC" = "true" ] || [ "$INSTALL_ARGO" = "true" ]; then
        if [ ! -f "$SINGBOX_PATH" ]; then
            local singbox_url="https://github.com/SagerNet/sing-box/releases/download/v1.9.0-beta.13/sing-box-1.9.0-beta.13-linux-${cpu_arch}.tar.gz"
            local temp_tar_path="$AGSBX_DIR/sing-box.tar.gz"
            download_and_verify "$singbox_url" "$temp_tar_path" "true"
            
            # 直接解压到目标目录
            tar -xzf "$temp_tar_path" -C "$AGSBX_DIR"
            # 从解压出的目录移动到最终位置
            mv "$AGSBX_DIR/sing-box-1.9.0-beta.13-linux-${cpu_arch}/sing-box" "$SINGBOX_PATH"
            # 检查文件是否存在
            if [ ! -f "$SINGBOX_PATH" ]; then print_msg "错误: sing-box 文件解压或移动失败 。" "red"; exit 1; fi
            chmod +x "$SINGBOX_PATH"
            # 清理
            rm -f "$temp_tar_path"; rm -rf "$AGSBX_DIR/sing-box-1.9.0-beta.13-linux-${cpu_arch}"
        fi
    fi
    if [ "$INSTALL_ARGO" = "true" ]; then
        if [ ! -f "$CLOUDFLARED_PATH" ]; then
            download_and_verify "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cpu_arch}" "$CLOUDFLARED_PATH" "false"
            chmod +x "$CLOUDFLARED_PATH"
        fi
    fi

    print_msg "\n--- 正在生成配置文件 ---" "blue"
    if [ ! -f "$SINGBOX_PATH" ]; then print_msg "错误: 找不到 sing-box 程序 ，无法生成配置。" "red"; exit 1; fi
    local UUID; UUID=$($SINGBOX_PATH generate uuid); echo "UUID='${UUID}'" >> "$VARS_PATH"
    print_msg "生成的 UUID: $UUID" "yellow"

    if [ "$INSTALL_TUIC" = "true" ]; then
        if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
            openssl ecparam -genkey -name prime256v1 -out "$KEY_PATH" >/dev/null 2>&1
            openssl req -new -x509 -days 36500 -key "$KEY_PATH" -out "$CERT_PATH" -subj "/CN=www.bing.com" >/dev/null 2>&1
        fi
    fi

    local inbounds=""
    if [ "$INSTALL_TUIC" = "true" ]; then inbounds=$(printf '{"type":"tuic","tag":"tuic-in","listen":"::","listen_port":%s,"users":[{"uuid":"%s","password":"%s"}],"congestion_control":"bbr","tls":{"enabled":true,"server_name":"www.bing.com","alpn":["h3"],"certificate_path":"%s","key_path":"%s"}}' "$TUIC_PORT" "$UUID" "$UUID" "$CERT_PATH" "$KEY_PATH"); fi
    if [ "$INSTALL_ARGO" = "true" ]; then
        if [ -n "$inbounds" ]; then inbounds="$inbounds,"; fi
        if [ "$ARGO_PROTOCOL" = "vless" ]; then inbounds="$inbounds$(printf '{"type":"vless","tag":"argo-in","listen":"127.0.0.1","listen_port":%s,"users":[{"uuid":"%s","flow":"xtls-rprx-vision"}],"transport":{"type":"ws","path":"/%s-vl"}}' "$ARGO_PORT" "$UUID" "$UUID")"; else inbounds="$inbounds$(printf '{"type":"vmess","tag":"argo-in","listen":"127.0.0.1","listen_port":%s,"users":[{"uuid":"%s","alterId":0}],"transport":{"type":"ws","path":"/%s-vm"}}' "$ARGO_PORT" "$UUID" "$UUID")"; fi
    fi

    cat > "$CONFIG_PATH" <<EOF
{ "log": {"level": "info", "timestamp": true}, "inbounds": [ ${inbounds} ], "outbounds": [{"type": "direct", "tag": "direct"}] }
EOF
    print_msg "配置文件创建成功。" "green"
    
    create_shortcut
    do_start
    do_list
}

# ... (do_list, do_start, do_stop, do_uninstall, create_shortcut, show_menu, main 函数保持不变) ...
# 为了简洁，这里省略了未改动的函数，请确保您复制的是包含所有函数的完整脚本。

do_list() {
    if ! load_variables; then print_msg "错误: 未找到任何节点配置。请先使用安装选项。" "red"; return; fi
    local server_ip; server_ip=$(get_server_ip); local hostname; hostname=$(hostname)
    print_msg "\n🎉 节点信息如下：\n" "blue"

    if [ "$INSTALL_TUIC" = "true" ]; then
        local tuic_params="congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=www.bing.com&allow_insecure=1"
        local tuic_link="tuic://${UUID}:${UUID}@${server_ip}:${TUIC_PORT}?${tuic_params}#tuic-${hostname}"
        print_msg "--- TUIC 节点 ---" "yellow"; echo "$tuic_link"
    fi

    if [ "$INSTALL_ARGO" = "true" ]; then
        local current_argo_domain="$ARGO_DOMAIN"
        if [ -z "$ARGO_TOKEN" ]; then
            print_msg "正在等待临时 Argo 域名生成..." "yellow"; sleep 8 
            local temp_argo_domain; temp_argo_domain=$(grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare\.com' "$AGSBX_DIR/argo.log" | sed 's/https:\/\///' | head -n 1 )
            if [ -z "$temp_argo_domain" ]; then print_msg "无法自动获取临时 Argo 域名，请检查日志: $AGSBX_DIR/argo.log" "red"; current_argo_domain="[请从日志中手动查找域名]"; else current_argo_domain=$temp_argo_domain; fi
        fi
        if [ "$ARGO_PROTOCOL" = "vless" ]; then
            local vless_link="vless://${UUID}@${ARGO_PREF_ADDR}:443?encryption=none&security=tls&sni=${current_argo_domain}&fp=chrome&type=ws&host=${current_argo_domain}&path=%2f${UUID}-vl#argo-vless-${hostname}"
            print_msg "\n--- Argo VLESS 节点 ---" "yellow"; echo "$vless_link"
        else
            local vmess_json; vmess_json=$(printf '{"v":"2","ps":"argo-vmess-%s","add":"%s","port":"443","id":"%s","aid":"0","scy":"auto","net":"ws","type":"none","host":"%s","path":"/%s-vm","tls":"tls","sni":"%s"}' "$hostname" "$ARGO_PREF_ADDR" "$UUID" "$current_argo_domain" "$UUID" "$current_argo_domain")
            local vmess_base64; vmess_base64=$(echo "$vmess_json" | tr -d '\n' | base64 -w0); local vmess_link="vmess://${vmess_base64}"
            print_msg "\n--- Argo VMess 节点 ---" "yellow"; echo "$vmess_link"
        fi
    fi
}

do_start() {
    print_msg "--- 启动服务 ---" "blue"
    if ! load_variables; then print_msg "错误: 未找到任何节点配置。请先使用安装选项。" "red"; return; fi
    do_stop
    
    if [ "$INSTALL_TUIC" = "true" ] || [ "$INSTALL_ARGO" = "true" ]; then
        nohup "$SINGBOX_PATH" run -c "$CONFIG_PATH" > "$AGSBX_DIR/sing-box.log" 2>&1 &
        print_msg "sing-box 服务已在后台启动。" "green"
    fi
    if [ "$INSTALL_ARGO" = "true" ]; then
        if [ -n "$ARGO_TOKEN" ]; then
            nohup "$CLOUDFLARED_PATH" tunnel --no-autoupdate run --token "$ARGO_TOKEN" > "$AGSBX_DIR/argo.log" 2>&1 &
        else
            nohup "$CLOUDFLARED_PATH" tunnel --url "http://127.0.0.1:${ARGO_PORT}" > "$AGSBX_DIR/argo.log" 2>&1 &
        fi
        print_msg "cloudflared 服务已在后台启动 。" "green"
    fi
}

do_stop() {
    print_msg "--- 停止服务 ---" "blue"
    pkill -f "$SINGBOX_PATH"
    pkill -f "$CLOUDFLARED_PATH"
    print_msg "所有相关服务已停止。" "green"
}

do_uninstall() {
    print_msg "--- 开始卸载 ---" "red"
    printf "${C_YELLOW}警告: 这将删除所有文件、配置和快捷键。确定吗? (y/n): ${C_NC}"; read -r confirmation
    if [ "$confirmation" != "y" ]; then print_msg "卸载已取消。" "green"; return; fi
    do_stop
    rm -rf "$AGSBX_DIR"
    if [ -f "$HOME/.bashrc" ]; then sed -i "/alias jiedian=/d" "$HOME/.bashrc"; fi
    if [ -f "$HOME/.zshrc" ]; then sed -i "/alias jiedian=/d" "$HOME/.zshrc"; fi
    print_msg "卸载完成。请运行 'source ~/.bashrc' 或 'source ~/.zshrc' 或重新登录以使快捷键失效。" "green"
}

create_shortcut() {
    local shell_config=""
    if [ -f "$HOME/.bashrc" ]; then shell_config="$HOME/.bashrc"; elif [ -f "$HOME/.zshrc" ]; then shell_config="$HOME/.zshrc"; fi
    
    if [ -n "$shell_config" ]; then
        sed -i "/alias jiedian=/d" "$shell_config"
        echo "alias jiedian='bash <(curl -Ls ${SCRIPT_URL})'" >> "$shell_config"
        print_msg "\n快捷键 'jiedian' 已创建成功！" "green"
        print_msg "请运行 'source ${shell_config}' 或重新登录 SSH 后，即可直接使用 'jiedian' 命令管理节点。" "yellow"
    else
        print_msg "无法自动创建快捷键，未找到 .bashrc 或 .zshrc 文件。" "red"
    fi
}

show_menu() {
    clear
    print_msg "==============================================" "blue"
    print_msg "          All-in-One 节点管理菜单 (v6.3)" "blue"
    print_msg "==============================================" "blue"
    print_msg " 1. 安装 TUIC 节点" "yellow"
    print_msg " 2. 安装 Argo 隧道节点 (VLESS/VMess)" "yellow"
    print_msg " 3. 同时安装 TUIC 和 Argo 隧道节点" "yellow"
    print_msg "----------------------------------------------" "blue"
    print_msg " 4. 显示节点信息" "green"
    print_msg " 5. 停止节点服务" "green"
    print_msg " 6. 开启/重启节点服务" "green"
    print_msg " 7. 卸载所有节点和脚本" "red"
    print_msg " 0. 退出"
    print_msg "==============================================" "blue"
    printf "${C_GREEN}请输入选项 [0-7]: ${C_NC}"
    read -r choice
    case "$choice" in
        1) do_install 1 ;;
        2) do_install 2 ;;
        3) do_install 3 ;;
        4) do_list ;;
        5) do_stop ;;
        6) do_start; print_msg "服务已重启" "green" ;;
        7) do_uninstall ;;
        0) exit 0 ;;
        *) print_msg "无效的选项，请重试。" "red" ;;
    esac
    printf "\n${C_YELLOW}按任意键返回主菜单...${C_NC}"; read -n 1 -s -r
    show_menu
}

# --- 脚本主入口 ---
show_menu
