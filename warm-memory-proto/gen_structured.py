#!/usr/bin/env python3
"""Arm B generator: chunked schema-driven extraction via the local SimiGo
server (localhost:8000). Each window ~10 messages -> one extraction call
(small renders only); merge + dedupe into MEMORY_SCHEMA v0 JSON.

Run only in an idle window (serial gate courtesy — see README).
Usage: python3 gen_structured.py transcript.jsonl warm_memory.json
"""

import json
import sys
import time
import urllib.request

URL = "http://127.0.0.1:8000/v1/chat/completions"
WINDOW = 10

EXTRACT_PROMPT = """你是会话状态提取器。以下是一个工作会话转录的第 {a}-{b} 条消息（共 {n} 条）。
从中提取【本窗口内新出现】的条目，严格输出 JSON（无其他文字）：
{{"decisions":[{{"text":"...","provenance":[消息号]}}],"facts":[...],"pending":[...],"constraints":[...],"sources":[{{"idx":0,"kind":"commit|pr|file|ruling","ref":"..."}}]}}
只提取有信息量的条目（裁定/事实/待办/约束/外部引用），忽略寒暄与系统提醒。
provenance 用本窗口内的全局消息号（已在每条前标注）。

转录：
{chunk}"""


def call(prompt: str, session: str, max_tokens: int = 1024) -> str:
    body = {
        "model": "Localmodel",
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": 0,
        "stream": False,
        "session_id": session,
    }
    req = urllib.request.Request(
        URL, data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=900) as resp:
        payload = json.loads(resp.read().decode())
    return payload["choices"][0]["message"]["content"] or ""


def wait_for_server(timeout_s: int = 1200) -> None:
    """等服务就绪（用户在 UI 重新开启模型后自动起跑）。"""
    import socket
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", 8000), timeout=2):
                return
        except OSError:
            time.sleep(5)
    raise SystemExit("server not reachable on 127.0.0.1:8000 after "
                     f"{timeout_s}s")


def main(transcript_path: str, out_path: str) -> None:
    wait_for_server()
    msgs = [json.loads(l) for l in open(transcript_path)]
    n = len(msgs)
    merged = {k: [] for k in
              ("decisions", "facts", "pending", "constraints", "sources")}
    windows_ok = 0
    windows_total = 0

    for start in range(0, n, WINDOW):
        window = msgs[start:start + WINDOW]
        chunk = "\n\n".join(
            f"[{m['idx']}][{m['role']}] {m['content']}"[:4000]
            for m in window if m["role"] != "system")
        if not chunk:
            continue
        windows_total += 1
        prompt = EXTRACT_PROMPT.format(
            a=window[0]["idx"], b=window[-1]["idx"], n=n, chunk=chunk)
        raw = call(prompt, session="wmemg")
        try:
            start_json = raw.find("{")
            end_json = raw.rfind("}")
            data = json.loads(raw[start_json:end_json + 1])
            for k in merged:
                for item in data.get(k, []):
                    if isinstance(item, dict) and item.get("text", item.get("ref")):
                        merged[k].append(item)
            windows_ok += 1
        except Exception as e:  # noqa: BLE001
            print(f"window {start}-{window[-1]['idx']} parse fail: {e}",
                  file=sys.stderr)
        time.sleep(1)

    coverage = windows_ok / max(windows_total, 1)
    result = {
        "schema": "simigo.warm-memory.v0",
        "lineage": {
            "storageKey": "default/31f725a0-dd79-4f88-9948-fea9aff21a38/main",
            "checkpointAt": "2026-10-16T09:40:21Z",
            "messageCount": n,
        },
        "generated": {
            "at": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "windows": f"{windows_ok}/{windows_total}",
            "coverage": round(coverage, 2),
        },
        "memory": merged,
    }
    json.dump(result, open(out_path, "w"), ensure_ascii=False, indent=1)
    print(json.dumps({
        "out": out_path,
        "coverage": coverage,
        "counts": {k: len(v) for k, v in merged.items()},
    }, ensure_ascii=False))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
