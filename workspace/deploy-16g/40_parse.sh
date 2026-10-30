#!/usr/bin/env bash
# 40 — 一键解析:PDF/图片 → Markdown(llama.cpp 后端 + 串行模式,可带 Jev)
# 用法:
#   bash 40_parse.sh <输入 pdf/图片> [输出目录]
#   JEV_ENABLED=true bash 40_parse.sh <输入> [输出目录]   # 启用 Jev 质检
#   JEV_FORCE_SCORE=true:单候选也强制送 Jev RM 评分(验证链路/采集 RM 耗时)
# 产出:<输出目录>/<输入主名>.md;SDK 中间产物在 workspace/runs/minicpmvocr_<时间戳>/
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

INPUT="${1:?用法: bash 40_parse.sh <输入 pdf/图片> [输出目录]}"
OUTPUT="${2:-$PWD/ocr-out}"
[ -e "$INPUT" ] || die "输入不存在: $INPUT"
# CLI 在 cd "$REPO_ROOT" 后执行——相对输入会按仓库根重新解析而失配,先钉成绝对路径
INPUT="$(cd "$(dirname "$INPUT")" && pwd)/$(basename "$INPUT")"

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
OUTPUT="$(cd "$OUTPUT" && pwd)"   # 同上:输出也钉绝对,落点与上方提示一致

# PDF 输入:预读页数给出耗时预期(CLI 的 PDF 栅格化与推理阶段都可能长时间静默,
# 不给 ETA 会被误判为卡死——2026-10-30 实机 djfyj.pdf 反馈的教训)
PDF_PAGES=""
if [ "${INPUT##*.}" = "pdf" ] || [ "${INPUT##*.}" = "PDF" ]; then
    PDF_PAGES="$($SDK_VENV/bin/python -c 'import sys; import fitz; print(fitz.open(sys.argv[1]).page_count)' "$INPUT" 2>/dev/null || true)"
    if [ -n "$PDF_PAGES" ] && [ "$PDF_PAGES" -gt 0 ] 2>/dev/null; then
        PER_PAGE_SEC="3.8"   # 版面 CPU 2.5 + 引擎 1.3(实测 2026-10-30)
        ETA_NOTE="版面 CPU + 引擎,未含栅格化"
        if [ "${JEV_ENABLED:-false}" = "true" ]; then
            PER_PAGE_SEC="7.1"   # + Jev 强制评分 3.3s/页
            ETA_NOTE="版面 CPU + 引擎 + Jev,未含栅格化"
        fi
        ETA_MIN="$(awk -v n="$PDF_PAGES" -v s="$PER_PAGE_SEC" 'BEGIN{printf "%d", (n*s+59)/60}')"
        say "PDF 共 $PDF_PAGES 页,预计约 ${ETA_MIN} 分钟($ETA_NOTE)"
    fi
fi

# CLI parse 语义:--output 是目标 Markdown 文件路径(非目录,直接 write_text);
# 脚本参数保持"输出目录",内部翻译为 <目录>/<输入主名>.md
MD_STEM="$(basename "$INPUT")"
MD_STEM="${MD_STEM%.*}"
OUTPUT_MD="$OUTPUT/$MD_STEM.md"

# 版面模型:自定义 config 不触发 SDK 自动下载(docs/minicpmvocr_api.md),
# 缺文件就在本地补齐(官方 Paddle 源,约几百 MB,仅首次)
LAYOUT_MODEL_DIR="${OCR_LAYOUT_MODEL_DIR:-$WORKSPACE_DIR/models/PP-DocLayoutV3_infer}"
if [ ! -f "$LAYOUT_MODEL_DIR/inference.pdiparams" ] \
    && [ "$LAYOUT_MODEL_DIR" != "$WORKSPACE_DIR/models/PP-DocLayoutV3_infer" ]; then
    warn "OCR_LAYOUT_MODEL_DIR 缺 inference.pdiparams,回退到 $WORKSPACE_DIR/models/PP-DocLayoutV3_infer"
    LAYOUT_MODEL_DIR="$WORKSPACE_DIR/models/PP-DocLayoutV3_infer"
fi
if [ ! -f "$LAYOUT_MODEL_DIR/inference.pdiparams" ]; then
    MODELS_DIR="$WORKSPACE_DIR/models"
    TARBALL="$MODELS_DIR/PP-DocLayoutV3_infer.tar"
    say "准备版面模型 PP-DocLayoutV3 → $LAYOUT_MODEL_DIR(约几百 MB,仅首次)"
    mkdir -p "$MODELS_DIR"
    [ -f "$TARBALL" ] || curl -fL --retry 3 -o "$TARBALL" \
        "https://paddle-model-ecology.bj.bcebos.com/paddlex/official_inference_model/paddle3.0.0/PP-DocLayoutV3_infer.tar"
    tar xf "$TARBALL" -C "$MODELS_DIR"
    [ -f "$LAYOUT_MODEL_DIR/inference.pdiparams" ] \
        || die "版面模型仍缺 inference.pdiparams — 检查网络,或按 README 手动下载解压后重跑"
fi

ARGS=(
    --config "$REPO_ROOT/sdk/minicpmvocr/configs/minicpmvocr.yaml"
    --backend llamacpp
    --server-url "http://$OCR_HOST:$OCR_PORT"
    --model "$OCR_MODEL_NAME"
    --set "layout.device=$LAYOUT_DEVICE"
    --set "layout.model_dir=$LAYOUT_MODEL_DIR"
    --set "run.run_root=$WORKSPACE_DIR/runs"
    --set pipeline.queue_mode=serial
    --set pipeline.max_workers=1
    # CLI oneshot 默认把 progress_log_every 设为 10**9(cli.py _build_parse_overrides),
    # 即便传 --config 也压掉 yaml 的 20 → 推理全程无进度。显式恢复,每 5 页打一条:
    --set logging.progress_log_every=5
)

if [ "${JEV_ENABLED:-false}" = "true" ]; then
    JEV_SERVICE_PORT="${JEV_SERVICE_PORT:-18500}"
    curl -sf "http://127.0.0.1:$JEV_SERVICE_PORT/healthz" >/dev/null 2>&1 \
        || die "Jev 评分服务未就绪(端口 $JEV_SERVICE_PORT)— 先起 21/23 号脚本"
    ARGS+=(
        --set tts.enabled=true
        --set "tts.rm_url=http://127.0.0.1:$JEV_SERVICE_PORT"
        --set tts.rm_input_form=ternary
        --set tts.sampling.seed=42
    )
    # llamacpp 方言丢弃 n 参数,采样候选常与 greedy 一致,去重后单候选会跳过 RM;
    # JEV_FORCE_SCORE=true 强制送评,用于验证 Jev 链路与采集 RM 耗时
    if [ "${JEV_FORCE_SCORE:-false}" = "true" ]; then
        ARGS+=(--set tts.force_score=true)
        echo "Jev 强制评分已启用(单候选也送 RM)"
    fi
    echo "Jev 质检已启用(rm_url=http://127.0.0.1:$JEV_SERVICE_PORT,ternary)"
fi

say "解析 $INPUT → $OUTPUT_MD"
if [ -n "$PDF_PAGES" ]; then
    echo "提示:PDF 栅格化阶段(整本渲染)无进度输出,大文件静默 1–3 分钟属正常;推理阶段每 5 页打一条 [infer] progress"
fi
cd "$REPO_ROOT"
export PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK=True
# 静音 fitz 兼容垫片的 FutureWarning(新版 pymupdf 自带 shim,每个 spawn 渲染进程各打一条,
# 无功能影响;按消息前缀精确忽略,不掩盖其他 FutureWarning;子进程继承本变量)
PYWARN='ignore:The `fitz` API is deprecated'
export PYTHONWARNINGS="${PYTHONWARNINGS:+$PYTHONWARNINGS,}$PYWARN"
export PYTHONUNBUFFERED=1   # 进度行实时刷出,避免管道/重定向下攒缓冲

set +e
"$SDK_VENV/bin/minicpmvocr" parse "${ARGS[@]}" --input "$INPUT" --output "$OUTPUT_MD"
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
    die "解析失败(rc=$rc) — 排查:tail -n 50 $LOG_DIR/*.log;最近中间产物:ls -td $WORKSPACE_DIR/runs/*/ | head -3"
fi
if [ -f "$OUTPUT_MD" ]; then
    say "完成: $OUTPUT_MD($(wc -c < "$OUTPUT_MD") 字节)"
fi
