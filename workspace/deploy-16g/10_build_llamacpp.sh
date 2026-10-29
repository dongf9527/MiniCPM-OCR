#!/usr/bin/env bash
# 10 — 克隆并编译 llama.cpp(CUDA),产出 llama-server 与 llama-quantize
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

need_bin git; need_bin cmake; need_bin g++

if [ -x "$LLAMACPP_DIR/build/bin/llama-server" ]; then
    say "llama-server 已存在($LLAMACPP_DIR/build/bin/llama-server),跳过编译"
    say "如需重编译: rm -rf $LLAMACPP_DIR 后重跑本脚本"
    exit 0
fi

if [ ! -d "$LLAMACPP_DIR/.git" ]; then
    say "克隆 llama.cpp(浅克隆)到 $LLAMACPP_DIR"
    git clone --depth 1 https://github.com/ggml-org/llama.cpp.git "$LLAMACPP_DIR"
fi

gpu_name="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || true)"
case "$gpu_name" in
    *"RTX 50"*)
        [ -z "${LLAMA_CUDA_ARCH:-}" ] && \
            warn "检测到 RTX 50 系(Blackwell/sm_120):建议在 env.local.sh 设 export LLAMA_CUDA_ARCH=\"120\"(需 nvcc ≥12.8),可大幅缩短编译时间" ;;
esac

ARCH_ARGS=()
[ -n "${LLAMA_CUDA_ARCH:-}" ] && ARCH_ARGS=(-DCMAKE_CUDA_ARCHITECTURES="$LLAMA_CUDA_ARCH")

say "CMake 配置(GGML_CUDA=ON)${LLAMA_CUDA_ARCH:+,架构 $LLAMA_CUDA_ARCH}"
cmake -B "$LLAMACPP_DIR/build" -S "$LLAMACPP_DIR" \
    -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release "${ARCH_ARGS[@]}"

JOBS="${JOBS:-$(nproc)}"
say "编译 llama-server + llama-quantize(并发 $JOBS jobs;内存紧张被 OOM 杀掉则用 JOBS=8 重跑)"
cmake --build "$LLAMACPP_DIR/build" -j"$JOBS" --target llama-server llama-quantize

[ -x "$LLAMACPP_DIR/build/bin/llama-server" ] || die "编译完成但未找到 llama-server,请检查上方日志"
echo "完成: $LLAMACPP_DIR/build/bin/{llama-server,llama-quantize}"
