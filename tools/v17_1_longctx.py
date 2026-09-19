#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V1.7-1 长上下文真实运行实验（外审指令 2026-09-19，断点续跑 P1 修复版）。

40K/80K/120K × (cold/restore/warm/rebuild) × 3 passes，固定生产阶梯步长
（无任何实验覆盖——stepFile 不存在、env 不设，meta 可证）。

有效性单位 = depth + passIdx + attempt：
  - 完整 attempt（5 场景全有）→ 跳过；
  - 不完整 attempt → 一律换全新 session 完整重跑整个 pass（外审 P1：
    不得沿用旧 attempt 的 scenario 完成状态——旧 session 的账本形状
    不可复用，部分续跑必然语义污染）；旧半程数据保留在 JSON 但带旧
    attempt 号，统计只取完整 attempt。

每行记录：trace 全字段 + attempt + stepUsed（trace prefillStep= 实测）+
evictions + memAfter + captureStatus；逐行 checkpoint。

用法：python3 tools/v17_1_longctx.py [--depths 40000,80000,120000]
前置：SimiGo 运行中（生产策略，无实验门）、无进行中生成。
"""
import argparse
import json
from pathlib import Path

import runtime_matrix as rm

OUT = Path("docs/experiments/V17_RUNTIME_MATRIX/results_v17_1_longctx.json")
SCENARIOS = ["restore", "warm_setup", "warm", "rebuild", "cold"]


def evictions_since(pos0):
    return sum(1 for line in rm.lines_since(pos0)
               if "[MEM] session LRU" in line and "evicted=1" in line)


def mem_after():
    return {"footprintGB": rm.footprint_gb(), "swapGB": rm.swap_gb()}


def checkpoint(store):
    OUT.write_text(json.dumps(store, ensure_ascii=False, indent=1))


def add_row(store, **kw):
    store["runs"].append(kw)
    checkpoint(store)
    t = kw.get("trace") or {}
    print(f"  [d{kw['depth']} p{kw['passIdx']} a{kw['attempt']} {kw['scenario']}] "
          f"wall={kw.get('wallS')}s ptime={t.get('promptTimeS')}s "
          f"mode={t.get('mode')} reuse={t.get('reuse')} "
          f"tok={t.get('promptTokens')} step={t.get('stepUsed')} "
          f"evict={kw.get('evictions')} "
          f"swap={round((kw.get('memAfter') or {}).get('swapGB') or 0, 1)}G",
          flush=True)


def attempt_scenarios(store, depth, p, attempt):
    return {r["scenario"] for r in store["runs"]
            if r["depth"] == depth and r["passIdx"] == p
            and r.get("attempt") == attempt and r.get("buildRound") is not True}


def complete_attempt(store, depth, p):
    """返回该 pass 下已完整（5 场景全有）的 attempt 号；无则 None。"""
    attempts = {r.get("attempt") for r in store["runs"]
                if r["depth"] == depth and r["passIdx"] == p}
    for a in sorted(attempts, reverse=True):
        if a is not None and set(SCENARIOS) <= attempt_scenarios(store, depth, p, a):
            return a
    return None


def run_pass(depth, p, attempt, store):
    """一个完整 pass：新会话 build → restore → warm_setup → warm →
    rebuild → cold。无条件全场景执行（调用方保证 attempt 未完成）。"""
    session = f"p{p}d{depth}" if attempt == 1 else f"p{p}d{depth}a{attempt}"
    print(f"===== depth {depth} pass {p} attempt {attempt} "
          f"(session={session}) =====", flush=True)
    messages, tools, build, session_key = rm.build_to_depth(session, depth)
    for b in build:
        b.update({"depth": depth, "passIdx": p, "attempt": attempt,
                  "scenario": "build", "session": session,
                  "buildRound": True})
        store["runs"].append(b)
    checkpoint(store)

    # RESTORE（C6：紧跟 build，风险尾完整；新会话语义逐 attempt 独立）
    call_id = rm.last_tool_call_id(messages)
    m3 = list(messages)
    m3.append({"role": "tool", "tool_call_id": call_id or "call_bench",
               "content": rm.filler("R", 400)})
    m3.append(rm.user("已收到。请只回复:OK"))
    msg, wall, pos0 = rm.chat(session, m3, tools=[rm.NOTE_TOOL],
                              max_tokens=16)
    add_row(store, depth=depth, passIdx=p, attempt=attempt,
            scenario="restore", session=session, wallS=wall,
            trace=rm.wait_completion(pos0, session_key),
            toolCallId=call_id, evictions=evictions_since(pos0),
            memAfter=mem_after())
    m_ledger = list(m3)
    m_ledger.append(rm.normalize_assistant(msg))

    # warm_setup：assistant(normal) 尾
    m_plain = list(m_ledger)
    m_plain.append(rm.user("不要调用工具,只回复:OK"))
    msg2, wall, pos0 = rm.chat(session, m_plain, max_tokens=8)
    add_row(store, depth=depth, passIdx=p, attempt=attempt,
            scenario="warm_setup", session=session, wallS=wall,
            trace=rm.wait_completion(pos0, session_key),
            evictions=evictions_since(pos0), memAfter=mem_after())
    m_plain.append(rm.normalize_assistant(msg2))

    # warm：normal 尾 + 小 delta → extend
    m2 = list(m_plain)
    m2.append(rm.user("只回复:OK"))
    _, wall, pos0 = rm.chat(session, m2, max_tokens=8)
    add_row(store, depth=depth, passIdx=p, attempt=attempt,
            scenario="warm", session=session, wallS=wall,
            trace=rm.wait_completion(pos0, session_key),
            evictions=evictions_since(pos0), memAfter=mem_after())

    # rebuild：首条 user 变异（逐 pass 变异标签区分）
    m4 = [dict(messages[0])]
    m4[0] = dict(m4[0])
    m4[0]["content"] = m4[0]["content"] + f" [mutated-p{p}]"
    m4.extend(messages[1:])
    _, wall, pos0 = rm.chat(session, m4, max_tokens=8)
    add_row(store, depth=depth, passIdx=p, attempt=attempt,
            scenario="rebuild", session=session, wallS=wall,
            trace=rm.wait_completion(pos0, session_key),
            evictions=evictions_since(pos0), memAfter=mem_after())

    # cold：同消息重放到全新 session
    cold_session = f"c{p}d{depth}" if attempt == 1 else f"c{p}d{depth}a{attempt}"
    _, wall, pos0 = rm.chat(cold_session, messages, max_tokens=8)
    add_row(store, depth=depth, passIdx=p, attempt=attempt,
            scenario="cold", session=cold_session, wallS=wall,
            trace=rm.wait_completion(pos0),
            evictions=evictions_since(pos0), memAfter=mem_after())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--depths", default="40000,80000,120000")
    args = ap.parse_args()
    depths = [int(x) for x in args.depths.split(",") if x.strip()]

    store = json.loads(OUT.read_text()) if OUT.exists() else {
        "model": rm.MODEL, "meta": rm.experiment_meta(),
        "design": ("V1.7-1: 40K/80K/120K x (cold/restore/warm/rebuild) x3 "
                   "passes, production step ladder (no override); "
                   "valid unit = depth+passIdx+attempt (complete only)"),
        "runs": []}

    for depth in depths:
        for p in range(1, 4):
            done_attempt = complete_attempt(store, depth, p)
            if done_attempt is not None:
                print(f"--- depth {depth} pass {p}: attempt {done_attempt} "
                      f"完整，跳过 ---", flush=True)
                continue
            # 不完整/未跑：一律全新 attempt（新 session 完整重跑）
            attempts = {r.get("attempt") for r in store["runs"]
                        if r["depth"] == depth and r["passIdx"] == p}
            attempt = max((a for a in attempts if a is not None), default=0) + 1
            run_pass(depth, p, attempt, store)

    print("=== V1.7-1 全部完成 ===", flush=True)


if __name__ == "__main__":
    main()
