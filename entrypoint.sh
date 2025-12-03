#!/bin/bash
set -e

# 如果 variables.conf 存在，则加载
[ -f /agsbx/variables.conf ] && source /agsbx/variables.conf

# 自动安装（使用环境变量或默认值）
if [ ! -f /agsbx/sb.json ]; then
    bash /agsbx/agsbx.sh install
fi

# 启动服务
bash /agsbx/agsbx.sh start

# 保持容器前台运行
tail -f /agsbx/sing-box.log
