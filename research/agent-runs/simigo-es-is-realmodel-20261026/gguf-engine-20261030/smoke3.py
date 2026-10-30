#!/usr/bin/env python3
"""Real-model smoke on the installed v2.2.2 build: 3 concurrent clients, distinct markers."""
import json, time, uuid, threading, urllib.request, os

BASE = "http://127.0.0.1:8000"
OUT = os.path.dirname(os.path.abspath(__file__))


def post(path, payload, timeout=900):
    req = urllib.request.Request(
        BASE + path,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "Authorization": "Bearer local"},
    )
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            body = r.read().decode()
            return {"status": r.status, "elapsed": round(time.time() - t0, 2), "body": body}
    except Exception as e:
        detail = ""
        if hasattr(e, "read"):
            try:
                detail = e.read().decode()[:2000]
            except Exception:
                pass
        return {"status": getattr(e, "code", None), "elapsed": round(time.time() - t0, 2),
                "error": repr(e), "detail": detail}


def main():
    models = json.loads(urllib.request.urlopen(BASE + "/v1/models", timeout=10).read())
    model = models["data"][0]["id"]
    record = {"started": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "model": model, "runs": {}}

    tags = ["ALPHA", "BRAVO", "CHARLIE"]
    results = {}


    def call(tag):
        payload = {
            "model": model,
            "messages": [
                {"role": "user", "content": f"Reply with exactly one line: MARK[{tag}]"}
            ],
            "max_tokens": 64,
            "temperature": 0,
            "stream": False,
        }
        results[tag] = post("/v1/chat/completions", payload)

    warm = post("/v1/chat/completions", {
        "model": model,
        "messages": [{"role": "user", "content": "Reply with exactly: WARMUP[OK]"}],
        "max_tokens": 32, "temperature": 0, "stream": False,
    })
    record["warmup"] = warm

    t0 = time.time()
    threads = [threading.Thread(target=call, args=(t,)) for t in tags]
    for th in threads:
        th.start()
    for th in threads:
        th.join()
    record["concurrent_wall"] = round(time.time() - t0, 2)

    for tag in tags:
        r = results[tag]
        entry = {"status": r.get("status"), "elapsed": r.get("elapsed")}
        if "body" in r and r["body"]:
            try:
                j = json.loads(r["body"])
                msg = j.get("choices", [{}])[0].get("message", {})
                entry["content"] = msg.get("content")
                entry["reasoning"] = (msg.get("reasoning_content") or "")[:400]
                entry["finish_reason"] = j.get("choices", [{}])[0].get("finish_reason")
                entry["usage"] = j.get("usage")
                entry["carries_own_marker"] = f"MARK[{tag}]" in (msg.get("content") or "")
                entry["foreign_markers"] = [
                    t for t in tags if t != tag and f"MARK[{t}]" in (msg.get("content") or "")
                ]
            except Exception as e:
                entry["parse_error"] = repr(e)
                entry["raw"] = r["body"][:2000]
        else:
            entry["error"] = r.get("error")
            entry["detail"] = r.get("detail")
        record["runs"][tag] = entry

    record["finished"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    path = os.path.join(OUT, "smoke3.json")
    with open(path, "w") as f:
        json.dump(record, f, ensure_ascii=False, indent=2)
    print(json.dumps({k: record[k] for k in ("model", "concurrent_wall", "runs")},
                     ensure_ascii=False, indent=2)[:3000])


if __name__ == "__main__":
    main()
