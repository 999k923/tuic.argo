FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        wget \
        jq \
        unzip \
        uuid-runtime \
        openssl \
        cron \
        iproute2 \
        procps \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . /app

RUN chmod +x /app/managedocker.sh /app/singdocker.sh /app/xdocker.sh

ENTRYPOINT ["/bin/bash", "/app/managedocker.sh", "run"]
