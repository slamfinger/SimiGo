#!/bin/bash
# SimiGo DMG 打包（V1.6+ 发布流程固化）。
# 用法: tools/package_dmg.sh <版本号，如 1.6>
# 前置: 已完成 xcodebuild build -derivedDataPath build/release
# 效果: 刷新 bundle 目录时间戳为打包时刻（消除 Finder 显示旧
#       创建日期的观感混淆），产出 SimiGo-v<版本>.dmg 并 hdiutil verify。
set -e
VER="$1"
[ -z "$VER" ] && { echo "用法: $0 <版本号>"; exit 1; }
DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="$DIR/build/release/Build/Products/Release/SimiGo.app"
[ -d "$APP" ] || { echo "构建产物不存在: $APP"; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/SimiGo.app"
# 刷新 bundle 目录与内容的 mtime 为打包时刻（Finder 观感=真实打包时间）
touch "$STAGE/SimiGo.app"
find "$STAGE/SimiGo.app" -exec touch {} +

hdiutil create -volname SimiGo -srcfolder "$STAGE" -format UDZO \
    -ov "$DIR/SimiGo-v$VER.dmg" | tail -1
hdiutil verify "$DIR/SimiGo-v$VER.dmg" | tail -1
echo "完成: SimiGo-v$VER.dmg"
