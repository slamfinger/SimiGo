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
TMPAPPLES="$(mktemp -d)/install.applescript"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/SimiGo.app"
ln -s /Applications "$STAGE/Applications"
cat > "$TMPAPPLES" <<'OSA'
-- SimiGo 图形安装器（DMG 内双击运行）
set myDir to POSIX file ((do shell script "dirname " & quoted form of (POSIX path of (path to me))) & "/")
set src to POSIX path of myDir & "SimiGo.app"
display dialog "安装 SimiGo 2.2.0" & return & return & "将把 SimiGo 安装到 /Applications（覆盖旧版本）。" & return & "安装完成后自动启动，进入安装向导。" buttons {"取消", "安装"} default button "安装" with icon note
-- 覆盖安装 = 重新进入安装向导：重置首启标记（不动数据库与已装二进制）
set userName to short user name of (system info)
do shell script "rm -rf /Applications/SimiGo.app && cp -R " & quoted form of src & " /Applications/SimiGo.app && rm -f /Users/" & userName & "/.simigo/manifests/first-run-done.json" with administrator privileges
display dialog "✅ 安装完成" & return & "正在启动 SimiGo（首次启动将进入安装向导）" buttons {"好"} default button "好" giving up after 4
-- `open` merely activates an already running copy, so the new bundle (and the wizard
-- triggered by the removed marker) never appeared. Stop the old instance first, and
-- identify it exactly: argv[0] compared against the installed bundle path, so launch
-- arguments cannot hide it and a development copy (build/, DerivedData, /tmp bundles),
-- an in-bundle helper or an unrelated process can never match. `comm` is not usable --
-- macOS truncates it at 64 characters, which is shorter than a DerivedData path.
-- SIGTERM, then wait up to 15 s for a graceful exit; bounded SIGKILL for survivors.
set stopCmd to "ids=$(ps -axo pid=,command= | awk '$2==\"/Applications/SimiGo.app/Contents/MacOS/SimiGo\"{print $1}'); if [ -n \"$ids\" ]; then kill -TERM $ids 2>/dev/null; fi; i=0; while [ $i -lt 15 ]; do i=$((i+1)); sleep 1; ids=$(ps -axo pid=,command= | awk '$2==\"/Applications/SimiGo.app/Contents/MacOS/SimiGo\"{print $1}'); if [ -z \"$ids\" ]; then break; fi; done; ids=$(ps -axo pid=,command= | awk '$2==\"/Applications/SimiGo.app/Contents/MacOS/SimiGo\"{print $1}'); if [ -n \"$ids\" ]; then kill -KILL $ids 2>/dev/null; fi; sleep 1; open /Applications/SimiGo.app"
do shell script stopCmd
OSA
osacompile -o "$STAGE/安装SimiGo.app" "$TMPAPPLES"
hdiutil create -volname "SimiGo 安装" -srcfolder "$STAGE" -ov -format UDZO "$OUT" >/dev/null 2>&1
hdiutil verify "$OUT" >/dev/null
echo "$OUT"
