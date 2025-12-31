只保留了TUIC5节点和argo固定隧道（vmess+argo或者vless+argo），小配置Nat鸡友好不卡顿，2个节点任意安装。


安装步骤
==
这是一键安装的命令引导完成交互式安装过程。
```bash
curl -Lo manage.sh https://raw.githubusercontent.com/999k923/tuic.argo/refs/heads/main/manage.sh && curl -Lo x.sh https://raw.githubusercontent.com/999k923/tuic.argo/refs/heads/main/x.sh && curl -Lo sing.sh https://raw.githubusercontent.com/999k923/tuic.argo/refs/heads/main/sing.sh && chmod +x sing.sh x.sh manage.sh && ./deploy.sh install
```
## 管理菜单
显示节点信息：导入节点后如果ip地址有错，IP地址和优选ip地址手动更换一下，以免节点不通。
```bash
./deploy.sh list
```
停止脚本（停止服务）
此命令会停止所有由该脚本启动的后台进程（sing-box 和 cloudflared）。
```bash
./deploy.sh stop
```
重新开启脚本（启动服务）
如果服务已停止，您可以使用此命令来重新启动它们。
```bash
./deploy.sh start
```
提示：您也可以直接使用 restart 命令来一步完成停止和启动操作：
```bash
./deploy.sh restart
```
卸载脚本
此命令将彻底从您的服务器上删除脚本、所有配置文件和下载的程序。这是一个不可逆的操作。
```bash
./deploy.sh uninstall
```
脚本会请求您输入 y 确认，以防止误操作。


错误提示：openssl: command not found解决办法：
==
方法 1：安装 OpenSSL

Debian/Ubuntu：
```bash
apt update && apt install -y openssl
```
Alpine（如果是 apk 系统）：
```bash
apk add --no-cache openssl
```
CentOS/RHEL：
```bash
yum install -y openssl
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

docker部署,docker版本只有hy2和tuic
==
```bash
version: "3.9"
services:
  proxy:
    image: 999k923/docker-proxy:latest
    container_name: proxy_server
    restart: always
    network_mode: host # 保留 host 模式，这样容器直接使用宿主机网络
    environment:
      SERVICE_TYPE: 1 # 1=HY2, 2=TUIC
      SERVICE_PORT: 30000
      IP_VERSION: "6" # ""=留空双栈VPS, "4"=IPv4 only, "6"=IPv6 only
    volumes:
      - /opt/stacks/proxy_server/data:/proxy_files
networks: {}
```
docker挂载目录下有一个hy2_link.txt文件，节点信息就在这里面查看。
