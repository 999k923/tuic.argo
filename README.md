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
curl -Lo manage.sh https://raw.githubusercontent.com/999k923/tuic.argo/refs/heads/main/manage.sh && curl -Lo x.sh https://raw.githubusercontent.com/999k923/tuic.argo/refs/heads/main/xapline.sh && curl -Lo sing.sh https://raw.githubusercontent.com/999k923/tuic.argo/refs/heads/main/sing.sh && chmod +x sing.sh x.sh manage.sh && ./manage.sh install
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
停止脚本（停止服务），装了保活命令会自动启动就是重启命令
此命令会停止所有由该脚本启动的后台进程（sing-box 和 cloudflared）。
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
