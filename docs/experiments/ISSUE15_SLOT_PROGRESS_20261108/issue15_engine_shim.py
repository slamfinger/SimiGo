#!/usr/bin/env python3
"""Issue #15 R2-A engine shim.

The Service launches this shim AS its llama-server (via the LlamaServerBin
config seam) with the production argument vector. The shim:

- spawns the REAL llama-server on an internal port Q (all original args kept,
  only --port rewritten) and manages its lifecycle (SIGTERM/SIGINT forwarding,
  abnormal-exit propagation, no leftovers on shim exit);
- forwards every HTTP path to Q verbatim EXCEPT /slots, which it answers from
  a controlled snapshot:
    SHIM_SLOTS_MODE=frozen    -> static busy snapshot (id_task/is_processing/
                                 counters never move)
    SHIM_SLOTS_MODE=passthrough -> verbatim from the real engine (R2-B
                                 false-kill control)

This keeps the Service's launch, health-check and slot-probe code paths
untouched: the Service observes whatever this shim decides /slots says.
"""
import json
import os
import signal
import sys
import threading
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

REAL_ENGINE = os.environ.get(
    "SHIM_REAL_ENGINE", str(Path.home() / ".simigo/bin/llama-server"))
MODE = os.environ.get("SHIM_SLOTS_MODE", "frozen")
# A2 orchestration: SHIM_HEALTH_MODE=fail makes /health return 503; with
# SHIM_SLOTS_FIRST=unknown the FIRST /slots observation is an empty list
# (unknown -> preflight not skipped) so the health check actually executes
# and fails, and every later /slots observation is the frozen busy snapshot
# (post-failure busy protection path). Real HTTP failures, product binary.
HEALTH_MODE = os.environ.get("SHIM_HEALTH_MODE", "pass")
slots_calls = {"n": 0}
# A2 state machine: waitReady probes pass through; after the first /slots
# observation (the unknown that keeps preflight active) exactly ONE /health
# request is answered 503 (a REAL transport-level failure), then everything
# passes through again. Branch-2 evidence without any build-time injection.
state = {"slots_seen": False, "health_fail_used": False}

FROZEN_SLOT = {
    "id": 0,
    "n_ctx": 8192,
    "speculative": False,
    "is_processing": True,
    "id_task": 424242,
    "n_prompt_tokens": 3416,
    "n_prompt_tokens_processed": 3416,
    "n_prompt_tokens_cache": 0,
    "next_token": [{"has_next_token": True, "n_remain": 100, "n_decoded": 777}],
    "prompt": "[frozen-by-issue15-shim]",
}

child = None


def parse_port(argv):
    for i, a in enumerate(argv):
        if a == "--port" and i + 1 < len(argv):
            return int(argv[i + 1])
    return 8080


def spawn_real(argv, internal_port):
    real_argv = []
    i = 0
    while i < len(argv):
        if argv[i] == "--port" and i + 1 < len(argv):
            real_argv += ["--port", str(internal_port)]
            i += 2
            continue
        real_argv.append(argv[i])
        i += 1
    log = open("/private/tmp/fifteen/shim_real_engine.log", "wb")
    return subprocess.Popen([REAL_ENGINE] + real_argv, stdout=log,
                            stderr=subprocess.STDOUT)


import subprocess  # noqa: E402


class Proxy(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *a):
        # R2-A observation: every request the Service makes through the shim
        # is part of the acceptance timeline (review 2026-11-08).
        import time as _t
        print(f"[shim-access] {_t.strftime('%H:%M:%S')} {self.command} {self.path}",
              flush=True)

    def _forward(self, method):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else None
        url = f"http://127.0.0.1:{INTERNAL_PORT}{self.path}"
        req = urllib.request.Request(url, data=body, method=method)
        for k, v in self.headers.items():
            if k.lower() not in ("host", "content-length", "connection"):
                req.add_header(k, v)
        try:
            with urllib.request.urlopen(req, timeout=600) as r:
                payload = r.read()
                self.send_response(r.status)
                self.send_header("Content-Type",
                                 r.headers.get("Content-Type", "application/json"))
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
        except Exception as exc:
            payload = json.dumps({"shim_error": repr(exc)}).encode()
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

    def do_GET(self):
        if self.path.startswith("/slots"):
            slots_calls["n"] += 1
            if slots_calls["n"] >= 1 and HEALTH_MODE == "fail":
                state["slots_seen"] = True
            first_unknown = (MODE == "frozen"
                             and slots_calls["n"] == 1
                             and os.environ.get("SHIM_SLOTS_FIRST") == "unknown")
            if MODE == "frozen" and not first_unknown:
                payload = json.dumps([dict(FROZEN_SLOT)]).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
                return
            if first_unknown:
                payload = b"[]"
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
                return
        if (self.path.startswith("/health") and HEALTH_MODE == "fail"
                and state["slots_seen"] and not state["health_fail_used"]):
            state["health_fail_used"] = True
            print("[shim] A2: armed /health failure fired (503, once)",
                  flush=True)
            payload = b'{"error":"issue15-a2-health-failure"}'
            self.send_response(503)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        self._forward("GET")

    def do_POST(self):
        self._forward("POST")


def main():
    global INTERNAL_PORT
    port = parse_port(sys.argv[1:])
    INTERNAL_PORT = port + 1
    child = spawn_real(sys.argv[1:], INTERNAL_PORT)

    def shutdown(signum, frame):
        # hard guarantee against leftovers: TERM first, then KILL after a
        # short grace window, then exit (review 2026-11-08: the shim owns
        # the real engine's lifecycle and must never leave it behind)
        child.terminate()
        try:
            child.wait(timeout=5)
        except Exception:
            child.kill()
            child.wait(timeout=5)
        os._exit(0)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    import atexit
    atexit.register(lambda: (child.poll() is None and child.kill()))

    def watchdog():
        rc = child.wait()
        print(f"[shim] real engine exited rc={rc}; shim exits too", flush=True)
        os._exit(rc or 0)

    threading.Thread(target=watchdog, daemon=True).start()

    server = ThreadingHTTPServer(("127.0.0.1", port), Proxy)
    print(f"[shim] listening on {port}, real engine on {INTERNAL_PORT}, "
          f"slots mode={MODE}", flush=True)
    try:
        server.serve_forever()
    finally:
        child.terminate()
        try:
            child.wait(timeout=5)
        except Exception:
            child.kill()


if __name__ == "__main__":
    main()
