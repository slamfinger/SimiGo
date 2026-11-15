#!/usr/bin/env python3
"""逐轮正文探针：把每次真实对话的「写进库的正文」与「交付出去的正文」比一次，落账。

用法：round_verbatim_probe.py [--dry]
    不带参数：扫全库会话，追加新轮次到隐式台账，打印本次增量与累计。
    --dry：只打印，不写台账。

口径（owner 2026-11-15）：
- 正文 = assistant 文本去掉「边界（入库时）：」信封之后的部分。
- VERBATIM 只认逐字节相等；相似度只作诊断，不抵消失败。
- 找不到可比对的宿主消息时记 UNMEASURED，既不是一致也不是不一致。
- 配对按顺序单调推进（先认逐字相等，再退到最像、且不许回头用已用过的消息）。
  不是「每行挑全表最像的」——那会让重复短句把一个判定挪到别的轮上。

只读 chat_messages / is_objects 与 rollout jsonl；台账是唯一写入目标。
"""
import json, os, re, sqlite3, sys, glob, difflib, time

HEADING = "边界（入库时）："
FRAME = "\n\n" + HEADING + "\n"
DB = os.path.expanduser("~/.simigo/simigo.sqlite3")
LEDGER = os.path.expanduser("~/.simigo/logs/verbatim_probe.jsonl")


def norm(s):
    s = re.sub(r"[`*#>|]", "", s)
    s = re.sub(r"[ \t]+", " ", s)
    return re.sub(r"\n+", "\n", s).strip()


def stored():
    db = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    rows = db.execute(
        """select m.session_id, m.request_id, cast(o.content as text)
           from chat_messages m join is_objects o on o.object_id = m.content_object_id
           where m.role = 'assistant' order by m.session_id, m.id""").fetchall()
    out = []
    for sid, rid, text in rows:
        body, sep, _ = text.rpartition(FRAME)
        out.append((sid, rid, body if sep else text))
    return out


def transcripts(session_id):
    tail = session_id[len("codex-"):] if session_id.startswith("codex-") else session_id
    for width in (36, 8):
        hits = glob.glob(os.path.expanduser(f"~/.codex/sessions/*/*/*/rollout-*{tail[:width]}.jsonl"))
        if hits:
            path = max(hits, key=os.path.getmtime)
            msgs = []
            for line in open(path):
                e = json.loads(line)
                p = e.get("payload", {})
                if e.get("type") == "response_item" and p.get("type") == "message" \
                   and p.get("role") == "assistant":
                    msgs.append("".join(c.get("text", "") for c in p.get("content", [])
                                        if isinstance(c, dict)))
            return path, msgs
    return None, []


def pair(bodies, msgs):
    """单调配对：逐字优先，其次最像；不许回头。返回 [(index 或 None, ratio)]。"""
    used, out, cursor = set(), [], 0
    for b in bodies:
        exact = next((j for j in range(cursor, len(msgs)) if msgs[j] == b), None)
        if exact is not None:
            out.append((exact, 1.0))
            cursor = exact + 1
            continue
        cand = [(j, difflib.SequenceMatcher(None, b, msgs[j]).ratio())
                for j in range(cursor, len(msgs))]
        cand = [c for c in cand if c[1] >= 0.5]
        if not cand:
            out.append((None, 0.0))
            continue
        j, r = max(cand, key=lambda c: c[1])
        out.append((j, r))
        cursor = j + 1
    return out


def main():
    dry = "--dry" in sys.argv
    seen = set()
    if os.path.exists(LEDGER):
        for line in open(LEDGER):
            try:
                e = json.loads(line)
                seen.add((e["session"], e["turn"]))
            except Exception:
                pass

    rows = stored()
    by_session = {}
    for sid, rid, body in rows:
        by_session.setdefault(sid, []).append((rid, body))

    new, total = [], len(seen)
    stats = {"VERBATIM": 0, "DIFFERS": 0, "UNMEASURED": 0}
    per_session = []
    skipped = 0
    for sid, items in by_session.items():
        path, msgs = transcripts(sid)
        # 没有转录的会话不进账：那既不是通过也不是失败，只是没有比对物。
        # 它们会让台账里 99% 的行都是 UNMEASURED，把 20 轮的水位淹掉。
        if not msgs:
            skipped += len(items)
            continue
        res = pair([b for _, b in items], msgs)
        used = {j for j, _ in res if j is not None}
        skipped_msgs = [len(msgs[i]) for i in range(len(msgs)) if i not in used]
        got = {"VERBATIM": 0, "DIFFERS": 0, "UNMEASURED": 0}
        for (rid, body), (j, r) in zip(items, res):
            if j is None:
                verdict = "UNMEASURED"
            else:
                verdict = "VERBATIM" if body == msgs[j] else "DIFFERS"
            got[verdict] += 1
            if (sid, rid) in seen:
                continue
            rec = {"at": round(time.time(), 3), "session": sid, "turn": rid,
                   "verdict": verdict, "body": len(body),
                   "msg": len(msgs[j]) if j is not None else None,
                   "raw": round(r, 4),
                   "norm": round(difflib.SequenceMatcher(None, norm(body), norm(msgs[j])).ratio(), 4)
                   if j is not None else None,
                   "rollout": os.path.basename(path) if path else None}
            new.append(rec)
        per_session.append((sid, len(items), got, skipped_msgs))

    for sid, n, got, skipped_msgs in sorted(per_session, key=lambda x: -x[1]):
        # 转录里有、库里没有的消息 = 缺行。长文几乎一定是正文，不是前言。
        gap = ""
        if skipped_msgs:
            gap = "  跳过 " + ",".join(f"{b}B" for b in skipped_msgs)
        print(f"{sid}  轮 {n:>3}  VERBATIM {got['VERBATIM']:>3}  "
              f"DIFFERS {got['DIFFERS']:>3}  UNMEASURED {got['UNMEASURED']:>3}{gap}")
    if skipped:
        print(f"（另有 {skipped} 轮属于没有转录的会话，未进账）")

    for r in new:
        stats[r["verdict"]] += 1
    print(f"\n本次新增 {len(new)} 轮：VERBATIM {stats['VERBATIM']} / "
          f"DIFFERS {stats['DIFFERS']} / UNMEASURED {stats['UNMEASURED']}；台账累计 {total + len(new)}")

    if dry or not new:
        return
    os.makedirs(os.path.dirname(LEDGER), exist_ok=True)
    with open(LEDGER, "a") as f:
        for r in new:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"已写入 {LEDGER}")


if __name__ == "__main__":
    main()
