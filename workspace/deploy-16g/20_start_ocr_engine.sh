#!/usr/bin/env bash
# 20 — 启动 1.0 解析引擎(llama-server,F16 GGUF,16G 保守参数)
# 官方基线(docs/llamacpp_deploy.md)在 ctx 40960 时显存约 26 GB;16G 卡将
# ctx 收紧到 8192(显存约 4–6 GB)。GGUF 内嵌模板已关 thinking,无需额外参数。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

require_engine_files "$OCR_GGUF"

OCR_HOST="${OCR_HOST:-127.0.0.1}"
OCR_PORT="${OCR_PORT:-18601}"
OCR_CTX="${OCR_CTX:-8192}"
OCR_NGL="${OCR_NGL:-999}"

BIN="$LLAMACPP_DIR/build/bin/llama-server"
export LD_LIBRARY_PATH="$LLAMACPP_DIR/build/bin${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

start_bg "ocr-engine" "$LOG_DIR/ocr-engine.log" "$RUN_DIR/ocr-engine.pid" \
    "http://$OCR_HOST:$OCR_PORT/health" \
    "$BIN" \
    --model "$OCR_GGUF" \
    --mmproj "$OCR_MMPROJ" \
    --host "$OCR_HOST" --port "$OCR_PORT" \
    -c "$OCR_CTX" -ngl "$OCR_NGL" \
    "$@"

echo "验证:  curl http://$OCR_HOST:$OCR_PORT/health"
echo "解析:  bash 40_parse.sh <pdf/图片> <输出目录>"
