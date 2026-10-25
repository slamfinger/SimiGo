#!/usr/bin/env python3
"""R4 改动2：分类预算裁剪.

各类独立优先级与预算（先去重，再按类分配有限额度）：
- decisions / constraints / pending / verification 类 facts：必保（必要条件不删）
- state 类 facts：额度 1600c（新近优先）
- event 类 facts：额度 700c（新近优先）
- sources：仅保留被引用者
全局仍超预算时按 state→event 顺序收缩，仍超则如实超额上报（不为凑
预算删必要条件——R3 教训）。预算校准：本血统 ≈2.3 c/tok，目标 ≤2000
tok 实渲染 ≈ 4400c 记忆体（回归的问句包装 ~几十 tok 另计）。

Usage: python3 trim_memory_v4.py warm_memory_v4.json warm_memory_trim4.json
"""

import json
import re
import sys

TOTAL_BUDGET_CHARS = 4400
STATE_QUOTA = 1600
EVENT_QUOTA = 700


def terms(text: str) -> set:
    return set(re.findall(r"[\w\u4e00-\u9fff]{2,}", text))


def dedupe(items: list) -> list:
    out = []
    for it in sorted(items, key=lambda x: -max(x.get("provenance") or [0])):
        t = terms(it.get("text", ""))
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


def chars_of(obj) -> int:
    return len(json.dumps(obj, ensure_ascii=False))


def main(src: str, dst: str) -> None:
    warm = json.load(open(src))
    mem = warm["memory"]
    out = {"decisions": dedupe(mem.get("decisions", [])),
           "constraints": dedupe(mem.get("constraints", [])),
           "pending": dedupe(mem.get("pending", []))}
    facts = dedupe(mem.get("facts", []))
    verif = [f for f in facts if f.get("kind") == "verification"]
    state = [f for f in facts if f.get("kind") == "state"]
    event = [f for f in facts if f.get("kind") not in
             ("verification", "state")]

    kept_state, kept_event = [], []
    state_used = event_used = 0
    for it in state:
        if state_used + chars_of(it) <= STATE_QUOTA:
            kept_state.append(it)
            state_used += chars_of(it)
    for it in event:
        if event_used + chars_of(it) <= EVENT_QUOTA:
            kept_event.append(it)
            event_used += chars_of(it)
    out["facts"] = verif + kept_state + kept_event

    refs = {s.get("idx") for s in mem.get("sources", [])}
    used = set()
    for k in ("decisions", "constraints", "pending", "facts"):
        for it in out[k]:
            used.update(i for i in it.get("provenance", []) if i in refs)
    out["sources"] = [s for s in mem.get("sources", [])
                      if s.get("idx") in used] or mem.get("sources", [])[:6]

    total = chars_of(out)
    over = total > TOTAL_BUDGET_CHARS
    result = {**warm,
              "schema": warm["schema"] + "+budgeted",
              "trim": {"budget_chars": TOTAL_BUDGET_CHARS,
                       "actual_chars": total,
                       "est_tokens": round(total / 2.3),
                       "over_budget": over,
                       "counts": {k: len(v) for k, v in out.items()},
                       "dropped": {"state": len(state) - len(kept_state),
                                   "event": len(event) - len(kept_event)}},
              "memory": out}
    json.dump(result, open(dst, "w"), ensure_ascii=False, indent=1)
    print(json.dumps(result["trim"], ensure_ascii=False))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
