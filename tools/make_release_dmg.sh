#!/bin/zsh
# 产"自启动安装"形态 DMG 到仓库根（owner 2026-10-26）。
# 形态：双击 DMG → Finder 自动打开安装窗口（App + Applications 拖放目标 +
# 安装说明背景）；双击 App 即进入首启安装向导（工作目录/引擎二进制/自举/
# 自动落位 /Applications 并重启）。
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-/tmp/simigo_rel/Build/Products/Release/SimiGo.app}"
[ -d "$APP" ] || { echo "未找到 Release SimiGo.app"; exit 1; }
VER="$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString)"
BUILD="$(defaults read "$APP/Contents/Info.plist" CFBundleVersion)"
EXE8="$(shasum -a 256 "$APP/Contents/MacOS/SimiGo" | cut -c1-8)"
OUT="$ROOT/SimiGo-v${VER}-${BUILD}-${EXE8}.dmg"
STAGE="$(mktemp -d)/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/SimiGo.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/双击 SimiGo 开始安装.txt" <<'TXT'
SimiGo 安装
1. 双击 SimiGo.app（可直接从本窗口运行）
2. 安装向导引导：设定外部工作目录 → 勾选引擎二进制（自动安装入 ~/.simigo/bin）→ 自举
3. 向导最后自动把 SimiGo 落位 /Applications 并重启
   （或把 SimiGo.app 拖到右侧 Applications 后启动）
TXT
# 安装窗口视图：图标排列 + 说明
osascript <<OSA
tell application "Finder"
  make new file at POSIX file "$STAGE" as alias with properties {name:".background"}
end tell
OSA
hdiutil create -volname "SimiGo 安装" -srcfolder "$STAGE" -ov -format UDZO "$OUT" >/dev/null 2>&1
hdiutil verify "$OUT" >/dev/null
echo "$OUT"
