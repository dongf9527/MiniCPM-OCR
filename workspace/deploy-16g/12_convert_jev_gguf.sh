#!/usr/bin/env bash
# 12 — Jev HF 权重 → GGUF 转换(按官方文档 docs/llamacpp_deploy_jev_zh.md 流程)
# 关键点:转换器按 config.json 的 architectures 认模型,Jev 需改为
# MiniCPMOCRForSequenceClassification(分类头);原目录只软链不改,另建转换用目录。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

[ -d "$LLAMACPP_DIR/.git" ] || die "未找到 llama.cpp 克隆 — 先执行 bash 10_build_llamacpp.sh"

JEV_REPO="${JEV_REPO:-openbmb/MiniCPM-OCR-1.0-Jev}"
JEV_SRC="$JEV_HF_DIR/$JEV_REPO"
JEV_CONV="$JEV_HF_DIR/MiniCPM-OCR-1.0-Jev-gguf"
[ -f "$JEV_SRC/config.json" ] || die "未找到 Jev 权重($JEV_SRC)— 先执行 bash 11_download_weights.sh"

if [ -s "$JEV_GGUF" ] && [ -s "$JEV_MMPROJ" ]; then
    say "Jev GGUF 已存在,跳过转换($JEV_GGUF)"
    exit 0
fi

# --- 转换用 python 环境(torch 取 CPU 版即可,转换不用 GPU)---
CONV_VENV="${CONV_VENV:-$WORKSPACE_DIR/venv-convert}"
if [ ! -x "$CONV_VENV/bin/python" ]; then
    say "创建转换环境 $CONV_VENV"
    python3 -m venv "$CONV_VENV"
    "$CONV_VENV/bin/pip" -q install -U pip
fi
if ! "$CONV_VENV/bin/python" -c 'import gguf' 2>/dev/null; then
    say "安装 GGUF 转换依赖(llama.cpp requirements;torch 为 CPU 版,体积较大,请耐心等待)"
    "$CONV_VENV/bin/pip" install -r "$LLAMACPP_DIR/requirements/requirements-convert_hf_to_gguf.txt"
fi

# --- 建转换用目录:软链全部文件,只放改过 architectures 的 config.json ---
say "准备转换用目录 $JEV_CONV"
mkdir -p "$JEV_CONV"
find "$JEV_SRC" -maxdepth 1 -type f ! -name config.json | while read -r f; do
    ln -sf "$f" "$JEV_CONV/$(basename "$f")"
done
"$CONV_VENV/bin/python" - "$JEV_SRC/config.json" "$JEV_CONV/config.json" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
c = json.load(open(src))
c["architectures"] = ["MiniCPMOCRForSequenceClassification"]
json.dump(c, open(dst, "w"), indent=2, ensure_ascii=False)
print("architectures ->", c["architectures"])
PY

say "转换语言模型(→ $JEV_GGUF)"
"$CONV_VENV/bin/python" "$LLAMACPP_DIR/convert_hf_to_gguf.py" "$JEV_CONV" \
    --outtype bf16 --outfile "$JEV_GGUF"

say "转换视觉投影器 mmproj(→ $JEV_MMPROJ)"
"$CONV_VENV/bin/python" "$LLAMACPP_DIR/convert_hf_to_gguf.py" "$JEV_CONV" --mmproj \
    --outtype bf16 --outfile "$JEV_MMPROJ"

ls -lh "$GGUF_DIR"/MiniCPM-OCR-Jev* "$GGUF_DIR"/mmproj-MiniCPM-OCR-Jev* | sed 's/^/    /'
echo "完成。mmproj 已带与训练一致的图片缩放下限(官方要求必须从转换目录导出)。"
