#!/usr/bin/env python3
"""E1 positive control: does the product KV prefix pool actually avoid recomputation?

Three probes over the real product HTTP entry (POST /v1/chat/completions), same
model identity, byte-identical message bodies where reuse is expected:

  P1 cold        session=pcA  [sys_long, user_q]              -> baseline, should export pool
  P2 cross-sess  session=pcB  byte-identical to P1            -> expect mode=restore / cacheHitTokens>0
  P3 same-sess   session=pcA  [sys_long, user_q, asst, user2]  -> expect prefix reuse=true

Metrics come from ~/.simigo/logs/native_mlx_trace.log only (no DB writes asserted).
"""
import json, os, time, urllib.request

BASE = "http://127.0.0.1:8000"
HOME = os.path.expanduser("~")
TRACE = f"{HOME}/.simigo/logs/native_mlx_trace.log"
OUT = os.path.dirname(os.path.abspath(__file__))
NONCE = time.strftime("%Y%m%d-%H%M%S")

LINES = []
for i in range(1, 241):
    LINES.append(
        f"Item {i:03d}: segment alpha-{i*7 % 97} beta-{i*13 % 89} gamma-{i*3 % 53} "
        f"carries a fixed invariant payload digest and is ordered by construction."
    )
SYS_LONG = ("You are a precise reference engine. Below is a frozen register. "
            "Never restate it; answer only from memory when asked.\nREGISTER\n"
            + "\n".join(LINES))
USER_Q = "What is the exact wording of Item 007? Answer with one short sentence."
USER_Q2 = "And Item 011? Answer with one short sentence."


def post(path, payload, timeout=900):
    req = urllib.request.Request(BASE + path, data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return int(r.status), json.loads(r.read().decode()), round(time.time() - t0, 2)
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw), round(time.time() - t0, 2)
        except Exception:
            return e.code, {"raw": raw[:400]}, round(time.time() - t0, 2)
    except Exception as e:
        return -1, {"error": repr(e)}, round(time.time() - t0, 2)


def get_model():
    with urllib.request.urlopen(BASE + "/v1/models", timeout=30) as r:
        data = json.loads(r.read().decode())
    return data["data"][0]["id"]


def trace_off():
    return os.path.getsize(TRACE) if os.path.exists(TRACE) else 0


def trace_since(off):
    with open(TRACE, "rb") as f:
        f.seek(off)
        return f.read().decode(errors="replace")


KEYS = ("arrive", "prefill", "promptTokens", "cacheHitTokens", "cacheEff", "mode=",
        "poolBind", "poolExport", "poolTokenHit", "reuseMiss", "prefixMismatch",
        "prefixDiff", "sessionClientSplit", "cacheSave", "RELEASED")


def keep(text):
    return [ln.strip() for ln in text.splitlines() if any(k in ln for k in KEYS)]


def run(name, sess, msgs):
    payload = {"model": MODEL, "session_id": sess, "stream": False,
               "temperature": 0.0, "max_tokens": 24, "messages": msgs}
    off = trace_off()
    code, body, secs = post("/v1/chat/completions", payload)
    ev = keep(trace_since(off))
    usage = body.get("usage", {}) if isinstance(body, dict) else {}
    rec = {"probe": name, "session": sess, "http": code, "seconds": secs,
           "prompt_tokens": usage.get("prompt_tokens"),
           "content": (body.get("choices") or [{}])[0].get("message", {}).get("content")
                      if isinstance(body, dict) else None,
           "trace": ev}
    print(f"== {name} http={code} secs={secs} prompt={rec['prompt_tokens']}", flush=True)
    for ln in ev:
        print("   " + ln, flush=True)
    return rec


MODEL = get_model()
print(f"model={MODEL} nonce={NONCE}", flush=True)
results = [
    run("P1_cold", f"pc-{NONCE}-A", [{"role": "system", "content": SYS_LONG},
                                     {"role": "user", "content": USER_Q}]),
    run("P2_crosssession_identical", f"pc-{NONCE}-B", [{"role": "system", "content": SYS_LONG},
                                                       {"role": "user", "content": USER_Q}]),
]
first = results[0]
asst = (first.get("content") or "Item 007 carries a fixed invariant payload digest.")
results.append(
    run("P3_samesession_append", f"pc-{NONCE}-A",
        [{"role": "system", "content": SYS_LONG},
         {"role": "user", "content": USER_Q},
         {"role": "assistant", "content": asst},
         {"role": "user", "content": USER_Q2}]))

with open(os.path.join(OUT, f"e1-positive-control-{NONCE}.json"), "w") as f:
    json.dump({"nonce": NONCE, "model": MODEL,
               "sha256_sys_long": __import__("hashlib").sha256(SYS_LONG.encode()).hexdigest(),
               "probes": results}, f, indent=2, ensure_ascii=False)
print(f"wrote e1-positive-control-{NONCE}.json", flush=True)
