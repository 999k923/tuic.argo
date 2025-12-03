FROM debian:stable-slim

ENV LANG=C.UTF-8
ENV AGSBX_DIR=/agsbx

RUN apt-get update && apt-get install -y \
    curl wget tar iproute2 procps openssl ca-certificates socat bash \
    && rm -rf /var/lib/apt/lists/*

WORKDIR $AGSBX_DIR

COPY agsbx.sh $AGSBX_DIR/agsbx.sh
COPY entrypoint.sh $AGSBX_DIR/entrypoint.sh
RUN chmod +x $AGSBX_DIR/agsbx.sh $AGSBX_DIR/entrypoint.sh

EXPOSE 443 8080

ENTRYPOINT ["/agsbx/entrypoint.sh"]
