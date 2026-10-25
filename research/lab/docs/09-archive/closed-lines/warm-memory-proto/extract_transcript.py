#!/usr/bin/env python3
"""Warm-memory prototype: checkpoint-lineage transcript extractor.

Offline (no inference). Reads a SimiGo branch-checkpoint meta.json, flattens
the embedded `history` transcript into normalized JSONL, and prints stats the
prototype needs: message count, per-role sizes, client-compaction-summary
location/size (Arm A material), and rough token estimates.

Usage:
  python3 extract_transcript.py <meta.json> <out.jsonl>
"""

import ast
import json
import sys
from pathlib import Path


def normalize(entry: dict, idx: int) -> dict:
    role = entry.get("role", "?")
    content = entry.get("content")
    if isinstance(content, list):  # multimodal parts
        content = " ".join(
            p.get("text", "") for p in content if isinstance(p, dict))
    return {
        "idx": idx,
        "role": role,
        "content": content if isinstance(content, str) else json.dumps(
            content, ensure_ascii=False),
        "tool_calls": entry.get("tool_calls"),
    }


def main(meta_path: str, out_path: str) -> None:
    meta = json.loads(Path(meta_path).read_text())
    history = meta.get("history")
    if isinstance(history, str):
        history = ast.literal_eval(history)
    msgs = [normalize(e, i) for i, e in enumerate(history)]

    with open(out_path, "w", encoding="utf-8") as fh:
        for m in msgs:
            fh.write(json.dumps(m, ensure_ascii=False) + "\n")

    total_chars = sum(len(m["content"] or "") for m in msgs)
    roles: dict[str, int] = {}
    for m in msgs:
        roles[m["role"]] = roles.get(m["role"], 0) + 1

    # Arm A marker: zcode L1 compaction summaries in this corpus open with a
    # status-alignment phrase injected as a user message.
    arm_a = [
        m for m in msgs
        if m["role"] == "user" and "状态已对齐" in (m["content"] or "")[:40]
    ]

    print(json.dumps({
        "meta": Path(meta_path).name,
        "storageKey": meta.get("storageKey"),
        "savedAt": meta.get("savedAt"),
        "messages": len(msgs),
        "roles": roles,
        "total_chars": total_chars,
        "est_tokens_chars_div4": total_chars // 4,
        "client_summary_msgs": [
            {"idx": m["idx"], "chars": len(m["content"] or "")}
            for m in arm_a
        ],
        "out": out_path,
    }, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
