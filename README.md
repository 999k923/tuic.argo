只保留了TUIC5节点和argo固定隧道（vmess+argo或者vless+argo），小配置Nat鸡友好不卡顿，2个节点任意安装。

重点：导入节点后IP地址和优选ip地址要手动更换一下，默认的地址可能是错误的。


安装步骤
==
这是在您的服务器上执行一键安装的命令。它会从您的 GitHub 链接下载并运行脚本，然后引导您完成交互式安装过程。
```bash
bash <(curl -Ls https://raw.githubusercontent.com/999k923/tuic.argo/refs/heads/main/deploy.sh ) install
```
操作步骤：
通过 SSH 连接到您的服务器。
复制并粘贴上面的命令到终端。
按下回车，脚本将开始运行。
您会看到一个菜单，提示您选择安装 1) TUIC, 2) VMess+Argo, 或 3) 两者。
根据提示输入数字并按回车，然后依次输入端口、Token 等信息即可完成安装。
2. 后续管理命令
为了方便地管理（停止、重启、卸载等），您需要先将脚本文件下载到服务器上。这个步骤只需要做一次。
下载管理脚本的命令：
```bash
curl -Lo deploy.sh https://raw.githubusercontent.com/999k923/tuic.argo/refs/heads/main/deploy.sh && chmod +x deploy.sh
```
执行此命令后 ，您的服务器当前目录下就会有一个名为 deploy.sh 的可执行文件。现在，您可以使用它来执行所有管理操作。
显示节点信息,重点：导入节点后如果ip地址有错，IP地址和优选ip地址手动更换一下，以免节点不通。
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
## 第一步：
```bash
curl -o ~/agsbx/keep_alive.sh -L https://raw.githubusercontent.com/999k923/tuic.argo/refs/heads/main/keep_alive.sh && chmod +x /root/agsbx/keep_alive.sh
```
## 第二步:
```bash
nohup bash ~/agsbx/keep_alive.sh > ~/agsbx/keep_alive.log 2>&1 &
```
```bash
bash <(curl -L https://raw.githubusercontent.com/999k923/tuic.argo/refs/heads/main/setup_keepalive_autostart.sh)
```
