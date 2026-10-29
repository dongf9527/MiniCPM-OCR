#!/usr/bin/env bash
# 90 — 按 pidfile 停止本包启动的全部服务
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

stopped=0
for pf in "$RUN_DIR"/*.pid; do
    [ -f "$pf" ] || continue
    name="$(basename "$pf" .pid)"
    pid="$(cat "$pf")"
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        # 给进程最多 10 秒退出,超时强杀
        for _ in $(seq 1 10); do
            kill -0 "$pid" 2>/dev/null || break
            sleep 1
        done
        kill -9 "$pid" 2>/dev/null || true
        echo "已停止 $name(pid $pid)"
    else
        echo "$name 未在运行,清理 pid 文件"
    fi
    rm -f "$pf"
    stopped=$((stopped+1))
done

[ "$stopped" -eq 0 ] && echo "没有需要停止的服务"
echo "剩余 GPU 进程自查: nvidia-smi | grep -E 'llama|python'"
