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
        python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . /app

RUN chmod +x /app/managedocker.sh /app/singdocker.sh /app/xdocker.sh

EXPOSE 18080

ENTRYPOINT ["/bin/bash", "/app/managedocker.sh", "run"]
