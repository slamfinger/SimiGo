#!/usr/bin/env python3
"""把轮次按内容归进房间（spaces），维护 space_turns 归属表。

为什么：spaces 现在只有两个目录型空间（参考文件、26.秦沈项目），会话轮次
没有任何归属，IS 的"房间"这一层是空的——素材齐（摘要、关键词）却没有一张
窄表把它们挂到房间上。

判据是**内容归属**，不是来源、不是 agent：谁写的不重要，写的是什么才决定
进哪个房间。房间分轴（project / nature / fallback），**每轮每轴最多一个房间**：
一轮可以同时属于「26.秦沈项目」（项目轴）和「合同类」（性质轴），但不能在同
一轴里挂两个。这是"平铺 + 轴"，不是文件系统那种单路径嵌套。

每一轴单独打分：该轴的判别词命中最多者胜；本轮在该轴没命中，就继承同会话在
该轴的多数（标 inherit）；两条轴都没结果，落「其他」。

房间 = space。目录型空间（人在外部建好的）同样是房间，可以接轮次；本脚本
只新建会话型房间，不碰已有空间。

    python3 tools/assign_turn_spaces.py --dry-run   # 只打印分布
    python3 tools/assign_turn_spaces.py             # 落表

可重复跑：只重写 space_turns 里非人工的行（assigned_by<>'human'），不动其他表。
"""

import os
import re
import sqlite3
import sys
from datetime import datetime, timezone

DB = os.path.expanduser("~/.simigo/simigo.sqlite3")

# 房间：(space_id, 标题, 轴, 判别词正则)。判别词只收有区分度的，别收「修复」
# 「编译」这种满库都有的词，否则每个房间都被命中。
ROOMS = [
    ("space-room-simigo", "SimiGo", "project",
     r"simigo|SettingsView|HTTPServer|McpClient|chat_round"),
    ("space-room-local-inference", "本地推理", "nature",
     r"NativeMLX|^MLX$|mlx-swift|GGUF|llama|量化|显存|KVCache|^KV$|MoE|^MTP$"),
    ("space-room-is", "信息空间", "nature",
     r"信息空间|拓扑|结算|is_objects|turn_digests|检索"),
    # 目录型空间本身就是房间，不再建同名会话房间：标题已存在就复用那一行。
    (None, "26.秦沈项目", "project", r"秦沈|合同|招标|考核|造价"),
]
OTHER = ("space-room-other", "其他", "fallback")

# 一个会话要够这么多条判别词命中，才有资格给「没命中的轮次」当默认房间。
# 少了就会出这种事：整场 201 轮只碰上 1 个「信息空间」，全场被判成信息空间。
MAJORITY_MIN_HITS = 3
# 还要占本会话轮数的 10%。否则一个 475 轮的会话碰上 17 次 SimiGo（3.6%），
# 就把那 475 轮全判进 SimiGo——那不是内容归属，是顺带提了一句。
MAJORITY_MIN_SHARE = 0.10


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def resolve_space(con, sid, title, axis):
    """按标题复用已有空间（目录型也算房间），没有才新建。返回 space_id。"""
    if sid:
        row = con.execute("SELECT space_id FROM spaces WHERE space_id=?", (sid,)).fetchone()
        if row:
            con.execute("UPDATE spaces SET axis=COALESCE(axis,?) WHERE space_id=?", (axis, sid))
            return row[0]
    row = con.execute("SELECT space_id FROM spaces WHERE title=?", (title,)).fetchone()
    if row:
        con.execute("UPDATE spaces SET axis=COALESCE(axis,?) WHERE space_id=?", (axis, row[0]))
        return row[0]
    con.execute(
        "INSERT INTO spaces(space_id,title,title_source,kind,parent_space_id,created_at,axis)"
        " VALUES(?,?,'content','session',NULL,?,?)",
        (sid or f"space-room-{title}", title, now(), axis))
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
        PRIMARY KEY(session_id, turn_index, space_id))""")
    con.execute("CREATE INDEX IF NOT EXISTS idx_space_turns_space"
                " ON space_turns(space_id, session_id, turn_index)")
    rules = [(sid or title, title, axis, re.compile(pat, re.I))
             for sid, title, axis, pat in ROOMS]
    kw = {}
    for s, t, term in con.execute(
            "SELECT tk.session_id, tk.turn_index, k.term FROM turn_keywords tk"
            " JOIN keywords k USING(keyword_id)"):
        kw.setdefault((s, t), []).append(term)

    turns = [r for r in con.execute(
        "SELECT session_id, turn_index FROM turn_digests ORDER BY session_id, turn_index")]

    chosen, hits = {}, 0
    for key in turns:
        terms = kw.get(key, [])
        per_axis = {}
        for sid, title, axis, rx in rules:
            n = sum(1 for x in terms if rx.search(x))
            if n > per_axis.get(axis, (0, None))[0]:
                per_axis[axis] = (n, sid)
        got = {axis: sid for axis, (n, sid) in per_axis.items() if n > 0}
        if got:
            chosen[key] = {axis: (sid, "content") for axis, sid in got.items()}
            hits += 1

    # 会话多数（按轴各算一份），给「本轮在该轴没命中」的轮次继承
    from collections import Counter
    maj = {}
    for (s, _t), per_axis in chosen.items():
        for axis, (room, _) in per_axis.items():
            maj.setdefault((s, axis), Counter())[room] += 1
    turns_per_session = Counter(s for s, _ in turns)
    maj = {k: c.most_common(1)[0][0] for k, c in maj.items()
           if c.most_common(1)[0][1] >= MAJORITY_MIN_HITS
           and c.most_common(1)[0][1] >= MAJORITY_MIN_SHARE * turns_per_session[k[0]]}

    for key in turns:
        per_axis = chosen.setdefault(key, {})
        for axis in ("project", "nature"):
            if axis not in per_axis and (key[0], axis) in maj:
                per_axis[axis] = (maj[(key[0], axis)], "inherit")
        if not per_axis:
            per_axis["fallback"] = (OTHER[0], "other")

    if dry:
        dist = Counter(room for per_axis in chosen.values() for room, _ in per_axis.values())
        by = Counter(by for per_axis in chosen.values() for _, by in per_axis.values())
        print(f"轮次 {len(turns)}；命中判别词 {hits}；归属行 {sum(dist.values())}；来源 {dict(by)}")
        for sid, n in dist.most_common():
            title = next((t for i, t, _a, _p in ROOMS if (i or t) == sid), OTHER[1])
            print(f"  {title:12s} {n:6d}")
        return

    ids = {sid or title: resolve_space(con, sid, title, axis)
           for sid, title, axis, _p in ROOMS}
    ids[OTHER[0]] = resolve_space(con, *OTHER)
    ts = now()
    human = con.execute(
        "SELECT count(*) FROM space_turns WHERE assigned_by='human'").fetchone()[0]
    con.execute("DELETE FROM space_turns WHERE assigned_by<>'human'")
    rows = [(s, t, ids[room], by, ts)
            for (s, t), per_axis in chosen.items()
            for room, by in per_axis.values()]
    con.executemany(
        "INSERT INTO space_turns(session_id,turn_index,space_id,assigned_by,assigned_at)"
        " VALUES(?,?,?,?,?) ON CONFLICT(session_id,turn_index,space_id) DO UPDATE SET"
        " assigned_by=excluded.assigned_by, assigned_at=excluded.assigned_at", rows)
    con.commit()

    dist = dict(con.execute(
        "SELECT space_id, count(*) FROM space_turns GROUP BY 1 ORDER BY 2 DESC"))
    print(f"写入 {len(rows)} 行（保留人工 {human} 行）")
    for sid, n in dist.items():
        title = con.execute("SELECT title FROM spaces WHERE space_id=?", (sid,)).fetchone()
        print(f"  {(title[0] if title else sid):12s} {n:6d}")
    con.close()


if __name__ == "__main__":
    main()
