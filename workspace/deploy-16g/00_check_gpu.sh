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

say "汇总: 通过 $pass 项 / 未过 $fail 项"
[ "$fail" -eq 0 ] || warn "存在未过项;带 [✗] 的项会导致后续脚本失败,请先处理"
exit 0
