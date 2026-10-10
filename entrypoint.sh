#!/bin/sh
# =============================================================
# ds-free-api 容器入口脚本
# 作用：
#   1) 解决“挂载卷遮挡镜像内配置”的问题 —— 挂载卷为空时自动播种默认配置
#   2) 云平台（Render / SnapDeploy / Serv00 等）注入 $PORT 时，自动把
#      服务端口改成 0.0.0.0:$PORT（Render 要求必须监听 $PORT）
# =============================================================
set -e

mkdir -p /app/config /app/data

if [ ! -s /app/config/config.toml ]; then
    echo "[entrypoint] 未检测到配置，播种默认配置 -> /app/config/config.toml"
    cp /app/config.default.toml /app/config/config.toml
fi

# ---------- 端口适配：云平台注入的 PORT 优先 ----------
TARGET_PORT="${PORT:-22217}"
case "$TARGET_PORT" in
    ''|*[!0-9]*)
        echo "[entrypoint][warn] PORT='$TARGET_PORT' 不是纯数字，回退到 22217"
        TARGET_PORT=22217
        ;;
esac

echo "[entrypoint] 服务端口 -> 0.0.0.0:${TARGET_PORT}"

# 把 [server] 下的 port 改成目标端口（只替换 port 那一行）
sed -i.bak -E "s|^([[:space:]]*port[[:space:]]*=[[:space:]]*)[0-9]+|\1${TARGET_PORT}|" /app/config/config.toml || true
rm -f /app/config/config.toml.bak

# 安全兜底：若配置里 host 仍是 127.0.0.1，云环境将无法从外部访问
if grep -qE '^[[:space:]]*host[[:space:]]*=[[:space:]]*"127\.0\.0\.1"' /app/config/config.toml; then
    echo "[entrypoint][warn] 配置中 host=127.0.0.1，外部将无法访问。"
    echo "[entrypoint][warn] 如需云平台访问，请改为 host = \"0.0.0.0\" 后重启。"
    echo "[entrypoint] 已自动修正为 0.0.0.0"
    sed -i.bak -E 's|^([[:space:]]*host[[:space:]]*=[[:space:]]*)"127\.0\.0\.1"|\1"0.0.0.0"|' /app/config/config.toml || true
    rm -f /app/config/config.toml.bak
fi

exec /usr/local/bin/ds-free-api -c /app/config/config.toml
