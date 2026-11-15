#!/usr/bin/env python3
"""把 trace 里的「客户端离开」证据对到 chat_messages 的具体行。

只读：不改库、不改 trace。open-problems 第 3 条最后一项验收用。

配对链（一段窗口内）：

    [PROTOCOL] peerClosed r=<req>          ← 客户端真的走了
    [LC] RELEASED r=<req> s=<session> reason=detached_by_client
    [CHAT_TURN_TERMINAL] session=<session> state=detached committed=0
                          ↓  session + 时间窗
    chat_messages: id / turn_state / created_at

用法:
    trace_row_pair.py --since 2026-11-15T06 [--until 2026-11-15T07] [--window 180]

与 05:5x 版的差别（三处都是收紧，不改判据本身）：
  * --until：上一版只有下界，跑「11-13 那个窗口」实际是跑到现在。
  * 要求 terminal 行 committed=0（五条判据里的第 4 条，原先没查）。
  * 配对取「释放线之前、最近的一条同状态行」，不再取窗口内任意一条
    （同一会话里有多条 detached 时会配错）。
"""
import argparse
import os
import re
import sqlite3
import sys
from datetime import datetime

LINE = re.compile(r"^\[(?P<t>[^\]]+)\] (?P<body>.*)$")
PEER = re.compile(r"\[PROTOCOL\] peerClosed r=(?P<r>\S+)")
RELEASE = re.compile(
    r"\[LC\] RELEASED r=(?P<r>\S+) s=(?P<s>\S+) reason=(?P<reason>\S+)")
TERMINAL = re.compile(
    r"\[CHAT_TURN_TERMINAL\] session=(?P<s>\S+) state=(?P<state>\S+)(?: committed=(?P<c>\d+))?")
DETACH_STOP = re.compile(r"\[DETACH\] stop=1 r=(?P<r>\S+) reason=(?P<why>\S+)")
KINDS = ("detached_by_client", "cancelled", "cancel_commit_skip")


def parse(path, since, until):
    peers, releases, terminals, stops = {}, {}, [], {}
    with open(path, errors="replace") as fh:
        for raw in fh:
            m = LINE.match(raw)
            if not m:
                continue
            try:
                t = datetime.strptime(m.group("t")[:19], "%Y-%m-%d %H:%M:%S")
            except ValueError:
                continue
            if (since and t < since) or (until and t > until):
                continue
            body = m.group("body")
            if (x := PEER.search(body)):
                peers[x.group("r")] = t
            elif (x := DETACH_STOP.search(body)):
                stops[x.group("r")] = (t, x.group("why"))
            elif (x := RELEASE.search(body)):
                releases[(x.group("r"), x.group("s"))] = (t, x.group("reason"))
            elif (x := TERMINAL.search(body)):
                terminals.append((t, x.group("s"), x.group("state"), x.group("c")))
    return peers, releases, terminals, stops


def rows_for(db, session, t, window):
    q = """SELECT id, turn_state, created_at FROM chat_messages
           WHERE session_id LIKE ? ORDER BY id"""
    out = []
    for rid, state, created in db.execute(q, ("%" + session + "%",)):
        # created_at 是 Apple 参考时基（2001-01-01Z）的秒数；trace 打的是本机时间。
        at = datetime.fromtimestamp(float(created) + 978307200)
        delta = (t - at).total_seconds()
        if -5 <= delta <= window:          # 行在请求开始时写，释放线在后
            out.append((rid, state, at))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--trace", default=os.path.expanduser("~/.simigo/logs/native_mlx_trace.log"))
    ap.add_argument("--db", default=os.path.expanduser("~/.simigo/simigo.sqlite3"))
    ap.add_argument("--since", default=None, help="YYYY-MM-DDTHH[:MM:SS] 起")
    ap.add_argument("--until", default=None, help="YYYY-MM-DDTHH[:MM:SS] 止")
    ap.add_argument("--window", type=int, default=180, help="行与释放线的允许时差（秒）")
    args = ap.parse_args()

    def ts(s):
        if not s:
            return None
        for fmt in ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%dT%H:%M", "%Y-%m-%dT%H"):
            try:
                return datetime.strptime(s, fmt)
            except ValueError:
                continue
        raise SystemExit("时间格式认不出：%s" % s)

    since, until = ts(args.since), ts(args.until)
    peers, releases, terminals, stops = parse(args.trace, since, until)
    db = sqlite3.connect("file:%s?mode=ro" % args.db, uri=True)
    found = yes = 0
    for (req, sess), (t, reason) in sorted(releases.items(), key=lambda kv: kv[1][0]):
        if reason not in KINDS:
            continue
        found += 1
        peer = peers.get(req)
        term = next(((tt, st, c) for tt, s, st, c in terminals
                     if s == sess and tt >= t and (tt - t).total_seconds() <= args.window), None)
        rows = rows_for(db, sess, t, args.window)
        cand = [r for r in rows if term and r[1] == term[1]]
        match = bool(peer and term and term[2] == "0" and cand)
        yes += match
        print("%s  r=%s s=%s reason=%s" % (t, req, sess, reason))
        print("    peerClosed=%s  terminal=%s  rows=%s  paired=%s"
              % (peer or "-", term or "-",
                 [(r[0], r[1]) for r in rows] or "-", "YES" if match else "NO"))
        if req in stops:
            print("    detachStop=%s reason=%s" % stops[req])
    if not found:
        print("窗口内没有 detached/cancelled 的释放线；先制造一次客户端断连再来。")
    else:
        print("\n合计 %d 条释放线，paired=YES %d 条。" % (found, yes))
    return 0


if __name__ == "__main__":
    sys.exit(main())
