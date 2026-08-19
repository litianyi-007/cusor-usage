#!/bin/bash
# 一键：构建 + 打包 + 启动 CursorUsage 菜单栏插件
set -e
cd "$(dirname "$0")"

export TMPDIR=${TMPDIR:-/tmp/swiftwork}
make app
echo
echo "已启动 CursorUsage（菜单栏图标，纯菜单栏常驻，无 Dock 图标）。"
echo "点击菜单栏图标查看用量；⚙️ 设置 token；退出请用面板底部电源键。"
open build/CursorUsage.app
