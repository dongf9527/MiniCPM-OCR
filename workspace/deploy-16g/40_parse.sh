#!/usr/bin/env bash
# 40 — 一键解析:PDF/图片 → Markdown(llama.cpp 后端 + 串行模式,可带 Jev)
# 用法:
#   bash 40_parse.sh <输入 pdf/图片> [输出目录]
#   JEV_ENABLED=true bash 40_parse.sh <输入> [输出目录]   # 启用 Jev 质检
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

INPUT="${1:?用法: bash 40_parse.sh <输入 pdf/图片> [输出目录]}"
OUTPUT="${2:-$PWD/ocr-out}"
[ -e "$INPUT" ] || die "输入不存在: $INPUT"

SDK_VENV="${SDK_VENV:-$WORKSPACE_DIR/venv-sdk}"
[ -x "$SDK_VENV/bin/minicpmvocr" ] || "$SDK_VENV/bin/python" -c 'import minicpmvocr' 2>/dev/null \
    || die "SDK 环境不存在 — 先执行 bash 30_setup_sdk_env.sh"

OCR_HOST="${OCR_HOST:-127.0.0.1}"
OCR_PORT="${OCR_PORT:-18601}"
OCR_MODEL_NAME="${OCR_MODEL_NAME:-minicpm-ocr}"
LAYOUT_DEVICE="${LAYOUT_DEVICE:-cpu}"

curl -sf "http://$OCR_HOST:$OCR_PORT/health" >/dev/null 2>&1 \
    || die "1.0 引擎未就绪(http://$OCR_HOST:$OCR_PORT)— 先执行 bash 20_start_ocr_engine.sh"

mkdir -p "$OUTPUT"

ARGS=(
    --config "$REPO_ROOT/sdk/minicpmvocr/configs/minicpmvocr.yaml"
    --backend llamacpp
    --server-url "http://$OCR_HOST:$OCR_PORT"
    --model "$OCR_MODEL_NAME"
    --set "layout.device=$LAYOUT_DEVICE"
    --set pipeline.queue_mode=serial
    --set pipeline.max_workers=1
)

if [ "${JEV_ENABLED:-false}" = "true" ]; then
    JEV_SERVICE_PORT="${JEV_SERVICE_PORT:-18500}"
    curl -sf "http://127.0.0.1:$JEV_SERVICE_PORT/healthz" >/dev/null 2>&1 \
        || die "Jev 评分服务未就绪(端口 $JEV_SERVICE_PORT)— 先起 21/23 号脚本"
    ARGS+=(
        --set tts.enabled=true
        --set "tts.rm_url=http://127.0.0.1:$JEV_SERVICE_PORT"
        --set tts.rm_input_form=ternary
    )
    echo "Jev 质检已启用(rm_url=http://127.0.0.1:$JEV_SERVICE_PORT,ternary)"
fi

say "解析 $INPUT → $OUTPUT"
cd "$REPO_ROOT"
export PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK=True
exec "$SDK_VENV/bin/minicpmvocr" parse "${ARGS[@]}" --input "$INPUT" --output "$OUTPUT"
