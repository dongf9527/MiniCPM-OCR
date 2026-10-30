#!/usr/bin/env bash
# 30 — 创建 SDK 环境:minicpm-ocr[all]==1.0.2 + PaddlePaddle(版面检测)
# 默认 CPU 版 paddle(版面走 CPU,不占显存,16G 最稳);
# LAYOUT_DEVICE=cuda:0 时装 GPU 版 paddle(需 CUDA 12.9 运行时,驱动 ≥575)。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

SDK_VENV="${SDK_VENV:-$WORKSPACE_DIR/venv-sdk}"

say "创建 SDK 虚拟环境 $SDK_VENV"
if [ ! -x "$SDK_VENV/bin/python" ]; then
    python3 -m venv "$SDK_VENV"
fi
"$SDK_VENV/bin/pip" -q install -U pip

say "安装 minicpm-ocr[all]==1.0.2"
"$SDK_VENV/bin/pip" install "minicpm-ocr[all]==1.0.2"

case "${LAYOUT_DEVICE:-cpu}" in
    cuda*)
        say "安装 GPU 版 paddlepaddle(版面检测走 $LAYOUT_DEVICE)"
        "$SDK_VENV/bin/pip" install "paddlepaddle-gpu==3.3.0" \
            -i https://www.paddlepaddle.org.cn/packages/stable/cu129/
        ;;
    *)
        say "安装 CPU 版 paddlepaddle(版面检测走 CPU,不占显存)"
        "$SDK_VENV/bin/pip" install "paddlepaddle==3.2.1"
        ;;
esac

"$SDK_VENV/bin/python" -c 'import minicpmvocr; print("    SDK ok:", minicpmvocr.__name__)' \
    || die "SDK 导入失败,请检查上方 pip 日志"
echo "完成。版面模型 PP-DocLayoutV3 由 40 号首次解析时准备(存于 workspace/models/,约几百 MB)。"
