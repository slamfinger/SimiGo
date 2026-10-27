#!/usr/bin/env python3
"""E1b isolating control: is the IS context-block injection the only reason the
prefix pool never hits?

Same as E1 but the user query uses terms that match nothing in the IS, so
SimiGoInformationLoop.contextBlock returns "" and HTTPServerChat does NOT insert
the extra system message (HTTPServerChat.swift:130-138). If reuse is then
reachable (mode=restore / cacheHitTokens>0), the pool machinery itself works and
the only defect is prompt placement.
"""
import json, os, time, urllib.request, hashlib

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
# deliberately unmatched by SimiGoInformationLoop.keywords()
USER_Q = "xqzj vkqp 请问 blorp 007 是什么"
USER_Q2 = "xqzj vkqp 请问 blorp 011 是什么"


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


def trace_off():
    return os.path.getsize(TRACE) if os.path.exists(TRACE) else 0


def trace_since(off):
    with open(TRACE, "rb") as f:
        f.seek(off)
        return f.read().decode(errors="replace")


KEYS = ("arrive", "prefill", "promptTokens", "cacheHitTokens", "cacheEff", "mode=",
        "poolBind", "poolExport", "poolTokenHit", "poolHit", "reuseMiss", "prefixMismatch",
        "prefixDiff", "cacheSave", "RELEASED")


def run(name, sess, msgs, model):
    payload = {"model": model, "session_id": sess, "stream": False,
               "temperature": 0.0, "max_tokens": 24, "messages": msgs}
    off = trace_off()
    code, body, secs = post("/v1/chat/completions", payload)
    ev = [ln.strip() for ln in trace_since(off).splitlines() if any(k in ln for k in KEYS)]
    usage = body.get("usage", {}) if isinstance(body, dict) else {}
    print(f"== {name} http={code} secs={secs} prompt={usage.get('prompt_tokens')}", flush=True)
    for ln in ev:
        print("   " + ln, flush=True)
    return {"probe": name, "session": sess, "http": code, "seconds": secs,
            "prompt_tokens": usage.get("prompt_tokens"),
            "content": (body.get("choices") or [{}])[0].get("message", {}).get("content")
            if isinstance(body, dict) else None,
            "trace": ev}


with urllib.request.urlopen(BASE + "/v1/models", timeout=30) as r:
    MODEL = json.loads(r.read().decode())["data"][0]["id"]
print(f"model={MODEL} nonce={NONCE}", flush=True)

M = [{"role": "system", "content": SYS_LONG}, {"role": "user", "content": USER_Q}]
res = [run("Q1_cold_noinject", f"pb-{NONCE}-X", M, MODEL),
       run("Q2_crosssession_identical_noinject", f"pb-{NONCE}-Y", M, MODEL)]
asst = res[0]["content"] or "Item 007 carries a fixed invariant payload digest."
res.append(run("Q3_samesession_append_noinject", f"pb-{NONCE}-X",
               M + [{"role": "assistant", "content": asst},
                    {"role": "user", "content": USER_Q2}], MODEL))

with open(os.path.join(OUT, f"e1b-isolating-{NONCE}.json"), "w") as f:
    json.dump({"nonce": NONCE, "model": MODEL,
               "sys_sha256": hashlib.sha256(SYS_LONG.encode()).hexdigest(),
               "probes": res}, f, indent=2, ensure_ascii=False)
print("wrote e1b-isolating json", flush=True)
