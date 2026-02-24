ARG HEADSCALE_VERSION=0.28.0

FROM alpine:3.23 AS litestream
ARG LITESTREAM_VERSION=0.5.9
RUN arch=$(uname -m | sed s/aarch64/arm64/ | sed s/amd64/x86_64/) && \
    wget -q -O /tmp/litestream.tar.gz \
      "https://github.com/benbjohnson/litestream/releases/download/v${LITESTREAM_VERSION}/litestream-${LITESTREAM_VERSION}-linux-${arch}.tar.gz" && \
    tar -xf /tmp/litestream.tar.gz -C /usr/local/bin/ && \
    rm /tmp/litestream.tar.gz

FROM ghcr.io/juanfont/headscale:v${HEADSCALE_VERSION} AS headscale

FROM alpine:3.23
COPY --from=headscale /ko-app/headscale /usr/local/bin/headscale
COPY --from=litestream /usr/local/bin/litestream /usr/local/bin/litestream

RUN apk add --no-cache ca-certificates tzdata && \
    addgroup -S headscale && adduser -S headscale -G headscale && \
    mkdir -p /etc/headscale /var/lib/headscale /var/run/headscale && \
    chown -R headscale:headscale /etc/headscale /var/lib/headscale /var/run/headscale

COPY config/litestream.yml /etc/litestream.yml
COPY scripts/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && chown headscale:headscale /etc/litestream.yml

VOLUME /var/lib/headscale
EXPOSE 8080 9090

USER headscale
ENTRYPOINT ["/entrypoint.sh"]
