#!/usr/bin/env python3
"""改动2：按类保护裁剪（round 3）。

策略：类内去重（同 work_item + 关键词重叠）→ 优先级保全
（decisions/constraints/pending 全保）→ facts 按时效（provenance 最大
消息号）top-k → sources 只留被引用者。预算按 chars 控制（校准：本血统
JSON 体 8858c → 实渲染 3920tok ≈ 2.26 c/tok，目标 1750tok ≈ 3950c），
实际渲染 token 由回归轮的 trace 实测回报，不以文件大小充数。

Usage: python3 trim_memory.py warm_memory_v2.json warm_memory_trim.json
"""

import json
import re
import sys

BUDGET_CHARS = 3400
KEEP_ALL = ("decisions", "constraints", "pending")


def terms(text: str) -> set:
    return set(re.findall(r"[\w\u4e00-\u9fff]{2,}", text))


def dedupe(items: list) -> list:
    out = []
    for it in sorted(items, key=lambda x: -max(x.get("provenance") or [0])):
        t = terms(it["text"])
        dup = False
        for kept in out:
            if kept.get("work_item") == it.get("work_item"):
                inter = len(t & terms(kept["text"]))
                if inter and inter / max(len(t), 1) > 0.6:
                    kept.setdefault("provenance", []).extend(
                        it.get("provenance", []))
                    dup = True
                    break
        if not dup:
            out.append(it)
    return out


def main(src: str, dst: str) -> None:
    warm = json.load(open(src))
    mem = warm["memory"]
    trimmed = {}
    used_refs = set()

    for k in KEEP_ALL:
        trimmed[k] = dedupe(mem.get(k, []))
    facts = dedupe(mem.get("facts", []))
    refs = {s["idx"] for s in mem.get("sources", [])}

    def size() -> int:
        return len(json.dumps(
            {k: trimmed.get(k, []) for k in
             ("decisions", "facts", "pending", "constraints", "sources")},
            ensure_ascii=False))

    # 按类保护：verification/ruling/state 类事实必保；event 按新近度让位
    protected = [f for f in facts
                 if f.get("kind") in ("verification", "ruling", "state")]
    events = [f for f in facts if f not in protected]
    kept_facts = protected[:]
    trimmed["facts"] = kept_facts
    for it in events:
        kept_facts.append(it)
        trimmed["facts"] = kept_facts
        if size() > BUDGET_CHARS:
            kept_facts.pop()
            trimmed["facts"] = kept_facts
            break
    for k in ("decisions", "constraints", "pending", "facts"):
        for it in trimmed[k]:
            used_refs.update(i for i in it.get("provenance", []) if i in refs)
    trimmed["sources"] = [
        s for s in mem.get("sources", []) if s.get("idx") in used_refs
    ] or mem.get("sources", [])[:6]

    out = {**warm, "schema": warm["schema"] + "+trimmed",
           "trim": {"budget_chars": BUDGET_CHARS,
                    "est_tokens": round(size() / 2.26),
                    "protected_facts": len(protected), "dropped_events": len(events) - (len(kept_facts) - len(protected))},
           "memory": trimmed}
    json.dump(out, open(dst, "w"), ensure_ascii=False, indent=1)
    print(json.dumps({
        "dst": dst, "chars": size(),
        "est_tokens": out["trim"]["est_tokens"],
        "counts": {k: len(v) for k, v in trimmed.items()},
        "protected": out["trim"]["protected_facts"], "dropped_events": out["trim"]["dropped_events"],
    }, ensure_ascii=False))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
