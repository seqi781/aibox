# aibox 代理网关：mihomo (Clash Meta) TUN 全局接管 + iptables 断线阻断
ARG MIHOMO_VERSION=v1.19.33
FROM metacubex/mihomo:${MIHOMO_VERSION} AS mihomo

FROM alpine:3.22
RUN apk add --no-cache iptables ip6tables iproute2 curl ca-certificates tzdata
COPY --from=mihomo /mihomo /usr/local/bin/mihomo
COPY entrypoint.sh healthcheck.sh validate-upstream.sh /usr/local/bin/
COPY config-head.yaml config-tail.yaml /etc/aibox/
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh /usr/local/bin/validate-upstream.sh
VOLUME /data
HEALTHCHECK --interval=30s --timeout=15s --start-period=60s --start-interval=3s --retries=3 \
  CMD ["/usr/local/bin/healthcheck.sh"]
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
