#!/usr/bin/env python3
"""Re-run ONLY the B-7 step-8 window (derived settlement as continuation
anchor) with a prompt that satisfies the continuation result contract
(`^RESULT=(.+)$` + equals_binding next_input).

The failed attempt is preserved verbatim in results-<nonce>.json inside
`chain_check` (422 NATIVE_RESULT_CONTRACT_REJECTED: the probe asked for plain
text, which that contract refuses by design). This script writes a separate
evidence file; it does not edit the earlier results.
"""
import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8000"
REPO = "/Users/mr.simi/Documents/SimiGo"
HOME = os.path.expanduser("~")
TRACE = os.path.join(HOME, ".simigo/logs/native_mlx_trace.log")
OUT = os.path.dirname(os.path.abspath(__file__))

GEN_KEYS = ("arrive", "prefill", "poolExport", "cacheSave", "session=",
            "RELEASED", "STATE_TRANSITION", "continuation_admitted")


def trace_offset():
    return os.path.getsize(TRACE) if os.path.exists(TRACE) else 0


def trace_since(off):
    with open(TRACE, "rb") as f:
        f.seek(off)
        return f.read().decode(errors="replace")


def post(path, payload, timeout=600):
    req = urllib.request.Request(
        BASE + path, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read().decode()), round(time.time() - t0, 3)
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        try:
            return e.code, json.loads(body), round(time.time() - t0, 3)
        except Exception:
            return e.code, {"raw": body}, round(time.time() - t0, 3)


def main(results_path):
    src = json.load(open(results_path))
    consumer_state = src["consumers"]["first"]["consumer_es_state_id"]
    settled_value = src["source"]["settled_value"].strip()
    model_id = src["identity"]["model_id"]

    prompt = ("只输出这一行，不要解释，不要引号：RESULT=%s" % settled_value)
    payload = {
        "model": model_id,
        "input": prompt,
        "max_output_tokens": 64,
        "previous_es_state_id": consumer_state,
        "continuation_settle": True,
    }
    off = trace_offset()
    status, body, secs = post("/v1/responses", payload)
    time.sleep(0.4)
    trace = trace_since(off)
    lines = [ln.strip() for ln in trace.splitlines()
             if any(k in ln for k in GEN_KEYS)]
    out_text = ""
    try:
        out_text = body["output"][0]["content"][0]["text"]
    except Exception:
        pass
    settlement = body.get("continuation_settlement") or {}
    record = {
        "anchor_consumer_state": consumer_state,
        "anchor_settled_value": settled_value,
        "prompt": prompt,
        "status": status,
        "seconds": secs,
        "output_text": out_text,
        "continuation_settlement": settlement,
        "body": body,
        "trace_lines": lines,
        "checks": {
            "status_200": status == 200,
            "settlement_recorded": bool(settlement.get("settlement_id")),
            "generation_ran": len(lines) > 0,
            "derived_settlement_was_anchor":
                (body.get("continuation_settlement") or {}).get(
                    "identity_binding_published") is not None,
        },
        "run_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "installed_exe_sha256": subprocess.run(
            ["shasum", "-a", "256",
             "/Applications/SimiGo.app/Contents/MacOS/SimiGo"],
            capture_output=True, text=True).stdout.split()[0],
    }
    record["checks"]["ok"] = all(record["checks"].values())
    path = os.path.join(
        OUT, "chain-retry-%s.json" % time.strftime("%Y%m%d-%H%M%S"))
    with open(path, "w") as f:
        json.dump(record, f, ensure_ascii=False, indent=1)
    print(json.dumps({k: record[k] for k in
                      ("status", "seconds", "output_text",
                       "continuation_settlement", "checks")},
                     ensure_ascii=False, indent=1))
    print("wrote", path)
    return 0 if record["checks"]["ok"] else 1


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else sorted(
        p for p in os.listdir(OUT) if p.startswith("results-"))[-1]
    sys.exit(main(os.path.join(OUT, path) if not os.path.isabs(path) else path))
