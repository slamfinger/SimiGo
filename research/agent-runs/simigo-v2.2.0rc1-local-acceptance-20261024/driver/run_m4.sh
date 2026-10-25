#!/bin/bash
# M4: ES1 -> IS settlement -> ES1 exit -> ES2 recovery -> real-model continuation,
# negative controls and memprobe, executed on the INSTALLED v2.2.0rc1 binary.
# Path class: restricted_production_path (in-app headless role). It is NOT the
# Service/HTTPServer dispatch; that boundary is reported separately, unrelaxed.
set -u
B=/Users/mr.simi/SimiGo-Agent-Runs/simigo-v2.2.0rc1-local-acceptance-20261024
APP="$B/install/SimiGo.app"
BIN="$APP/Contents/MacOS/SimiGo"
PTY="$B/driver/pty_run.py"
MODEL="/Users/mr.simi/.cache/huggingface/hub/models--mlx-community--Qwen3-Coder-30B-A3B-Instruct-4bit/snapshots/6e302ea604ad9ab206367e2c501d1571023e7b6d"
OTHER_MODEL="/Users/mr.simi/.cache/huggingface/hub/models--peculiar-ragdoll--Cyber-Tiel-Coder-35B-A3B-MLX-oQ4e/snapshots/b867c9dac94e521b9cabc59038fc6bf4b2f18e81"
RID="${1:-m4a}"
TARGET="${SIMIGO_EXPERIMENT_TARGET:-hello}"
BASE="${SIMIGO_COUNTERFACTUAL_BASELINE_VALUE:-world}"
RUN="$B/m4/$RID"
mkdir -p "$RUN"

{ echo "# M4 run $RID $(date -u +%FT%TZ)"
  echo "app=$APP"
  for img in SimiGo; do
    printf "exe_sha256=%s\n" "$(shasum -a 256 "$APP/Contents/MacOS/$img" | cut -d' ' -f1)"
    printf "exe_uuid=%s\n" "$(dwarfdump --uuid "$APP/Contents/MacOS/$img" 2>/dev/null | awk '{print $2}' | head -1)"
  done
  printf "app_version=%s build=%s\n" "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
  printf "codesign_designated=%s\n" "$(codesign -d -r- "$APP" 2>&1 | tail -1)"
  printf "model=%s\n" "$MODEL"
} > "$RUN/binary_identity.txt"

run_role() { local log="$1"; shift; python3 "$PTY" "$log" -- "$@"; }

echo "== ES1 produce (target=$TARGET) =="
rm -rf "$RUN/home" "$RUN/cache_es1"; mkdir -p "$RUN/home" "$RUN/cache_es1"
run_role "$RUN/es1.log" SIMIGO_HEADLESS_ROLE=produce SIMIGO_EXPERIMENT_ROOT="$RUN" SIMIGO_RUN_ID="$RID" SIMIGO_HOME="$RUN/home" SIMIGO_CACHE_ROOT="$RUN/cache_es1" SIMIGO_HEADLESS_MODEL_PATH="$MODEL" SIMIGO_HEADLESS_TARGET_VALUE="$TARGET" "$BIN"
echo "ES1 rc=$?" | tee "$RUN/es1_rc.txt"
PID_ES1="$(python3 -c "import json;print(json.load(open('$RUN/produce_$RID.json'))['pid'])" 2>/dev/null)"
if [ -n "$PID_ES1" ] && kill -0 "$PID_ES1" 2>/dev/null; then echo "ERROR ES1 still alive pid=$PID_ES1" | tee -a "$RUN/es1_rc.txt"; else echo "ES1 exited before ES2 - OK" | tee -a "$RUN/es1_rc.txt"; fi

STATE_ID="$(python3 -c "import json;print(json.load(open('$RUN/produce_handoff_$RID.json'))['state_id'])" 2>/dev/null)"
echo "state_id_from_handoff=$STATE_ID" | tee "$RUN/es2_state_id_source.txt"
if [ -z "$STATE_ID" ]; then echo "ERROR: no state_id"; exit 3; fi

echo "== ES2 consume (fresh empty cache root) =="
rm -rf "$RUN/cache_es2"; mkdir -p "$RUN/cache_es2"
find "$RUN/cache_es2" -type f | wc -l | tr -d ' ' > "$RUN/es2_cache_prelaunch.txt"
ES2_ENV=(SIMIGO_HEADLESS_ROLE=consume SIMIGO_EXPERIMENT_ROOT="$RUN" SIMIGO_RUN_ID="$RID"
  SIMIGO_HOME="$RUN/home" SIMIGO_CACHE_ROOT="$RUN/cache_es2" SIMIGO_HEADLESS_MODEL_PATH="$MODEL"
  SIMIGO_HEADLESS_STATE_ID="$STATE_ID"
  SIMIGO_HEADLESS_ES1_CACHE_IDENTITY="$(python3 -c "import json;print(json.load(open('$RUN/produce_$RID.json')).get('cache_identity',''))" 2>/dev/null)"
  SIMIGO_COUNTERFACTUAL_BASELINE_VALUE="$BASE")
printf "%s\n" "${ES2_ENV[@]}" | sed 's/=.*//' | sort > "$RUN/es2_env_keys.txt"
run_role "$RUN/es2.log" /usr/bin/env -u SIMIGO_EXPERIMENT_TARGET -u SIMIGO_HEADLESS_TARGET_VALUE "${ES2_ENV[@]}" "$BIN"
echo "ES2 rc=$?" | tee "$RUN/es2_rc.txt"

echo "== NC1 settlement missing (state S-9999) =="
run_role "$RUN/nc_missing.log" /usr/bin/env -u SIMIGO_EXPERIMENT_TARGET -u SIMIGO_HEADLESS_TARGET_VALUE SIMIGO_HEADLESS_ROLE=consume SIMIGO_EXPERIMENT_ROOT="$RUN" SIMIGO_RUN_ID="${RID}_ncmiss" SIMIGO_HOME="$RUN/home" SIMIGO_HEADLESS_MODEL_PATH="$MODEL" SIMIGO_HEADLESS_STATE_ID=S-9999 "$BIN"
echo "NC1 rc=$?" | tee "$RUN/nc1_rc.txt"

echo "== NC2 payload digest tamper (isolated DB copy) =="
rm -rf "$RUN/home_tamper"; cp -R "$RUN/home" "$RUN/home_tamper"
python3 - "$RUN/home_tamper/simigo.sqlite3" "$STATE_ID" <<'PY'
import sqlite3,sys
db,state=sys.argv[1],sys.argv[2]; c=sqlite3.connect(db)
n=c.execute("SELECT COUNT(*) FROM settlements WHERE state_id=?", (state,)).fetchone()[0]
assert n==1, "expected 1 settlement, found %d" % n
c.execute("UPDATE settlements SET payload=? WHERE state_id=?", (b'{"content":"TAMPERED","values":{"content":"TAMPERED"}}', state))
c.commit(); print("tampered", state)
PY
run_role "$RUN/nc_tamper.log" /usr/bin/env -u SIMIGO_EXPERIMENT_TARGET -u SIMIGO_HEADLESS_TARGET_VALUE SIMIGO_HEADLESS_ROLE=consume SIMIGO_EXPERIMENT_ROOT="$RUN" SIMIGO_RUN_ID="${RID}_nctamper" SIMIGO_HOME="$RUN/home_tamper" SIMIGO_HEADLESS_MODEL_PATH="$MODEL" SIMIGO_HEADLESS_STATE_ID="$STATE_ID" "$BIN"
echo "NC2 rc=$?" | tee "$RUN/nc2_rc.txt"

echo "== NC3 settlement invalidated (isolated DB copy) =="
rm -rf "$RUN/home_inval"; cp -R "$RUN/home" "$RUN/home_inval"
python3 - "$RUN/home_inval/simigo.sqlite3" "$STATE_ID" <<'PY'
import sqlite3,sys
c=sqlite3.connect(sys.argv[1])
c.execute("UPDATE settlements SET validity='invalid' WHERE state_id=?", (sys.argv[2],)); c.commit(); print("invalidated", sys.argv[2])
PY
run_role "$RUN/nc_inval.log" /usr/bin/env -u SIMIGO_EXPERIMENT_TARGET -u SIMIGO_HEADLESS_TARGET_VALUE SIMIGO_HEADLESS_ROLE=consume SIMIGO_EXPERIMENT_ROOT="$RUN" SIMIGO_RUN_ID="${RID}_ncinval" SIMIGO_HOME="$RUN/home_inval" SIMIGO_HEADLESS_MODEL_PATH="$MODEL" SIMIGO_HEADLESS_STATE_ID="$STATE_ID" "$BIN"
echo "NC3 rc=$?" | tee "$RUN/nc3_rc.txt"

echo "== NC4 model identity mismatch (same IS, different model path) =="
run_role "$RUN/nc_model.log" /usr/bin/env -u SIMIGO_EXPERIMENT_TARGET -u SIMIGO_HEADLESS_TARGET_VALUE SIMIGO_HEADLESS_ROLE=consume SIMIGO_EXPERIMENT_ROOT="$RUN" SIMIGO_RUN_ID="${RID}_ncmodel" SIMIGO_HOME="$RUN/home" SIMIGO_CACHE_ROOT="$RUN/cache_ncmodel" SIMIGO_HEADLESS_MODEL_PATH="$OTHER_MODEL" SIMIGO_HEADLESS_STATE_ID="$STATE_ID" "$BIN"
echo "NC4 rc=$?" | tee "$RUN/nc4_rc.txt"

echo "== NC5 invalid role =="
run_role "$RUN/nc_badrole.log" SIMIGO_HEADLESS_ROLE=bogus "$BIN"; echo "NC5 rc=$?" | tee "$RUN/nc5_rc.txt"

echo "== NC6 missing required param =="
run_role "$RUN/nc_missingparam.log" SIMIGO_HEADLESS_ROLE=produce SIMIGO_HEADLESS_TARGET_VALUE=hello "$BIN"; echo "NC6 rc=$?" | tee "$RUN/nc6_rc.txt"

echo "== NC7 value leaked into consume env (audit-1 guard) =="
run_role "$RUN/nc_leak.log" SIMIGO_HEADLESS_ROLE=consume SIMIGO_EXPERIMENT_ROOT="$RUN" SIMIGO_RUN_ID="${RID}_ncleak" SIMIGO_HOME="$RUN/home" SIMIGO_HEADLESS_MODEL_PATH="$MODEL" SIMIGO_HEADLESS_STATE_ID="$STATE_ID" SIMIGO_HEADLESS_TARGET_VALUE="$TARGET" "$BIN"
echo "NC7 rc=$?" | tee "$RUN/nc7_rc.txt"

echo "== memprobe (G3 memory tiers) =="
rm -rf "$RUN/home_mem" "$RUN/cache_mem"; mkdir -p "$RUN/home_mem" "$RUN/cache_mem"
run_role "$RUN/memprobe.log" SIMIGO_HEADLESS_ROLE=memprobe SIMIGO_EXPERIMENT_ROOT="$RUN" SIMIGO_RUN_ID="${RID}_mem" SIMIGO_HOME="$RUN/home_mem" SIMIGO_CACHE_ROOT="$RUN/cache_mem" SIMIGO_HEADLESS_MODEL_PATH="$MODEL" SIMIGO_HEADLESS_TARGET_VALUE="$TARGET" "$BIN"
echo "MEMPROBE rc=$?" | tee "$RUN/memprobe_rc.txt"
echo "DRIVER DONE RID=$RID"
