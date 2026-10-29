#!/usr/bin/env bash
# deploy-16g 公共库:路径推导 + env.local.sh 加载 + 通用工具函数。
# 各编号脚本 source 本文件,不单独执行。

set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$DEPLOY_DIR")"

# 仓库根目录:协作规则 v1.4 要求以 git 实测为准
REPO_ROOT="$(cd "$WORKSPACE_DIR/.." && git rev-parse --show-toplevel 2>/dev/null || echo "$WORKSPACE_DIR/..")"
REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"

RUN_DIR="${RUN_DIR:-$WORKSPACE_DIR/run}"
LOG_DIR="$RUN_DIR/logs"
mkdir -p "$RUN_DIR" "$LOG_DIR"

# 加载用户覆盖(可选)
ENV_LOCAL="$DEPLOY_DIR/env.local.sh"
# shellcheck disable=SC1090
[ -f "$ENV_LOCAL" ] && . "$ENV_LOCAL"

LLAMACPP_DIR="${LLAMACPP_DIR:-$WORKSPACE_DIR/llama.cpp}"
GGUF_DIR="${GGUF_DIR:-$WORKSPACE_DIR/gguf}"
JEV_HF_DIR="${JEV_HF_DIR:-$WORKSPACE_DIR/jev-hf}"

OCR_GGUF="$GGUF_DIR/MiniCPM-OCR-1_0-F16.gguf"
OCR_MMPROJ="$GGUF_DIR/mmproj-model-f16-4x.gguf"
JEV_GGUF="$GGUF_DIR/MiniCPM-OCR-Jev-bf16.gguf"
JEV_MMPROJ="$GGUF_DIR/mmproj-MiniCPM-OCR-Jev-bf16.gguf"

say()  { printf '\n==> %s\n' "$*"; }
warn() { printf '!!  %s\n' "$*" >&2; }
die()  { warn "$*"; exit 1; }

need_bin() {
    command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1(请先安装并放入 PATH)"
}

# 依赖:引擎二进制与权重文件存在性检查
require_engine_files() {
    local bin="$LLAMACPP_DIR/build/bin/llama-server"
    [ -x "$bin" ] || die "找不到 $bin — 先执行 bash 10_build_llamacpp.sh"
    [ -e "$1" ] || die "找不到权重 $1 — 先执行 11 号(下载)/12 号(转换)脚本"
}

# 后台启动:写 pid、记日志、轮询健康端点
# 用法: start_bg <name> <logfile> <pidfile> <health_url> <command...>
start_bg() {
    local name="$1" logfile="$2" pidfile="$3" health="$4"
    shift 4
    if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
        warn "$name 已在运行(pid $(cat "$pidfile")),先执行 bash 90_stop_all.sh"
        exit 1
    fi
    say "启动 $name(日志: $logfile)"
    nohup "$@" >"$logfile" 2>&1 &
    local pid=$!
    echo "$pid" > "$pidfile"
    local i
    for i in $(seq 1 90); do
        if curl -sf "$health" >/dev/null 2>&1; then
            echo "    就绪: $health(pid $pid)"
            return 0
        fi
        kill -0 "$pid" 2>/dev/null || break
        sleep 2
    done
    warn "$name 未能就绪,日志末尾:"
    tail -20 "$logfile" >&2 || true
    exit 1
}

# 显存快照(MiB,当前卡)
vram_total_mib() {
    nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 || echo 0
}
vram_used_mib() {
    nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -1 || echo 0
}
