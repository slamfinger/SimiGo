#!/usr/bin/env python3
"""Issue #15 Round 1 (corrected): real llama.cpp slot-progress measurement.

Corrections over the a1457df collector (review 2026-11-08):
- n_decoded is read from slot.next_token[0].n_decoded (the b11720 schema has
  NO top-level n_decoded; the old collector read the wrong place and captured
  null for every decode sample).
- The cancel scenario samples CONTINUOUSLY from the exact client-close
  timestamp until the slot is observed idle (the old collector stopped
  sampling at close and only resumed 10 s later, so the release latency was
  unproven).
- Raw rows keep whatever the schema offers; analysis segments per id_task and
  per phase (see analyze_slots_v2.py).

Measurement only: no recovery policy is changed or consulted.
"""
import json
import subprocess
import sys
import threading
import time
import urllib.request
from pathlib import Path

SERVER = "/private/tmp/fifteen/bin/llama-server"
MODEL = str(Path.home() / ".cache/huggingface/hub/gemma-4-12b-it-Q4_K_M.gguf")
PORT = 8917
BASE = f"http://127.0.0.1:{PORT}"
EV = Path(__file__).parent / ("evidence" if len(sys.argv) < 2 else sys.argv[1])
INTERVAL = 0.5


def slot_view(s):
    """Project one slot dict to the counters this experiment tracks."""
    next_token = (s.get("next_token") or [None])[0] or {}
    return {
        "id_task": s.get("id_task"),
        "is_processing": s.get("is_processing"),
        "n_prompt_tokens_processed": s.get("n_prompt_tokens_processed"),
        "n_prompt_tokens": s.get("n_prompt_tokens"),
        "n_decoded": next_token.get("n_decoded"),
        "n_remain": next_token.get("n_remain"),
    }


class Sampler:
    def __init__(self):
        self.rows = []
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self._loop, daemon=True)

    def _loop(self):
        while not self.stop.is_set():
            t = time.time()
            try:
                with urllib.request.urlopen(BASE + "/slots", timeout=2) as r:
                    slots = json.loads(r.read())
                t_resp = time.time()
            except Exception as exc:
                self.rows.append({"t": t, "error": repr(exc)})
            else:
                # t/t_resp bracket the /slots observation: a state change is
                # only proven to lie within [t, t_resp] of the sample that
                # first saw it (review 2026-11-08, detail 1).
                self.rows.append({
                    "t": t,
                    "t_resp": t_resp,
                    "slots": [slot_view(s) for s in slots],
                })
            self.stop.wait(INTERVAL)

    def start(self):
        self.thread.start()

    def idle_seen(self, after_t):
        for r in reversed(self.rows):
            if "slots" in r and r["t"] >= after_t:
                if not any(s["is_processing"] for s in r["slots"]):
                    return r["t"]
        return None

    def stop_and_save(self, name):
        self.stop.set()
        self.thread.join(timeout=3)
        out = EV / f"samples_{name}.jsonl"
        with open(out, "w") as fh:
            for row in self.rows:
                fh.write(json.dumps(row) + "\n")
        return len(self.rows)


def post(path, payload, timeout=600):
    body = json.dumps(payload).encode()
    req = urllib.request.Request(
        BASE + path, data=body, headers={"Content-Type": "application/json"})
    start = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read()), start, time.time()
    except Exception as exc:
        return None, repr(exc), start, time.time()


def wait_ready(deadline=240):
    start = time.time()
    while time.time() - start < deadline:
        try:
            with urllib.request.urlopen(BASE + "/health", timeout=2) as r:
                if r.status == 200:
                    return time.time() - start
        except Exception:
            pass
        time.sleep(1)
    raise SystemExit("server never became healthy")


def chat(prompt, max_tokens):
    return post("/v1/chat/completions", {
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": 0.0,
    })


def big_prompt(tokens=3000):
    unit = ("The lighthouse keeper wrote a numbered line of the log every hour; "
            "each line recorded the wind, the swell and the lamps. ")
    reps = max(1, tokens // len(unit.split()))
    return unit * reps + "\nNow summarize the log in one short sentence."


def main():
    EV.mkdir(parents=True, exist_ok=True)
    proc = subprocess.Popen(
        [SERVER,
         "--model", MODEL,
         "--port", str(PORT),
         "--host", "127.0.0.1",
         "--alias", "issue15-measure",
         "--parallel", "1",
         "--cache-prompt",
         "--slots",
         "--cache-type-k", "q4_0",
         "--cache-type-v", "q4_0",
         "-ngl", "99",
         "-b", "1024",
         "-ub", "512",
         "--ctx-size", "8192",
         "--flash-attn", "on"],
        stdout=open(EV / "server.log", "wb"),
        stderr=subprocess.STDOUT)
    try:
        print(f"server ready in {wait_ready():.1f}s", flush=True)
        results = {}

        s = Sampler(); s.start()
        _, _, t0, t1 = chat("Name three colours.", 256)
        results["normal"] = {"wall": round(t1 - t0, 2),
                             "samples": s.stop_and_save("normal")}

        s = Sampler(); s.start()
        _, _, t0, t1 = chat("Count from one to two hundred.", 1024)
        results["decode_heavy"] = {"wall": round(t1 - t0, 2),
                                   "samples": s.stop_and_save("decode_heavy")}

        s = Sampler(); s.start()
        _, _, t0, t1 = chat(big_prompt(3000), 64)
        results["prefill_heavy"] = {"wall": round(t1 - t0, 2),
                                    "samples": s.stop_and_save("prefill_heavy")}

        # 4) cancel: sample continuously from the exact close timestamp until
        # the slot is observed idle (never a silent 10 s gap).
        s = Sampler(); s.start()
        payload = json.dumps({
            "messages": [{"role": "user", "content": "Write a very long story."}],
            "max_tokens": 1024, "stream": True, "temperature": 0.0,
        }).encode()
        req = urllib.request.Request(BASE + "/v1/chat/completions", data=payload,
                                     headers={"Content-Type": "application/json"})
        resp = urllib.request.urlopen(req, timeout=600)
        try:
            deadline = time.time() + 6.0
            for line in resp:
                if time.time() > deadline:
                    break
        finally:
            close_t = time.time()
            resp.close()
        idle_t = None
        while time.time() - close_t < 30:
            idle_t = s.idle_seen(after_t=close_t)
            if idle_t is not None:
                break
            time.sleep(0.2)
        results["cancel"] = {
            "client_close_t": close_t,
            "first_idle_t": idle_t,
            "release_latency_s": round(idle_t - close_t, 2) if idle_t else None,
            "samples": s.stop_and_save("cancel"),
        }

        s = Sampler(); s.start()
        t0 = time.time()
        import concurrent.futures as cf
        with cf.ThreadPoolExecutor(max_workers=3) as pool:
            futures = [pool.submit(chat, f"Question {i}: what is {i}+{i}?", 128)
                       for i in range(3)]
            [f.result() for f in futures]
        results["concurrent"] = {"wall": round(time.time() - t0, 2),
                                 "samples": s.stop_and_save("concurrent")}

        with open(EV / "scenarios.json", "w") as fh:
            json.dump(results, fh, indent=1)
        print("scenarios done", flush=True)
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=15)
        except Exception:
            proc.kill()


if __name__ == "__main__":
    main()
