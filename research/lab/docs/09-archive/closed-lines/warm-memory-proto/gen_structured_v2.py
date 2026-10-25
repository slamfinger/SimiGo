#!/usr/bin/env python3
"""Arm B v2 generator — round 2 (改动2：条目级归属约束).

Differences from round 1 (frozen):
- Every item MUST carry work_item + kind(event|verification|ruling|state).
- Attribution rule: provenance must be the message that EXPLICITLY states
  the item belongs to that work item; proximity inference forbidden.
- Post-hoc support check: provenance message must contain a distinctive
  fragment of the item text — reported as a metric SEPARATE from
  reference-exists (round-1 lesson: Q8 misattribution).

Usage: python3 gen_structured_v2.py transcript.jsonl warm_memory_v2.json
"""

import json
import sys
import time
import urllib.request

URL = "http://127.0.0.1:8000/v1/chat/completions"
WINDOW = 10

PROMPT = """你是会话状态提取器。以下是一个工作会话转录的第 {a}-{b} 条消息（共 {n} 条）。
提取【本窗口内新出现】的条目，严格输出 JSON（无其他文字）：
{{"decisions":[{{"text":"...","work_item":"B1|B3|B4|产品解析器|Lab|其他","kind":"ruling|state","provenance":[消息号]}}],
 "facts":[{{"text":"...","work_item":"...","kind":"event|verification|state","provenance":[消息号]}}],
 "pending":[...同facts...],"constraints":[...同facts...],
 "sources":[{{"idx":0,"kind":"commit|pr|file|ruling","ref":"..."}}]}}

条目级归属约束（违反即错）：
1. provenance 必须是【明确陈述该条目归属于该工作项】的消息，不得凭相邻上下文推断归属。
2. 区分三种事实：「某事件发生过」（event）、「某工作项以某事件作为验证」（verification）、「某结论已获验证」（state）。一个事件只归属它被明确陈述所属的工作项。
3. 例：若窗口里 A 工作项的核验动作与 B 工作项的状态报告相邻，B 的条目不得把 A 的核验写成自己的验证方式。
4. 无信息量条目（寒暄/系统提醒）不提取；每条 provenance 用全局消息号（已标注）。

转录：
{chunk}"""


def wait_for_server(timeout_s: int = 1800) -> None:
    import socket
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", 8000), timeout=2):
                return
        except OSError:
            time.sleep(5)
    raise SystemExit("server not reachable")


def call(prompt: str, max_tokens: int = 2000) -> str:
    body = {"model": "Localmodel",
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": max_tokens, "temperature": 0,
            "stream": False, "session_id": "wmg2"}
    req = urllib.request.Request(
        URL, data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=900) as resp:
        return json.loads(resp.read().decode())["choices"][0]["message"]["content"] or ""


def support_check(item: dict, msgs: list) -> bool:
    """引用确实支持：provenance 消息须包含条目的可辨别片段
    （工作项词或 ≥6 连续字符片段），与「引用存在」分开计。"""
    text = item.get("text", "")
    for idx in item.get("provenance", []):
        if not 0 <= idx < len(msgs):
            continue
        src = msgs[idx]["content"] or ""
        if item.get("work_item", "") and item["work_item"] in src:
            return True
        for frag in (text[i:i + 8] for i in range(0, max(len(text) - 8, 0), 4)):
            if frag and frag in src:
                return True
    return False


def main(transcript_path: str, out_path: str) -> None:
    wait_for_server()
    msgs = [json.loads(l) for l in open(transcript_path)]
    n = len(msgs)
    merged = {k: [] for k in
              ("decisions", "facts", "pending", "constraints", "sources")}
    ok = total = 0
    for start in range(0, n, WINDOW):
        window = msgs[start:start + WINDOW]
        chunk = "\n\n".join(
            f"[{m['idx']}][{m['role']}] {m['content']}"[:4000]
            for m in window if m["role"] != "system")
        if not chunk:
            continue
        total += 1
        raw = call(PROMPT.format(
            a=window[0]["idx"], b=window[-1]["idx"], n=n, chunk=chunk))
        def ingest(text: str) -> bool:
            try:
                s, e = text.find("{"), text.rfind("}")
                data = json.loads(text[s:e + 1])
                for k in merged:
                    for item in data.get(k, []):
                        if isinstance(item, dict) and item.get(
                                "text", item.get("ref")):
                            merged[k].append(item)
                return True
            except Exception:  # noqa: BLE001
                return False
        if ingest(raw):
            ok += 1
        elif ingest(call(PROMPT.format(
                a=window[0]["idx"], b=window[-1]["idx"], n=n,
                chunk=chunk) + "\n输出必须是完整合法 JSON。")):
            ok += 1
        else:
            print(f"window {start}-{window[-1]['idx']} parse fail "
                  "(after retry)", file=sys.stderr)
        time.sleep(1)

    support = {k: sum(1 for i in merged[k] if support_check(i, msgs))
               for k in ("decisions", "facts", "pending", "constraints")}
    counts = {k: len(v) for k, v in merged.items()}
    result = {
        "schema": "simigo.warm-memory.v1-attributed",
        "lineage": {
            "storageKey": "default/31f725a0-dd79-4f88-9948-fea9aff21a38/main",
            "checkpointAt": "2026-10-16T09:40:21Z", "messageCount": n},
        "generated": {"at": time.strftime("%Y-%m-%dT%H:%M:%S"),
                      "windows": f"{ok}/{total}",
                      "coverage": round(ok / max(total, 1), 2)},
        "support_check": support, "counts": counts,
        "memory": merged,
    }
    json.dump(result, open(out_path, "w"), ensure_ascii=False, indent=1)
    print(json.dumps({"out": out_path, "coverage": result["generated"]
                      ["coverage"], "counts": counts,
                      "support": support}, ensure_ascii=False))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
