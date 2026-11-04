#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V1.7-A 步长受控重复实验（外审 P1：单次观测 → 交错 ×3 复核）。

120K 会话构建一次（消息持久化到 seed 文件，断点续跑不重建），然后交错：
  cold   512/1024 各 ×3（同消息重放到全新 session，顺序 512↔1024 交错）
  rebuild 512/1024 各 ×3（同 session 首条 user 逐轮不同变异，保证真重渲）

步长经 ~/.simigo/prefill_step_exp 文件运行中切换（RuntimeTuning 实验门），
App 无需重启；实验结束删除该文件即恢复生产语义。

用法：
  python3 tools/step_ab_repeats.py               # 全程（build 若无 seed）
  python3 tools/step_ab_repeats.py --colds-only  # 只跑 cold 侧
前置：SimiGo 运行中、无进行中生成。
"""
import argparse
import json
import time
import urllib.request
from pathlib import Path

import runtime_matrix as rm

STEP_FILE = Path.home() / ".simigo/prefill_step_exp"
OUT = Path("docs/experiments/V17_RUNTIME_MATRIX/results_step_ab_repeats.json")
SEED = Path("docs/experiments/V17_RUNTIME_MATRIX/step_ab_seed_messages.json")
SIDES = ["512", "1024"]
REPEATS = 3


def set_step(side):
    STEP_FILE.write_text(side)


def clear_step():
    if STEP_FILE.exists():
        STEP_FILE.unlink()


def memory_now():
    return {"footprintGB": rm.footprint_gb(), "swapGB": rm.swap_gb()}


def checkpoint(store):
    OUT.write_text(json.dumps(store, ensure_ascii=False, indent=1))


def post(session, messages):
    pos0 = rm.trace_pos()
    t0 = time.time()
    with urllib.request.urlopen(urllib.request.Request(
            rm.BASE, data=json.dumps({"model": rm.MODEL, "session_id": session,
                                      "messages": messages, "max_tokens": 8,
                                      "temperature": 0}).encode(),
            headers={"Content-Type": "application/json"}),
            timeout=7200) as r:
        json.loads(r.read())
    return pos0, round(time.time() - t0, 1)


def record(store, scenario, side, i, session, pos0, wall):
    row = {"scenario": scenario, "side": side, "iter": i, "session": session,
           "wallS": wall, "trace": rm.wait_completion(pos0),
           "memAfter": memory_now()}
    store["runs"].append(row)
    t = row["trace"] or {}
    print(f"  [{scenario} {side} #{i}] wall={wall}s "
          f"promptTime={t.get('promptTimeS')}s mode={t.get('mode')} "
          f"tok={t.get('promptTokens')} swap={row['memAfter']['swapGB']}G",
          flush=True)
    checkpoint(store)


def done(store, scenario, side, i):
    return any(r["scenario"] == scenario and r["side"] == side and r["iter"] == i
               for r in store["runs"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--colds-only", action="store_true")
    args = ap.parse_args()

    # P2（外审 2026-09-19）：实验门文件必须保证清理——异常/中断也不得
    # 遗留 ~/.simigo/prefill_step_exp 影响后续生产运行。
    try:
        run(args)
    finally:
        clear_step()
        print("=== 实验门已清除（finally）===", flush=True)


def run(args):
    store = json.loads(OUT.read_text()) if OUT.exists() else {
        "model": rm.MODEL, "meta": rm.experiment_meta(),
        "design": "interleaved 512/1024 x3, cold then rebuild, 120K", "runs": []}

    if SEED.exists():
        messages = json.loads(SEED.read_text())
        print(f"=== seed 复用（{len(messages)} 条消息）===", flush=True)
    else:
        print("=== build 120K（一次性，消息将持久化）===", flush=True)
        messages, _, _, _ = rm.build_to_depth("stepab", 120000)
        SEED.write_text(json.dumps(messages, ensure_ascii=False))

    print("=== cold 交错 ×3（512↔1024）===", flush=True)
    for i in range(1, REPEATS + 1):
        for side in SIDES:
            if done(store, "cold", side, i):
                continue
            set_step(side)
            pos0, wall = post(f"stepab_c{side}_{i}", messages)
            record(store, "cold", side, i, f"stepab_c{side}_{i}", pos0, wall)

    if args.colds_only:
        print("=== colds-only 完成 ===", flush=True)
        return

    print("=== rebuild 交错 ×3（512↔1024，逐轮不同变异）===", flush=True)
    for i in range(1, REPEATS + 1):
        for side in SIDES:
            if done(store, "rebuild", side, i):
                continue
            set_step(side)
            m = [dict(messages[0])]
            m[0] = dict(m[0])
            m[0]["content"] = m[0]["content"] + f" [mutated-{i}-{side}]"
            m.extend(messages[1:])
            pos0, wall = post("stepab", m)
            record(store, "rebuild", side, i, "stepab", pos0, wall)

    print("=== 全部完成 ===", flush=True)


if __name__ == "__main__":
    main()
