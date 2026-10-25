#!/bin/bash
# Stage C probe (round 2): wait for the installed RC binary to bind its product
# HTTPServer, then probe the route WITHOUT relaxing auth. Never sends a valid
# LOCALB proof: the authorized leg stays BLOCKED by design.
set -u
B=/Users/mr.simi/SimiGo-Agent-Runs/simigo-v2.2.0rc1-local-acceptance-20261024
OUT="$B/evidence/m3_stage_c_probe.txt"
BIN="$B/install/SimiGo.app/Contents/MacOS/SimiGo"
MODEL="/Users/mr.simi/.cache/huggingface/hub/models--mlx-community--Qwen3-Coder-30B-A3B-Instruct-4bit/snapshots/6e302ea604ad9ab206367e2c501d1571023e7b6d"
WAIT=${1:-420}

{
echo "# M3 stage C probe round3 $(date -u +%FT%TZ)"
echo "# target: installed RC binary $BIN"
echo "# method: poll this pid's listening socket, then probe the product HTTPServer"
echo "# auth policy: NO relaxation. No valid LOCALB proof is fabricated."
} > "$OUT"

PORT=""
PID=""
# Every matching pid is checked: the RC binary runs as a parent/child pair and
# only the child that owns the model binds the HTTPServer.
for i in $(seq 1 $WAIT); do
  for cand in $(pgrep -f "$BIN"); do
    p=$(lsof -nP -a -p "$cand" -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR==2 {print $9}' | sed 's/.*://')
    if [ -n "$p" ]; then PID=$cand; PORT=$p; break 2; fi
  done
  sleep 1
done

if [ -z "$PORT" ]; then
  { echo "listening_socket_found=0"
    echo "authorized_request_completed=0"
    echo "probe_result=NO_SOCKET_WINDOW OBSERVED"; } >> "$OUT"
  exit 0
fi

{
echo "pid=$PID"
echo "bound_port=$PORT"
echo "listening_socket_found=1"
echo "--- bind (lsof) ---"
lsof -nP -a -p "$PID" -iTCP -sTCP:LISTEN
echo "--- bind address (netstat) ---"
netstat -an | grep "[.]$PORT " | head -3
echo "--- plain HTTP POST /v1/chat/completions (no proof) ---"
curl -sS -m 8 -o /tmp/rc2c_body.txt -w "http_status=%{http_code}\n" \
  -X POST "http://127.0.0.1:$PORT/v1/chat/completions" -H 'content-type: application/json' \
  -d '{"model":"m","messages":[{"role":"user","content":"hi"}],"max_tokens":4}' 2>&1 || true
head -c 300 /tmp/rc2c_body.txt 2>/dev/null; echo
echo "--- TLS handshake (openssl s_client, no client cert) ---"
(openssl s_client -connect "127.0.0.1:$PORT" -servername localhost -brief </dev/null 2>&1 | head -12) || true
echo "--- HTTPS GET /health with -k (no pin, no proof) ---"
curl -skS -m 8 -o /tmp/rc2c_health.txt -w "http_status=%{http_code} tls_verify=%{ssl_verify_result}\n" \
  "https://127.0.0.1:$PORT/health" 2>&1 || true
head -c 300 /tmp/rc2c_health.txt 2>/dev/null; echo
echo "--- HTTPS POST /v1/chat/completions with bogus LOCALB proof-v2 ---"
curl -skS -m 8 -o /tmp/rc2c_body2.txt -w "http_status=%{http_code}\n" \
  -X POST "https://127.0.0.1:$PORT/v1/chat/completions" -H 'content-type: application/json' \
  -H 'x-simigo-localb-client-key-id: probe' \
  -H "x-simigo-localb-challenge: $(printf '0%.0s' $(seq 1 32))" \
  -H "x-simigo-localb-proof-v2: $(printf '0%.0s' $(seq 1 64))" \
  -d '{"model":"m","messages":[{"role":"user","content":"hi"}],"max_tokens":4}' 2>&1 || true
head -c 400 /tmp/rc2c_body2.txt 2>/dev/null; echo
echo "authorized_request_completed=0"
echo "authorization_relaxed=0"
echo "probe_result=UNAUTHORIZED_LEG_ONLY"
} >> "$OUT" 2>&1
