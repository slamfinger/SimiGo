#!/usr/bin/env python3
"""Round-3 regression（三方对比+Q8专项）: trimmed + attributed Arm B vs frozen baseline.

- Main set: the SAME 10 questions (strict comparability); per-question
  delta vs round-1 frozen verdicts (embedded below).
- Directed set: 3 attribution-boundary questions (Q8 lesson).
- Provenance metrics reported separately: reference-exists rate vs
  support-check rate (from gen v2 / trim output).
Usage: python3 run_regression_v2.py transcript.jsonl warm_memory_trim.json
"""

import json
import sys
import time
import urllib.request

URL = "http://127.0.0.1:8000/v1/chat/completions"
QA = json.load(open("qa_regression.json"))

# round-1 冻结基线（regression_report.round1.json）
BASE_R2B = {"1": "PARTIAL", "2": "PARTIAL", "3": "PASS", "4": "FAIL", "5": "PASS",
            "6": "PASS", "7": "PASS", "8": "FAIL", "9": "PASS", "10": "PASS"}
BASE_R1A = {"1": "PARTIAL", "2": "PASS", "3": "PASS", "4": "PARTIAL", "5": "PARTIAL",
            "6": "PARTIAL", "7": "FAIL", "8": "PARTIAL", "9": "FAIL", "10": "FAIL"}

DIRECTED = [
    {"id": "D1", "q": "B3 本轮实际执行的验证方式是什么？（注意：不是其他环节的核验动作）",
     "answer_keywords": [["烟测", "swift", "Swift"]], "forbid": ["fetch-only"]},
    {"id": "D2", "q": "fetch-only 核验（提交链 e22a3cab→f0ee2083 的那次）属于哪个环节的动作？",
     "answer_keywords": [["Lab", "核验", "本地"]], "forbid": []},
    {"id": "D3", "q": "B1 放行裁定的核验对象是什么？结论是什么？",
     "answer_keywords": [["dbaeedcf"], ["放行", "通过"]], "forbid": []},
]


def ask(memory: str, question: str, session: str) -> str:
    body = {"model": "Localmodel",
            "messages": [{"role": "user",
                          "content": f"以下是你此前会话的工作状态记忆：\n{memory}\n\n"
                                     f"问题：{question}\n"
                                     "只依据记忆回答；记忆未覆盖就回答「记忆未覆盖」。"}],
            "max_tokens": 128, "temperature": 0, "stream": False,
            "session_id": session}
    req = urllib.request.Request(
        URL, data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=900) as resp:
        return json.loads(resp.read().decode())["choices"][0]["message"]["content"] or ""


def score(answer: str, groups: list, forbid: list = None) -> str:
    if forbid and any(f in answer for f in forbid):
        return "FAIL"
    hit = sum(1 for g in groups if all(k in answer for k in g))
    if hit == len(groups):
        return "PASS"
    if hit >= max(1, int(len(groups) * 0.7)):
        return "PARTIAL"
    return "FAIL"


def main(transcript_path: str, warm_path: str) -> None:
    msgs = [json.loads(l) for l in open(transcript_path)]
    client_summary = next(
        m["content"] for m in msgs
        if m["role"] == "user" and "状态已对齐" in (m["content"] or "")[:40])
    warm = json.load(open(warm_path))
    valid = {m["idx"] for m in msgs}
    dropped = 0
    for k in ("decisions", "facts", "pending", "constraints"):
        keep = []
        for it in warm["memory"].get(k, []):
            prov = [p for p in it.get("provenance", []) if p in valid]
            if prov:
                it["provenance"] = prov
                keep.append(it)
            else:
                dropped += 1
        warm["memory"][k] = keep
    memory_b = json.dumps(warm["memory"], ensure_ascii=False)

    results_main, results_dir = [], []
    for q in QA["questions"]:
        results_main.append({
            "id": q["id"], "verdict": score(
                ask(memory_b, q["q"], "wm3b"), q["answer_keywords"]),
            "round1A": BASE_R1A[str(q["id"])],
                "round2B": BASE_R2B[str(q["id"])]})
        time.sleep(1)
    for q in DIRECTED:
        results_dir.append({
            "id": q["id"], "verdict": score(
                ask(memory_b, q["q"], "wm3b"), q["answer_keywords"],
                q.get("forbid"))})
        time.sleep(1)
    # Arm A 只跑定向题对照（主十题基线已冻结，不重跑）
    for q in DIRECTED:
        results_dir.append({
            "id": q["id"] + "-armA", "verdict": score(
                ask(client_summary, q["q"], "wm3a"), q["answer_keywords"],
                q.get("forbid"))})
        time.sleep(1)

    deltas = {r["id"]: {"armA": r["round1A"], "round2B": r["round2B"],
                        "round3B": r["verdict"]} for r in results_main}
    new_fail = [i for i, d in deltas.items()
                if d["round2B"] in ("PASS", "PARTIAL")
                and d["round3B"] == "FAIL"]
    smoke = [f for f in warm["memory"].get("facts", [])
             if "烟测" in f.get("text", "")]
    q8_special = {"smoke_fact_present": bool(smoke),
                  "smoke_attributed_to": sorted({f.get("work_item") for f in smoke})}
    report = {
        "dropped_no_provenance": dropped,
        "memory_chars": len(memory_b),
        "est_tokens": warm.get("trim", {}).get("est_tokens"),
        "coverage": warm.get("generated", {}).get("coverage"),
        "support_check": warm.get("support_check"),
        "main": deltas,
        "new_failures_vs_baseline": new_fail,
        "q8_gate": {"qa": deltas.get("8"), "memory": q8_special},
        "directed": results_dir,
    }
    json.dump(report, open("regression_report.round3.json", "w"),
              ensure_ascii=False, indent=1)
    print(json.dumps(report, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
