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
# 签名身份解析（2026-10-16 收口）：显式 env 恒优先；否则从钥匙串运行时
# 发现唯一的 "Apple Development" 签名身份——私人标识不得进跟踪树
# （与 SimiGo-Lab 零豁免审计对齐）。零个/多个匹配都响亮失败并列出候选。
if [ -n "${CODE_SIGN_IDENTITY:-}" ]; then
    IDENTITY="$CODE_SIGN_IDENTITY"
else
    DISCOVERED="$(security find-identity -v -p codesigning \
        | awk -F'"' '/Apple Development/ {print $2}')"
    MATCHES="$(printf '%s\n' "$DISCOVERED" | grep -c .)"
    if [ "$MATCHES" -eq 1 ]; then
        IDENTITY="$DISCOVERED"
    elif [ "$MATCHES" -eq 0 ]; then
        echo "错误: 钥匙串中无 'Apple Development' 签名身份；请设置 CODE_SIGN_IDENTITY" >&2
        exit 1
    else
        echo "错误: 钥匙串中有 $MATCHES 个 'Apple Development' 身份；请设置 CODE_SIGN_IDENTITY 为其中之一:" >&2
        printf '%s\n' "$DISCOVERED" | sed 's/^/  /' >&2
        exit 1
    fi
fi
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
