#!/usr/bin/env python3
"""Two-arm regression runner.

Arm A (baseline): client compaction summary (transcript idx of the
'状态已对齐' message) as the new session's carried memory.
Arm B: structured warm memory (gen_structured.py output, serialized
compact) as the carried memory.

Per arm: fresh session id, one request per question (memory + Q).
Metrics: carried-memory chars/token-est, per-question keyword score,
restore cost read from SimiGo trace (promptTokens of first request).

Usage: python3 run_regression.py transcript.jsonl warm_memory.json
"""

import json
import sys
import time
import urllib.request

URL = "http://127.0.0.1:8000/v1/chat/completions"
QA = json.load(open("qa_regression.json"))


def ask(memory: str, question: str, session: str) -> str:
    body = {
        "model": "Localmodel",
        "messages": [
            {"role": "user",
             "content": f"以下是你此前会话的工作状态记忆：\n{memory}\n\n"
                        f"问题：{question}\n"
                        "只依据记忆回答；记忆未覆盖就回答「记忆未覆盖」。"}
        ],
        "max_tokens": 128,
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


def score(answer: str, keyword_groups: list) -> str:
    hit = sum(
        1 for group in keyword_groups
        if all(k in answer for k in group))
    if hit == len(keyword_groups):
        return "PASS"
    if hit >= max(1, int(len(keyword_groups) * 0.7)):
        return "PARTIAL"
    return "FAIL"


def run_arm(name: str, memory: str, session: str) -> dict:
    results = []
    for q in QA["questions"]:
        answer = ask(memory, q["q"], session)
        results.append({
            "id": q["id"],
            "verdict": score(answer, q["answer_keywords"]),
            "answer": answer.strip()[:120],
        })
        time.sleep(1)
    counts: dict = {}
    for r in results:
        counts[r["verdict"]] = counts.get(r["verdict"], 0) + 1
    return {
        "arm": name,
        "memory_chars": len(memory),
        "memory_tokens_est": len(memory) // 4,
        "score": counts,
        "results": results,
    }


def main(transcript_path: str, warm_path: str) -> None:
    msgs = [json.loads(l) for l in open(transcript_path)]
    client_summary = next(
        m["content"] for m in msgs
        if m["role"] == "user" and "状态已对齐" in (m["content"] or "")[:40])
    warm = json.load(open(warm_path))
    # 可追溯性抽查：provenance 越界即剔除（回退契约 §1）
    valid_idx = {m["idx"] for m in msgs}
    dropped = 0
    for k in ("decisions", "facts", "pending", "constraints"):
        keep = []
        for item in warm["memory"].get(k, []):
            prov = [p for p in item.get("provenance", []) if p in valid_idx]
            if prov:
                item["provenance"] = prov
                keep.append(item)
            else:
                dropped += 1
        warm["memory"][k] = keep
    warm_memory = json.dumps(warm["memory"], ensure_ascii=False)

    report = {
        "dropped_no_provenance": dropped,
        "armA": run_arm("client-summary", client_summary, "wmra"),
        "armB": run_arm("structured-warm", warm_memory, "wmrb"),
    }
    json.dump(report, open("regression_report.json", "w"),
              ensure_ascii=False, indent=1)
    a, b = report["armA"], report["armB"]
    print(json.dumps({
        "dropped_no_provenance": dropped,
        "armA": {"tokens_est": a["memory_tokens_est"], **a["score"]},
        "armB": {"tokens_est": b["memory_tokens_est"], **b["score"]},
    }, ensure_ascii=False))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
