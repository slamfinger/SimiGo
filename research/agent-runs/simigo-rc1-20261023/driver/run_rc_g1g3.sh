#!/bin/bash
# RC driver (step 4): minimal ES1 -> IS settlement -> ES1 exit -> ES2 recovery -> real-model
# continuation, executed on the SAME artifact that was built and tested in this RC batch.
# Launches independent product processes (ES1 produce, ES2 consume) and negative
# controls against ISOLATED copies of the experiment DB. Never touches the real
# or sealed database. Uses pty_run.py so the GUI app runs in-process (a pipe/
# file redirect would make macOS detach it and lose the headless env).
set -u
SRC_APP="${RC_SRC_APP:-/Users/mr.simi/SimiGo-Agent-Runs/simigo-rc1-20261023/derived/Build/Products/Debug/SimiGo.app}"
MODEL="/Users/mr.simi/.cache/huggingface/hub/models--mlx-community--Qwen3-Coder-30B-A3B-Instruct-4bit/snapshots/6e302ea604ad9ab206367e2c501d1571023e7b6d"
G1G3="/Users/mr.simi/SimiGo-Agent-Runs/simigo-rc1-20261023/experiment"
RID="${1:-r6}"
REPO="${RC_REPO:-/Users/mr.simi/Documents/SimiGo}"
TARGET="${SIMIGO_EXPERIMENT_TARGET:-hello}"
BASELINE="${SIMIGO_COUNTERFACTUAL_BASELINE_VALUE:-}"
POISON="${SIMIGO_POISON_ES1_CACHE:-0}"
RUN="$G1G3/$RID"
# RC: execute the SAME bytes that were built and tested - no copy, no re-sign.
ISO_APP="$SRC_APP"
ISO_BIN="$ISO_APP/Contents/MacOS/SimiGo"
PTY="/Users/mr.simi/SimiGo-Agent-Runs/simigo-rc1-20261023/driver/pty_run.py"
mkdir -p "$RUN"
# RC step 4: identity is byte-for-byte; therefore copy/rewrite/re-sign are deliberately NOT done.

# Binary identity (audit 3): ties every claim below to ONE concrete build.
{
  echo "# binary identity for run $RID ($(date +%FT%T))"
  printf "src_app=%s\n" "$SRC_APP"
  printf "src_exe_mtime=%s\n" "$(stat -f %Sm -t %FT%T "$SRC_APP/Contents/MacOS/SimiGo" 2>/dev/null)"
  # The Debug launcher is ~40 KB; the code lives in SimiGo.debug.dylib. Record
  # content digests AND LC_UUID for both, src (build product) vs iso (executed).
  for img in SimiGo SimiGo.debug.dylib; do
    key="$(echo "$img" | tr '.' '_')"
    printf "src_%s_sha256=%s\n" "$key" "$(shasum -a 256 "$SRC_APP/Contents/MacOS/$img" 2>/dev/null | cut -d' ' -f1)"
    printf "src_%s_uuid=%s\n" "$key" "$(dwarfdump --uuid "$SRC_APP/Contents/MacOS/$img" 2>/dev/null | awk '{print $2}' | head -1)"
    printf "iso_%s_sha256=%s\n" "$key" "$(shasum -a 256 "$ISO_APP/Contents/MacOS/$img" 2>/dev/null | cut -d' ' -f1)"
    printf "iso_%s_uuid=%s\n" "$key" "$(dwarfdump --uuid "$ISO_APP/Contents/MacOS/$img" 2>/dev/null | awk '{print $2}' | head -1)"
  done
  printf "xcodebuild=%s\n" "$(xcodebuild -version 2>/dev/null | tr '\n' ' ')"
} > "$RUN/binary_identity_$RID.txt"

run_role() { # logfile expkey runid home extra-env... 
  local log="$1"; shift
  python3 "$PTY" "$log" -- "$@"
}

# Source identity for this run: which product sources produced the evidence.
{
  echo "# source digests at run $RID ($(date +%FT%T))"
  for f in SimiGo/Inference/NativeMLX.swift SimiGo/Inference/NativeMLXObservation.swift \
           SimiGo/Headless/SimiGoG1G3Entry.swift \
           Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoSettlementAuthority.swift \
           Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift \
           Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoModelDiscovery.swift; do
    printf "%s  %s\n" "$(shasum -a 256 "$REPO/$f" | cut -d" " -f1)" "$f"
  done
  printf "%s  %s\n" "$(shasum -a 256 "/Users/mr.simi/SimiGo-Agent-Runs/simigo-rc1-20261023/driver/run_rc_g1g3.sh" | cut -d" " -f1)" "driver/run_rc_g1g3.sh"
  printf "%s  %s\n" "$(shasum -a 256 "/Users/mr.simi/SimiGo-Agent-Runs/simigo-rc1-20261023/driver/validate_g1_g3.py" | cut -d" " -f1)" "driver/validate_g1_g3.py"
} > "$RUN/source_digests_$RID.txt"

echo "== ES1 produce (target=$TARGET) =="
rm -rf "$RUN/home" "$RUN/cache_es1"; mkdir -p "$RUN/home" "$RUN/cache_es1"
date +%FT%T > "$RUN/es1_start.txt"
run_role "$RUN/es1.log" SIMIGO_HEADLESS_ROLE=produce SIMIGO_EXPERIMENT_ROOT="$RUN" SIMIGO_RUN_ID="$RID" SIMIGO_HOME="$RUN/home" SIMIGO_CACHE_ROOT="$RUN/cache_es1" SIMIGO_HEADLESS_MODEL_PATH="$MODEL" SIMIGO_HEADLESS_TARGET_VALUE="$TARGET" "$ISO_BIN"
echo "ES1 rc=$?" | tee "$RUN/es1_rc.txt"
if kill -0 "$(python3 -c "import json;print(json.load(open('$RUN/produce_$RID.json'))['pid'])" 2>/dev/null)" 2>/dev/null; then
  echo "ERROR ES1 still alive" | tee -a "$RUN/es1_rc.txt"
else
  echo "ES1 exited before ES2 - OK" | tee -a "$RUN/es1_rc.txt"
fi

echo "== ES2 consume (positive, shared IS, FRESH EMPTY cache root) =="
rm -rf "$RUN/cache_es2"; mkdir -p "$RUN/cache_es2"
# The addressed state id comes from ES1's own handoff, not a driver literal.
STATE_ID="$(python3 -c "import json;print(json.load(open('$RUN/produce_handoff_$RID.json'))['state_id'])" 2>/dev/null)"
if [ -z "$STATE_ID" ]; then echo "ERROR: no state_id in produce_handoff_$RID.json"; exit 3; fi
echo "produce_handoff_$RID.json:state_id=$STATE_ID" > "$RUN/es2_state_id_source_$RID.txt"
# ES2's cache root must be empty at launch (recorded, not assumed afterwards).
find "$RUN/cache_es2" -type f | wc -l | tr -d ' ' > "$RUN/es2_cache_prelaunch_$RID.txt"

# The ES2 environment is passed inline (not exported), so record the EXACT key set
# the child receives instead of the parent shell's env: that is what makes
# "no target-value channel" a checkable fact rather than an assumption.
ES2_ENV=(
  SIMIGO_HEADLESS_ROLE=consume
  SIMIGO_EXPERIMENT_ROOT="$RUN"
  SIMIGO_RUN_ID="$RID"
  SIMIGO_HOME="$RUN/home"
  SIMIGO_CACHE_ROOT="$RUN/cache_es2"
  SIMIGO_HEADLESS_MODEL_PATH="$MODEL"
  SIMIGO_HEADLESS_STATE_ID="$STATE_ID"
  SIMIGO_HEADLESS_ES1_CACHE_IDENTITY="$(python3 -c "import json;print(json.load(open('$RUN/produce_$RID.json')).get('cache_identity',''))" 2>/dev/null)"
  SIMIGO_COUNTERFACTUAL_BASELINE_VALUE="$BASELINE"
)
printf "%s\n" "${ES2_ENV[@]}" | sed 's/=.*//' | sort > "$RUN/es2_env_keys_$RID.txt"
env | grep -E '^SIMIGO_' | sed 's/=.*//' | sort > "$RUN/es2_inherited_env_keys_$RID.txt" || true
date +%FT%T > "$RUN/es2_start.txt"

# ES1 carrier manifest BEFORE poisoning: proves ES2 neither rewrote nor deleted it.
find "$RUN/cache_es1" -type f -exec shasum -a 256 {} \; | sort > "$RUN/cache_es1_manifest_before_$RID.txt"
if [ "$POISON" = "1" ]; then
  # Dependency test: make ES1's on-disk KV unreadable while ES2 runs. If ES2 still
  # recovers U1 from IS and generates U2, it provably does not depend on ES1's KV.
  chmod -R 000 "$RUN/cache_es1" 2>/dev/null || true
  echo "cache_es1 chmod 000 before ES2 launch (poisoned carrier test)" > "$RUN/es1_cache_poisoned_$RID.txt"
fi
# Scrub every env var that could carry the produced value: the child must see
# NONE of them. /usr/bin/env removes them, then applies the ES2_ENV assignments.
run_role "$RUN/es2.log" /usr/bin/env -u SIMIGO_EXPERIMENT_TARGET -u SIMIGO_HEADLESS_TARGET_VALUE "${ES2_ENV[@]}" "$ISO_BIN"
echo "ES2 rc=$?" | tee "$RUN/es2_rc.txt"
if [ "$POISON" = "1" ]; then
  chmod -R 755 "$RUN/cache_es1" 2>/dev/null || true
  echo "cache_es1 permissions restored after ES2 (evidence preserved)" >> "$RUN/es1_cache_poisoned_$RID.txt"
fi
find "$RUN/cache_es1" -type f -exec shasum -a 256 {} \; | sort > "$RUN/cache_es1_manifest_after_$RID.txt"
if diff -q "$RUN/cache_es1_manifest_before_$RID.txt" "$RUN/cache_es1_manifest_after_$RID.txt" >/dev/null 2>&1; then
  echo "unchanged" > "$RUN/cache_es1_unchanged_during_es2_$RID.txt"
else
  echo "CHANGED" > "$RUN/cache_es1_unchanged_during_es2_$RID.txt"
fi

echo "== NC1 consume missing settlement (S-9999) =="
run_role "$RUN/nc_missing.log" /usr/bin/env -u SIMIGO_EXPERIMENT_TARGET -u SIMIGO_HEADLESS_TARGET_VALUE SIMIGO_HEADLESS_ROLE=consume SIMIGO_EXPERIMENT_ROOT="$RUN" SIMIGO_RUN_ID="${RID}_ncmiss" SIMIGO_HOME="$RUN/home" SIMIGO_HEADLESS_MODEL_PATH="$MODEL" SIMIGO_HEADLESS_STATE_ID=S-9999 "$ISO_BIN"
echo "NC1 rc=$?" | tee "$RUN/nc1_rc.txt"

echo "== NC2 digest tamper (isolated copy) =="
rm -rf "$RUN/home_tamper"; cp -R "$RUN/home" "$RUN/home_tamper"
python3 - "$RUN/home_tamper/simigo.sqlite3" "$STATE_ID" <<'PY'
import sqlite3,sys
db,state=sys.argv[1],sys.argv[2]; c=sqlite3.connect(db)
n=c.execute("SELECT COUNT(*) FROM settlements WHERE state_id=?", (state,)).fetchone()[0]
assert n==1, f"expected exactly 1 settlement for {state}, found {n}"
c.execute("UPDATE settlements SET payload=? WHERE state_id=?",
          (b'{"content":"TAMPERED","values":{"content":"TAMPERED"}}', state))
c.commit(); print("tampered state", state)
PY
rm -f "$RUN/consume_${RID}_nctamper.json"
run_role "$RUN/nc_tamper.log" /usr/bin/env -u SIMIGO_EXPERIMENT_TARGET -u SIMIGO_HEADLESS_TARGET_VALUE SIMIGO_HEADLESS_ROLE=consume SIMIGO_EXPERIMENT_ROOT="$RUN" SIMIGO_RUN_ID="${RID}_nctamper" SIMIGO_HOME="$RUN/home_tamper" SIMIGO_HEADLESS_MODEL_PATH="$MODEL" SIMIGO_HEADLESS_STATE_ID="$STATE_ID" "$ISO_BIN"
echo "NC2 rc=$?" | tee "$RUN/nc2_rc.txt"

echo "== NC3 invalidated settlement (isolated copy) =="
rm -rf "$RUN/home_inval"; cp -R "$RUN/home" "$RUN/home_inval"
python3 - "$RUN/home_inval/simigo.sqlite3" "$STATE_ID" <<'PY'
import sqlite3,sys
db=sys.argv[1]; c=sqlite3.connect(db)
try:
  c.execute("UPDATE settlements SET validity='invalid' WHERE state_id=?", (sys.argv[2],)); c.commit(); print("invalidated", sys.argv[2])
except Exception as e: print("inval err",e)
PY
rm -f "$RUN/consume_${RID}_ncinval.json"
run_role "$RUN/nc_inval.log" /usr/bin/env -u SIMIGO_EXPERIMENT_TARGET -u SIMIGO_HEADLESS_TARGET_VALUE SIMIGO_HEADLESS_ROLE=consume SIMIGO_EXPERIMENT_ROOT="$RUN" SIMIGO_RUN_ID="${RID}_ncinval" SIMIGO_HOME="$RUN/home_inval" SIMIGO_HEADLESS_MODEL_PATH="$MODEL" SIMIGO_HEADLESS_STATE_ID="$STATE_ID" "$ISO_BIN"
echo "NC3 rc=$?" | tee "$RUN/nc3_rc.txt"

echo "== NC4 invalid role =="
run_role "$RUN/nc_badrole.log" SIMIGO_HEADLESS_ROLE=bogus "$ISO_BIN"; echo "NC4 rc=$?" | tee "$RUN/nc4_rc.txt"

echo "== NC6 consume rejects leaked target value (audit 1 guard) =="
rm -f "$RUN/consume_${RID}_ncleak.json"
run_role "$RUN/nc_leak.log" SIMIGO_HEADLESS_ROLE=consume SIMIGO_EXPERIMENT_ROOT="$RUN" SIMIGO_RUN_ID="${RID}_ncleak" SIMIGO_HOME="$RUN/home" SIMIGO_HEADLESS_MODEL_PATH="$MODEL" SIMIGO_HEADLESS_STATE_ID="$STATE_ID" SIMIGO_HEADLESS_TARGET_VALUE="$TARGET" "$ISO_BIN"
echo "NC6 rc=$?" | tee "$RUN/nc6_rc.txt"

echo "== NC7 consume rejects inherited experiment-target channel (audit 1 guard) =="
rm -f "$RUN/consume_${RID}_ncleak2.json"
run_role "$RUN/nc_leak2.log" SIMIGO_HEADLESS_ROLE=consume SIMIGO_EXPERIMENT_ROOT="$RUN" SIMIGO_RUN_ID="${RID}_ncleak2" SIMIGO_HOME="$RUN/home" SIMIGO_HEADLESS_MODEL_PATH="$MODEL" SIMIGO_HEADLESS_STATE_ID="$STATE_ID" SIMIGO_EXPERIMENT_TARGET="$TARGET" "$ISO_BIN"
echo "NC7 rc=$?" | tee "$RUN/nc7_rc.txt"

echo "== NC5 missing required param =="
run_role "$RUN/nc_missingparam.log" SIMIGO_HEADLESS_ROLE=produce SIMIGO_HEADLESS_TARGET_VALUE=hello "$ISO_BIN"; echo "NC5 rc=$?" | tee "$RUN/nc5_rc.txt"

echo "DRIVER DONE RID=$RID"
