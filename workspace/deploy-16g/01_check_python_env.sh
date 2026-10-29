#!/usr/bin/env bash
# 01 — Python 环境体检:conda env / python 版本 / pip / venv / 当前环境下的 nvcc
# 用法:先 conda activate <env> 再执行;与 00 号(系统级)配合:
#   conda create -n py312 python=3.12 -y && conda activate py312
#   bash 00_check_gpu.sh && bash 01_check_python_env.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

pass=0; fail=0
ok()   { printf '  [✓] %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  [✗] %s\n' "$1"; fail=$((fail+1)); }
item() { printf '  [?] %s\n' "$1"; }

py_bin="$(command -v python3 || true)"
py_ver="$(python3 -c 'import sys;print("%d.%d"%sys.version_info[:2])' 2>/dev/null || true)"

say "conda / 当前环境"
if command -v conda >/dev/null 2>&1; then
    cur="${CONDA_DEFAULT_ENV:-}"
    if [ -n "$cur" ] && [ "$cur" != "base" ]; then
        ok "conda 已安装,当前环境: $cur"
    else
        item "当前在 conda base(或未激活环境);建议先执行:"
        echo "    conda create -n py312 python=3.12 -y && conda activate py312"
    fi
else
    item "未安装 conda:将直接使用系统 python3;只要下方版本检查通过亦可,不必强装 conda"
fi

say "python 版本(受控范围 3.9–3.13,首选 3.12)"
if [ -n "$py_ver" ]; then
    major="${py_ver%%.*}"; minor="${py_ver#*.}"
    if [ "$major" -eq 3 ] && [ "$minor" -ge 10 ] && [ "$minor" -le 12 ]; then
        ok "python3 = $py_ver($py_bin)"
    elif [ "$major" -eq 3 ] && [ "$minor" -eq 9 ]; then
        item "python3 = $py_ver:可用但非首选,推荐 3.12"
    elif [ "$major" -eq 3 ] && [ "$minor" -eq 13 ]; then
        item "python3 = $py_ver:paddle 对 3.13 轮子支持不全(PaddlePaddle#71616),建议改用 3.12:"
        echo "    conda create -n py312 python=3.12 -y && conda activate py312"
    else
        bad "python3 = $py_ver:不在受控范围(3.9–3.13);请改用 3.12"
    fi
else
    bad "python3 不可用"
fi

say "pip / venv 模块(11/12/30 号建 venv 必需)"
if python3 -m pip --version >/dev/null 2>&1; then
    ok "pip: $(python3 -m pip --version 2>/dev/null | head -1 || true)"
else
    bad "python3 -m pip 不可用"
fi
selftest="$RUN_DIR/.venv-selftest"
rm -rf "$selftest"
if python3 -m venv "$selftest" >/dev/null 2>&1; then
    ok "venv 模块可用(试建 $selftest 成功,已清理)"
    rm -rf "$selftest"
else
    bad "python3 -m venv 失败(Debian/Ubuntu 需先安装 python3-venv 包)"
fi

say "nvcc(当前环境 PATH;10 号编译期间需保持本环境激活)"
if command -v nvcc >/dev/null 2>&1; then
    nvcc_ver="$(nvcc --version 2>/dev/null | grep -oE 'release [0-9]+\.[0-9]+' | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)"
    ok "nvcc $nvcc_ver($(command -v nvcc))"
    nvcc_major="${nvcc_ver%%.*}"; nvcc_minor="${nvcc_ver#*.}"
    if [ "${nvcc_major:-0}" -gt 12 ] || { [ "${nvcc_major:-0}" -eq 12 ] && [ "${nvcc_minor:-0}" -ge 8 ]; }; then
        ok "CUDA ≥12.8:满足 RTX 50 系(Blackwell/sm_120)编译要求"
    else
        bad "CUDA $nvcc_ver <12.8:不支持 RTX 50 系(sm_120);处理:"
        echo "    conda install -c nvidia cuda-toolkit=12.9 -y   # 或 13.0;宿主 g++ 较新时优先 12.9+"
    fi
else
    item "当前 PATH 无 nvcc:已装则先激活对应环境;未装则在本环境内安装:"
    echo "    conda install -c nvidia cuda-toolkit=12.9 -y   # sm_120 需 ≥12.8,建议 12.9+(兼容更新宿主 g++)"
fi

say "编译工具链(当前 PATH;conda env 可能遮蔽系统工具)"
for b in git cmake make g++; do
    if command -v "$b" >/dev/null 2>&1; then
        v="$("$b" --version 2>/dev/null | head -1 | grep -oE '[0-9]+(\.[0-9]+)*' | head -1 || true)"
        ok "$b $v"
    else
        bad "缺少 $b"
    fi
done

say "汇总: 通过 $pass 项 / 未过 $fail 项"
[ "$fail" -eq 0 ] || warn "存在未过项;带 [✗] 的项会阻塞后续脚本,请先处理再继续"
exit 0
