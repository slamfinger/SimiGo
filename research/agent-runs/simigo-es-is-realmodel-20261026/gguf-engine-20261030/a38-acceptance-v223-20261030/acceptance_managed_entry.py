#!/usr/bin/env python3
"""a38 GGUF managed-entry acceptance on the installed v2.2.3 (build 33, exe 740484b5).

Window: 2026-10-30 19:0x, product HTTPServer holds :8000, engine child on a random
loopback port.
Raw outputs are written next to this script as acceptance_managed_entry.json."""
import json
import os
import time
import urllib.parse
import urllib.request

BASE = "http://127.0.0.1:8000"
OUT = os.path.dirname(os.path.abspath(__file__))
AUTH = {"Authorization": "Bearer local"}

NONCE = time.strftime("%Y%m%dT%H%M%S")
SESSION = f"a38-accept-{NONCE}"
QUERY = f"A38 managed-entry acceptance {NONCE}: reply with exactly one line MARK[A38-{NONCE}]"


def http(method, path, payload=None, timeout=900):
    data = json.dumps(payload).encode() if payload is not None else None
    headers = dict(AUTH)
    if data is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    started = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return {"status": r.status, "elapsed": round(time.time() - started, 3),
                    "body": r.read().decode()}
    except Exception as e:
        detail = ""
        if hasattr(e, "read"):
            try:
                detail = e.read().decode()[:2000]
            except Exception:
                pass
        return {"status": getattr(e, "code", None), "elapsed": round(time.time() - started, 3),
                "error": repr(e), "detail": detail}


def summarize(resp):
    out = {"status": resp.get("status"), "elapsed_s": resp.get("elapsed")}
    if resp.get("body"):
        j = json.loads(resp["body"])
        choice = (j.get("choices") or [{}])[0]
        msg = choice.get("message") or {}
        out.update({
            "id": j.get("id"),
            "content": msg.get("content"),
            "message_keys": sorted(msg.keys()),
            "reasoning_chars": len(msg.get("reasoning_content") or ""),
            "finish_reason": choice.get("finish_reason"),
            "simigo": j.get("simigo"),
            "usage": j.get("usage"),
            "model": j.get("model"),
            "raw_body": resp["body"],
        })
    else:
        out.update({"error": resp.get("error"), "detail": resp.get("detail")})
    return out


def main():
    model = json.loads(urllib.request.urlopen(
        urllib.request.Request(BASE + "/v1/models", headers=AUTH), timeout=10
    ).read())["data"][0]["id"]
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": QUERY}],
        "max_tokens": 1024,
        "temperature": 0,
        "stream": False,
        "user": SESSION,
    }
    rec = {
        "started": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "base": BASE, "model": model, "session": SESSION, "query": QUERY,
        "payload_sha256_body": json.dumps(payload, sort_keys=True),
    }

    rec["first"] = summarize(http("POST", "/v1/chat/completions", payload))
    rec["replay"] = summarize(http("POST", "/v1/chat/completions", payload))

    q = urllib.parse.urlencode({"q": QUERY, "session_id": SESSION})
    search = http("GET", "/v1/simigo/search?" + q)
    rec["search"] = {"status": search.get("status"), "elapsed_s": search.get("elapsed")}
    if search.get("body"):
        j = json.loads(search["body"])
        rec["search"].update({
            "demand_id": j.get("demand_id"),
            "reused": j.get("reused"),
            "status_value": j.get("status"),
            "result_sha256": j.get("result_sha256"),
            "retrieval_settlement_id": j.get("retrieval_settlement_id"),
            "item_count": len(j.get("items") or []),
            "items": (j.get("items") or [])[:5],
        })
    else:
        rec["search"].update({"error": search.get("error"), "detail": search.get("detail")})

    rec["finished"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    path = os.path.join(OUT, "acceptance_managed_entry.json")
    with open(path, "w") as f:
        json.dump(rec, f, ensure_ascii=False, indent=2)
    print(json.dumps(rec, ensure_ascii=False, indent=2)[:6000])
    print("written:", path)


if __name__ == "__main__":
    main()
