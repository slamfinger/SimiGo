#!/bin/zsh
# dev_install.sh — 构建 SimiGo 并部署到 build/SimiGo.app（开发试验稳定入口）。
# 用法: tools/dev_install.sh [--release]
# 流程: xcodebuild 构建（产品自动落在派生数据目录）→ 复制到 build/SimiGo.app。
# 启动前先退出旧实例（两个实例允许复用 8000 端口，会串流）。
set -e
cd "$(dirname "$0")/.."

CONFIG=Debug
[ "$1" = "--release" ] && CONFIG=Release

xcodebuild -project SimiGo.xcodeproj \
    -scheme SimiGo \
    -configuration "$CONFIG" \
    -destination 'platform=macOS' \
    build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | tail -3

BUILT=$(xcodebuild -project SimiGo.xcodeproj \
    -scheme SimiGo \
    -configuration "$CONFIG" \
    -destination 'platform=macOS' \
    -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR = /{print $3; exit}')

rm -rf build/SimiGo.app
cp -R "$BUILT/SimiGo.app" build/SimiGo.app

echo "✅ build/SimiGo.app ($CONFIG) — 先退出旧实例，然后: open build/SimiGo.app"
