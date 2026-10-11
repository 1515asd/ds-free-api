# ds-free-api 云部署镜像

在 Render（免费层 / Singapore）等云平台部署 ds-free-api。

## 文件
- `Dockerfile`：从官方 GitHub Release 下载 musl 静态二进制构建（镜像约 53MB）
- `entrypoint.sh`：启动时①跟随平台注入的 `$PORT`，②**可从环境变量重建配置**
- `config.default.toml`：默认配置模板（未使用环境变量注入时的兜底）

## ⚠️ 为什么需要环境变量注入
Render / SnapDeploy 等免费平台的文件系统是**临时的**：服务休眠、重启或重新部署后，
容器内的 `config.toml` 会被清空 —— 管理密码、API Key、DeepSeek 账号全部丢失。
因此本项目的 `entrypoint.sh` 支持在启动时**用环境变量重建配置**，凭据保存在平台加密的
环境变量里（不进 Git、不怕重启）。

## 支持的环境变量（全部可选）
| 变量 | 说明 |
|---|---|
| `DS_ADMIN_PASSWORD_HASH` | 管理面板密码的 **bcrypt 哈希** |
| `DS_JWT_SECRET` | 管理面板 JWT 密钥（可选） |
| `DS_API_KEYS` | API Key 列表，逗号分隔，如 `sk-abc,sk-def` |
| `DS_ACCOUNTS` | DeepSeek 账号，**每行一个**，字段用 `\|` 分隔：`email\|mobile\|area_code\|password\|device_id`（email 与 mobile 二选一，另一个留空） |
| `DS_HOURLY_QUOTA` | 每账号每小时请求上限，默认 60 |

只要设置了其中任意一个，就会启用「重建配置」模式。

## 生成管理密码的 bcrypt 哈希
```bash
python3 -c "import bcrypt;print(bcrypt.hashpw(b'你的密码'.encode(), bcrypt.gensalt(rounds=12)).decode())"
# 未安装 bcrypt 时：pip install bcrypt
```

## 部署要求
服务必须监听 `0.0.0.0:$PORT`（Render 默认 `PORT=10000`）——已由 entrypoint 处理。
