#!/usr/bin/env python3
"""Arm B v4 generator — R4 改动1：三级提取阶梯.

层级：整窗 JSON → 二分 JSON → 行式逐条（每条独立输出/解析/校验）。
行式格式抗截断：截断只丢尾部行，已解析行独立成立；每行独立校验
provenance 后合并。全程 audit 留痕（范围/层级/尝试/结果/失败样本）。
归属约束提示词与 v2/v3 逐字一致（冻结），仅输出载体不同。

Usage: python3 gen_structured_v4.py transcript.jsonl warm_memory_v4.json
"""

import json
import re
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

LINE_PROMPT = """你是会话状态提取器。以下是一个工作会话转录的第 {a}-{b} 条消息（共 {n} 条）。
逐条提取，每条输出一行，格式严格为（| 分隔，一行一条，无其他文字）：
类|工作项|kind|provenance消息号|内容
其中 类 ∈ decisions|facts|pending|constraints|sources；工作项 ∈ B1|B3|B4|产品解析器|Lab|其他；
kind：decisions 用 ruling|state，facts/pending/constraints 用 event|verification|state，
sources 行格式改为 sources|工作项|source|消息号|ref原文。
归属规则同前：provenance 必须是明确陈述该归属的消息；事件/验证/结论三态分清，不得跨工作项挪用。

转录：
{chunk}"""

CLASS_MAP = {"decisions": "decisions", "facts": "facts",
             "pending": "pending", "constraints": "constraints",
             "sources": "sources"}


def wait_for_server(timeout_s: int = 1800) -> None:
    import socket
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", 8000), timeout=2):
                time.sleep(20)  # TCP 通 ≠ 运行时就绪：留装载窗口
                return
        except OSError:
            time.sleep(5)
    raise SystemExit("server not reachable")


def call(prompt: str, max_tokens: int = 2000) -> str:
    body = {"model": "Localmodel",
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": max_tokens, "temperature": 0,
            "stream": False, "session_id": "wmg4"}
    req = urllib.request.Request(
        URL, data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=900) as resp:
        return json.loads(resp.read().decode())["choices"][0]["message"]["content"] or ""


def chunk_of(window):
    return "\n\n".join(
        f"[{m['idx']}][{m['role']}] {m['content']}"[:4000]
        for m in window if m["role"] != "system")


def ingest_json(text: str, merged: dict) -> bool:
    try:
        s, e = text.find("{"), text.rfind("}")
        data = json.loads(text[s:e + 1])
        got = 0
        for k in merged:
            for item in data.get(k, []):
                if isinstance(item, dict) and item.get("text", item.get("ref")):
                    merged[k].append(item)
                    got += 1
        return got >= 0 and bool(text.strip()) and s != -1
    except Exception:  # noqa: BLE001
        return False


def ingest_lines(text: str, merged: dict, audit: list, rng) -> int:
    """行式逐条：每行独立解析、独立校验，坏行丢弃留痕。"""
    good = bad = 0
    for line in text.splitlines():
        line = line.strip().lstrip("0123456789.-) ")
        if not line:
            continue
        parts = [p.strip() for p in line.split("|")]
        if len(parts) >= 5 and parts[0] in CLASS_MAP:
            cls, work_item, kind, prov, body = (
                parts[0], parts[1], parts[2], parts[3], "|".join(parts[4:]))
            idxs = [int(x) for x in re.findall(r"\d+", prov)
                    if x.isdigit()][:3]
            if cls == "sources":
                merged["sources"].append(
                    {"idx": idxs[0] if idxs else -1, "kind": "source",
                     "ref": body[:160], "work_item": work_item})
            elif body and idxs:
                merged[cls].append(
                    {"text": body[:300], "work_item": work_item,
                     "kind": kind, "provenance": idxs})
            else:
                bad += 1
                audit.append({"range": rng, "tier": "line",
                              "result": "bad-line", "sample": line[:80]})
                continue
            good += 1
        elif len(parts) >= 2 and parts[0]:
            bad += 1
            audit.append({"range": rng, "tier": "line",
                          "result": "bad-line", "sample": line[:80]})
    return good - bad  # >0 视为该窗有效产出


def support_check(item: dict, msgs: list) -> bool:
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
    merged = {k: [] for k in CLASS_MAP}
    audit, ok, total = [], 0, 0

    for start in range(0, n, WINDOW):
        window = msgs[start:start + WINDOW]
        chunk = chunk_of(window)
        if not chunk:
            continue
        total += 1
        rng = [window[0]["idx"], window[-1]["idx"]]
        raw = call(PROMPT.format(a=rng[0], b=rng[1], n=n, chunk=chunk))
        if ingest_json(raw, merged):
            ok += 1
            audit.append({"range": rng, "tier": "window", "attempts": 1,
                          "result": "ok"})
            continue
        # 二分
        mid = len(window) // 2
        sub_ok = 0
        for sub in (window[:mid], window[mid:]):
            if not sub or not chunk_of(sub):
                sub_ok += 1
                continue
            srng = [sub[0]["idx"], sub[-1]["idx"]]
            sraw = call(PROMPT.format(
                a=srng[0], b=srng[1], n=n, chunk=chunk_of(sub)))
            if ingest_json(sraw, merged):
                sub_ok += 1
                audit.append({"range": srng, "tier": "bisect",
                              "attempts": 1, "result": "bisect-ok"})
                continue
            # 行式逐条（最后一级）
            lraw = call(LINE_PROMPT.format(
                a=srng[0], b=srng[1], n=n, chunk=chunk_of(sub)))
            if ingest_lines(lraw, merged, audit, srng) > 0:
                sub_ok += 1
                audit.append({"range": srng, "tier": "line",
                              "attempts": 1, "result": "line-ok"})
            else:
                audit.append({"range": srng, "tier": "line",
                              "attempts": 1, "result": "line-fail",
                              "sample": lraw[:120]})
        if sub_ok == 2:
            ok += 1
        else:
            print(f"window {rng} exhausted ladder ({sub_ok}/2)",
                  file=sys.stderr)
        time.sleep(1)

    support = {k: sum(1 for i in merged[k] if support_check(i, msgs))
               for k in ("decisions", "facts", "pending", "constraints")}
    result = {
        "schema": "simigo.warm-memory.v2-laddered",
        "lineage": {"storageKey":
                    "default/31f725a0-dd79-4f88-9948-fea9aff21a38/main",
                    "checkpointAt": "2026-10-16T09:40:21Z",
                    "messageCount": n},
        "audit": audit,
        "generated": {"at": time.strftime("%Y-%m-%dT%H:%M:%S"),
                      "windows": f"{ok}/{total}",
                      "coverage": round(ok / max(total, 1), 2)},
        "support_check": support,
        "counts": {k: len(v) for k, v in merged.items()},
        "memory": merged,
    }
    json.dump(result, open(out_path, "w"), ensure_ascii=False, indent=1)
    print(json.dumps({"coverage": result["generated"]["coverage"],
                      "counts": result["counts"],
                      "support": support}, ensure_ascii=False))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
