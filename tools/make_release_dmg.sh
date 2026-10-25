#!/bin/zsh
# 产出版本 DMG 到仓库根（owner 2026-10-26：构建产物直接落在
# /Users/mr.simi/Documents/SimiGo 下，供安装使用）。
# 用法: tools/make_release_dmg.sh [Release产物路径(默认最新 Release 构建的 App)]
# 无需签名身份：ad-hoc DMG（与 RC 候选一致）。
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-}"
if [ -z "$APP" ]; then
  for d in "$ROOT/build/release"*/Build/Products/Release/SimiGo.app /tmp/simigo_rel/Build/Products/Release/SimiGo.app; do
    [ -d "$d" ] && APP="$d" && break
  done
fi
[ -d "$APP" ] || { echo "未找到 Release SimiGo.app（先构建或传路径）"; exit 1; }
VER="$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString)"
BUILD="$(defaults read "$APP/Contents/Info.plist" CFBundleVersion)"
EXE8="$(shasum -a 256 "$APP/Contents/MacOS/SimiGo" | cut -c1-8)"
OUT="$ROOT/SimiGo-v${VER}-${BUILD}-${EXE8}.dmg"
hdiutil create -volname "SimiGo" -srcfolder "$APP" -ov -format UDZO "$OUT" >/dev/null
hdiutil verify "$OUT" >/dev/null
echo "$OUT"
