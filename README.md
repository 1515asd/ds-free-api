# ds-free-api 云部署镜像

用于在 Render（免费层，Singapore 区域）等云平台部署 ds-free-api。

- `Dockerfile`：从官方 GitHub Release 下载 musl 静态二进制构建（镜像约 53MB）
- `entrypoint.sh`：启动时自动跟随平台注入的 `$PORT`，并强制 `host = "0.0.0.0"`
- `config.default.toml`：默认配置模板（端口会被 entrypoint 改写）

平台要求：监听 `0.0.0.0:$PORT`（Render 默认 PORT=10000）。
