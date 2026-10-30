#!/usr/bin/env python3
"""GGUF 4-slot engine experiment (route 04 blocked item).

Starts the installed llama-server shim with the product's launch arguments
(SIMIGO_LLAMA_PARALLEL=4), sends 4 concurrent chat completions that each carry
a distinct marker, then a 5th after they settle. Verifies per-request answers,
slot accounting and slot reclamation. Read-only w.r.t. user state.
"""
import json
import os
import signal
import subprocess
import sys
import threading
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

EV = os.path.dirname(os.path.abspath(__file__))
SHIM = os.path.expanduser("~/.simigo/bin/llama-server")
MODEL = os.path.expanduser(
    "~/.cache/huggingface/hub/models--LiquidAI--LFM2.5-24B-A2B-GGUF/"
    "snapshots/0912d33141f77e10705345a6732bfd83f0252fdc/LFM2.5-24B-A2B-Q6_K.gguf"
)
PORT = 59997
BASE = f"http://127.0.0.1:{PORT}"

args = [
    SHIM,
    "--model", MODEL,
    "--port", str(PORT),
    "--host", "127.0.0.1",
    "--alias", "lfm2.5-24b-a2b",
    "--parallel", "4",
    "--cache-prompt",
    "--slots",
    "--cache-type-k", "q4_0",
    "--cache-type-v", "q4_0",
    "-ngl", "999",
    "-b", "1024",
    "-ub", "512",
    "--ctx-size", "16384",
    "--flash-attn", "on",
    "--jinja",
]

server_log = open(os.path.join(EV, "server.log"), "wb")
started = time.time()
proc = subprocess.Popen(args, stdout=server_log, stderr=subprocess.STDOUT)

rss_samples = []
stop_sampler = threading.Event()


def sample_rss():
    while not stop_sampler.is_set():
        try:
            out = subprocess.check_output(
                ["ps", "-o", "rss=", "-p", str(proc.pid)], text=True).strip()
            if out:
                rss_samples.append((round(time.time() - started, 1), int(out) * 1024))
        except subprocess.CalledProcessError:
            break
        time.sleep(2)


sampler = threading.Thread(target=sample_rss, daemon=True)
sampler.start()


def get_json(path, timeout=30):
    with urllib.request.urlopen(BASE + path, timeout=timeout) as r:
        return json.loads(r.read().decode())


def post_chat(marker, tag):
    body = {
        "model": "lfm2.5-24b-a2b",
        "messages": [
            {"role": "system", "content": "You are a terse echo test."},
            {"role": "user", "content":
                f"Reply with exactly one token and nothing else: {marker}"},
        ],
        "temperature": 0,
        "max_tokens": 1024,
        "stream": False,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        BASE + "/v1/chat/completions", data=data,
        headers={"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=1800) as r:
        payload = json.loads(r.read().decode())
    dt = time.time() - t0
    msg_obj = payload["choices"][0]["message"]
    content = msg_obj.get("content") or ""
    usage = payload.get("usage", {})
    return {"tag": tag, "marker": marker, "content": content,
            "reasoning": msg_obj.get("reasoning_content"),
            "seconds": round(dt, 3), "usage": usage}


result = {"started_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
          "model": MODEL, "args": args, "port": PORT}

try:
    ready_at = None
    for _ in range(300):
        if proc.poll() is not None:
            raise SystemExit(f"engine exited early rc={proc.returncode}")
        try:
            get_json("/health", timeout=3)
            ready_at = round(time.time() - started, 1)
            break
        except Exception:
            time.sleep(2)
    if ready_at is None:
        raise SystemExit("engine did not become healthy in 600s")
    result["engine_ready_seconds"] = ready_at

    result["props"] = get_json("/props")
    result["slots_before"] = get_json("/slots")

    markers = ["ENGINE[ALPHA]", "ENGINE[BRAVO]", "ENGINE[CHARLIE]", "ENGINE[DELTA]"]
    tags = ["alpha", "bravo", "charlie", "delta"]
    batch_start = time.time()
    with ThreadPoolExecutor(max_workers=4) as pool:
        futures = [pool.submit(post_chat, m, t) for m, t in zip(markers, tags)]
        responses = [f.result() for f in futures]
    result["batch_seconds"] = round(time.time() - batch_start, 3)
    result["responses"] = responses

    checks = {}
    for r in responses:
        own = r["marker"] in r["content"]
        foreign = [m for m in markers if m != r["marker"] and m in r["content"]]
        foreign_any = [m for m in markers if m != r["marker"]
                       and (m in r["content"] or m in (r.get("reasoning") or ""))]
        checks[r["tag"]] = {
            "carries_own_marker": own,
            "foreign_markers": foreign,
            "foreign_markers_in_any_channel": foreign_any,
            "reasoning_has_own_marker": r["marker"] in (r.get("reasoning") or ""),
            "completion_tokens": r["usage"].get("completion_tokens"),
        }
    result["marker_checks"] = checks

    time.sleep(1.0)
    result["slots_after_batch"] = get_json("/slots")

    fifth = post_chat("ENGINE[ECHO]", "echo")
    result["fifth_request"] = fifth
    result["fifth_check"] = {
        "carries_own_marker": "ENGINE[ECHO]" in fifth["content"],
        "foreign_markers": [m for m in markers if m in fifth["content"]],
        "foreign_markers_in_any_channel": [
            m for m in markers
            if m in fifth["content"] or m in (fifth.get("reasoning") or "")],
    }
finally:
    stop_sampler.set()
    try:
        proc.send_signal(signal.SIGTERM)
        proc.wait(timeout=30)
    except Exception:
        proc.kill()
    server_log.close()

result["rss_peak_bytes"] = max((b for _, b in rss_samples), default=None)
result["rss_samples_head"] = rss_samples[:5]
result["rss_samples_tail"] = rss_samples[-5:]
result["server_exit_code"] = proc.returncode

with open(os.path.join(EV, "summary.json"), "w") as f:
    json.dump(result, f, ensure_ascii=False, indent=2)

print(json.dumps({
    "engine_ready_seconds": result.get("engine_ready_seconds"),
    "batch_seconds": result.get("batch_seconds"),
    "marker_checks": result.get("marker_checks"),
    "fifth_check": result.get("fifth_check"),
    "rss_peak_gb": round(result["rss_peak_bytes"] / 1e9, 2) if result["rss_peak_bytes"] else None,
    "server_exit_code": result["server_exit_code"],
}, ensure_ascii=False, indent=2))
