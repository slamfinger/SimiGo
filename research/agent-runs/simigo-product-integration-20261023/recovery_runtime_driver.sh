#!/bin/bash
# Product-runtime mid-failure + recovery demonstration for autonomous bootstrap.
set -u
BIN="/Users/mr.simi/Documents/SimiGo-evofcdvfrduenndpdvzkbznpxpba/Build/Products/Debug/SimiGo.app/Contents/MacOS/SimiGo"
EV="$HOME/SimiGo-Agent-Runs/simigo-product-integration-20261023"
RT="$EV/recovery-runtime"
echo "=== prepare isolated managed root ==="
rm -rf "$RT"; mkdir -p "$RT"
printf 'not-a-directory' > "$RT/bin"
ls -la "$RT"
run_once () {
  local tag="$1"
  echo "=== RUN ($tag): launching product binary with SIMIGO_HOME=$RT ==="
  SIMIGO_HOME="$RT" "$BIN" >/tmp/simigo-rt-$tag.out 2>&1 &
  local pid=$!
  echo "pid=$pid"; sleep 5; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  echo "--- bootstrap log ---"; grep -i "SimiGo bootstrap" /tmp/simigo-rt-$tag.out || echo "(no bootstrap log)"
  local rep="$RT/manifests/bootstrap-report.json"
  if [ -f "$rep" ]; then
    cp "$rep" "$EV/bootstrap-report.$tag.json"
    echo "--- report ($tag) key facts ---"
    python3 "$EV/_summarize_report.py" "$rep"
  else
    echo "!! NO report written at $rep"
  fi
}
run_once "run1-obstacle"
echo "=== resolve obstacle: remove the 'bin' file ==="; rm -f "$RT/bin"
run_once "run2-recovered"
echo "=== final layout (must have NO work/ or models/) ==="; ls -1 "$RT"
