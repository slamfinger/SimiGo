#!/bin/zsh
# 产 PKG 安装器到仓库根（owner 2026-10-26：自启动安装形态）。
# 双击 SimiGo-vX.Y.Z-Installer.pkg → macOS 系统安装向导（简介→安装→完成）
# → 安装后脚本自动启动 /Applications/SimiGo.app → 首启向导（工作目录/
# 引擎二进制/自举/DMG 无关）。
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-/tmp/simigo_rel/Build/Products/Release/SimiGo.app}"
[ -d "$APP" ] || { echo "未找到 Release SimiGo.app"; exit 1; }
VER="$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString)"
BUILD="$(defaults read "$APP/Contents/Info.plist" CFBundleVersion)"
EXE8="$(shasum -a 256 "$APP/Contents/MacOS/SimiGo" | cut -c1-8)"
OUT="$ROOT/SimiGo-v${VER}-${BUILD}-${EXE8}-Installer.pkg"

TMPD="$(mktemp -d)"; PAYLOAD="$TMPD/payload"; SCRIPTS="$TMPD/scripts"
mkdir -p "$PAYLOAD" "$SCRIPTS"
cp -R "$APP" "$PAYLOAD/SimiGo.app"
cat > "$SCRIPTS/postinstall" <<'POST'
#!/bin/zsh
# 安装完成即启动：进入首启安装向导（若 ~/.simigo 已就绪则直接常驻菜单栏）
open /Applications/SimiGo.app
exit 0
POST
chmod +x "$SCRIPTS/postinstall"

pkgbuild --root "$PAYLOAD" --scripts "$SCRIPTS" \
  --identifier "SwiftUI.SimiGo.installer" \
  --version "$VER.$BUILD" \
  "$ROOT/.tmp_component.pkg" >/dev/null
productbuild --package "$ROOT/.tmp_component.pkg" "$OUT" >/dev/null
rm -f "$ROOT/.tmp_component.pkg"
echo "$OUT"
