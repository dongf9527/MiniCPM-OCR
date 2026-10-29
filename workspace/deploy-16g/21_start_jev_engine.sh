#!/usr/bin/env bash
# 21 — 启动 Jev 判别引擎(llama-server,bf16 GGUF)
# 官方示例 -c 32768;与 1.0 共卡 16G 时收紧到 16384(无并发足够),OOM 再降。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

require_engine_files "$JEV_GGUF"

JEV_HOST="${JEV_HOST:-127.0.0.1}"
JEV_PORT="${JEV_PORT:-18602}"
JEV_CTX="${JEV_CTX:-16384}"
JEV_NGL="${JEV_NGL:-999}"

BIN="$LLAMACPP_DIR/build/bin/llama-server"
export LD_LIBRARY_PATH="$LLAMACPP_DIR/build/bin${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

start_bg "jev-engine" "$LOG_DIR/jev-engine.log" "$RUN_DIR/jev-engine.pid" \
    "http://$JEV_HOST:$JEV_PORT/health" \
    "$BIN" \
    --model "$JEV_GGUF" \
    --mmproj "$JEV_MMPROJ" \
    --host "$JEV_HOST" --port "$JEV_PORT" \
    -c "$JEV_CTX" -ngl "$JEV_NGL" \
    "$@"

echo "Jev 引擎就绪。下一步: bash 23_start_jev_service.sh(评分服务指向本引擎)"
