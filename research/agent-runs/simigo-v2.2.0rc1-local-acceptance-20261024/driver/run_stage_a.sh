#!/bin/bash
# M3 stage A (round 2): launch the INSTALLED v2.2.0rc1 app under three isolated
# roots, prove the running image is the installed binary, collect bootstrap and
# persistence evidence, quit, then restart from the same bundle and quit again.
set -u
B=/Users/mr.simi/SimiGo-Agent-Runs/simigo-v2.2.0rc1-local-acceptance-20261024
APP="$B/install/SimiGo.app"
BIN="$APP/Contents/MacOS/SimiGo"
OUT="$B/evidence/m3_stage_a_process.txt"
M3="$B/m3"
rm -rf "$M3"
mkdir -p "$M3/home" "$M3/cache" "$M3/state-graph"

{
echo "# M3 stage A round3 $(date -u +%FT%TZ)"
echo "# app bundle: $APP"
echo "# exe sha256 (on disk): $(shasum -a 256 "$BIN" | cut -d' ' -f1)"
echo "# exe uuid: $(dwarfdump --uuid "$BIN" | awk '{print $2}' | head -1)"
echo "launch_env:"
echo "  SIMIGO_HOME=$M3/home"
echo "  SIMIGO_CACHE_ROOT=$M3/cache"
echo "  SIMIGO_STATE_GRAPH_STORE=$M3/state-graph/reference-graph-v1.json"
} > "$OUT"

SIMIGO_HOME="$M3/home" SIMIGO_CACHE_ROOT="$M3/cache" \
SIMIGO_STATE_GRAPH_STORE="$M3/state-graph/reference-graph-v1.json" \
nohup "$BIN" > "$B/logs/stage_a_stdout.log" 2>&1 &
echo "launcher_pid=$!" >> "$OUT"
sleep 25
PID=$(pgrep -f "$BIN" | head -1)
echo "pid=$PID" >> "$OUT"
if [ -z "$PID" ]; then echo "ERROR app not running"; exit 5; fi
{
echo "--- ps ---"
ps -o pid,ppid,lstart,etime,command -p "$PID" | tail -2
echo "--- executable path (lsof txt) ---"
lsof -p "$PID" 2>/dev/null | awk '$4=="txt" {print $NF}' | head -5
echo "--- env SIMIGO_ (ps eww) ---"
ps eww -p "$PID" | tr ' ' '\n' | grep '^SIMIGO_' | sort
echo "--- running executable sha256 ---"
shasum -a 256 "$(ps -o command= -p "$PID" | awk '{print $1}')" | cut -d' ' -f1
echo "--- listening sockets ---"
lsof -nP -a -p "$PID" -iTCP -sTCP:LISTEN 2>/dev/null | tail -5 || true
echo "(no rows above = the app bound no TCP listener)"
} >> "$OUT"
sleep 20
{
echo "--- isolation root: m3/home ---"
find "$M3/home" -maxdepth 2 | sed "s|$B/||" | sort | head -40
echo "--- isolation root: m3/cache ---"
find "$M3/cache" -maxdepth 2 | sed "s|$B/||" | sort | head -20
echo "--- isolation root: m3/state-graph ---"
find "$M3/state-graph" -maxdepth 1 | sed "s|$B/||" | sort
echo "--- bootstrap report ---"
if [ -f "$M3/home/manifests/bootstrap-report.json" ]; then
  python3 -c "import json;d=json.load(open('$M3/home/manifests/bootstrap-report.json'));print(json.dumps({k:d.get(k) for k in ('modelsDiscovered','schemaVersion','issueCount','completedAt')},indent=1,ensure_ascii=False))"
else
  echo "bootstrap-report.json ABSENT"
fi
echo "--- sqlite tables ---"
if [ -f "$M3/home/simigo.sqlite3" ]; then
  sqlite3 "$M3/home/simigo.sqlite3" "select name from sqlite_master where type='table' order by name;" | tr '\n' ' '
  echo
fi
} >> "$OUT"

echo "--- quit (SIGTERM to test instance) ---" >> "$OUT"
kill -TERM "$PID" 2>/dev/null
for i in $(seq 1 20); do kill -0 "$PID" 2>/dev/null || break; sleep 1; done
if kill -0 "$PID" 2>/dev/null; then
  echo "quit_result=STILL_ALIVE after 20s" >> "$OUT"
else
  echo "quit_result=exited" >> "$OUT"
fi
echo "--- post-quit process check ---" >> "$OUT"
(ps -Ao pid,command | grep "$BIN" | grep -v grep) >> "$OUT" || echo "(no matching process)" >> "$OUT"

echo "--- restart from same bundle ---" >> "$OUT"
SIMIGO_HOME="$M3/home" SIMIGO_CACHE_ROOT="$M3/cache" \
SIMIGO_STATE_GRAPH_STORE="$M3/state-graph/reference-graph-v1.json" \
nohup "$BIN" > "$B/logs/stage_a_restart_stdout.log" 2>&1 &
sleep 20
PID2=$(pgrep -f "$BIN" | head -1)
echo "restart_pid=$PID2 (first_launch_pid=$PID)" >> "$OUT"
if [ -n "$PID2" ]; then
  ps -o pid,command -p "$PID2" | tail -1 >> "$OUT"
  ps eww -p "$PID2" | tr ' ' '\n' | grep '^SIMIGO_' | sort >> "$OUT"
  echo "--- persisted files (home) ---" >> "$OUT"
  ls -la "$M3/home/simigo.sqlite3"* 2>/dev/null | awk '{print $5, $6, $7, $8, $9}' >> "$OUT"
  kill -TERM "$PID2" 2>/dev/null
  sleep 5
  if kill -0 "$PID2" 2>/dev/null; then echo "restart_quit=STILL_ALIVE" >> "$OUT"; else echo "restart_quit=exited" >> "$OUT"; fi
fi
echo "STAGE_A_DONE" >> "$OUT"
