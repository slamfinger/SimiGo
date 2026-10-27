#!/bin/zsh
# C-0b: verify the admission-refusal classification fix at the REAL HTTP entry.
# Build happens OUTSIDE the window; the window is test-without-building only,
# inside an isolated xctestrun (three roots), with a bundle-inode sampler and a
# pre/post non-interference pair against the real user state.
set -u
ROOT=/Users/mr.simi/Documents/SimiGo
EV=$ROOT/research/agent-runs/simigo-es-is-realmodel-20261026/c0b-20261027-041301
APP=$ROOT/build/a2/test/Build/Products/Debug/SimiGo.app
BIN=$APP/Contents/MacOS/SimiGo
BUNDLE=$APP/Contents/PlugIns/SimiGoTests.xctest
SEED=$ROOT/build/a5/isolation/home
CLASS=SimiGoTests/ResponsesSettlementConsumptionHTTPTests
cd "$ROOT" || exit 3

echo "HEAD=$(git rev-parse HEAD)"
echo "WORKTREE_TRACKED_DIFF=$(git status --porcelain | wc -l | tr -d ' ')"
echo "WORKTREE_DIFF_SHA=$(git diff | shasum -a 256 | cut -d' ' -f1)"
echo "BINARY_SHA=$(shasum -a 256 "$BIN" | cut -d' ' -f1)"
echo "BINARY_MTIME=$(stat -f %Sm -t '%F %T' "$BIN")"
echo "TESTBUNDLE_SHA=$(shasum -a 256 "$BUNDLE/Contents/MacOS/SimiGoTests" | cut -d' ' -f1)"
echo "TESTBUNDLE_INODE=$(stat -f %i "$BUNDLE")"
echo "TESTBUNDLE_MTIME=$(stat -f %Sm -t '%F %T' "$BUNDLE")"

ISO=$EV/isolation
LOG=$EV/window.log
XCR=$EV/Test-refusal.xcresult
PRODDIR=$(dirname "$(dirname "$APP")")

rm -rf "$ISO"; mkdir -p "$ISO/home" "$ISO/cache" "$ISO/state-graph"
mkdir -p "$ISO/home/bin" "$ISO/home/manifests" "$ISO/home/logs" "$ISO/home/locks"
cp -R "$SEED/bin/." "$ISO/home/bin/" 2>/dev/null
cp -R "$SEED/manifests/." "$ISO/home/manifests/" 2>/dev/null

find "$PRODDIR" -maxdepth 1 -name 'xctestrun_isolated.xctestrun' -delete
BASE=$(find "$PRODDIR" -maxdepth 1 -name 'SimiGo_*.xctestrun' | head -1)
[[ -n "$BASE" ]] || { echo "NO_BASE_XCTESTRUN"; exit 4; }
python3 tools/make_isolated_xctestrun.py --app "$APP" --isolation-root "$ISO" \
  --base-xctestrun "$BASE" --record "$EV/xctestrun_isolation.json" || exit 4
XR=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["isolated_xctestrun"])' "$EV/xctestrun_isolation.json") || exit 4
[[ -f $XR ]] || { echo "NO_ISOLATED_XCTESTRUN"; exit 4; }

python3 tools/rc_noninterference.py --real-root "$HOME/.simigo" \
  --real-root "$HOME/Library/Application Support/SimiGo" --phase pre \
  --out "$EV/snapshot_pre.json"

(
  while sleep 2; do
    T=$(date "+%F %T")
    if [[ -e $BUNDLE ]]; then
      echo "$T BUNDLE_PRESENT inode=$(stat -f %i "$BUNDLE")"
    else
      echo "$T BUNDLE_MISSING"
    fi
    echo "$T $(sysctl -n vm.swapusage) free_mb=$(vm_stat | awk '/free/ {print $3}') load=$(sysctl -n vm.loadavg)"
  done
) > "$EV/watch.log" 2>&1 &
WATCH_PID=$!

rm -rf "$XCR"
xcodebuild test-without-building -xctestrun "$XR" \
  -destination 'platform=macOS' -only-testing:"$CLASS" \
  -resultBundlePath "$XCR" 2>&1 | tee "$LOG"
RC=${pipestatus[1]}
kill "$WATCH_PID" 2>/dev/null

cp "$ISO/home/logs/native_mlx_trace.log" "$EV/native_mlx_trace.log" 2>/dev/null

python3 tools/rc_noninterference.py --real-root "$HOME/.simigo" \
  --real-root "$HOME/Library/Application Support/SimiGo" --phase post \
  --out "$EV/snapshot_post.json"
python3 tools/rc_noninterference_diff.py "$EV/snapshot_pre.json" "$EV/snapshot_post.json" \
  "$EV/snapshot_diff.json" --allow-prefix "$EV" >/dev/null 2>&1

echo "WINDOW_RC=$RC"
echo "TESTCASES=$(grep -c 'Test Case .*\(passed\|failed\)' "$LOG")"
echo "FAILURES=$(grep -c 'error: -\[\|failed (' "$LOG")"
echo "ENGINE_COMPILE_IN_WINDOW=$(grep -c 'Building CXX' "$LOG")"
echo "COULD_NOT_LAUNCH=$(grep -c 'Could not launch' "$LOG")"
echo "BUNDLE_MISSING_IN_WINDOW=$(grep -c BUNDLE_MISSING "$EV/watch.log")"
echo "VIOLATIONS=$(python3 -c 'import json;d=json.load(open("'$EV'/snapshot_diff.json"));print(d.get("violation_events","unknown"))' 2>/dev/null)"
echo "REAL_USER_STATE_WRITES=$(python3 -c 'import json;d=json.load(open("'$EV'/snapshot_diff.json"));print(d.get("real_user_state_write_count","unknown"))' 2>/dev/null)"
grep -E "Test Case .*(passed|failed)|Executed [0-9]+ test" "$LOG" | tail -20
