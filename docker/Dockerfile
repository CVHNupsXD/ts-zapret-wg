FROM rust:alpine AS doge-builder

RUN apk add --no-cache \
    musl-dev \
    openssl-dev \
    openssl-libs-static \
    perl \
    make

RUN cargo install dns-doge

FROM alpine:3.19

RUN apk add --no-cache \
    bash \
    curl \
    wget \
    iptables \
    ip6tables \
    ipset \
    iproute2 \
    wireguard-tools \
    libcap \
    libnetfilter_queue \
    nftables \
    jq \
    ca-certificates \
    openssl \
    unzip \
    bind-tools && \
    rm -rf /var/cache/apk/*

COPY --from=doge-builder /usr/local/cargo/bin/doge /usr/local/bin/doge
RUN doge --version

RUN wget -qO- https://pkgs.tailscale.com/stable/tailscale_latest_amd64.tgz | tar xzf - -C /usr/local/bin --strip-components=1

RUN ZAPRET_VERSION="72.9" && \
    wget -O /tmp/zapret.tar.gz "https://github.com/bol-van/zapret/releases/download/v${ZAPRET_VERSION}/zapret-v${ZAPRET_VERSION}.tar.gz" && \
    mkdir -p /opt/zapret && \
    tar -xzf /tmp/zapret.tar.gz -C /opt/zapret --strip-components=1 && \
    rm /tmp/zapret.tar.gz && \
    chmod +x /opt/zapret/binaries/linux-x86_64/nfqws && \
    chmod +x /opt/zapret/binaries/linux-x86_64/tpws && \
    ln -sf /opt/zapret/binaries/linux-x86_64/nfqws /usr/local/bin/nfqws && \
    ln -sf /opt/zapret/binaries/linux-x86_64/tpws /usr/local/bin/tpws && \
    ls -la /usr/local/bin/nfqws /usr/local/bin/tpws

RUN mkdir -p /scripts /config /var/run/tailscale

COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh

ENTRYPOINT ["/scripts/entrypoint.sh"]