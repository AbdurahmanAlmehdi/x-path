# The XPath engine (`xpd serve`) in a container.
#
#   tool/release/bundles.sh
#   docker build -t xpath .
#   docker run -d --name xpath -p 127.0.0.1:7480:7480 -v xpath-data:/data xpath
#   docker exec xpath xpd token create --name laptop --kind cli
#
# The image copies the Linux bundles that tool/release/bundles.sh built
# (build/release/bundles/linux-<arch>/), so build them first; `docker buildx
# build --platform linux/amd64,linux/arm64` picks the bundle of each platform.
# The engine runs as the unprivileged user `xpath` and keeps everything,
# master.key included (D-07: a 0600 key file without a systemd credential), in
# the volume /data. The image has git and ssh for the mirrors but no Flutter:
# build jobs go to runners (`xp runner`).

FROM debian:trixie-slim AS bundles
ARG TARGETARCH
COPY build/release/bundles/ /bundles/
RUN set -eu; \
    case "${TARGETARCH:-amd64}" in \
      amd64) arch=x64 ;; \
      arm64) arch=arm64 ;; \
      *) echo "no XPath bundle for ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    bundle="/bundles/linux-$arch"; \
    if [ ! -x "$bundle/xpd/bin/xpd" ] || [ ! -x "$bundle/xp/bin/xp" ]; then \
      echo "no bundle in build/release/bundles/linux-$arch: run tool/release/bundles.sh" >&2; \
      exit 1; \
    fi; \
    mkdir -p /opt/xpath; \
    cp -R "$bundle/xpd" "$bundle/xp" /opt/xpath/

FROM debian:trixie-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git openssh-client \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 xpath \
    && useradd --system --uid 10001 --gid xpath --create-home --home-dir /home/xpath \
      --shell /usr/sbin/nologin xpath \
    && mkdir /data \
    && chown xpath:xpath /data
COPY --from=bundles /opt/xpath /opt/xpath
COPY LICENSE /opt/xpath/LICENSE
RUN ln -s /opt/xpath/xpd/bin/xpd /usr/local/bin/xpd \
    && ln -s /opt/xpath/xp/bin/xp /usr/local/bin/xp

ENV XPATH_DATA_DIR=/data
USER xpath
WORKDIR /home/xpath
VOLUME /data
EXPOSE 7480
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --start-interval=2s --retries=3 \
  CMD curl -fsS http://127.0.0.1:7480/health || exit 1
# 0.0.0.0 inside the container; publish the port on 127.0.0.1 or behind TLS.
CMD ["xpd", "serve", "--host", "0.0.0.0", "--port", "7480"]
