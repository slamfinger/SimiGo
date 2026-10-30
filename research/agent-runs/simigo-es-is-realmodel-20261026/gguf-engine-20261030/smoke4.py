#!/usr/bin/env python3
"""4 concurrent real-model clients + post-settlement reuse probe on the installed v2.2.2 build."""
import json, time, threading, urllib.request, os

BASE = "http://127.0.0.1:8000"
OUT = os.path.dirname(os.path.abspath(__file__))
TAGS = ["ALPHA", "BRAVO", "CHARLIE", "DELTA"]


def post(payload, timeout=600):
    req = urllib.request.Request(
        BASE + "/v1/chat/completions",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "Authorization": "Bearer local"},
    )
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return {"status": r.status, "elapsed": round(time.time() - t0, 2), "body": r.read().decode()}
    except Exception as e:
        detail = ""
        if hasattr(e, "read"):
            try:
                detail = e.read().decode()[:1500]
            except Exception:
                pass
        return {"status": getattr(e, "code", None), "elapsed": round(time.time() - t0, 2),
                "error": repr(e), "detail": detail}


def payload(model, tag, session):
    return {
        "model": model,
        "messages": [{"role": "user", "content": f"Reply with exactly one line: MARK[{tag}]"}],
        "max_tokens": 64,
        "temperature": 0,
        "stream": False,
        "user": session,
    }


def summarize(resp, tag):
    e = {"status": resp.get("status"), "elapsed": resp.get("elapsed")}
    body = resp.get("body")
    if body:
        j = json.loads(body)
        msg = j.get("choices", [{}])[0].get("message", {})
        content = msg.get("content") or ""
        e.update({
            "content": content,
            "finish_reason": j.get("choices", [{}])[0].get("finish_reason"),
            "carries_own_marker": f"MARK[{tag}]" in content,
            "foreign_markers": [t for t in TAGS if t != tag and f"MARK[{t}]" in content],
        })
    else:
        e.update({"error": resp.get("error"), "detail": resp.get("detail")})
    return e


def main():
    model = json.loads(urllib.request.urlopen(BASE + "/v1/models", timeout=10).read())["data"][0]["id"]
    rec = {"started": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "model": model, "runs": {}}
    results = {}

    def call(tag):
        results[tag] = post(payload(model, tag, f"sess-{tag.lower()}"))

    t0 = time.time()
    ths = [threading.Thread(target=call, args=(t,)) for t in TAGS]
    for th in ths:
        th.start()
    for th in ths:
        th.join()
    rec["concurrent_wall"] = round(time.time() - t0, 2)
    for tag in TAGS:
        rec["runs"][tag] = summarize(results[tag], tag)

    fifth = post(payload(model, "ALPHA", "sess-alpha-retry"))
    rec["fifth_reuse_probe"] = summarize(fifth, "ALPHA")

    rec["finished"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    with open(os.path.join(OUT, "smoke4.json"), "w") as f:
        json.dump(rec, f, ensure_ascii=False, indent=2)
    print(json.dumps(rec, ensure_ascii=False, indent=2)[:4000])


if __name__ == "__main__":
    main()
