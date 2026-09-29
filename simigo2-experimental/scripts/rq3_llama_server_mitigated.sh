#!/usr/bin/env bash
# Canonical mitigated llama-server profile for RQ3 active-concurrency probes.
# Required: MODEL_PATH. Optional environment overrides:
#   LLAMA_SERVER_BIN, LLAMA_HOST, LLAMA_PORT, LLAMA_THREADS, LLAMA_UBATCH
# Extra arguments are appended verbatim to llama-server.
set -euo pipefail

MODEL_PATH=${1:?usage: rq3_llama_server_mitigated.sh MODEL_PATH [extra llama-server args...]}
shift

LLAMA_SERVER_BIN=${LLAMA_SERVER_BIN:-$(command -v llama-server)}
LLAMA_HOST=${LLAMA_HOST:-127.0.0.1}
LLAMA_PORT=${LLAMA_PORT:-18080}
LLAMA_THREADS=${LLAMA_THREADS:-4}
LLAMA_UBATCH=${LLAMA_UBATCH:-2}

exec "$LLAMA_SERVER_BIN" \
  --host "$LLAMA_HOST" \
  --port "$LLAMA_PORT" \
  --model "$MODEL_PATH" \
  --ctx-size 2048 \
  --parallel 4 \
  --ubatch-size "$LLAMA_UBATCH" \
  --threads "$LLAMA_THREADS" \
  --threads-batch "$LLAMA_THREADS" \
  --no-cache-prompt \
  --no-cache-idle-slots \
  --cache-ram 0 \
  --slot-prompt-similarity 0.0 \
  "$@"
