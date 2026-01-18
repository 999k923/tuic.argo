用于NAT小鸡安装节点，友好不卡顿。
==

## 鸡特别小，建议只安装1或者2，或者1,2一起，容量不够4不要和其他一起装，会安装两个内核。
1) 安装 TUIC,（自签证书，不需要自定义域名）"
2) 安装 Argo 隧道 (VLESS 或 VMess)"
3) 安装 AnyTLS (使用CF域名证书，需要自定义域名A记录到vps)"(域名可以自己加放一个静态网页https可以访问增强隐蔽性)
4) 安装 VLESS-TCP-XTLS-Vision-REALITY，当前代理/隧道体系里的「顶级 / T0～T1 级别方案」，属于 高对抗、高隐蔽、低特征 的现代协议组合，直连协议，速度快不快就看vps和协议无关

####       1,2,3是sing-box内核，4是xray内核。


这是一键安装的命令。
==
```bash
curl -Lo manage.sh https://raw.githubusercontent.com/999k923/tuic.argo/refs/heads/main/manage.sh && curl -Lo x.sh https://raw.githubusercontent.com/999k923/tuic.argo/refs/heads/main/x.sh && curl -Lo sing.sh https://raw.githubusercontent.com/999k923/tuic.argo/refs/heads/main/sing.sh && chmod +x sing.sh x.sh manage.sh && ./manage.sh install
```

保活命令
==
```bash
curl -o ~/agsbx/keep_alive.sh -L https://raw.githubusercontent.com/999k923/tuic.argo/refs/heads/main/keep_alive.sh && chmod +x ~/agsbx/keep_alive.sh && bash <(curl -L https://raw.githubusercontent.com/999k923/tuic.argo/refs/heads/main/setup_keepalive_autostart.sh)
```
## 取消保活：
```bash
curl -fsSL https://raw.githubusercontent.com/999k923/tuic.argo/refs/heads/main/stop.sh | sh
```

## 管理菜单
显示节点信息：导入节点后如果ip地址有错，IP地址和优选ip地址手动更换一下，以免节点不通。
```bash
./manage.sh list
```
停止脚本（停止服务），装了保活命令会自动启动就是重启命令.
```bash
./manage.sh stop
```
重新开启脚本（启动服务）
如果服务已停止，您可以使用此命令来重新启动它们。
```bash
./manage.sh start
```
卸载脚本
此命令将彻底从您的服务器上删除脚本、所有配置文件和下载的程序。这是一个不可逆的操作。
```bash
./manage.sh uninstall
```
脚本会请求您输入 y 确认，以防止误操作。




# Docker 使用说明

本项目提供 Docker 版本脚本，避免修改原有文件。默认使用 `managedocker.sh` 作为容器入口。

## 环境变量

### 节点开关（任意一个设为 `true/1/1ture` 即启用）

- `NODE1`：安装 TUIC
- `NODE2`：安装 Argo 隧道 (VLESS/VMess)
- `NODE3`：安装 AnyTLS (Cloudflare 证书)
- `NODE4`：安装 VLESS + Vision + Reality

### 端口变量（对应 4 个节点）

- `PORT1`：TUIC 端口（默认 443）
- `PORT2`：Argo 本地监听端口（默认 8080）
- `PORT3`：AnyTLS 端口（默认 443）
- `PORT4`：Reality 监听端口（默认 8443）

### Reality (NODE4) 必需变量

- `XRAY_SNI`：Reality SNI（如 `microsoft.com`、`cloudflare.com`）

### 哪吒探针（可选）

- `NEZHA_SERVER`：哪吒面板地址（如 `nezha.example.com:8008`）
- `NEZHA_KEY`：哪吒 V1 客户端密钥（NZ_CLIENT_SECRET）

### 节点信息 HTTP 服务（可选）

- `PORT0`：节点信息 HTTP 服务端口（默认 `18080`）
- `HTTP_SERVER`：是否启用节点信息 HTTP 服务（默认 `true`）

### AnyTLS (NODE3) 必需变量

- `CF_EMAIL`：Cloudflare 账户邮箱
- `CF_API_KEY`：Cloudflare Global API Key
- `ANYTLS_DOMAIN`：AnyTLS 域名

### Argo (NODE2) 可选变量

- `ARGO_PROTOCOL`：`vless` 或 `vmess`（默认 `vless`）
- `ARGO_TOKEN`：Argo Tunnel Token（留空则临时隧道）
- `ARGO_DOMAIN`：与 Token 对应的域名（临时隧道不需要）

## 示例

建议将容器内目录挂载到宿主,避免容器重建后配置与证书丢失：

- `/root/agsbx`：TUIC/Argo/AnyTLS 的配置、证书、日志等
- `/etc/xray`：Reality 配置与变量

### 使用宿主机目录,改自己的路径即可
```bash
mkdir -p /data/tuic/agsbx
mkdir -p /data/tuic/xray
```

# 运行时按需添加环境变量与端口映射
```bash
docker run -d \
  --name tuic-argo \
  --network host \
  -e NODE1=true \
  -e NODE4=true \
  -e PORT1=21300 \
  -e PORT4=21400 \
  -e XRAY_SNI=cloudflare.com \
  -v /data/tuic/agsbx:/root/agsbx \
  -v /data/tuic/xray:/etc/xray \
  999k923/tuic-argo:latest
```

# 全部安装的示例
-e PORT0=25000，可自行更改端口号。安装日志里面就可以看到节点信息，如果平台看不到日志才需要加上http端口服务。
```bash
docker run -d \
  --name tuic-argo \
  --network host \
  -e NODE1=true \
  -e NODE2=true \
  -e NODE3=true \
  -e NODE4=true \
  -e PORT1=21300 \
  -e PORT2=21410 \
  -e PORT3=21420 \
  -e PORT4=21400 \
  -e PORT0=25000 \
  -e XRAY_SNI=cloudflare.com \
  -e CF_EMAIL=your@email.com \
  -e CF_API_KEY=your_cf_global_api_key \
  -e ANYTLS_DOMAIN=your.domain.com \
  -e ARGO_PROTOCOL=vless \
  -e ARGO_TOKEN=your_argo_token \
  -e ARGO_DOMAIN=your.argo.domain.com \
  -e NEZHA_SERVER=nezha.example.com:8008 \
  -e NEZHA_KEY=your_nezha_v1_secret \
  -v /data/tuic/agsbx:/root/agsbx \
  -v /data/tuic/xray:/etc/xray \
  999k923/tuic-argo:latest
```

