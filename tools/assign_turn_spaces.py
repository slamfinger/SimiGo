#!/usr/bin/env python3
"""把轮次按内容归进房间（spaces），建 space_turns 归属表。

为什么：spaces 现在只有两个目录型空间（参考文件、26.秦沈项目），会话轮次
没有任何归属，IS 的"房间"这一层是空的——素材齐（摘要、关键词）却没有一张
窄表把它们挂到房间上。

判据是**内容归属**，不是来源、不是 agent：谁写的不重要，写的是什么才决定
进哪个房间。一轮里关键词命中哪个房间的判别词最多，就归哪个房间；一轮全不
命中，继承同会话的多数房间（标 inherit）；整个会话都没命中，归「其他」。

房间 = space。目录型空间（人在外部建好的）同样是房间，可以接轮次；本脚本
只新建会话型房间，不碰已有空间。

    python3 tools/assign_turn_spaces.py --dry-run   # 只打印分布
    python3 tools/assign_turn_spaces.py             # 落表

可重复跑：只 UPSERT space_turns，不动其他表；人改过的行（assigned_by='human'）
不会被覆盖。
"""

import os
import re
import sqlite3
import sys
from datetime import datetime, timezone

DB = os.path.expanduser("~/.simigo/simigo.sqlite3")

# 房间：(space_id, 标题, 判别词正则)。判别词只收有区分度的，别收「修复」「编译」
# 这种满库都有的词，否则每个房间都被命中。
ROOMS = [
    ("space-room-simigo", "SimiGo", r"simigo|SettingsView|HTTPServer|McpClient|chat_round"),
    ("space-room-local-inference", "本地推理",
     r"NativeMLX|^MLX$|mlx-swift|GGUF|llama|量化|显存|KVCache|^KV$|MoE|^MTP$"),
    ("space-room-is", "信息空间", r"信息空间|拓扑|结算|is_objects|turn_digests|检索"),
    # 目录型空间本身就是房间，不再建同名会话房间：标题已存在就复用那一行。
    (None, "26.秦沈项目", r"秦沈|合同|招标|考核|造价"),
]
OTHER = ("space-room-other", "其他")

# 一个会话要够这么多条判别词命中，才有资格给「没命中的轮次」当默认房间。
# 少了就会出这种事：整场 201 轮只碰上 1 个「信息空间」，全场被判成信息空间。
MAJORITY_MIN_HITS = 3


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def resolve_space(con, sid, title):
    """按标题复用已有空间（目录型也算房间），没有才新建。返回 space_id。"""
    if sid:
        row = con.execute("SELECT space_id FROM spaces WHERE space_id=?", (sid,)).fetchone()
        if row:
            return row[0]
    row = con.execute("SELECT space_id FROM spaces WHERE title=?", (title,)).fetchone()
    if row:
        return row[0]
    con.execute(
        "INSERT INTO spaces(space_id,title,title_source,kind,parent_space_id,created_at)"
        " VALUES(?,?,'content','session',NULL,?)", (sid or f"space-room-{title}", title, now()))
    return sid or f"space-room-{title}"


def main():
    dry = "--dry-run" in sys.argv
    con = sqlite3.connect(DB, timeout=30)
    con.execute("PRAGMA journal_mode=WAL")

    con.execute("""CREATE TABLE IF NOT EXISTS space_turns(
        session_id TEXT NOT NULL,
        turn_index INTEGER NOT NULL,
        space_id TEXT NOT NULL REFERENCES spaces(space_id),
        assigned_by TEXT NOT NULL,
        assigned_at TEXT NOT NULL,
        PRIMARY KEY(session_id, turn_index))""")
    con.execute("CREATE INDEX IF NOT EXISTS idx_space_turns_space"
                " ON space_turns(space_id, session_id, turn_index)")
    rules = [(sid, title, re.compile(pat, re.I)) for sid, title, pat in ROOMS]
    kw = {}
    for s, t, term in con.execute(
            "SELECT tk.session_id, tk.turn_index, k.term FROM turn_keywords tk"
            " JOIN keywords k USING(keyword_id)"):
        kw.setdefault((s, t), []).append(term)

    turns = [r for r in con.execute(
        "SELECT session_id, turn_index FROM turn_digests ORDER BY session_id, turn_index")]

    chosen, per_turn_hits = {}, 0
    for key in turns:
        terms = kw.get(key, [])
        score = {(sid or title): sum(1 for x in terms if rx.search(x))
                 for sid, title, rx in rules}
        best = max(score, key=score.get) if score else None
        if best and score[best] > 0:
            chosen[key] = (best, "content")
            per_turn_hits += 1

    # 会话多数，给「本轮没命中判别词」的轮次继承
    from collections import Counter
    majority = {}
    for (s, t), (room, _) in chosen.items():
        majority.setdefault(s, Counter())[room] += 1
    majority = {s: c.most_common(1)[0][0] for s, c in majority.items()
                if sum(c.values()) >= MAJORITY_MIN_HITS}

    for key in turns:
        if key not in chosen:
            room = majority.get(key[0])
            chosen[key] = (room, "inherit") if room else (OTHER[0], "other")

    if dry:
        dist = Counter(v[0] for v in chosen.values())
        by = Counter(v[1] for v in chosen.values())
        print(f"轮次 {len(turns)}；命中判别词 {per_turn_hits}；按来源 {dict(by)}")
        for sid, n in dist.most_common():
            title = next((t for i, t, _ in ROOMS if (i or t) == sid), OTHER[1])
            print(f"  {title:12s} {n:6d}")
        return

    ids = {sid or title: resolve_space(con, sid, title) for sid, title, _ in ROOMS}
    ids[OTHER[0]] = resolve_space(con, *OTHER)
    ts = now()
    human = {(r[0], r[1]) for r in con.execute(
        "SELECT session_id, turn_index FROM space_turns WHERE assigned_by='human'")}
    rows = [(s, t, ids[room], by, ts) for (s, t), (room, by) in chosen.items()
            if (s, t) not in human]
    con.executemany(
        "INSERT INTO space_turns(session_id,turn_index,space_id,assigned_by,assigned_at)"
        " VALUES(?,?,?,?,?) ON CONFLICT(session_id,turn_index) DO UPDATE SET"
        " space_id=excluded.space_id, assigned_by=excluded.assigned_by,"
        " assigned_at=excluded.assigned_at", rows)
    con.commit()

    dist = dict(con.execute(
        "SELECT space_id, count(*) FROM space_turns GROUP BY 1 ORDER BY 2 DESC"))
    print(f"写入 {len(rows)} 行（跳过人工 {len(human)} 行）")
    for sid, n in dist.items():
        title = con.execute("SELECT title FROM spaces WHERE space_id=?", (sid,)).fetchone()
        print(f"  {(title[0] if title else sid):12s} {n:6d}")
    con.close()


if __name__ == "__main__":
    main()
