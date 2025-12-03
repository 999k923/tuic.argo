# 使用 Debian slim 作为基础镜像
FROM debian:stable-slim

ENV LANG=C.UTF-8
ENV AGSBX_DIR=/agsbx

# 安装依赖
RUN apt-get update && apt-get install -y \
    curl wget tar iproute2 procps openssl ca-certificates socat bash \
    && rm -rf /var/lib/apt/lists/*

# 设置工作目录
WORKDIR $AGSBX_DIR

# 复制 deploy.sh
COPY deploy.sh $AGSBX_DIR/deploy.sh

# 给脚本添加执行权限
RUN chmod +x $AGSBX_DIR/deploy.sh

# 默认端口
EXPOSE 443 8080

# 容器启动入口
ENTRYPOINT ["/agsbx/deploy.sh"]
