#!/bin/bash
# Gate-closure item 2: run the G3 memory-tier memprobe ON THE RC1 BUILD PRODUCT
# itself - no rebuild, no re-sign, no copy - so tier A/B/C evidence is bound to
# the binary identity recorded in simigo-rc1-20261023/RC_IDENTITY.json.
#
# The experiment roots (IS home + KV cache) are ISOLATED inside this batch, so the
# real ~/.simigo IS/prefix-pool/branch-checkpoints are not used as experiment state.
# ONE known exception is recorded, not hidden: the RC1 binary resolves its trace
# log through a hardcoded home path (SimiGo/Observability/TraceLogger.swift:25),
# so it appends to the REAL ~/.simigo/logs/native_mlx_trace.log. That write is
# measured below and is the motivation for gate-closure item 1.
set -u
BATCH="/Users/mr.simi/SimiGo-Agent-Runs/simigo-rc1-gate-closure-20261023"
RC1="/Users/mr.simi/SimiGo-Agent-Runs/simigo-rc1-20261023"
APP="$RC1/derived/Build/Products/Debug/SimiGo.app"
BIN="$APP/Contents/MacOS/SimiGo"
MODEL="/Users/mr.simi/.cache/huggingface/hub/models--mlx-community--Qwen3-Coder-30B-A3B-Instruct-4bit/snapshots/6e302ea604ad9ab206367e2c501d1571023e7b6d"
MP="$BATCH/memprobe/${MP_ID:-mp1}"
RID="${MP_ID:-mp1}"
PTY="$BATCH/driver/pty_run.py"
EXPECTED_DYLIB="6e32892fe776f30bac69596d78d2d774513a656db901339ecfb7d7f3e0ad1b7b"
EXPECTED_TREE="842f72a68b7936fd6d5e33bb64af43b300920ec0c32fe6788574212a0df4bdc6"

mkdir -p "$MP"
rm -rf "$MP/home" "$MP/cache_mp"; mkdir -p "$MP/home" "$MP/cache_mp"

# Identity is captured with the RC1 tool itself (rc_artifact_identity.py), so the
# digest is comparable FOR DEFINITION with RC_IDENTITY.json. An earlier draft of this
# script recomputed the tree from (rel, bytes, mtime_ns) - a different formula that
# produced a different digest for an unchanged bundle. That draft bug is why the
# formula is not re-invented here.
identity() { # phase-name
  RC_APP="$APP" RC_OUT="$MP" RC_XCTESTRUN="$RC1/derived/Build/Products/SimiGo_SimiGo_macosx27.0-arm64.xctestrun" \
    python3 "$BATCH/driver/rc_artifact_identity.py" "$1" > "$MP/id_$1.json" 2>"$MP/id_$1.err" || return 9
  python3 -c "import json;print(json.load(open('$MP/id_$1.json'))['bundle_tree_sha256'])" > "$MP/id_$1.txt"
}

echo "== 0a. 受保护资源基线快照（扩大覆盖：整个 ~/.simigo + App Support + HF 缓存） =="
python3 "$BATCH/driver/rc_noninterference.py" "pre-$RID" | tee "$MP/snapshot_pre摘要.json"
identity identity-before

echo "== 0b. RC1 二进制身份门禁（必须是 RC_IDENTITY 里那一份，未重建/未重签名） =="
{
  printf "expected_dylib=%s\n" "$EXPECTED_DYLIB"
  printf "actual_dylib=%s\n" "$(shasum -a 256 "$APP/Contents/MacOS/SimiGo.debug.dylib" | cut -d' ' -f1)"
  printf "expected_bundle_tree=%s\n" "$EXPECTED_TREE"
  printf "actual_bundle_tree=%s\n" "$(cat "$MP/id_identity-before.txt")"
  printf "dylib_lc_uuid=%s\n" "$(dwarfdump --uuid "$APP/Contents/MacOS/SimiGo.debug.dylib" | awk '{print $2}' | head -1)"
  printf "codesign_identifier=%s\n" "$(codesign -dv "$APP" 2>&1 | awk -F= '/^Identifier=/{print $2}')"
} | tee "$MP/identity_gate.txt"
if ! grep -q "actual_dylib=$EXPECTED_DYLIB" "$MP/identity_gate.txt"; then echo "ABORT: RC1 dylib changed"; exit 9; fi
if ! grep -q "actual_bundle_tree=$EXPECTED_TREE" "$MP/identity_gate.txt"; then echo "ABORT: RC1 bundle tree changed"; exit 9; fi

echo "== 1. 启动独立 OS 侧 VM 采样器（外部进程，非产品自报） =="
: > "$MP/launcher.pid"
nohup python3 "$BATCH/driver/os_vm_sampler.py" "$MP/launcher.pid" "$MP/os_vm_series.jsonl" 1200 "${MP_INTERVAL:-1}" "$APP" >/dev/null 2>&1 &
SAMPLER=$!
echo "$SAMPLER" > "$MP/sampler.pid"; echo "sampler=$SAMPLER"

echo "== 2. 在 RC1 产物上执行 memprobe（角色 memprobe，隔离 home/cache 根） =="
date +%FT%T > "$MP/mp_start.txt"
SIMIGO_EXPERIMENT_ROOT="$MP" SIMIGO_RUN_ID="$RID" SIMIGO_HEADLESS_ROLE=memprobe \
SIMIGO_HEADLESS_MODEL_PATH="$MODEL" SIMIGO_HOME="$MP/home" SIMIGO_CACHE_ROOT="$MP/cache_mp" \
SIMIGO_HEADLESS_TARGET_VALUE="hello" SIMIGO_HEADLESS_MODEL_PATH="$MODEL" \
python3 "$PTY" "$MP/mp.log" -- "$BIN" --home "$MP/home" --model "$MODEL" --es-db "$MP/home/simigo.sqlite3" &
APP_PID=$!
echo "$APP_PID" > "$MP/launcher.pid"
wait $APP_PID; RC=$?
echo "mp rc=$RC" | tee "$MP/mp_rc.txt"
date +%FT%T > "$MP/mp_end.txt"
sleep 3; kill $SAMPLER 2>/dev/null || true

echo "== 3. 实验后产物身份 + 快照差分 =="
identity identity-after
python3 "$BATCH/driver/rc_noninterference.py" "post-$RID" | tee "$MP/snapshot_post摘要.json"
python3 "$BATCH/driver/rc_noninterference_diff.py" \
  "$BATCH/noninterference_pre-$RID.json" "$BATCH/noninterference_post-$RID.json" \
  "$BATCH/noninterference_diff_$RID-window.json" "$BATCH" \
  | tee "$MP/diff_summary.txt"
DYLIB_SAME_AFTER="$(python3 -c "
import json
b=json.load(open('$MP/id_identity-before.json'))['key_binaries']['SimiGo.debug.dylib']['sha256']
a=json.load(open('$MP/id_identity-after.json'))['key_binaries']['SimiGo.debug.dylib']['sha256']
print('YES' if b==a and b=='$EXPECTED_DYLIB' else 'NO')")"
{
  printf "bundle_tree_before=%s\n" "$(cat "$MP/id_identity-before.txt")"
  printf "bundle_tree_after=%s\n" "$(cat "$MP/id_identity-after.txt")"
  printf "rc1_dylib_unchanged_by_experiment=%s\n" "$DYLIB_SAME_AFTER"
} | tee "$MP/identity_gate_after.txt"

echo "== 4. 用 RC1 的核心路径证据 + 本次 memprobe 重算 G3（写入本批次，不动 RC1 冻结批次） =="
rm -rf "$MP/rc1_run_snapshot"; cp -R "$RC1/experiment/rc1" "$MP/rc1_run_snapshot"
python3 "$BATCH/driver/validate_g1_g3.py" "$MP/rc1_run_snapshot" rc1 "$MP" | tail -12
echo "GATE-CLOSURE MEMPROBE DONE"
