#!/usr/bin/env bash
# 11 — 下载权重:1.0 GGUF(语言模型 + 视觉投影器)与 Jev 原始 HF 权重
# 上游文档给出的权重入口(docs/llamacpp_deploy.md 与评估报告附录 A)。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

OCR_REPO="${OCR_REPO:-openbmb/MiniCPM-OCR-1.0-gguf}"
JEV_REPO="${JEV_REPO:-openbmb/MiniCPM-OCR-1.0-Jev}"

mkdir -p "$GGUF_DIR" "$JEV_HF_DIR"

# --- hf CLI:无则建一个极简 venv 只装 huggingface_hub ---
ensure_hf_cli() {
    if command -v hf >/dev/null 2>&1 || command -v huggingface-cli >/dev/null 2>&1; then
        return 0
    fi
    say "未找到 hf CLI,创建 $WORKSPACE_DIR/venv-dl 并安装 huggingface_hub"
    python3 -m venv "$WORKSPACE_DIR/venv-dl"
    "$WORKSPACE_DIR/venv-dl/bin/pip" -q install -U "huggingface_hub"
    export PATH="$WORKSPACE_DIR/venv-dl/bin:$PATH"
}

hf_download() {
    # 用法: hf_download <repo> <file|"*"> <dest_dir>;target 为 * 时下载整仓
    local repo="$1" target="$2" dest="$3"
    if command -v hf >/dev/null 2>&1; then
        if [ "$target" = "*" ]; then hf download "$repo" --local-dir "$dest"; \
        else hf download "$repo" "$target" --local-dir "$dest"; fi
    else
        if [ "$target" = "*" ]; then huggingface-cli download "$repo" --local-dir "$dest"; \
        else huggingface-cli download "$repo" "$target" --local-dir "$dest"; fi
    fi
}

say "下载 1.0 GGUF(共约 2.3 GB)→ $GGUF_DIR"
if [ -s "$OCR_GGUF" ] && [ -s "$OCR_MMPROJ" ]; then
    echo "    已存在,跳过(重下请删除 $GGUF_DIR 下对应文件)"
else
    ensure_hf_cli
    [ -s "$OCR_GGUF" ]   || hf_download "$OCR_REPO" "MiniCPM-OCR-1_0-F16.gguf"     "$GGUF_DIR"
    [ -s "$OCR_MMPROJ" ] || hf_download "$OCR_REPO" "mmproj-model-f16-4x.gguf"    "$GGUF_DIR"
fi
ls -lh "$GGUF_DIR" | sed 's/^/    /'

if [ "${SKIP_JEV:-false}" = "true" ]; then
    say "SKIP_JEV=true,跳过 Jev 权重下载(最小路径:仅跑 1.0 解析)"
else
    say "下载 Jev 原始权重(约 4–5 GB)→ $JEV_HF_DIR/$JEV_REPO"
    if [ -f "$JEV_HF_DIR/$JEV_REPO/config.json" ]; then
        echo "    已存在,跳过"
    else
        ensure_hf_cli
        hf_download "$JEV_REPO" "*" "$JEV_HF_DIR/$JEV_REPO"
    fi
    ls "$JEV_HF_DIR/$JEV_REPO" 2>/dev/null | head -20 | sed 's/^/    /' || true
fi

if [ "${SKIP_JEV:-false}" = "true" ]; then
    say "下一步: bash 20_start_ocr_engine.sh(1.0 GGUF 无需转换)"
else
    say "下一步: bash 12_convert_jev_gguf.sh(1.0 侧无需转换,也可直接起 20 号脚本)"
fi
