#!/usr/bin/env bash
# 00 — 环境体检:16G 部署前置条件逐项核对
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

pass=0; fail=0
ok()   { printf '  [✓] %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  [✗] %s\n' "$1"; fail=$((fail+1)); }
item() { printf '  [?] %s\n' "$1"; }

say "GPU / 驱动 / 显存"
if command -v nvidia-smi >/dev/null 2>&1; then
    name="$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1 || true)"
    drv="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1 || true)"
    mem="$(vram_total_mib)"
    ok "GPU: $name"
    if [ "${mem:-0}" -ge 15000 ]; then
        ok "显存: ${mem} MiB(≥16 GB 档)"
    else
        bad "显存仅 ${mem} MiB,低于 16 GB 档;请改用 CPU 模式(OCR_NGL=0)"
    fi
    drv_major="${drv%%.*}"
    if [ "${drv_major:-0}" -ge 535 ]; then
        ok "驱动: $drv(llama.cpp 路径要求 ≥535)"
    else
        bad "驱动: $drv 低于 535;vLLM 路径需 ≥580,本包 llama.cpp 路径也建议升级"
    fi
else
    bad "nvidia-smi 不可用:无 NVIDIA 驱动或非 NVIDIA 环境"
fi

say "系统资源"
mem_gb="$(free -g 2>/dev/null | awk '/^Mem:/{print $2}' || true)"
if [ "${mem_gb:-0}" -ge 16 ]; then
    ok "内存: ${mem_gb} GB(≥16 GB)"
else
    item "内存: ${mem_gb:-?} GB,官方低配要求 ≥16 GB"
fi
disk_free_gb="$(df -BG "$WORKSPACE_DIR" 2>/dev/null | awk 'NR==2{gsub("G","",$4);print $4}' || true)"
if [ "${disk_free_gb:-0}" -ge 15 ]; then
    ok "磁盘余量: ${disk_free_gb} GB(权重+编译约需 15 GB)"
else
    bad "磁盘余量: ${disk_free_gb:-?} GB 不足 15 GB"
fi

say "工具链(编译 llama.cpp 与转换权重)"
for b in git cmake make g++ curl python3 pip3; do
    if command -v "$b" >/dev/null 2>&1; then
        v="$("$b" --version 2>/dev/null | head -1 | grep -oE '[0-9]+(\.[0-9]+)*' | head -1 || true)"
        ok "$b $v"
    else
        bad "缺少 $b"
    fi
done
cmake_major="$(cmake --version 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1 || true)"
[ "${cmake_major:-0}" -ge 3 ] && ok "cmake 版本满足 ≥3.14" || bad "cmake 需 ≥3.14"

say "CUDA 工具链(10 号 GGML_CUDA=ON 编译必需)"
if command -v nvcc >/dev/null 2>&1; then
    nvcc_ver="$(nvcc --version 2>/dev/null | grep -oE 'release [0-9]+\.[0-9]+' | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)"
    ok "nvcc $nvcc_ver"
    nvcc_major="${nvcc_ver%%.*}"; nvcc_minor="${nvcc_ver#*.}"
    case "${name:-}" in
        *"RTX 50"*)
            # Blackwell(sm_120)首个支持版本为 CUDA 12.8
            if [ "${nvcc_major:-0}" -gt 12 ] || { [ "${nvcc_major:-0}" -eq 12 ] && [ "${nvcc_minor:-0}" -ge 8 ]; }; then
                ok "CUDA $nvcc_ver 支持 Blackwell/sm_120(RTX 50 系)"
            else
                bad "CUDA $nvcc_ver 不支持 RTX 50 系(sm_120);需 CUDA Toolkit ≥12.8"
            fi ;;
        *) item "非 Blackwell 卡,CUDA $nvcc_ver 一般可用;若未装 nvcc 仅影响 10 号编译" ;;
    esac
else
    bad "缺少 nvcc:请安装 CUDA Toolkit(RTX 50 系需 ≥12.8)并确认 nvcc 在 PATH;装好后重跑本脚本"
fi

say "网络(HF 权重下载,11 号使用)"
hf_ok=0; mir_ok=0
curl -sf -m 6 https://huggingface.co >/dev/null 2>&1 && hf_ok=1
curl -sf -m 6 https://hf-mirror.com >/dev/null 2>&1 && mir_ok=1
if [ "$hf_ok" -eq 1 ]; then
    ok "huggingface.co 可达(可直连下载)"
elif [ "$mir_ok" -eq 1 ]; then
    item "huggingface.co 不可达,hf-mirror.com 可达:建议启用镜像"
    echo "    编辑 env.local.sh(无则 cp env.16g.example.sh env.local.sh),取消注释:"
    echo "    export HF_ENDPOINT=\"https://hf-mirror.com\""
else
    bad "huggingface.co 与 hf-mirror.com 均不可达,11 号下载会失败;请检查网络或代理"
fi

say "汇总: 通过 $pass 项 / 未过 $fail 项"
[ "$fail" -eq 0 ] || warn "存在未过项;带 [✗] 的项会导致后续脚本失败,请先处理"
exit 0
