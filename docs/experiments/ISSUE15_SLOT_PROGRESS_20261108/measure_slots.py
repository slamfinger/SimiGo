#!/usr/bin/env python3
"""Issue #15 Round 1: real llama.cpp slot-progress measurement.

Launches the SimiGo-managed llama-server with production-style arguments and
samples /slots at a fixed interval while driving five load profiles:
normal, decode-heavy, prefill-heavy, client-cancel, concurrent (np=1 queue).

No recovery policy is changed or consulted here: this run only measures.
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
EV = Path("/private/tmp/fifteen/evidence")
INTERVAL = 0.5


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
            except Exception as exc:  # server restarting / busy listener
                self.rows.append({"t": t, "error": repr(exc)})
            else:
                self.rows.append({
                    "t": t,
                    "slots": [
                        {
                            "id_task": s.get("id_task"),
                            "is_processing": s.get("is_processing"),
                            "n_prompt_tokens_processed": s.get("n_prompt_tokens_processed"),
                            "n_prompt_tokens": s.get("n_prompt_tokens"),
                            "n_decoded": s.get("n_decoded"),
                            "prompt": (s.get("prompt") or "")[:40],
                        }
                        for s in slots
                    ],
                })
            self.stop.wait(INTERVAL)

    def start(self):
        self.thread.start()

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


def chat(prompt, max_tokens, session=None):
    payload = {
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": 0.0,
    }
    if session:
        payload["session_id"] = session
    return post("/v1/chat/completions", payload)


def big_prompt(tokens=3000):
    unit = ("The lighthouse keeper wrote a numbered line of the log every hour; "
            "each line recorded the wind, the swell and the lamps. ")
    per = len(unit.split())
    reps = max(1, tokens // per)
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
        ready = wait_ready()
        print(f"server ready in {ready:.1f}s", flush=True)

        results = {}

        # 1) normal generation
        s = Sampler(); s.start()
        status, body, t0, t1 = chat("Name three colours.", 256)
        results["normal"] = {"wall": t1 - t0, "samples": s.stop_and_save("normal")}

        # 2) decode-heavy (long generation)
        s = Sampler(); s.start()
        status, body, t0, t1 = chat("Count from one to two hundred.", 1024)
        results["decode_heavy"] = {"wall": t1 - t0, "samples": s.stop_and_save("decode_heavy")}

        # 3) prefill-heavy (long prompt, short output)
        s = Sampler(); s.start()
        status, body, t0, t1 = chat(big_prompt(3000), 64)
        results["prefill_heavy"] = {"wall": t1 - t0, "samples": s.stop_and_save("prefill_heavy")}

        # 4) client cancel mid-decode: open a stream, read a little, close
        s = Sampler(); s.start()
        payload = json.dumps({
            "messages": [{"role": "user", "content": "Write a very long story."}],
            "max_tokens": 1024, "stream": True, "temperature": 0.0,
        }).encode()
        req = urllib.request.Request(BASE + "/v1/chat/completions", data=payload,
                                     headers={"Content-Type": "application/json"})
        t0 = time.time()
        resp = urllib.request.urlopen(req, timeout=600)
        read_for = 0.0
        try:
            deadline = time.time() + 6.0  # cancel ~6s into decode
            for line in resp:
                if time.time() > deadline:
                    break
                read_for = time.time() - t0
        finally:
            resp.close()  # abrupt client cancel
        results["cancel"] = {"client_read_s": read_for, "samples": s.stop_and_save("cancel")}
        # sample for a while after cancel to capture busy->idle latency
        time.sleep(10)
        tail = Sampler(); tail.start(); time.sleep(3)
        results["cancel"]["post_samples"] = tail.stop_and_save("cancel_post")

        # 5) concurrent: three overlapping requests against np=1
        s = Sampler(); s.start()
        t0 = time.time()
        import concurrent.futures as cf
        with cf.ThreadPoolExecutor(max_workers=3) as pool:
            futures = [
                pool.submit(chat, f"Question {i}: what is {i}+{i}?", 128)
                for i in range(3)
            ]
            done = [f.result() for f in futures]
        t1 = time.time()
        results["concurrent"] = {"wall": t1 - t0, "samples": s.stop_and_save("concurrent")}

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
