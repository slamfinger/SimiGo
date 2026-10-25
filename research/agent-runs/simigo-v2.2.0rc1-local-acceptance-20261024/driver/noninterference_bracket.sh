#!/bin/bash
# Round 2 residual attribution: the whole-batch pre/post diff reported exactly one
# real-root change, ~/.simigo/.DS_Store (Finder view metadata, Bud1 header). This
# bracket re-measures the protected roots immediately around one isolated launch of
# the installed candidate, so "does the candidate itself write user state?" is
# answered by a before/after pair that contains no other actor window.
set -u
B=/Users/mr.simi/SimiGo-Agent-Runs/simigo-v2.2.0rc1-local-acceptance-20261024
APP="$B/install/SimiGo.app"
BIN="$APP/Contents/MacOS/SimiGo"
ROOT="$B/m3-bracket"
OUT="$B/evidence/noninterference_bracket.txt"
mkdir -p "$ROOT/home" "$ROOT/cache" "$ROOT/state-graph"
: > "$OUT"

ds() { stat -f "bytes=%z mtime=%Sm sha=%Y" -t "%Y-%m-%dT%H:%M:%S" "$1" 2>/dev/null || echo ABSENT; }

cd /Users/mr.simi/Documents/SimiGo
echo "# bracket start $(date -u +%FT%TZ)" >> "$OUT"
echo "DS_Store_before: $(ds /Users/mr.simi/.simigo/.DS_Store)" >> "$OUT"
python3 tools/rc_noninterference.py --phase bracket_pre --out "$B/evidence/noninterference_bracket_pre.json" >/dev/null
echo "pre_snapshot_rc=$?" >> "$OUT"

SIMIGO_HOME="$ROOT/home" SIMIGO_CACHE_ROOT="$ROOT/cache" \
SIMIGO_STATE_GRAPH_STORE="$ROOT/state-graph/reference-graph-v1.json" \
nohup "$BIN" > "$B/logs/bracket_launch_stdout.log" 2>&1 &
LPID=$!
sleep 40
PID=$(pgrep -f "$BIN" | head -1)
echo "launcher_pid=$LPID pid=$PID" >> "$OUT"
echo "exe_sha256_on_disk=$(shasum -a 256 "$BIN" | cut -d' ' -f1)" >> "$OUT"
if [ -n "$PID" ]; then
  echo "--- env (ps eww) ---" >> "$OUT"
  ps eww -p "$PID" | tr ' ' '\n' | grep '^SIMIGO_' | sort >> "$OUT"
  echo "--- files created under isolated home ---" >> "$OUT"
  find "$ROOT/home" -maxdepth 2 | sed "s|$B/||" | sort | head -30 >> "$OUT"
  kill -TERM "$PID" 2>/dev/null
  for i in $(seq 1 20); do kill -0 "$PID" 2>/dev/null || break; sleep 1; done
  kill -0 "$PID" 2>/dev/null && echo "quit_result=STILL_ALIVE" >> "$OUT" || echo "quit_result=exited" >> "$OUT"
else
  echo "ERROR app did not start" >> "$OUT"
fi
echo "DS_Store_after: $(ds /Users/mr.simi/.simigo/.DS_Store)" >> "$OUT"
python3 tools/rc_noninterference.py --phase bracket_post --out "$B/evidence/noninterference_bracket_post.json" >/dev/null
echo "post_snapshot_rc=$?" >> "$OUT"
python3 tools/rc_noninterference_diff.py "$B/evidence/noninterference_bracket_pre.json" \
  "$B/evidence/noninterference_bracket_post.json" "$B/evidence/noninterference_bracket_diff.json" >> "$OUT" 2>&1
python3 - <<'PY' >> "$OUT"
import json
d=json.load(open("/Users/mr.simi/SimiGo-Agent-Runs/simigo-v2.2.0rc1-local-acceptance-20261024/evidence/noninterference_bracket_diff.json"))
print("bracket_violation_events=%s" % d.get("violation_events"))
print("bracket_real_user_state_write_count=%s" % d.get("real_user_state_write_count"))
print("bracket_paths=%s" % d.get("real_user_state_write_paths"))
PY
echo "BRACKET_DONE" >> "$OUT"
cat "$OUT"
