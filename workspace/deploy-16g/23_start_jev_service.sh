#!/usr/bin/env bash
# 23 — 启动 Jev 内置渲染器评分服务(渲染 + precheck + 前向,单进程内完成)
# 该服务即 SDK 解析流水线对接的 /v1/rm/score* 端点(tts.rm_url 指向这里)。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

VENV="${JEV_RENDER_VENV:-$WORKSPACE_DIR/venv-render}"
JEV_SERVICE_HOST="${JEV_SERVICE_HOST:-127.0.0.1}"
JEV_SERVICE_PORT="${JEV_SERVICE_PORT:-18500}"
JEV_ENGINE_URL="${JEV_ENGINE_URL:-http://127.0.0.1:${JEV_PORT:-18602}}"
BACKEND_YAML="${BACKEND_YAML:-$REPO_ROOT/scripts/minicpm-ocr-jev/sdk/backends/llamacpp.yaml}"

[ -f "$BACKEND_YAML" ] || die "后端配置不存在: $BACKEND_YAML"
[ -x "$VENV/bin/python" ] || die "渲染环境不存在($VENV)— 先执行 bash 22_setup_jev_render_env.sh"
curl -sf "$JEV_ENGINE_URL/health" >/dev/null 2>&1 || die "Jev 引擎未就绪($JEV_ENGINE_URL)— 先执行 bash 21_start_jev_engine.sh"

PIDFILE="$RUN_DIR/jev-service.pid"
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    warn "jev-service 已在运行(pid $(cat "$PIDFILE")),先执行 bash 90_stop_all.sh"
    exit 1
fi

say "启动 jev-service $JEV_SERVICE_HOST:$JEV_SERVICE_PORT → 引擎 $JEV_ENGINE_URL"
# 渲染并发由 RM_RENDER_BROWSERS 控制,无并发需求保持 1
export RM_RENDER_BROWSERS="${RM_RENDER_BROWSERS:-1}"
export JEV_BACKEND_CONFIG="$BACKEND_YAML"
# 上游 start_render_score.sh 以 ${HOST:-0.0.0.0} 决定绑定地址;而 conda 编译工具链
# (gxx/cuda)激活脚本会把 HOST 改写为交叉编译三元组(如 x86_64-conda-linux-gnu),
# uvicorn 将其解析为非本机 IP 导致 bind 失败。这里显式钉回本服务监听地址。
PATH="$VENV/bin:$PATH" HOST="$JEV_SERVICE_HOST" nohup bash "$REPO_ROOT/scripts/minicpm-ocr-jev/sdk/start_render_score.sh" \
    "$JEV_SERVICE_PORT" "$JEV_ENGINE_URL" >"$LOG_DIR/jev-service.log" 2>&1 &
echo $! > "$PIDFILE"

for i in $(seq 1 60); do
    if curl -sf "http://$JEV_SERVICE_HOST:$JEV_SERVICE_PORT/healthz" 2>/dev/null | grep -q '"status": *"ok"'; then
        echo "    就绪: http://$JEV_SERVICE_HOST:$JEV_SERVICE_PORT/healthz"
        echo "SDK 对接: 40 号脚本设 JEV_ENABLED=true 即可(等价 tts.rm_url 指向本服务)"
        exit 0
    fi
    kill -0 "$(cat "$PIDFILE")" 2>/dev/null || break
    sleep 2
done
warn "jev-service 未能就绪,日志末尾:"
tail -20 "$LOG_DIR/jev-service.log" >&2 || true
if grep -qE 'Name or service not known|could not bind' "$LOG_DIR/jev-service.log" 2>/dev/null; then
    warn "识别到绑定失败特征:JEV_SERVICE_HOST 需为可直接绑定的地址(默认 127.0.0.1,勿填主机名);"
    warn "若日志 announce 行是三元组(x86_64-conda-linux-gnu 之类),说明上游 HOST 被 conda 工具链改写——见指南排障表"
fi
exit 1
