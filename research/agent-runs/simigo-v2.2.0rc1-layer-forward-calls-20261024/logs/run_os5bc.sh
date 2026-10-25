#!/bin/zsh
cd /Users/mr.simi/SimiGo-Agent-Runs/simigo-v2.2.0rc1-layer-forward-calls-20261024
for T in os5b os5c; do
  echo "=== $T start $(date +%H:%M:%S)"
  OS_PROBE_CANDIDATE="$PWD/install_v5/SimiGo.app" \
  OS_PROBE_RAW="$PWD/evidence/os_page_return_raw_${T}.json" \
  OS_PROBE_INTERVAL=0.01 OS_PROBE_BASELINE=20 \
  python3 driver/run_os_page_return.py "$T" > "logs/${T}_run.log" 2>&1
  echo "run rc=$?"
  python3 driver/verify_os_page_return.py "evidence/os_page_return_raw_${T}.json" \
    "evidence/os_page_return_verdict_${T}.json" 20 1500 > "logs/${T}_verify.log" 2>&1
  echo "verify rc=$? verdict=$(python3 -c "import json;print(json.load(open('evidence/os_page_return_verdict_${T}.json'))['verdict'], json.load(open('evidence/os_page_return_verdict_${T}.json'))['numbers']['kernel_returned_over_drop'])")"
done
echo "=== all done $(date +%H:%M:%S)"
