# =============================================================
# ds-free-api 云部署镜像（自建版）
#
# 为什么不直接用官方镜像？
#   官方 compose 里写的 ghcr.io/niyuee/ds-free-api:latest 实测**不是公开包**，
#   匿名 pull 会被 denied，云平台无法拉取。所以改为：
#   直接下载官方 GitHub Release 的预编译二进制来构建，轻量、无需 Rust 工具链。
#
# 版本可改：--build-arg VERSION=v0.5.1
# =============================================================
FROM alpine:3.21

ARG VERSION=v0.5.1
ARG TARGETARCH=amd64

# 1) 基础依赖 + 时区
RUN apk add --no-cache ca-certificates tzdata curl tar gzip \
    && case "${TARGETARCH}" in \
         amd64|x86_64) DSARCH=x86_64 ;; \
         arm64|aarch64) DSARCH=aarch64 ;; \
         *) DSARCH=x86_64 ;; \
       esac \
    && echo "building for linux-${DSARCH}-musl, version ${VERSION}" \
    && curl -fL --retry 5 --retry-delay 2 -o /tmp/ds.tar.gz \
         "https://github.com/NIyueeE/ds-free-api/releases/download/${VERSION}/ds-free-api-${VERSION}-linux-${DSARCH}-musl.tar.gz" \
    && mkdir -p /tmp/x && tar -xzf /tmp/ds.tar.gz -C /tmp/x \
    && BIN=$(find /tmp/x -type f -name 'ds-free-api' | head -n1) \
    && test -n "$BIN" \
    && cp "$BIN" /usr/local/bin/ds-free-api \
    && chmod +x /usr/local/bin/ds-free-api \
    && rm -rf /tmp/x /tmp/ds.tar.gz

WORKDIR /app
RUN mkdir -p /app/config /app/data

# 2) 默认配置放在“不会被挂载卷遮挡”的位置，
#    由 entrypoint 在首次启动时复制到 /app/config/config.toml。
#    关键：host 必须是 0.0.0.0，否则云平台外部访问不到 22217。
COPY config.default.toml /app/config.default.toml

# 3) 入口脚本：挂载卷为空时自动播种配置
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENV RUST_LOG=info \
    DS_DATA_DIR=/app/data \
    DS_CONFIG_PATH=/app/config/config.toml \
    TZ=Asia/Shanghai

EXPOSE 22217
VOLUME ["/app/config", "/app/data"]

ENTRYPOINT ["/app/entrypoint.sh"]
