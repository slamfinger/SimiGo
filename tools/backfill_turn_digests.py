#!/usr/bin/env python3
"""用本地 MLX 模型把已有的会话轮次补成摘要 + 关键词。

写的是 `recordTurnDigest`（ESISDatabase.swift）同样三张表、同样的语义：
`turn_digests` 一行一轮（覆盖写）、`keywords` 去重、`turn_keywords` 关联。
改写前先删这一轮的旧关联，否则改过摘要之后旧词还能把这一轮捞出来。

可重复跑：已经有摘要的轮次跳过。

    python3 tools/backfill_turn_digests.py --limit 3      # 先量一轮多贵
    python3 tools/backfill_turn_digests.py                # 全部
"""

import argparse
import json
import os
import sqlite3
import sys
import time
import urllib.request

DB = os.path.expanduser("~/.simigo/simigo.sqlite3")
ENDPOINT = "http://127.0.0.1:8000/v1/chat/completions"
MODEL = "local"
MAX_QUESTION = 3000
MAX_ANSWER = 9000
DIGEST_LIMIT = 300

PROMPT = """你在给一个信息空间写轮次摘要。下面是一轮会话的问题和回答。

只输出两行，不要任何解释：
摘要：<两到三句。这一轮要解决什么、最后的结论是什么、哪件事明确没做。不要写"用户说/助手回答"这类套话，不要抄原句>
关键词：<5 到 8 个词，空格分隔。每个词 2 到 8 个字，是以后要拿它检索的东西的名字（如 依赖区间 双时钟 FTS5），不要标点，不要整句>

问题：
%s

回答：
%s
"""


def connect(path, readonly=False):
    if readonly:
        con = sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=10)
    else:
        con = sqlite3.connect(path, timeout=30)
    con.execute("PRAGMA busy_timeout=30000")
    return con


def pending_turns(con, limit=None, session=None):
    sql = """
    SELECT l.session_id, l.turn_index,
           (SELECT content_object_id FROM chat_messages m
             WHERE m.session_id=l.session_id AND m.request_id=l.request_id
               AND m.role='user' LIMIT 1),
           (SELECT content_object_id FROM chat_messages m
             WHERE m.session_id=l.session_id AND m.request_id=l.request_id
               AND m.role='assistant' LIMIT 1),
           (SELECT id FROM chat_messages m
             WHERE m.session_id=l.session_id AND m.request_id=l.request_id
               AND m.role='user' LIMIT 1),
           (SELECT id FROM chat_messages m
             WHERE m.session_id=l.session_id AND m.request_id=l.request_id
               AND m.role='assistant' LIMIT 1)
      FROM chat_turn_ledger l
     WHERE NOT EXISTS (SELECT 1 FROM turn_digests d
                        WHERE d.session_id=l.session_id
                          AND d.turn_index=l.turn_index)
       AND (? IS NULL OR l.session_id=?)
     ORDER BY l.session_id, l.turn_index
    """
    rows = con.execute(sql, (session, session)).fetchall()
    return rows[:limit] if limit else rows


def payload(con, object_id):
    if not object_id:
        return ""
    row = con.execute(
        "SELECT CAST(content AS TEXT) FROM is_objects WHERE object_id=?",
        (object_id,)).fetchone()
    return row[0] if row else ""


def call_model(text, retry_note=""):
    body = json.dumps({
        "model": MODEL,
        "messages": [{"role": "user", "content": retry_note + text}],
        "max_tokens": 600,
        "temperature": 0.2,
    }).encode()
    req = urllib.request.Request(
        ENDPOINT, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=600) as resp:
        data = json.loads(resp.read())
    return data["choices"][0]["message"]["content"].strip()


def parse(out):
    digest, keywords = None, None
    for line in out.splitlines():
        line = line.strip().lstrip("*-• ").strip()
        if line.startswith("摘要：") or line.startswith("摘要:"):
            digest = line[3:].strip()
        elif line.startswith("关键词：") or line.startswith("关键词:"):
            keywords = line[4:].strip()
    if not digest or not keywords:
        return None, None
    terms, seen = [], set()
    for raw in keywords.replace("，", " ").replace("、", " ").replace(",", " ").split():
        term = raw.strip(" 　.。\"'“”()（）[]【】:：;；")
        if term and term not in seen:
            seen.add(term)
            terms.append(term)
    if not terms:
        return digest[:DIGEST_LIMIT], None
    return digest[:DIGEST_LIMIT], terms


def store(con, session, turn, qid, aid, digest, terms, model):
    # 和 `Self.stamp` 同一把尺子：%.17g 的「2001-01-01 起秒数」，不是 Unix 秒。
    now = f"{time.time() - 978307200:.17g}"
    with con:
        con.execute("""
        INSERT INTO turn_digests(
            session_id, turn_index, question_message_id, answer_message_id,
            digest, keywords, model, created_at)
        VALUES(?,?,?,?,?,?,?,?)
        ON CONFLICT(session_id, turn_index) DO UPDATE SET
            question_message_id=excluded.question_message_id,
            answer_message_id=excluded.answer_message_id,
            digest=excluded.digest, keywords=excluded.keywords,
            model=COALESCE(excluded.model, turn_digests.model),
            created_at=excluded.created_at
        """, (session, turn, qid, aid, digest, " ".join(terms), model, now))
        con.execute(
            "DELETE FROM turn_keywords WHERE session_id=? AND turn_index=?",
            (session, turn))
        for term in terms:
            con.execute(
                "INSERT INTO keywords(term, created_at) VALUES(?,?) "
                "ON CONFLICT(term) DO NOTHING", (term, now))
            kid = con.execute(
                "SELECT keyword_id FROM keywords WHERE term=?", (term,)).fetchone()[0]
            con.execute(
                "INSERT OR IGNORE INTO turn_keywords(session_id, turn_index, keyword_id) "
                "VALUES(?,?,?)", (session, turn, kid))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int)
    ap.add_argument("--session")
    args = ap.parse_args()

    ro = connect(DB, readonly=True)
    rw = connect(DB)
    todo = pending_turns(ro, args.limit, args.session)
    print(f"待补 {len(todo)} 轮", flush=True)
    done = failed = 0
    started = time.time()
    for n, (session, turn, qobj, aobj, qid, aid) in enumerate(todo, 1):
        q = payload(ro, qobj)[:MAX_QUESTION]
        a = payload(ro, aobj)[:MAX_ANSWER]
        if not q and not a:
            print(f"[skip] {session} t{turn} 没有正文", flush=True)
            failed += 1
            continue
        t0 = time.time()
        try:
            out = call_model(PROMPT % (q, a))
            digest, terms = parse(out)
            if not digest:
                out = call_model(
                    PROMPT % (q, a),
                    "上一轮的输出不合格式。只输出两行，第一行以「摘要：」开头，"
                    "第二行以「关键词：」开头。\n\n")
                digest, terms = parse(out)
            if not digest:
                print(f"[fail] {session} t{turn} 格式不合：{out[:80]!r}", flush=True)
                failed += 1
                continue
            store(rw, session, turn, qid, aid, digest,
                  terms or [], f"local:{MODEL}")
            done += 1
            print(f"[{n}/{len(todo)}] {session} t{turn} "
                  f"{time.time() - t0:.1f}s 词{len(terms or [])} {digest[:40]}", flush=True)
        except Exception as exc:  # noqa: BLE001 - 一轮失败不该拖垮整批
            failed += 1
            print(f"[fail] {session} t{turn} {type(exc).__name__}: {exc}", flush=True)
    print(f"完成 {done} 轮，失败 {failed} 轮，用时 {time.time() - started:.0f}s", flush=True)
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
