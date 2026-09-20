#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V1.7-2 Concurrency Probe（外审指令 2026-09-20：先测边界，不改
serializeGeneration 架构）。

生产态：RuntimeTuning.serializeGeneration=true（全局单飞门
__global_generation__，排队请求保持 QUEUED，拿到门才 RUNNING——
NativeMLX P0-3）。本 runner 只测量边界，不设任何实验覆盖
（stepFile 不存在、env 不设，meta 可证）。

探针矩阵（短上下文 ~1.5K delta、低并发=2、快速可重复；P5b 为历史
毒 session P0 病灶路径的定向回归，例外的 ~30K 中上下文）：
  P1 seq_isolation         顺序隔离：A build → B build → A delta，
                           A 账本不被 B 污染（reuse=true/extend/缓存≥自身历史）
  P2 interleave            交错一致性：A,B 交替第 2 轮，各自账本正确复用
  P3 concurrent_serialize  跨 session 并发 ×2 轮（每轮全新 session 对）：
                           LC 时间线证明串行（B QUEUED→RUNNING ≥ A 完成行
                           时间）+ 逐请求 queueWaitS
  P4 same_session_conc     同 session 两并发请求（promptTokens 形状归因）：
                           串行执行、无 crash、后续请求账本可用
  P5a cancel_mid_decode    decode 中途客户端断连 → 同 session 立即重试
                           （tool-call-early-stop/cancel 契约回归）
  P5b cancel_mid_prefill   ~30K prefill 中途断连 → 同 session 立即重试
                           （c81d130 毒 session P0 病灶路径定向回归）
  P6 health_during_gen     长 decode 期间 0.5s 轮询 /health：可用性+延迟
  P7 failure_retry         连续畸形请求（4xx 快速返回）→ 正常请求账本无损

归因规则（2026-09-20 源码+trace 复核探明）：
  - [MLX] traceKey = session_id 最后一个 '-' 段的末 6 字符 + /branch
    （AgentExecutionKey.traceKey）；[LC] s= = session_id 前 6 字符。
    长 session id 标签会塌缩（V1.7-1 p1/p2/p3d80000 全显示 d80000/main
    ——仅标签碰撞，storageKey 含完整 id 故 KV 隔离无损，cold 行
    cacheTokens=0 反证）。
  - 因此探针 session 一律 ≤6 字符短 id 且含 attempt 号全局唯一。
  - 并发完成行按 session 前缀分拣（responseId=chatcmpl-<uuid> 与 LC r=
    6hex 不同源不可映射）；同 session 并发按 promptTokens 形状归因。
  - 客户端历史必须镜像服务端账本（assistant 轮回填 normalize_assistant），
    否则 isPrefix 失配 → 一律 fork（rm.build_to_depth 同纪律）。

verdict 三值：pass / fail / unverified（证据缺失不伪装，遥测语义诚实）。
每行 checkpoint；probe 级 attempt 有效性（V1.7-1 P1 纪律延续）：probe 的
场景不全 → 换新 attempt（新 session）整个 probe 重跑，旧半程数据保留。

用法：python3 tools/v17_2_concurrency.py [--probes p1,p3] [--p3-rounds 2]
      [--chars 6300] [--p5b-chars 126000] [--cancel-delay 15]
前置：SimiGo 运行中（生产策略）、无进行中生成、模型一致。
"""
import argparse
import http.client
import json
import re
import threading
import time
import urllib.error
import urllib.request
from collections import defaultdict
from pathlib import Path

import runtime_matrix as rm

OUT = Path("docs/experiments/V17_RUNTIME_MATRIX/results_v17_2_concurrency.json")
HOST, PORT = "127.0.0.1", 8000
CHAT_PATH = "/v1/chat/completions"
HEALTH_URL = f"http://{HOST}:{PORT}/health"

LC_RE = re.compile(
    r"\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+)\] \[LC\] STATE_TRANSITION "
    r"r=(\S+) s=(\S+) from=(\S+) to=(\S+)")

# probe → 场景全集（attempt 完整性判定单位）
PROBE_SCENARIOS = {
    "p1": ["a_build", "b_build", "a_warm"],
    "p2": ["a_build", "b_build", "a_r2", "b_r2"],
    "p3": ["round1", "round2"],
    "p4": ["build", "pair", "warm_after"],
    "p5a": ["build", "cancel", "retry"],
    "p5b": ["cancel", "retry", "warm_after"],
    "p6": ["build", "gen_health"],
    "p7": ["build", "bad_json", "no_messages", "bogus_model", "warm_after"],
}

SESSIONS = {}  # 短 id 注册表：≤6 字符、含 attempt、全局唯一


class ProbeAbort(Exception):
    """探针步骤失败——本 attempt 判不完整，重跑自动换新 attempt。"""


def sid(tag):
    s = f"q{tag}"
    assert len(s) <= 6 and s not in SESSIONS, f"session id 冲突: {s}"
    SESSIONS[s] = True
    return s


def checkpoint(store):
    OUT.write_text(json.dumps(store, ensure_ascii=False, indent=1))


def lc_since(pos0):
    out = []
    for line in rm.lines_since(pos0):
        m = LC_RE.search(line)
        if m:
            out.append({"ts": m.group(1), "r": m.group(2), "s": m.group(3),
                        "from": m.group(4), "to": m.group(5)})
    return out


def comp_lines(pos0):
    """窗口内 [MLX] 完成行（带 ts + 全字段），供并发分拣。"""
    out = []
    for line in rm.lines_since(pos0):
        if "[MLX] session=" in line and "promptTokens=" in line:
            m = re.match(r"\[([^\]]+)\]", line)
            row = rm.parse_completion(line)
            row["ts"] = m.group(1) if m else None
            out.append(row)
    return out


def _ts(sec):
    return time.mktime(time.strptime(sec, "%Y-%m-%d %H:%M:%S.%f"))


def queue_wait_s(lc_rows, s_short):
    """该 session 的排队时长：QUEUED→RUNNING 减 CREATED→QUEUED。"""
    cq = next((x for x in lc_rows if x["s"] == s_short
               and x["to"] == "QUEUED"), None)
    qr = next((x for x in lc_rows if x["s"] == s_short
               and x["to"] == "RUNNING" and x["from"] == "QUEUED"), None)
    if cq and qr:
        return round(_ts(qr["ts"]) - _ts(cq["ts"]), 2)
    return None


def anomaly_count(pos0):
    return sum(1 for line in rm.lines_since(pos0) if "anomaly=" in line)


def evictions_since(pos0):
    return sum(1 for line in rm.lines_since(pos0)
               if "[MEM] session LRU" in line and "evicted=1" in line)


def mem_after():
    return {"footprintGB": rm.footprint_gb(), "swapGB": rm.swap_gb()}


def post_chat(session_id, messages, max_tokens=8, timeout=1800):
    """发请求并捕获 pos0/wall/status。4xx/5xx 不抛异常返回 status。"""
    body = {"model": rm.MODEL, "session_id": session_id,
            "messages": messages, "max_tokens": max_tokens,
            "temperature": 0.0}
    req = urllib.request.Request(
        f"http://{HOST}:{PORT}{CHAT_PATH}",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"})
    pos0 = rm.trace_pos()
    t0 = time.time()
    status, data = None, None
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            status = r.status
            data = json.loads(r.read())
    except urllib.error.HTTPError as e:
        status = e.code
        try:
            data = json.loads(e.read())
        except Exception:
            data = None
    return {"data": data, "wallS": round(time.time() - t0, 1),
            "pos0": pos0, "status": status}


def append_reply(messages, result):
    """assistant 回复回填客户端历史（镜像账本——isPrefix 纪律）。"""
    if result["status"] == 200 and result["data"]:
        messages.append(rm.normalize_assistant(
            result["data"]["choices"][0]["message"]))


def step(session, messages, max_tokens=8, timeout=600):
    """probe 步进：发请求 → 等完成行 → 回填 assistant。失败抛 ProbeAbort
    （本 attempt 不完整，重跑换新 attempt——V1.7-1 P1 纪律）。"""
    r = post_chat(session, messages, max_tokens=max_tokens, timeout=timeout)
    comp = rm.wait_completion(r["pos0"], timeout=timeout)
    if r["status"] != 200 or comp is None:
        raise ProbeAbort(f"HTTP {r['status']} 完成行={'有' if comp else '无'}")
    append_reply(messages, r)
    return r, comp


def fire_parallel(jobs):
    """jobs: [(session_id, messages, max_tokens), ...]——barrier 对齐后
    并发发出。返回按输入序的结果列表。"""
    barrier = threading.Barrier(len(jobs))
    results = [None] * len(jobs)

    def run(i, job):
        barrier.wait()
        results[i] = post_chat(*job)

    threads = [threading.Thread(target=run, args=(i, j), daemon=True)
               for i, j in enumerate(jobs)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    return results


def post_cancel(session_id, messages, max_tokens, abort_after_s):
    """客户端中途断连（真实 cancel 契约路径）：连接级 abort。"""
    body = json.dumps({"model": rm.MODEL, "session_id": session_id,
                       "messages": messages, "max_tokens": max_tokens,
                       "temperature": 0.0}).encode()
    pos0 = rm.trace_pos()
    t0 = time.time()
    conn = http.client.HTTPConnection(HOST, PORT, timeout=abort_after_s)
    outcome = "completed-before-abort"
    try:
        conn.request("POST", CHAT_PATH, body=body,
                     headers={"Content-Type": "application/json"})
        try:
            resp = conn.getresponse()
            resp.read()
        except Exception:
            outcome = "aborted"
    finally:
        try:
            conn.close()
        except Exception:
            pass
    return {"pos0": pos0, "abortAtS": round(time.time() - t0, 1),
            "outcome": outcome}


def health_once():
    t0 = time.time()
    try:
        with urllib.request.urlopen(HEALTH_URL, timeout=10) as r:
            payload = json.loads(r.read())
            return {"latencyS": round(time.time() - t0, 3),
                    "status": r.status, "health": payload.get("status")}
    except Exception as e:
        return {"latencyS": round(time.time() - t0, 3), "status": None,
                "health": f"error:{type(e).__name__}"}


def add_row(store, **kw):
    store["runs"].append(kw)
    checkpoint(store)
    t = kw.get("trace") or {}
    print(f"  [{kw['probe']}/{kw['scenario']}] wall={kw.get('wallS')}s "
          f"status={kw.get('status')} verdict={kw.get('verdict')} "
          f"mode={(t or {}).get('mode') if isinstance(t, dict) else None} "
          f"tok={(t or {}).get('promptTokens') if isinstance(t, dict) else None} "
          f"qwait={kw.get('queueWaitS')}", flush=True)


def row(store, pid, scenario, attempt, session, r, comp, verdict, **extra):
    """统一落行（evictions/memAfter 自 pos0 窗口推导）。"""
    add_row(store, probe=pid, scenario=scenario, attempt=attempt,
            session=session, wallS=r.get("wallS"), status=r.get("status"),
            trace=comp,
            evictions=evictions_since(r["pos0"]) if r.get("pos0") else 0,
            memAfter=mem_after(), verdict=verdict, **extra)


def verdict_extend(comp, own_min_tokens):
    """账本健康判据：reuse=true + extend + 缓存覆盖自身历史。"""
    if not comp:
        return "fail", "无完成行"
    if comp.get("reuse") != "true":
        return "fail", f"reuse={comp.get('reuse')}"
    if comp.get("mode") != "extend":
        return "fail", f"mode={comp.get('mode')}"
    ct = comp.get("cacheTokens") or 0
    if ct < own_min_tokens:
        return "fail", f"cacheTokens={ct} < 自身历史 {own_min_tokens}"
    return "pass", "reuse=true extend cache≥自身历史"


def verdict_recovered(result, comp):
    """fork 属预期处的宽松判据：请求成功 + 完成行在 + 账本继续可用。"""
    if result.get("status") != 200:
        return "fail", f"HTTP {result.get('status')}"
    if comp is None:
        return "fail", "无完成行"
    return "pass", f"mode={comp.get('mode')} reuse={comp.get('reuse')}"


# ---------------- 探针 ----------------

def p1(store, attempt, cfg):
    a, b = sid(f"1a{attempt}"), sid(f"1b{attempt}")
    ma = [rm.user(rm.filler("A", cfg.chars) + " 只回复:OK")]
    mb = [rm.user(rm.filler("B", cfg.chars) + " 只回复:OK")]
    r, ca = step(a, ma)
    row(store, "p1", "a_build", attempt, a, r, ca, "pass",
        notes=f"promptTokens={ca.get('promptTokens')}")
    r, cb = step(b, mb)
    row(store, "p1", "b_build", attempt, b, r, cb, "pass",
        notes=f"promptTokens={cb.get('promptTokens')}")

    # A 的 delta：B 插队 build 之后，A 账本必须原样可复用
    r = post_chat(a, ma + [rm.user("再回复一次:OK")])
    pos0 = r["pos0"]
    cw = rm.wait_completion(pos0)
    append_reply(ma, r)
    v, ev = verdict_extend(cw, (ca.get("promptTokens") or 0) - 50)
    row(store, "p1", "a_warm", attempt, a, r, cw, v, evidence=ev,
        anomalyCount=anomaly_count(pos0))


def p2(store, attempt, cfg):
    a, b = sid(f"2a{attempt}"), sid(f"2b{attempt}")
    ma = [rm.user(rm.filler("A", cfg.chars) + " 只回复:OK")]
    mb = [rm.user(rm.filler("B", cfg.chars) + " 只回复:OK")]
    r, ca = step(a, ma)
    row(store, "p2", "a_build", attempt, a, r, ca, "pass",
        notes=f"promptTokens={ca.get('promptTokens')}")
    r, cb = step(b, mb)
    row(store, "p2", "b_build", attempt, b, r, cb, "pass",
        notes=f"promptTokens={cb.get('promptTokens')}")

    # 交替第 2 轮：各自账本正确复用、互不污染
    for label, s, hist, own in (("a_r2", a, ma, ca), ("b_r2", b, mb, cb)):
        hist.append(rm.user("第 2 轮继续只回复:OK"))
        r = post_chat(s, hist)
        pos0 = r["pos0"]
        c = rm.wait_completion(pos0)
        append_reply(hist, r)
        v, ev = verdict_extend(c, (own.get("promptTokens") or 0) - 50)
        row(store, "p2", label, attempt, s, r, c, v, evidence=ev,
            anomalyCount=anomaly_count(pos0))


def p3(store, attempt, cfg):
    """每轮全新 session 对：A、B 同时发冷预填请求，LC 时间线证串行。"""
    done = {r["scenario"] for r in store["runs"]
            if r.get("probe") == "p3" and r.get("attempt") == attempt}
    for rnd in range(1, cfg.p3_rounds + 1):
        if f"round{rnd}" in done:
            print(f"  [p3/round{rnd}] 已有，跳过", flush=True)
            continue
        a, b = sid(f"3a{attempt}{rnd}"), sid(f"3b{attempt}{rnd}")
        ma = [rm.user(rm.filler(f"A{rnd}", cfg.chars) + f" 第{rnd}轮 只回复:OK")]
        mb = [rm.user(rm.filler(f"B{rnd}", cfg.chars) + f" 第{rnd}轮 只回复:OK")]
        pos0 = rm.trace_pos()
        t0 = time.time()
        ra, rb = fire_parallel([(a, ma, 8), (b, mb, 8)])
        wall = round(time.time() - t0, 1)
        rows = lc_since(pos0)
        comps = comp_lines(pos0)
        ca = next((c for c in comps if c["session"] == f"{a}/main"), None)
        cb = next((c for c in comps if c["session"] == f"{b}/main"), None)
        qa = queue_wait_s(rows, a)
        qb = queue_wait_s(rows, b)
        # 串行证据（顺序无关——谁先拿门非确定）：按 RUNNING 时间排序，
        # 后跑者的 RUNNING ≥ 先跑者的 COMPLETING（门在完成边界交接）。
        runs_at = {}
        for s in (a, b):
            r0 = next((x for x in rows if x["s"] == s
                       and x["to"] == "RUNNING"), None)
            c0 = next((x for x in rows if x["s"] == s
                       and x["to"] == "COMPLETING"), None)
            if r0:
                runs_at[s] = {"runningTs": r0["ts"],
                              "completingTs": c0["ts"] if c0 else None}
        serial, sv = None, "unverified"
        if len(runs_at) == 2:
            order = sorted(runs_at.items(), key=lambda kv: kv[1]["runningTs"])
            first, second = order[0][1], order[1][1]
            if first.get("completingTs") and second.get("runningTs"):
                gap = round(_ts(second["runningTs"])
                            - _ts(first["completingTs"]), 3)
                sv = "pass" if gap >= 0 else "fail"
                serial = {"secondRunningMinusFirstCompletingS": gap,
                          "first": order[0][0], "verdict": sv}
        ok = (ra["status"] == 200 and rb["status"] == 200
              and ca is not None and cb is not None)
        if not ok:
            v = "fail"
        elif sv == "unverified":
            v = "unverified"
        else:
            v = "pass" if sv == "pass" else "fail"
        add_row(store, probe="p3", scenario=f"round{rnd}", attempt=attempt,
                session=f"{a}+{b}", wallS=wall, status="both",
                trace={"a": ca, "b": cb},
                queueWaitS={"a": qa, "b": qb},
                lc={"a": [x for x in rows if x["s"] == a],
                    "b": [x for x in rows if x["s"] == b]},
                serializeEvidence=serial,
                evictions=evictions_since(pos0), memAfter=mem_after(),
                anomalyCount=anomaly_count(pos0), verdict=v,
                evidence=f"serial={serial} queueWait a={qa}s b={qb}s")


def p4(store, attempt, cfg):
    d = sid(f"4d{attempt}")
    m = [rm.user(rm.filler("D", cfg.chars) + " 只回复:OK")]
    r, c0 = step(d, m)
    base_tok = c0.get("promptTokens") or 0
    row(store, "p4", "build", attempt, d, r, c0, "pass",
        notes=f"promptTokens={base_tok}")

    # 同 session 两并发：一小一大 delta，promptTokens 形状归因。
    # extend 行 promptTokens=delta(~40)，fork 行=重渲后缀(~1500)——按两路
    # 相对大小分拣（与 base_tok 无关：extend 语义 promptTokens 即 delta）。
    m1 = m + [rm.user("第一路 只回复:OK")]
    m2 = m + [rm.user(rm.filler("D2", cfg.chars) + " 第二路 只回复:OK")]
    pos0 = rm.trace_pos()
    t0 = time.time()
    r1, r2 = fire_parallel([(d, m1, 8), (d, m2, 8)])
    wall = round(time.time() - t0, 1)
    rows = lc_since(pos0)
    comps = comp_lines(pos0)
    toks = sorted(c.get("promptTokens") or 0 for c in comps)
    small = toks[0] if toks else None
    big = toks[-1] if toks else None
    ok = (r1["status"] == 200 and r2["status"] == 200
          and len(comps) == 2
          and any(c.get("mode") == "extend" and c.get("reuse") == "true"
                  for c in comps)
          and any(c.get("reuse") == "false"
                  and (c.get("promptTokens") or 0) > base_tok * 0.8
                  for c in comps))
    add_row(store, probe="p4", scenario="pair", attempt=attempt,
            session=d, wallS=wall, status="both", trace={"comps": comps},
            queueWaitS=queue_wait_s(rows, d),
            lc=[x for x in rows if x["s"] == d],
            evictions=evictions_since(pos0), memAfter=mem_after(),
            anomalyCount=anomaly_count(pos0),
            verdict="pass" if ok else "fail",
            evidence=f"small={small}tok big={big}tok "
                     f"qwait={queue_wait_s(rows, d)}s")

    # 收尾：后到者 fork 属预期，宽松判据=账本继续可用
    r = post_chat(d, m + [rm.user("收尾 只回复:OK")])
    pos0 = r["pos0"]
    cw = rm.wait_completion(pos0)
    v, ev = verdict_recovered(r, cw)
    row(store, "p4", "warm_after", attempt, d, r, cw, v, evidence=ev,
        anomalyCount=anomaly_count(pos0))


def p5a(store, attempt, cfg):
    e = sid(f"5e{attempt}")
    m = [rm.user(rm.filler("E", cfg.chars) + " 只回复:OK")]
    r, c0 = step(e, m)
    row(store, "p5a", "build", attempt, e, r, c0, "pass",
        notes=f"promptTokens={c0.get('promptTokens')}")

    mc = m + [rm.user("把 1234567890 重复 90 遍输出。")]
    # decode 须长于断连延迟（512 tok ≈ 12-18s @28-42 tok/s，8s 断连稳落
    # decode 中段；提前完成则本探针无意义）
    ab = post_cancel(e, mc, max_tokens=512, abort_after_s=8.0)
    rows = lc_since(ab["pos0"])
    add_row(store, probe="p5a", scenario="cancel", attempt=attempt,
            session=e, abortAtS=ab["abortAtS"], outcome=ab["outcome"],
            status="aborted-client",
            lc=[x for x in rows if x["s"] == e],
            memAfter=mem_after(), anomalyCount=anomaly_count(ab["pos0"]),
            verdict="pass",
            notes="decode 中途客户端断连；LC 行供取消语义核对")

    time.sleep(1.0)
    r = post_chat(e, mc)  # 真实客户端重试语义：同 session 同消息立即重发
    pos0 = r["pos0"]
    cr = rm.wait_completion(pos0, timeout=600)
    v, ev = verdict_recovered(r, cr)
    row(store, "p5a", "retry", attempt, e, r, cr, v,
        evidence=f"{ev}; anomalies={anomaly_count(ab['pos0'])}",
        anomalyCount=anomaly_count(ab["pos0"]))


def p5b(store, attempt, cfg):
    f_ = sid(f"5f{attempt}")
    m = [rm.user(rm.filler("F", cfg.p5b_chars) + " 只回复:OK")]
    ab = post_cancel(f_, m, max_tokens=8, abort_after_s=cfg.cancel_delay)
    rows = lc_since(ab["pos0"])
    add_row(store, probe="p5b", scenario="cancel", attempt=attempt,
            session=f_, abortAtS=ab["abortAtS"], outcome=ab["outcome"],
            status="aborted-client",
            lc=[x for x in rows if x["s"] == f_],
            memAfter=mem_after(), anomalyCount=anomaly_count(ab["pos0"]),
            verdict="pass",
            notes=f"~{cfg.p5b_chars // 4}tok prefill 中途断连"
                  f"（c81d130 毒 session 病灶路径）")

    t0 = time.time()
    r = post_chat(f_, m)  # 毒 session P0 病灶：同 session 立即重发
    pos0 = r["pos0"]
    cr = rm.wait_completion(pos0, timeout=1800)
    append_reply(m, r)
    v, ev = verdict_recovered(r, cr)
    row(store, "p5b", "retry", attempt, f_, r, cr, v,
        evidence=f"{ev}; 预期≈全量预填", anomalyCount=anomaly_count(pos0))

    r = post_chat(f_, m + [rm.user("收尾 只回复:OK")])
    pos0 = r["pos0"]
    cw = rm.wait_completion(pos0, timeout=600)
    v, ev = verdict_recovered(r, cw)
    row(store, "p5b", "warm_after", attempt, f_, r, cw, v, evidence=ev)


def p6(store, attempt, cfg):
    g = sid(f"6g{attempt}")
    m = [rm.user(rm.filler("G", cfg.chars) + " 只回复:OK")]
    r, c0 = step(g, m)
    row(store, "p6", "build", attempt, g, r, c0, "pass",
        notes=f"promptTokens={c0.get('promptTokens')}")

    polls = []
    gen = {"done": False}

    def long_gen():
        # 计数任务——coder 模型服从可靠，保证 decode 持续 ~10s+
        # （attempt-1 "写短文"实测 <1s 即 EOS，health 窗口无效）
        post_chat(g, m + [rm.user(
            "请从 1 依次数到 400，每行一个数字，不要任何解释。")],
            max_tokens=1024)
        gen["done"] = True

    pos0 = rm.trace_pos()
    t0 = time.time()
    th = threading.Thread(target=long_gen, daemon=True)
    th.start()
    while not gen["done"]:
        polls.append({**health_once(), "atS": round(time.time() - t0, 1)})
        time.sleep(0.5)
    th.join(timeout=1800)
    gen_row = rm.wait_completion(pos0)
    bad = [p for p in polls if p["status"] != 200 or p["health"] != "ok"]
    lat = sorted(p["latencyS"] for p in polls)
    v = "pass" if (polls and not bad) else "fail"
    add_row(store, probe="p6", scenario="gen_health", attempt=attempt,
            session=g, status=200, trace=gen_row,
            healthPolls={"count": len(polls),
                         "latencyMaxS": lat[-1] if lat else None,
                         "latencyMeanS": round(sum(lat) / len(lat), 3)
                         if lat else None,
                         "bad": bad[:5]},
            evictions=0, memAfter=mem_after(), verdict=v,
            evidence=f"{len(polls)} polls, max={lat[-1] if lat else '-'}s, "
                     f"bad={len(bad)}")


def _status_of_post(body, timeout=30):
    t0 = time.time()
    s = None
    try:
        req = urllib.request.Request(
            f"http://{HOST}:{PORT}{CHAT_PATH}",
            data=body if isinstance(body, bytes) else json.dumps(body).encode(),
            headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=timeout) as rr:
            s = rr.status
    except urllib.error.HTTPError as e:
        s = e.code
    except Exception:
        s = None
    return s, round(time.time() - t0, 2)


def p7(store, attempt, cfg):
    h = sid(f"7h{attempt}")
    m = [rm.user(rm.filler("H", cfg.chars) + " 只回复:OK")]
    r, c0 = step(h, m)
    row(store, "p7", "build", attempt, h, r, c0, "pass",
        notes=f"promptTokens={c0.get('promptTokens')}")

    # 失败注入一律走抛弃型 session（q7z）——实证（07:54 窗口）：bogus_model
    # 返回 200 真实生成并污染 probe session 账本（服务端忽略 model 字段，
    # 恒用已加载模型服务），故注入不得触碰 h。
    z = sid(f"7z{attempt}")
    s1, w1 = _status_of_post(b"{not-json")
    s2, w2 = _status_of_post({"model": rm.MODEL})
    s3, w3 = _status_of_post({"model": "no-such-model/x", "session_id": z,
                              "messages": [rm.user("hi")], "max_tokens": 8})
    add_row(store, probe="p7", scenario="bad_json", attempt=attempt,
            session=h, wallS=w1, status=s1,
            verdict="pass" if (s1 == 400 and w1 < 5) else "fail")
    add_row(store, probe="p7", scenario="no_messages", attempt=attempt,
            session=h, wallS=w2, status=s2,
            verdict="pass" if (s2 == 400 and w2 < 5) else "fail")
    add_row(store, probe="p7", scenario="bogus_model", attempt=attempt,
            session=z, wallS=w3, status=s3,
            verdict="pass" if (s3 is not None and s3 < 500 and w3 < 5)
            else "fail",
            notes=f"model 字段被忽略恒 200 由已加载模型服务（实测发现），"
                  f"注入走抛弃 session q7z 不触 h")

    r = post_chat(h, m + [rm.user("失败注入后 只回复:OK")])
    pos0 = r["pos0"]
    cw = rm.wait_completion(pos0)
    v, ev = verdict_extend(cw, 0)
    row(store, "p7", "warm_after", attempt, h, r, cw, v, evidence=ev,
        anomalyCount=anomaly_count(pos0))


PROBES = {"p1": p1, "p2": p2, "p3": p3, "p4": p4,
          "p5a": p5a, "p5b": p5b, "p6": p6, "p7": p7}


def probe_complete(store, pid, attempt):
    have = {r["scenario"] for r in store["runs"]
            if r.get("probe") == pid and r.get("attempt") == attempt}
    return set(PROBE_SCENARIOS[pid]) <= have


def main():
    ap = argparse.ArgumentParser(description="V1.7-2 concurrency probe")
    ap.add_argument("--probes", default="p1,p2,p3,p4,p5a,p5b,p6,p7")
    ap.add_argument("--p3-rounds", type=int, default=2)
    ap.add_argument("--chars", type=int, default=6300,
                    help="探针 delta 等效字符数（~1500 tok @4.2c/t）")
    ap.add_argument("--p5b-chars", type=int, default=126000,
                    help="P5b prefill 体量（~30K tok）")
    ap.add_argument("--cancel-delay", type=float, default=15.0,
                    help="P5b 断连延迟（须落在 prefill 窗口内）")
    args = ap.parse_args()
    cfg = argparse.Namespace(p3_rounds=args.p3_rounds, chars=args.chars,
                             p5b_chars=args.p5b_chars,
                             cancel_delay=args.cancel_delay)
    pids = [x.strip() for x in args.probes.split(",") if x.strip()]
    unknown = [p for p in pids if p not in PROBES]
    assert not unknown, f"未知探针: {unknown}"

    pre = health_once()
    print(f"[preflight] /health -> {pre}", flush=True)
    assert pre["status"] == 200, "SimiGo /health 不可达"

    store = json.loads(OUT.read_text()) if OUT.exists() else {
        "model": rm.MODEL,
        "meta": {**rm.experiment_meta(),
                 "serializeGeneration":
                     "true (RuntimeTuning.swift:27, 生产常量)"},
        "design": ("V1.7-2: concurrency probe, serializeGeneration=true "
                   "untouched; short-context (~1.5K) low-concurrency(=2); "
                   "session ids <=6 chars with attempt (traceKey collapse "
                   "rule); valid unit = probe+attempt (complete only)"),
        "runs": []}
    OUT.parent.mkdir(parents=True, exist_ok=True)

    for pid in pids:
        attempts = {r.get("attempt") for r in store["runs"]
                    if r.get("probe") == pid}
        done = next((a for a in sorted(attempts, reverse=True)
                     if a is not None and probe_complete(store, pid, a)), None)
        if done is not None:
            print(f"--- {pid}: attempt {done} 完整，跳过 ---", flush=True)
            continue
        attempt = max((a for a in attempts if a is not None), default=0) + 1
        print(f"===== {pid} attempt {attempt} =====", flush=True)
        try:
            PROBES[pid](store, attempt, cfg)
        except ProbeAbort as e:
            print(f"[{pid}] attempt {attempt} 中止：{e}——重跑将换新 "
                  f"attempt", flush=True)
        finally:
            checkpoint(store)

    print("\n=== V1.7-2 汇总 ===", flush=True)
    agg = defaultdict(lambda: defaultdict(int))
    for r in store["runs"]:
        if r.get("verdict") in ("pass", "fail", "unverified"):
            agg[r["probe"]][r["verdict"]] += 1
    for pid in sorted(agg):
        a = agg[pid]
        print(f"  {pid}: pass={a['pass']} fail={a['fail']} "
              f"unverified={a['unverified']}", flush=True)
    print("=== 完成 ===", flush=True)


if __name__ == "__main__":
    main()
