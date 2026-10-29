#!/usr/bin/env bash
# 22 — 安装 Jev 评分服务的渲染环境(调用上游 setup_render.sh,本包不改上游文件)
# 上游脚本会装:固定版本 Pillow/playwright、Node、CJK 字体、Chromium。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

VENV="${JEV_RENDER_VENV:-$WORKSPACE_DIR/venv-render}"
SETUP="$REPO_ROOT/scripts/minicpm-ocr-jev/sdk/setup_render.sh"
[ -f "$SETUP" ] || die "上游渲染环境脚本不存在: $SETUP"

if [ -x "$VENV/bin/python" ] && "$VENV/bin/python" -c 'import playwright, PIL' 2>/dev/null; then
    say "渲染环境已存在($VENV),跳过"
else
    say "安装渲染环境 → $VENV(含 Chromium 下载,慢网时可设 PIP_INDEX_URL / PLAYWRIGHT_DOWNLOAD_HOST)"
    bash "$SETUP" "$VENV"
fi
echo "完成。启动服务: bash 23_start_jev_service.sh"
