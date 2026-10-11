#!/bin/sh
# =============================================================
# ds-free-api 容器入口脚本（支持环境变量注入配置）
#
# 解决的问题：
#   1) Render 等免费平台的文件系统是「临时的」——服务休眠/重启后
#      config.toml 被清空，导致管理密码、API Key、DeepSeek 账号全部丢失。
#      → 现在支持从环境变量重建配置：凭据存在平台加密环境变量里，
#        不进 Git、不怕重启。
#   2) 云平台会注入 $PORT（Render 默认 10000），服务必须监听 0.0.0.0:$PORT。
#
# 支持的环境变量（全部可选）：
#   PORT                     平台注入，默认 22217
#   DS_ADMIN_PASSWORD_HASH   管理密码的 bcrypt 哈希（生成方法见 README）
#   DS_JWT_SECRET            管理面板 JWT 密钥（可选）
#   DS_API_KEYS              API Key 列表，逗号分隔，如：sk-abc,sk-def
#   DS_ACCOUNTS              DeepSeek 账号，每行一个，字段用 | 分隔：
#                            email|mobile|area_code|password|device_id
#                            （email 与 mobile 二选一，另一个留空）
#   DS_HOURLY_QUOTA          每账号每小时请求上限，默认 60
# =============================================================
set -e

CFG_DIR=/app/config
CFG="$CFG_DIR/config.toml"
mkdir -p "$CFG_DIR" /app/data

# ---------- 端口适配：平台注入的 PORT 优先 ----------
TARGET_PORT="${PORT:-22217}"
case "$TARGET_PORT" in
    ''|*[!0-9]*)
        echo "[entrypoint][warn] PORT='$TARGET_PORT' 不是纯数字，回退到 22217"
        TARGET_PORT=22217
        ;;
esac

# ---------- 是否启用「环境变量注入」模式 ----------
USE_INJECT=0
if [ -n "${DS_ADMIN_PASSWORD_HASH:-}" ] || [ -n "${DS_API_KEYS:-}" ] || [ -n "${DS_ACCOUNTS:-}" ] || [ -n "${DS_JWT_SECRET:-}" ]; then
    USE_INJECT=1
fi

if [ "$USE_INJECT" = "1" ]; then
    echo "[entrypoint] 检测到注入变量，按环境变量重建配置 -> $CFG"

    if [ -s "$CFG" ]; then
        cp "$CFG" "$CFG.prev" 2>/dev/null || true
    fi

    : > "$CFG"

    # ---- [server] ----
    {
        echo "# ===== 由 entrypoint.sh 依据环境变量自动生成，请勿手工编辑 ====="
        echo
        echo "[server]"
        echo 'host = "0.0.0.0"'
        echo "port = ${TARGET_PORT}"
    } >> "$CFG"

    # ---- [[api_keys]] ----
    if [ -n "${DS_API_KEYS:-}" ]; then
        echo "" >> "$CFG"
        echo "$DS_API_KEYS" | tr ',' '\n' | while IFS= read -r k; do
            k=$(printf '%s' "$k" | tr -d ' \t\r')
            [ -z "$k" ] && continue
            {
                echo "[[api_keys]]"
                echo "key = \"$k\""
                echo "description = \"env-injected\""
                echo
            } >> "$CFG"
        done
    fi

    # ---- [ds_core] + 拟态身份 + [[ds_core.accounts]] ----
    {
        echo "[ds_core]"
        echo 'model_types = ["default"]'
        echo "hourly_request_quota = ${DS_HOURLY_QUOTA:-60}"

        # 拟态身份档位：DS_EMULATION=android 时切换为原生安卓 App 档
        # （与 deeperseeker 同路线：上游对安卓客户端头不强制 AWS WAF）
        if [ "${DS_EMULATION:-}" = "android" ]; then
            echo 'emulation = "okhttp4_12"'
            echo 'user_agent = "DeepSeek/2.5.0 Android/35"'
            echo 'client_platform = "android"'
            echo 'client_os = "android"'
        fi
        echo
    } >> "$CFG"

    if [ -n "${DS_ACCOUNTS:-}" ]; then
        printf '%s\n' "$DS_ACCOUNTS" | while IFS='|' read -r a_email a_mobile a_area a_pass a_device; do
            a_email=$(printf '%s' "$a_email" | tr -d ' \t\r')
            a_mobile=$(printf '%s' "$a_mobile" | tr -d ' \t\r')
            a_area=$(printf '%s' "$a_area" | tr -d ' \t\r')
            a_device=$(printf '%s' "$a_device" | tr -d ' \t\r')
            [ -z "$a_email$a_mobile" ] && continue
            {
                echo "[[ds_core.accounts]]"
                echo "email = \"$a_email\""
                echo "mobile = \"$a_mobile\""
                echo "area_code = \"$a_area\""
                echo "password = \"$a_pass\""
                if [ -n "$a_device" ]; then
                    echo "device_id = \"$a_device\""
                fi
                echo
            } >> "$CFG"
        done
        ACC_N=$(printf '%s\n' "$DS_ACCOUNTS" | grep -c '|' || true)
        echo "[entrypoint] 已注入账号条数: ${ACC_N}"
    fi

    # ---- [admin] ----
    if [ -n "${DS_ADMIN_PASSWORD_HASH:-}" ] || [ -n "${DS_JWT_SECRET:-}" ]; then
        {
            echo "[admin]"
            [ -n "${DS_ADMIN_PASSWORD_HASH:-}" ] && echo "password_hash = \"${DS_ADMIN_PASSWORD_HASH}\""
            [ -n "${DS_JWT_SECRET:-}" ] && echo "jwt_secret = \"${DS_JWT_SECRET}\""
            echo
        } >> "$CFG"
    fi

    chmod 600 "$CFG" 2>/dev/null || true
    echo "[entrypoint] 配置已重建，服务端口 -> 0.0.0.0:${TARGET_PORT}"
else
    # ---------- 回退模式：无注入变量时，沿用默认配置播种 ----------
    if [ ! -s "$CFG" ]; then
        echo "[entrypoint] 未检测到配置，播种默认配置 -> $CFG"
        cp /app/config.default.toml "$CFG"
    fi

    sed -i.bak -E "s|^([[:space:]]*port[[:space:]]*=[[:space:]]*)[0-9]+|\1${TARGET_PORT}|" "$CFG" || true
    rm -f "$CFG.bak"

    if grep -qE '^[[:space:]]*host[[:space:]]*=[[:space:]]*"127\.0\.0\.1"' "$CFG"; then
        echo "[entrypoint][warn] 检测到 host=127.0.0.1，已自动修正为 0.0.0.0"
        sed -i.bak -E 's|^([[:space:]]*host[[:space:]]*=[[:space:]]*)"127\.0\.0\.1"|\1"0.0.0.0"|' "$CFG" || true
        rm -f "$CFG.bak"
    fi

    echo "[entrypoint] 服务端口 -> 0.0.0.0:${TARGET_PORT}（未启用环境变量注入）"
fi

exec /usr/local/bin/ds-free-api -c "$CFG"
