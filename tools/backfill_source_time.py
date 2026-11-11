#!/usr/bin/env python3
"""把各来源的原始对话时间回填进 chat_turn_ledger.source_time（UTC ISO）。

seen_at 是导入批次时间（实测整库只差几分钟），排不出"7 月→8 月→…→11 月"
这条线。原始时间在源文件/会话 id 里，六条来源：

- aistudio:    ~/Desktop/大模型会话记录/Google AI Studio/<标题>
               chunkedPrompt.chunks[] 里第 N 个带 text 的 user chunk 的 createTime
               （ISO UTC；对拍 25/25：库 turn N ↔ 第 N 个 user chunk）
- deepseek:    ~/Desktop/大模型会话记录/deepseek_data-2026-07-29/conversations.json
               mapping 主链第 N 个 REQUEST 消息的 inserted_at（带 +08:00）
               （对拍 25/25；库 140 会话全在 142 个源会话里）
- codex:       ~/.codex/sessions|archived_sessions/**/rollout-<本地ISO>-<uuid>
               文件名，按 uuid 匹配；id 自带日期的（codex-YYYY-MM-DD-*、
               codex-YYYYMMDD-*）直接用日期；都没有的用 seen_at（codex 轮次
               是 codex agent 逐轮实时记账的，seen_at 即对话时刻）
- qoder:       id 内 -Qoder-YYYY-MM-DD- 日期段；短 id（qoder-<8hex>）用 seen_at
               （qoder agent 同样逐轮实时记账）
- flat-export: id 内 YYYYMMDD_HHMMSS（本地时刻）
- zcode:       seen_at 即对话时间（zcode 轮次是实时入账的，Core Data 秒）

写法：只 ALTER 加列、只 UPDATE source_time；不删行、不改其他列。可重复跑。
本地时间按 +08:00 折算成 UTC 存（`YYYY-MM-DDTHH:MM:SSZ`）；只有日期的存
`YYYY-MM-DD`（那天是本地那天）。字典序即时间序。

    python3 tools/backfill_source_time.py            # 回填并打印覆盖率
"""

import glob
import json
import os
import re
import sqlite3
import sys
from datetime import datetime, timedelta, timezone

DB = os.path.expanduser("~/.simigo/simigo.sqlite3")
AI_STUDIO_DIR = os.path.expanduser("~/Desktop/大模型会话记录/Google AI Studio")
AI_STUDIO_DIR_FALLBACK = os.path.expanduser(
    "~/Desktop/大模型会话记录/drive-download-20260728T040110Z-1-001")
DEEPSEEK_JSON = os.path.expanduser(
    "~/Desktop/大模型会话记录/deepseek_data-2026-07-29/conversations.json")
CODEX_SESSIONS = os.path.expanduser("~/.codex/sessions")
CST = timezone(timedelta(hours=8))  # 本地时区

RE_QODER_DATE = re.compile(r"-Qoder-(\d{4}-\d{2}-\d{2})-")
RE_FLAT_TS = re.compile(r"flat-export:(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})")
RE_CODEX_DATE = re.compile(r"codex-(\d{4}-\d{2}-\d{2})-")
RE_CODEX_COMPACT = re.compile(r"codex-\S*?(\d{4})(\d{2})(\d{2})\b")
RE_CODEX_ROLLOUT = re.compile(
    r"rollout-(\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2})-(.+)\.jsonl(?:\.zst)?$")


def iso_utc(dt):
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_local(s):
    """本地(北京)时刻字符串 → UTC ISO；解析失败返回 None。

    兼容 `2026-11-03T19-13-50`（rollout 文件名）与 `2026-08-02T20:59:12`。
    """
    s = re.sub(r"T(\d{2})-(\d{2})-(\d{2})$", r"T\1:\2:\3", s.strip())
    try:
        return iso_utc(datetime.fromisoformat(s).replace(tzinfo=CST))
    except ValueError:
        return None


def deepseek_utc(s):
    """`2025-01-28T02:17:33.787000+08:00` → UTC ISO。"""
    try:
        return iso_utc(datetime.fromisoformat(s))
    except ValueError:
        return None


def coredata_utc(s):
    """`815847801.083776`（2001-01-01 起秒）→ UTC ISO。"""
    try:
        return iso_utc(datetime(2001, 1, 1, tzinfo=timezone.utc)
                       + timedelta(seconds=float(s)))
    except ValueError:
        return None


def load_deepseek_users():
    """{uuid: [该轮 REQUEST 的 inserted_at（UTC ISO），按主链顺序]}"""
    conv = json.load(open(DEEPSEEK_JSON, encoding="utf-8"))
    out = {}
    for c in conv:
        mp = c["mapping"]
        node, times = "root", []
        while True:
            kids = [k for k in (mp.get(node, {}).get("children") or []) if k in mp]
            if not kids:
                break
            node = kids[-1]
            m = mp[node].get("message")
            if not m:
                continue
            for f in m.get("fragments") or []:
                if f.get("type") == "REQUEST" and f.get("content"):
                    t = deepseek_utc(m.get("inserted_at") or "")
                    if t:
                        times.append(t)
                    break
        out[c["id"]] = times
    return out


def load_aistudio_users(path):
    """[该轮 user chunk 的 createTime（UTC ISO），按文件内顺序]"""
    d = json.load(open(path, encoding="utf-8"))
    chunks = d.get("chunkedPrompt", {}).get("chunks", [])
    out = []
    for c in chunks:
        if c.get("role") == "user" and c.get("text"):
            t = (c.get("createTime") or "")[:19]
            try:
                out.append(iso_utc(datetime.strptime(t, "%Y-%m-%dT%H:%M:%S")
                                   .replace(tzinfo=timezone.utc)))
            except ValueError:
                pass
    return out


def main():
    con = sqlite3.connect(DB, timeout=30)
    cols = [r[1] for r in con.execute("PRAGMA table_info(chat_turn_ledger)")]
    if "source_time" not in cols:
        con.execute("ALTER TABLE chat_turn_ledger ADD COLUMN source_time TEXT")
        con.commit()

    led = con.execute(
        "SELECT session_id, turn_index, seen_at FROM chat_turn_ledger "
        "ORDER BY session_id, turn_index").fetchall()

    ds_users = load_deepseek_users()
    codex_rollouts = {}
    for pat_dir in (os.path.join(CODEX_SESSIONS, "*", "*", "*", "rollout-*"),
                    os.path.expanduser("~/.codex/archived_sessions/rollout-*")):
        for p in glob.glob(pat_dir):
            m = RE_CODEX_ROLLOUT.search(os.path.basename(p))
            if m:
                codex_rollouts.setdefault(m.group(2), m.group(1))

    per_prefix = {}
    miss = {}
    cur_sid, aistudio_times = None, None

    for sid, turn, seen_at in led:
        pre = sid.split(":", 1)[0] if ":" in sid else sid.split("-", 1)[0]
        t = None
        if pre == "aistudio":
            title = sid.split(":", 1)[1]
            if sid != cur_sid:
                cur_sid, aistudio_times = sid, None
                p = os.path.join(AI_STUDIO_DIR, title)
                if not os.path.exists(p):
                    p = os.path.join(AI_STUDIO_DIR_FALLBACK, title)
                if os.path.exists(p):
                    try:
                        aistudio_times = load_aistudio_users(p)
                    except Exception:
                        aistudio_times = None
            if aistudio_times and turn - 1 < len(aistudio_times):
                t = aistudio_times[turn - 1]
        elif pre == "deepseek":
            times = ds_users.get(sid.split(":", 1)[1])
            if times and turn - 1 < len(times):
                t = times[turn - 1]
        elif pre == "codex":
            m = RE_CODEX_DATE.search(sid)
            if m:
                t = m.group(1)  # 日期粒度（本地那天）
            else:
                for k, v in codex_rollouts.items():
                    if k and k in sid:
                        t = parse_local(v)
                        break
                if not t:
                    m2 = RE_CODEX_COMPACT.search(sid)
                    if m2:
                        try:
                            datetime.strptime(f"{m2.group(1)}-{m2.group(2)}"
                                              f"-{m2.group(3)}", "%Y-%m-%d")
                            t = f"{m2.group(1)}-{m2.group(2)}-{m2.group(3)}"
                        except ValueError:
                            t = None
                if not t:
                    t = coredata_utc(seen_at)  # 实时记账兜底
        elif pre == "qoder":
            m = RE_QODER_DATE.search(sid)
            if m:
                t = m.group(1)
            else:
                t = coredata_utc(seen_at)  # 短 id：实时记账兜底
        elif pre == "flat-export":
            m = RE_FLAT_TS.match(sid)
            if m:
                t = parse_local(f"{m.group(1)}-{m.group(2)}-{m.group(3)}"
                                f"T{m.group(4)}:{m.group(5)}:{m.group(6)}")
        elif pre == "zcode":
            t = coredata_utc(seen_at)

        if t:
            con.execute("UPDATE chat_turn_ledger SET source_time=? "
                        "WHERE session_id=? AND turn_index=?", (t, sid, turn))
            stat = per_prefix.setdefault(pre, [0, 0])
            stat[0] += 1
        else:
            stat = per_prefix.setdefault(pre, [0, 0])
            stat[1] += 1
            miss[(sid, turn)] = pre

    con.commit()
    total_f = sum(v[0] for v in per_prefix.values())
    total_m = sum(v[1] for v in per_prefix.values())
    print(f"回填完成：命中 {total_f} / 缺 {total_m} / 共 {total_f + total_m}")
    for pre in sorted(per_prefix):
        f, m = per_prefix[pre]
        print(f"  {pre:13s} 命中 {f:5d}  缺 {m:5d}")
    if miss:
        by_sess = {}
        for (sid, turn), pre in miss.items():
            by_sess.setdefault((pre, sid), []).append(turn)
        print("缺口会话（前 15 个）:")
        for (pre, sid), turns in sorted(by_sess.items())[:15]:
            print(f"  {pre:6s} {sid[:60]}  缺 {len(turns)} 轮 "
                  f"(如 turn {min(turns)}..{max(turns)})")
    con.close()


if __name__ == "__main__":
    main()
