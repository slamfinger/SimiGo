#!/usr/bin/env python3
# Copyright © 2026 SimiGo-Lab. Track E(命名待定)Residency Policy Simulator v5
# (P3-C F2 Counter-Basis 拆解;设计 RESIDENCY_P3C_DESIGN_F2_COUNTER_BASIS_
#  20260921.md v0.3,2026-09-21 审核方终审 PASS / Implementation UNLOCKED)
#
# 冻结规范(设计 v0.3):
#   2×2 grid(全 recency tie(last_access, id),F3 固定):
#     A = window 200 无衰减   = V4(P3-B 冻结;回归门复现)
#     B = window 200 + 条目级半衰(唯一新语义格;UNLOCK 后才采)
#     C = cumulative 无衰减  (先验诊断交叉核对:1084.5/775/763 tree)
#     D = cumulative + dict 整除半衰 = lfu_aging(P3-A 冻结;回归门复现)
#   B 格语义:窗口条目 (s,n) 权重 = 2^(K−k),k = now//200 − s//200,
#     K = TRACE_LEN/DECAY = 10;有效计数 = 条目权重和,纯整数。
#   B/D 衰减算子不同构 = 设计故意(D 首要身份 = P3-A frozen reference);
#   cross-basis contrast = (J(B)−J(A)) − F2-b,非严格 factorial
#   interaction,仅描述性。
#   主判据(预注册):R-W = |F2-a| ≥ 35.25;R-D = |F2-b| ≥ 35.25,
#   两线独立可同达;符号纪律:signed delta(+ = J 增加)≠ effect
#   direction(有利/adverse)。全部读数 = cost/effect decomposition,
#   非 causal proof。
#   术语:step-200 首分歧 = structural activation point(参数巧合
#   结构产物,无因子归因力)。
# 门位(审核冻结):Regression Gate(A ≡ V4 / D ≡ lfu_aging /
#   C ≡ prior diagnostic 逐项封锁确认)PASS → 才允许采 B;不是形式手续。
# NORM①②③延续;边界:合成 workload 单 seed;B=12;H=8;W=200=
# 衰减间隔冻结;不反推 P0.2/Track B;V0/P3-A/P3-B 全部封存不动。

import importlib.util
import os
import random
import sys
from collections import deque

_HERE = os.path.dirname(os.path.abspath(__file__))


def _load(name, fname):
    spec = importlib.util.spec_from_file_location(
        name, os.path.join(_HERE, fname))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


sim3 = _load("sim3", "residency_policy_simulator_v3.py")
v4 = _load("v4mod", "residency_policy_simulator_v4.py")

SEED = sim3.SEED
N_NODES = sim3.N_NODES
TRACE_LEN = sim3.TRACE_LEN
C_EXT, C_REHY = sim3.C_EXT, sim3.C_REHY
W = sim3.W_WINDOW
DECAY = sim3.LFU_DECAY_INTERVAL
B_BUDGET = 12
H_MAIN = 8
K = TRACE_LEN // DECAY  # 整数权重缩放(B 格;= 10)

# ---- 冻结参照(P3-A / P3-B 判别表;J round 1 位,rehy/ext 精确)----
FROZEN_A = {"hot": (548.7, 395, 383), "tree": (1133.8, 810, 798)}   # = V4
FROZEN_D = {"hot": (544.4, 392, 380), "tree": (1085.9, 776, 764)}   # = lfu_aging
DIAG_C = {"hot": (544.4, 392, 380), "tree": (1084.5, 775, 763)}     # 先验诊断
FROZEN_LRU = {"hot": (973.1, 696, 684), "tree": (1422.9, 1015, 1003)}
FROZEN_BELADY = {"hot": (475.3, 343, 331), "tree": (740.4, 531, 519)}
GAP_TREE = 70.5          # V0→lfu_aging 原始差距(P3-B 冻结;50% 线分母)
HALF_LINE = GAP_TREE / 2  # 35.25


def run_cell(basis, decay, trace, budget, c_ext, c_rehy, record_seq=False):
    """P3-C cell 引擎(全格 recency tie (last_access, id))。
    basis: "window" | "cum";decay: bool。
    cum/decay(D)复刻 v3 lfu_aging 语义;window/no-decay(A)复刻
    v4 V4 语义——两者均由回归门逐位断言。"""
    resident = set()
    externalized = set()
    last_access = {}
    freq = {}
    window = deque()
    rehy_count = ext_count = violations = 0
    evict_events = 0
    tie_events = 0
    seq = []
    for step, node in enumerate(trace):
        if decay and step > 0 and step % DECAY == 0:
            for k in list(freq):
                freq[k] //= 2
        # NORM①:touch(non-resident → REHYDRATE)
        if node not in resident:
            rehy_count += 1
            externalized.discard(node)
            resident.add(node)
        last_access[node] = step
        freq[node] = freq.get(node, 0) + 1
        if basis == "window":
            window.append((step, node))
            while window and window[0][0] <= step - W:
                window.popleft()
        while len(resident) > budget:
            candidates = [n for n in resident if n != node]  # NORM③
            if not candidates:
                break
            if basis == "cum":
                primary = lambda n: freq.get(n, 0)
            elif decay:  # window + 条目级半衰(B 格;纯整数)
                eff = {}
                kb = step // DECAY
                for (s, nd) in window:
                    kk = kb - s // DECAY
                    eff[nd] = eff.get(nd, 0) + (1 << (K - kk))
                primary = lambda n: eff.get(n, 0)
            else:  # window,无衰减(A 格)
                cnt = {}
                for (s, nd) in window:
                    cnt[nd] = cnt.get(nd, 0) + 1
                primary = lambda n: cnt.get(n, 0)
            vmin = min(primary(n) for n in candidates)
            tie_set = [n for n in candidates if primary(n) == vmin]
            if len(tie_set) >= 2:
                tie_events += 1
            victim = min(candidates,
                         key=lambda n: (primary(n), last_access[n], n))
            evict_events += 1
            resident.discard(victim)
            externalized.add(victim)
            ext_count += 1
            if record_seq:
                seq.append((step, victim))
        if len(resident) > budget:
            violations += 1
    return {"violations": violations,
            "J": c_ext * ext_count + c_rehy * rehy_count,
            "rehy": rehy_count, "ext": ext_count,
            "resident_final": len(resident),
            "evict_events": evict_events, "tie_events": tie_events,
            "seq": seq if record_seq else None}


def core(m):
    return (m["violations"], round(m["J"], 1), m["rehy"], m["ext"])


def main():
    rng = random.Random(SEED)
    parent8 = sim3.gen_topology(N_NODES, 8)
    traces = {
        "hot": sim3.gen_hot_trace(rng, N_NODES, TRACE_LEN),
        "tree": sim3.gen_tree_trace(rng, parent8, N_NODES, TRACE_LEN),
    }

    print("=== Residency Policy Simulator v5(P3-C F2 Counter-Basis 2×2;设计 v0.3 PASS)===")
    print(f"seed={SEED};nodes={N_NODES};trace={TRACE_LEN};B={B_BUDGET};W={W};"
          f"DECAY={DECAY};K={K};C_ext={C_EXT};C_rehy={C_REHY}")
    print("cells: A=window 无衰减(=V4) / B=window+条目级半衰(新) / "
          "C=cumulative 无衰减 / D=cumulative+半衰(=lfu_aging)\n")

    # ============ Regression Gate(先于 B 采集;审核冻结门位)============
    print("-- Regression Gate:A ≡ V4 / D ≡ lfu_aging / C ≡ 诊断值 逐项封锁 --")
    gate_ok = True
    cells = {}
    for wname, trace in traces.items():
        # A:vs P3-B 冻结数字 + vs v4 V4 引擎逐位
        ma = run_cell("window", False, trace, B_BUDGET, C_EXT, C_REHY,
                      record_seq=True)
        cells[("A", wname)] = ma
        mv4 = v4.run_policy("V4", trace, B_BUDGET, C_EXT, C_REHY, H=H_MAIN,
                            record_seq=True)
        fa = FROZEN_A[wname]
        ok = (core(ma) == (ma["violations"], fa[0], fa[1], fa[2])
              and v4.differing_decisions(ma["seq"], mv4["seq"], TRACE_LEN) == 0)
        gate_ok &= ok
        print(f"  A {wname:>5}: J={ma['J']:>7.1f} (rehy={ma['rehy']} ext={ma['ext']}) "
              f"frozen={fa} -> {'OK' if ok else 'FAIL'}(含 v4 序列逐位)")
        # D:vs P3-A 冻结数字 + vs v4 lfu_aging 引擎逐位(v4 自身已经
        # v3 回归门,故 v4 序列即 lfu_aging 语义的逐位基准)
        md = run_cell("cum", True, trace, B_BUDGET, C_EXT, C_REHY,
                      record_seq=True)
        cells[("D", wname)] = md
        mlfu4 = v4.run_policy("lfu_aging", trace, B_BUDGET, C_EXT, C_REHY,
                              H=H_MAIN, record_seq=True)
        fd = FROZEN_D[wname]
        ok = (core(md) == (md["violations"], fd[0], fd[1], fd[2])
              and v4.differing_decisions(md["seq"], mlfu4["seq"],
                                         TRACE_LEN) == 0)
        gate_ok &= ok
        print(f"  D {wname:>5}: J={md['J']:>7.1f} (rehy={md['rehy']} ext={md['ext']}) "
              f"frozen={fd} -> {'OK' if ok else 'FAIL'}(含 v4 序列逐位)")
        # C:vs 先验诊断交叉核对
        mc = run_cell("cum", False, trace, B_BUDGET, C_EXT, C_REHY,
                      record_seq=True)
        cells[("C", wname)] = mc
        fc = DIAG_C[wname]
        ok = (core(mc) == (mc["violations"], fc[0], fc[1], fc[2]))
        gate_ok &= ok
        print(f"  C {wname:>5}: J={mc['J']:>7.1f} (rehy={mc['rehy']} ext={mc['ext']}) "
              f"diagnostic={fc} -> {'OK' if ok else 'FAIL'}")
    # 参照行(冻结)
    for wname, trace in traces.items():
        mlru = sim3.simulate_v3("lru", trace, B_BUDGET, C_EXT, C_REHY, H=H_MAIN)
        mbel = sim3.simulate_v3("belady_greedy", trace, B_BUDGET, C_EXT,
                                C_REHY, H=H_MAIN)
        ok = (round(mlru["J"], 1) == FROZEN_LRU[wname][0]
              and round(mbel["J"], 1) == FROZEN_BELADY[wname][0])
        gate_ok &= ok
        print(f"  参照 {wname:>5}: lru={mlru['J']} belady={mbel['J']} -> "
              f"{'OK' if ok else 'FAIL'}")
    if not gate_ok:
        print("*** Regression Gate FAIL:停,不采集 B(任何一项失败即停)***")
        sys.exit(1)
    print("*** Regression Gate PASS(A/D/C 逐项封锁确认)→ UNLOCK B ***\n")

    # ============ B 采集(UNLOCK 后唯一新格)============
    print("-- B 采集(window + 条目级半衰;唯一新语义格)--")
    for wname, trace in traces.items():
        mb = run_cell("window", True, trace, B_BUDGET, C_EXT, C_REHY,
                      record_seq=True)
        cells[("B", wname)] = mb
        print(f"  B {wname:>5}: J={mb['J']:>7.1f} (rehy={mb['rehy']} "
              f"ext={mb['ext']})")
    print()

    # ============ 2×2 与分解(cost/effect decomposition)============
    print("-- 2×2 grid(B=12,H=8;signed delta:+ = J 增加)--")
    hdr = f"{'cell':>10} {'hot J':>8} {'(rehy/ext)':>12} {'tree J':>8} {'(rehy/ext)':>12}"
    print(hdr)
    for cell in ["A", "B", "C", "D"]:
        mh, mt = cells[(cell, "hot")], cells[(cell, "tree")]
        print(f"{cell:>10} {mh['J']:>8.1f} ({mh['rehy']}/{mh['ext']:>3})"
              f" {mt['J']:>8.1f} ({mt['rehy']}/{mt['ext']:>3})")
    print()
    for wname in ["hot", "tree"]:
        ja, jb, jc, jd = (cells[(c, wname)]["J"] for c in "ABCD")
        f2a = jc - ja
        f2b = jd - jc
        contrast = (jb - ja) - f2b
        # 整数恒等式校验(J100 = 69*ext + 72*rehy,精确)
        j100 = {c: 69 * cells[(c, wname)]["ext"] + 72 * cells[(c, wname)]["rehy"]
                for c in "ABCD"}
        ident = (j100["C"] - j100["A"]) + (j100["D"] - j100["C"]) == \
            j100["D"] - j100["A"]
        print(f"  {wname}: F2-a = J(C)−J(A) = {f2a:+.1f} J"
              f"(window vs cumulative,有利 = window 降本)")
        print(f"        F2-b = J(D)−J(C) = {f2b:+.1f} J"
              f"(decay vs no-decay,adverse = 半衰增本)")
        print(f"        signed 校验 (C−A)+(D−C) = {(f2a + f2b):+.1f} = "
              f"D−A = {jd - ja:+.1f} -> {'OK' if ident else 'FAIL'}(整数精确)")
        print(f"        cross-basis contrast = (J(B)−J(A)) − F2-b = "
              f"{contrast:+.1f} J(描述性;非 factorial interaction)")
        # 主判据(预注册;50% 线 = 35.25)
        rw = abs(f2a) >= HALF_LINE
        rd = abs(f2b) >= HALF_LINE
        print(f"        R-W(|F2-a| ≥ {HALF_LINE}): "
              f"{'成立' if rw else '不成立'};R-D(|F2-b| ≥ {HALF_LINE}): "
              f"{'成立' if rd else '不成立'}(两线独立)")
    print()

    # ============ 机制哨兵(描述性;不承担归因)============
    print("-- 机制哨兵(dd ≥ |Δrehy|;首分歧 = structural activation point)--")
    for wname in ["hot", "tree"]:
        for pa, pb in [("C", "A"), ("D", "C"), ("B", "A")]:
            sa = cells[(pa, wname)]["seq"]
            sb = cells[(pb, wname)]["seq"]
            dd = v4.differing_decisions(sa, sb, TRACE_LEN)
            fd = v4.first_divergence(sa, sb, TRACE_LEN)
            dr = abs(cells[(pa, wname)]["rehy"] - cells[(pb, wname)]["rehy"])
            print(f"  {wname:>5} {pa} vs {pb}: dd={dd:>4} |Δrehy|={dr:>3} "
                  f"-> {'PASS' if dd >= dr else 'FAIL(实现错误)'};"
                  f"首分歧 step={fd}(structural activation point)")
            assert dd >= dr, "行为一致性下界违反:实现/定义错误"
    print()
    print("-- tie_rate(纯辅助,禁归因)--")
    for wname in ["hot", "tree"]:
        row = []
        for c in "ABCD":
            m = cells[(c, wname)]
            row.append(f"{c}={m['tie_events'] / m['evict_events']:.3f}")
        print(f"  {wname:>5}: " + "  ".join(row))
    print()

    # ============ 确定性自检 ============
    b1 = run_cell("window", True, traces["tree"], B_BUDGET, C_EXT, C_REHY)
    b2 = run_cell("window", True, traces["tree"], B_BUDGET, C_EXT, C_REHY)
    det = core(b1) == core(b2) and b1["tie_events"] == b2["tie_events"]
    print(f"确定性自检(B 格同配置重跑): {'PASS' if det else 'FAIL'}")
    assert det

    print()
    print("*** P3-C 2×2 执行完成(Regression Gate PASS 后采 B;全部读数")
    print("*** = cost/effect decomposition,非 causal proof;结果文档")
    print("*** 判读待审核终判)。***")


if __name__ == "__main__":
    main()
