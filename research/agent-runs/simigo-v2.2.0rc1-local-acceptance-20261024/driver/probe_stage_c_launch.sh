#!/bin/bash
# Stage C (round 3): launch the INSTALLED candidate under the three isolated
# roots, wait for the product HTTPServer window, probe it WITHOUT relaxing auth,
# then quit. Attempt 1 (probe against no running process) is kept in
# logs/stage_c_probe_driver.log; this attempt is the recorded evidence.
set -u
B=/Users/mr.simi/SimiGo-Agent-Runs/simigo-v2.2.0rc1-local-acceptance-20261024
BIN="$B/install/SimiGo.app/Contents/MacOS/SimiGo"
M3C="$B/m3c"
rm -rf "$M3C"; mkdir -p "$M3C/home" "$M3C/cache" "$M3C/state-graph"
SIMIGO_HOME="$M3C/home" SIMIGO_CACHE_ROOT="$M3C/cache" \
SIMIGO_STATE_GRAPH_STORE="$M3C/state-graph/reference-graph-v1.json" \
  nohup "$BIN" > "$B/logs/stage_c_launch_stdout.log" 2>&1 &
LAUNCH_PID=$!
sleep 60
bash "$B/driver/probe_stage_c.sh" 180
{
  echo "# launch attempt: pid=$LAUNCH_PID (quit after probe)"
  echo "# isolated roots: $M3C"
} >> "$B/evidence/m3_stage_c_probe.txt"
kill -TERM "$LAUNCH_PID" 2>/dev/null
sleep 3
pkill -TERM -f "$BIN" 2>/dev/null
sleep 2
echo "stage_c_launch_done"
