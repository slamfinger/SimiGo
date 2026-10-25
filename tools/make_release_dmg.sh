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
cat > "$STAGE/安装SimiGo.command" <<'CMD'
#!/bin/zsh
# 双击即装：拷贝 SimiGo 到 /Applications 并启动（首启向导自动出现）
set -e
VOL="$(cd "$(dirname "$0")" && pwd)"
TARGET="/Applications/SimiGo.app"
if [ -d "$TARGET" ]; then rm -rf "$TARGET"; fi
cp -R "$VOL/SimiGo.app" "$TARGET"
open "$TARGET"
echo "✅ SimiGo 已安装到 /Applications 并启动"
sleep 2
CMD
chmod +x "$STAGE/安装SimiGo.command"
hdiutil create -volname "SimiGo 安装" -srcfolder "$STAGE" -ov -format UDZO "$OUT" >/dev/null 2>&1
hdiutil verify "$OUT" >/dev/null
echo "$OUT"
