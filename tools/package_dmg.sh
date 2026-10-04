#!/bin/bash
# SimiGo DMG 打包（V1.6+ 发布流程固化）。
# 用法: tools/package_dmg.sh <版本号，如 1.6>
# 前置: 已完成 xcodebuild build -derivedDataPath build/release-v2.1
#（v2.1 起发布构建根 = fresh build/release-v2.1；v1.7 构建根退役）
# 效果: 刷新 bundle 目录时间戳为打包时刻（消除 Finder 显示旧
#       创建日期的观感混淆），产出 SimiGo-v<版本>.dmg 并 hdiutil verify。
set -e
VER="$1"
[ -z "$VER" ] && { echo "用法: $0 <版本号>"; exit 1; }
DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="$DIR/build/release-v2.1/Build/Products/Release/SimiGo.app"
IDENTITY="${CODE_SIGN_IDENTITY:-Apple Development: slamfinger@163.com (99T9X7WUK3)}"
ENTITLEMENTS="$DIR/build/release-v2.1/Build/Intermediates.noindex/SimiGo.build/Release/SimiGo.build/SimiGo.app.xcent"
[ -d "$APP" ] || { echo "构建产物不存在: $APP"; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/SimiGo.app"
# 刷新 bundle 目录与内容的 mtime 为打包时刻（Finder 观感=真实打包时间）
touch "$STAGE/SimiGo.app"
find "$STAGE/SimiGo.app" -exec touch {} +

# Re-sign after touching every file; ad-hoc rebuilds kept invalidating the
# Keychain ACL for cloud.api-key and turned every launch into a password prompt.
codesign --force --sign "$IDENTITY" --options runtime \
    --entitlements "$ENTITLEMENTS" "$STAGE/SimiGo.app"

hdiutil create -volname SimiGo -srcfolder "$STAGE" -format UDZO -fs APFS \
    -ov "$DIR/SimiGo-v$VER.dmg" | tail -1
hdiutil verify "$DIR/SimiGo-v$VER.dmg" | tail -1
echo "完成: SimiGo-v$VER.dmg"
