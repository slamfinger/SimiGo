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
import re
import sqlite3
import sys
import time
import urllib.request

DB = os.path.expanduser("~/.simigo/simigo.sqlite3")
ENDPOINT = "http://127.0.0.1:8000/v1/chat/completions"
MODEL = "local"
# 记账调用：不带这个头，请求会走一遍检索并注入约 2,500 tokens 上下文，还会
# 把摘要自己写成一对假问答（35e7ebc 之前实测 796 行）。摘要问的不是「空间里
# 有什么」，是「这段文本说了什么」。
SCOPE_HEADER = {"X-SimiGo-Request-Scope": "internal"}
# 分层投喂：散文行全留，代码块只留前 6 行、声明行与报错行，散文太薄才补标题行。
# 长回答里代码占 86%–97%，而语义全在散文里（2026-11-11 实测：纯散文那一路
# 用 178 字写出比喂 3004 字更具体的摘要）。与 TurnDigestText 同一把尺子。
MAX_QUESTION = 1200
MAX_FEED = 1800
MAX_DECL_LINES = 12
HEAD_LINES = 6
MAX_ERROR_LINES = 8
MAX_HEAD_LINES = 10
DIGEST_LIMIT = 300
MAX_KEYWORDS = 8

DECL_LINE = re.compile(
    r"^\s*(?:public |private |internal |fileprivate |open |static |final |"
    r"@\w+\s+)*(?:func|class|struct|enum|protocol|extension|actor|let|var|"
    r"init|case|import|def|async def|function|export|interface|type)\b")
ERROR_LINE = re.compile(
    r"(error|Error|ERROR|错误|报错|失败|warning|Warning|警告|Exception|"
    r"Traceback|fatal|panic)")
CODE_FENCE = re.compile(r"^\s*```")


def layer_answer(text, budget=MAX_FEED):
    """散文行 + 每块前 6 行 + 声明行 + 报错行。代码体不进 prompt。

    代码体是「修饰」不是「主谓宾」：长回答里它占 86%–97%，而语义全在散文里
    （2026-11-11 实测：纯散文用 178 字写出比喂 3004 字更具体的摘要）。留着
    声明行是因为「提供了什么代码」只能从声明看出来，否则模型会误判成没给代码。
    """
    prose, heads, errors, decls = [], [], [], []
    inside = False
    first_n = 0
    heads_hidden = []
    for raw in text.splitlines():
        line = raw.strip()
        if CODE_FENCE.match(raw):
            inside = not inside
            first_n = 0
            continue
        if not line:
            continue
        if not inside:
            prose.append(line)
            continue
        if first_n < HEAD_LINES:
            heads.append(line)
            first_n += 1
        else:
            heads_hidden.append(line)
        if ERROR_LINE.search(line):
            errors.append(line)
        if DECL_LINE.match(line):
            decls.append(line)

    parts = list(prose) + decls[:MAX_DECL_LINES]
    parts += [h for h in heads[:MAX_HEAD_LINES] if h not in parts]
    parts += [e for e in errors[:MAX_ERROR_LINES] if e not in parts]
    shaped = "\n".join(parts)
    layered = len(heads_hidden) > 0
    if len(shaped) <= budget:
        return shaped, layered
    return shaped[: budget // 2] + "\n……\n" + shaped[-budget // 2:], True


INSTRUCTION = """你在给一个信息空间写轮次摘要。下面是一轮会话的问题和回答。

只输出两行，不要任何解释：
摘要：<两到三句。这一轮要解决什么、最后的结论是什么、哪件事明确没做。不要写"用户说/助手回答"这类套话，不要抄原句>
关键词：<5 到 8 个词，空格分隔。每个词 2 到 8 个字，是以后要拿它检索的东西的名字（如 依赖区间 双时钟 FTS5），不要标点，不要整句>
"""

# 说明写在指令区、不塞进正文（塞正文会被当成原文缺陷）。而且不能只说「别提」，
# 要说清「这一层你看不到、也不在摘要范围内」——只说别提，模型照样写「代码未全部提供」。
NOTE = """注意：回答里的代码体已略去，只留下散文、声明行与报错行。所以你**看不到**代码是否完整，\
这一层也不在摘要范围内——不要评价代码完不完整、有没有给全、是否只是片段。\
原文只要出现代码块，就说明这一轮把代码给出了，不要写「只给了片段」「未提供完整代码」。\
摘要只写：这一轮要解决什么、结论是什么、哪件事明确没做。

"""


def code_meta(text):
    """代码概况：几块、多少行、有哪些声明。

    只留散文时模型会误判成「没给代码 / 只给了片段」——实测 t241 三轮都这么说。
    补一行规模与声明清单，它就知道「给了什么」，而不用看代码体。
    """
    blocks = lines = 0
    inside = False
    decls = []
    for raw in text.splitlines():
        if CODE_FENCE.match(raw):
            inside = not inside
            blocks += 1 if inside else 0
            continue
        if not inside:
            continue
        lines += 1
        if len(decls) < 12 and DECL_LINE.match(raw.strip()):
            decls.append(raw.strip()[:60])
    if not blocks:
        return ""
    return f"【代码概况】{blocks} 个代码块，共 {lines} 行；声明：{'；'.join(decls)}"


def build_prompt(question, answer):
    feed, layered = layer_answer(answer)
    meta = code_meta(answer)
    note = NOTE if layered else ""
    if meta:
        feed = f"{feed}\n\n{meta}"
    return (f"{INSTRUCTION}\n{note}问题：\n{question[:MAX_QUESTION]}"
            f"\n\n回答：\n{feed}\n")


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
        ENDPOINT, data=body,
        headers={"Content-Type": "application/json", **SCOPE_HEADER})
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
            if len(terms) == MAX_KEYWORDS:
                break
    if not terms:
        return digest[:DIGEST_LIMIT], None
    return digest[:DIGEST_LIMIT], terms


def normalize_terms(keywords):
    """关键词归一化。摘要谁写都一样，这里只认词。"""
    terms, seen = [], set()
    for raw in (keywords or "").replace("，", " ").replace("、", " ") \
            .replace(",", " ").split():
        term = raw.strip(" 　.。\"'“”()（）[]【】:：;；")
        if term and term not in seen:
            seen.add(term)
            terms.append(term)
            if len(terms) == MAX_KEYWORDS:
                break
    return terms


def emit(todo, ro, path):
    """把待补轮次连同分层后的投喂正文导出成 JSONL，交给别的模型写摘要。

    只读，不写库。每行一轮：who（定位） + text（喂给模型的问题与回答）。
    """
    n = 0
    with open(path, "w", encoding="utf-8") as out:
        for session, turn, qobj, aobj, qid, aid in todo:
            q = payload(ro, qobj)[:MAX_QUESTION]
            a = payload(ro, aobj)
            if not q and not a:
                continue
            fed, layered = layer_answer(a)
            meta = code_meta(a)
            if meta:
                fed = f"{fed}\n\n{meta}"
            out.write(json.dumps({
                "session": session, "turn": turn,
                "question": q, "answer_fed": fed,
                "layered": layered, "answer_chars": len(a),
            }, ensure_ascii=False) + "\n")
            n += 1
    return n


def ingest(rw, path, model):
    """读回写了摘要的 JSONL 并落库。一行失败不影响其它行。"""
    done = failed = 0
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
                digest = (row.get("digest") or "").strip()
                terms = normalize_terms(row.get("keywords"))
                if not digest or not terms:
                    raise ValueError("缺 digest 或 keywords")
                ids = rw.execute("""
                SELECT
                  (SELECT id FROM chat_messages WHERE session_id=? AND request_id=(
                     SELECT request_id FROM chat_turn_ledger WHERE session_id=? AND turn_index=?)
                   AND role='user' LIMIT 1),
                  (SELECT id FROM chat_messages WHERE session_id=? AND request_id=(
                     SELECT request_id FROM chat_turn_ledger WHERE session_id=? AND turn_index=?)
                   AND role='assistant' LIMIT 1)
                """, (row["session"], row["session"], row["turn"],
                      row["session"], row["session"], row["turn"])).fetchone()
                store(rw, row["session"], row["turn"], ids[0], ids[1],
                      digest[:DIGEST_LIMIT], terms, model)
                done += 1
            except Exception as exc:  # noqa: BLE001 - 一行失败不拖垮整批
                failed += 1
                print(f"[fail] {line[:60]!r} {type(exc).__name__}: {exc}", flush=True)
    return done, failed


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
    ap.add_argument("--emit", metavar="PATH",
                    help="只导出待补轮次到 JSONL，不调模型、不写库")
    ap.add_argument("--ingest", metavar="PATH",
                    help="把写好摘要的 JSONL 落库（digest + keywords 字段）")
    ap.add_argument("--model", default="local", help="写进 model 列的来源标记")
    args = ap.parse_args()

    ro = connect(DB, readonly=True)
    rw = connect(DB)
    todo = pending_turns(ro, args.limit, args.session)

    if args.emit:
        n = emit(todo, ro, args.emit)
        print(f"导出 {n} 轮 → {args.emit}", flush=True)
        return 0
    if args.ingest:
        done, failed = ingest(rw, args.ingest, args.model)
        print(f"落库 {done} 轮，失败 {failed} 行", flush=True)
        return 0 if failed == 0 else 1

    print(f"待补 {len(todo)} 轮", flush=True)
    done = failed = 0
    started = time.time()
    for n, (session, turn, qobj, aobj, qid, aid) in enumerate(todo, 1):
        q = payload(ro, qobj)[:MAX_QUESTION]
        a = payload(ro, aobj)
        if not q and not a:
            print(f"[skip] {session} t{turn} 没有正文", flush=True)
            failed += 1
            continue
        t0 = time.time()
        try:
            out = call_model(build_prompt(q, a))
            digest, terms = parse(out)
            if not digest:
                out = call_model(
                    build_prompt(q, a),
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
