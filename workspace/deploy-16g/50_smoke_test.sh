#!/usr/bin/env bash
# 50 — 冒烟测试:健康检查 + 显存快照 + 示例图端到端(可选)
# 用法: bash 50_smoke_test.sh [测试图片]
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

OCR_HOST="${OCR_HOST:-127.0.0.1}"; OCR_PORT="${OCR_PORT:-18601}"
JEV_PORT="${JEV_PORT:-18602}";     JEV_SERVICE_PORT="${JEV_SERVICE_PORT:-18500}"
TEST_IMAGE="${1:-$REPO_ROOT/scripts/minicpm-ocr-jev/examples/01_text_putnam/block.png}"

say "健康检查"
curl -sf "http://$OCR_HOST:$OCR_PORT/health" >/dev/null 2>&1 \
    && echo "  [✓] 1.0 引擎   http://$OCR_HOST:$OCR_PORT" \
    || echo "  [–] 1.0 引擎未启动(如需解析: bash 20_start_ocr_engine.sh)"
if curl -sf "http://$OCR_HOST:$JEV_PORT/health" >/dev/null 2>&1; then
    echo "  [✓] Jev 引擎   http://$OCR_HOST:$JEV_PORT"
else
    echo "  [–] Jev 引擎未启动(可选)"
fi
if curl -sf "http://127.0.0.1:$JEV_SERVICE_PORT/healthz" 2>/dev/null | grep -q '"status": *"ok"'; then
    echo "  [✓] Jev 评分服务 http://127.0.0.1:$JEV_SERVICE_PORT/healthz"
else
    echo "  [–] Jev 评分服务未启动(可选)"
fi

say "显存快照"
total="$(vram_total_mib)"; used="$(vram_used_mib)"
if [ "$total" -gt 0 ]; then
    echo "  总量 ${total} MiB / 已用 ${used} MiB(余量 $((total-used)) MiB)"
    [ "$((total-used))" -ge 1500 ] || warn "显存余量 <1.5 GB:再起引擎可能 OOM,建议降 JEV_CTX/OCR_CTX"
else
    warn "nvidia-smi 不可用"
fi

say "端到端测试(需 1.0 引擎在线)"
if ! curl -sf "http://$OCR_HOST:$OCR_PORT/health" >/dev/null 2>&1; then
    echo "  [–] 跳过:引擎未启动"
    exit 0
fi
[ -f "$TEST_IMAGE" ] || { echo "  [–] 跳过:测试图不存在 $TEST_IMAGE"; exit 0; }
[ -x "${SDK_VENV:-$WORKSPACE_DIR/venv-sdk}/bin/minicpmvocr" ] \
    || { echo "  [–] 跳过:SDK 未安装(先执行 bash 30_setup_sdk_env.sh)"; exit 0; }

OUT="$RUN_DIR/smoke-$(date +%H%M%S)"
mkdir -p "$OUT"
if bash "$DEPLOY_DIR/40_parse.sh" "$TEST_IMAGE" "$OUT" >/dev/null 2>&1; then
    echo "  [✓] 解析成功,产物:"
    ls -lh "$OUT" | sed 's/^/      /'
else
    warn "解析失败:查看 ../run/logs/*.log 与 $OUT"
    exit 1
fi
