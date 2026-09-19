#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V1.7-1 长上下文真实运行实验（外审指令 2026-09-19）。

40K/80K/120K × (cold/restore/warm/rebuild) × 3 passes，固定生产阶梯步长
（无任何实验覆盖——stepFile 不存在、env 不设，meta 可证）。每 pass 全新
会话构建：restore 风险尾完整（C6 语义）、cold 真新会话、rebuild 逐 pass
不同变异防前 pass 提交污染。逐行记录：trace 全字段 + stepUsed（trace
prefillStep= 实测）+ evictions（本行窗口内 LRU 逐出）+ memAfter +
captureStatus；逐行 checkpoint，可断点续跑（部分完成的 pass 用全新
session id 重做，防半程会话污染语义）。

用法：python3 tools/v17_1_longctx.py [--depths 40000,80000,120000]
前置：SimiGo 运行中（生产策略，无实验门）、无进行中生成。
"""
import argparse
import json
import time
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
    print(f"  [d{kw['depth']} p{kw['passIdx']} {kw['scenario']}] "
          f"wall={kw.get('wallS')}s ptime={t.get('promptTimeS')}s "
          f"mode={t.get('mode')} reuse={t.get('reuse')} "
          f"tok={t.get('promptTokens')} step={t.get('stepUsed')} "
          f"evict={kw.get('evictions')} "
          f"swap={round((kw.get('memAfter') or {}).get('swapGB') or 0, 1)}G",
          flush=True)


def scenario_done(store, depth, p, scenario):
    return any(r["depth"] == depth and r["passIdx"] == p
               and r["scenario"] == scenario for r in store["runs"])


def run_pass(depth, p, session, store):
    """一个完整 pass：新会话 build → restore → warm_setup → warm →
    rebuild → cold。任一场景已记录则跳过（断点续跑）。"""
    print(f"===== depth {depth} pass {p}（session={session}）=====", flush=True)
    messages, tools, build, session_key = rm.build_to_depth(session, depth)
    for b in build:
        if not any(r.get("buildRound") is True and r["depth"] == depth
                   and r["passIdx"] == p and r.get("round") == b["round"]
                   for r in store["runs"]):
            b.update({"depth": depth, "passIdx": p, "scenario": "build",
                      "session": session, "buildRound": True})
            store["runs"].append(b)
            checkpoint(store)

    if not scenario_done(store, depth, p, "restore"):
        call_id = rm.last_tool_call_id(messages)
        m3 = list(messages)
        m3.append({"role": "tool", "tool_call_id": call_id or "call_bench",
                   "content": rm.filler("R", 400)})
        m3.append(rm.user("已收到。请只回复:OK"))
        msg, wall, pos0 = rm.chat(session, m3, tools=[rm.NOTE_TOOL],
                                  max_tokens=16)
        add_row(store, depth=depth, passIdx=p, scenario="restore",
                session=session, wallS=wall,
                trace=rm.wait_completion(pos0, session_key),
                toolCallId=call_id, evictions=evictions_since(pos0),
                memAfter=mem_after())
        m_ledger = list(m3)
        m_ledger.append(rm.normalize_assistant(msg))
    else:
        # 续跑场景：restore 已记录但后续场景未完——账本形状不可重建，
        # 调用方已为本 pass 换新 session，直接重跑整 pass（下方全部场景
        # 逐个判 done，已记录的跳过；此处只需返回不继续用旧账本）。
        return

    if not scenario_done(store, depth, p, "warm_setup"):
        m_plain = list(m_ledger)
        m_plain.append(rm.user("不要调用工具,只回复:OK"))
        msg2, wall, pos0 = rm.chat(session, m_plain, max_tokens=8)
        add_row(store, depth=depth, passIdx=p, scenario="warm_setup",
                session=session, wallS=wall,
                trace=rm.wait_completion(pos0, session_key),
                evictions=evictions_since(pos0), memAfter=mem_after())
        m_plain.append(rm.normalize_assistant(msg2))
    else:
        return

    if not scenario_done(store, depth, p, "warm"):
        m2 = list(m_plain)
        m2.append(rm.user("只回复:OK"))
        _, wall, pos0 = rm.chat(session, m2, max_tokens=8)
        add_row(store, depth=depth, passIdx=p, scenario="warm",
                session=session, wallS=wall,
                trace=rm.wait_completion(pos0, session_key),
                evictions=evictions_since(pos0), memAfter=mem_after())
    else:
        return

    if not scenario_done(store, depth, p, "rebuild"):
        m4 = [dict(messages[0])]
        m4[0] = dict(m4[0])
        m4[0]["content"] = m4[0]["content"] + f" [mutated-p{p}]"
        m4.extend(messages[1:])
        _, wall, pos0 = rm.chat(session, m4, max_tokens=8)
        add_row(store, depth=depth, passIdx=p, scenario="rebuild",
                session=session, wallS=wall,
                trace=rm.wait_completion(pos0, session_key),
                evictions=evictions_since(pos0), memAfter=mem_after())
    else:
        return

    if not scenario_done(store, depth, p, "cold"):
        cold_session = f"{session}c"
        _, wall, pos0 = rm.chat(cold_session, messages, max_tokens=8)
        add_row(store, depth=depth, passIdx=p, scenario="cold",
                session=cold_session, wallS=wall,
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
                   "passes, production step ladder (no override), fresh "
                   "session per pass"),
        "runs": []}
    json.dump(depths, open("/tmp/v17_1_depths.json", "w"))

    for depth in depths:
        for p in range(1, 4):
            # 断点续跑：本 pass 已有行但未全部完成 → 换全新 session id
            # （服务端半程会话不得复用，防语义污染）。
            existing = [r for r in store["runs"]
                        if r["depth"] == depth and r["passIdx"] == p]
            attempt = 1
            if existing:
                complete = all(scenario_done(store, depth, p, s)
                               for s in SCENARIOS)
                if complete:
                    print(f"--- depth {depth} pass {p} 已完成，跳过 ---",
                          flush=True)
                    continue
                attempt = store.get("attempts", {}).get(f"{depth}:{p}", 1) + 1
                store.setdefault("attempts", {})[f"{depth}:{p}"] = attempt
                checkpoint(store)
            session = f"v{depth}p{p}" if attempt == 1 else f"v{depth}p{p}a{attempt}"
            run_pass(depth, p, session, store)

    print("=== V1.7-1 全部完成 ===", flush=True)


if __name__ == "__main__":
    main()
