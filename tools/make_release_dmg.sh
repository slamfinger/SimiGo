#!/bin/zsh
# 产"自启动安装"形态 DMG 到仓库根（owner 2026-10-26）。
# 形态：双击 DMG → Finder 自动打开安装窗口（App + Applications 拖放目标 +
# 安装说明背景）；双击 App 即进入首启安装向导（工作目录/引擎二进制/自举/
# 自动落位 /Applications 并重启）。
# 用法：tools/make_release_dmg.sh [SimiGo.app]
# 不给 .app 时按 README 的发布口径自建 Release（关覆盖率插桩）再打包；
# 给了 .app 也会先验二进制里没有插桩计数器，带插桩直接拒绝。
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-}"
if [ -z "$APP" ]; then
  DD="$ROOT/build/release"
  echo "未给 .app：自建 Release（ENABLE_CODE_COVERAGE=NO）→ $DD" >&2
  xcodebuild build -project "$ROOT/SimiGo.xcodeproj" -scheme SimiGo \
    -configuration Release -destination 'platform=macOS' \
    -derivedDataPath "$DD" \
    ENABLE_CODE_COVERAGE=NO CLANG_COVERAGE_MAPPING=NO >/dev/null
  APP="$DD/Build/Products/Release/SimiGo.app"
fi
[ -d "$APP" ] || { echo "未找到 Release SimiGo.app"; exit 1; }
# 插桩在二进制里看得见、在目录名上看不出来：有 ___profc_ 就拒绝，别让他交给用户。
# （带插桩的包大六成，且 __llvm_prf_names 里写着构建机的绝对路径。）
if nm -a "$APP/Contents/MacOS/SimiGo" 2>/dev/null | grep -q "___profc_"; then
  echo "拒绝打包：$APP 带覆盖率插桩（二进制里有 ___profc_）。" >&2
  echo "用 ENABLE_CODE_COVERAGE=NO CLANG_COVERAGE_MAPPING=NO 重编，或不带参数跑本脚本。" >&2
  exit 1
fi
VER="$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString)"
BUILD="$(defaults read "$APP/Contents/Info.plist" CFBundleVersion)"
STAGE="$(mktemp -d)/dmg"
TMPAPPLES="$(mktemp -d)/install.applescript"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/SimiGo.app"
# 发布门要求产物里不含构建路径（家目录前缀 + 用户名）。Release 编译会把 __FILE__ /
# #filePath 原样写进 __cstring，文本级清洗救不了 Mach-O，所以在此做等长擦除并
# 重新 adhoc 签名。只动路径字符串，不动指令；见 tools/redact_binary_paths.py。
python3 "$ROOT/tools/redact_binary_paths.py" "$STAGE/SimiGo.app/Contents/MacOS/SimiGo" --apply --no-backup
# 名字里的 hash 取擦除之后的那颗二进制：文件名必须描述真正发出去的东西。
EXE8="$(shasum -a 256 "$STAGE/SimiGo.app/Contents/MacOS/SimiGo" | cut -c1-8)"
OUT="$ROOT/SimiGo-v${VER}-${BUILD}-${EXE8}.dmg"
ln -s /Applications "$STAGE/Applications"
cat > "$TMPAPPLES" <<'OSA'
-- SimiGo 图形安装器（DMG 内双击运行）
set myDir to POSIX file ((do shell script "dirname " & quoted form of (POSIX path of (path to me))) & "/")
set src to POSIX path of myDir & "SimiGo.app"
-- 提示里的版本实读本 DMG 内待安装的 bundle；读不到就用不带版本号的通用文案，
-- 不显示可能与产物不符的固定版本。
set ver to ""
try
    set ver to do shell script "defaults read " & quoted form of (src & "/Contents/Info.plist") & " CFBundleShortVersionString"
end try
if ver is "" then
    set titleLine to "安装 SimiGo"
else
    set titleLine to "安装 SimiGo " & ver
end if
display dialog titleLine & return & return & "将把 SimiGo 安装到 /Applications（覆盖旧版本）。" & return & "安装完成后自动启动，进入安装向导。" buttons {"取消", "安装"} default button "安装" with icon note
-- 覆盖安装 = 重新进入安装向导：重置首启标记（不动数据库与已装二进制）
-- 主目录由系统解析（与产品 ManagedPaths 用的 homeDirectoryForCurrentUser 同一权威），
-- 不拼接固定的家目录前缀与用户名；求值发生在提权之前，
-- 故拿到的是当前用户的主目录，而不是提权后 root 的。
set markerPath to (POSIX path of (path to home folder)) & ".simigo/manifests/first-run-done.json"
do shell script "rm -rf /Applications/SimiGo.app && cp -R " & quoted form of src & " /Applications/SimiGo.app && rm -f " & quoted form of markerPath with administrator privileges
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
