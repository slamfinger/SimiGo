#!/usr/bin/env python3
# Copyright © 2026 SimiGo-Lab. Track E(命名待定)Residency Policy Simulator v4
# (P3-B 三因子消融;设计 RESIDENCY_P3B_DESIGN_CAG_SHAPE_20260921.md v0.3,
#  2026-09-21 审核方复审 PASS / Implementation UNLOCKED)
#
# 冻结规范(设计 v0.3):
#   变体集封闭 {V0,V1,V2,V3,V4}(消融组 V0–V3;V4=底座控制组,仅
#   V4−V3 与 V4↔lfu_aging 两差分合法,禁五策略 J 排序解读);
#   V0 = v3 冻结 cost_aware_greedy 语义(min(1,n/H),window 200,tie id);
#   V1 = 同 V0 分数,tie last_access(F3);V2 = S_cont=n/(n+H),tie id
#   (F1;H=half-saturation scale);V3 = S_cont + recency tie(F1×F3);
#   V4 = 窗口原始计数 + recency tie(F2 控制组)。
#   机制通道五通道封顶(§3.1):tie_rate=纯辅助禁归因;
#   F3=tie_resolution_disagreement(V0 轨迹内单跑反事实:同一候选集
#   换 last_access 规则;实现审计点:禁止跨跑对齐/禁止在 V2 轨迹重统计);
#   F1=sat_collision_flip(sat_collision=全体候选饱和 n≥H 事件;部分
#   饱和可证两函数 argmin 同选,只披露;flip=最低 id 候选≠最小 n 候选);
#   F2=eviction 序列对比(V4↔lfu_aging 唯一合法对;首分歧位=主信息);
#   行为一致性下界=不一致驱逐决策数≥|Δrehy|(两侧决策计步法;违反=
#   实现错误,停,不得判读)。预注册反事实量级界(设计 §4 条件2)同时
#   报告,级联效应差异如实披露,判读待审核。
# 执行顺序(审核冻结):V0 回归门(全格逐位复现 P3-A 冻结数字,先于
#   一切变体)→ PASS 才采变体数。变体=诊断工具非 target。
# NORM①②③延续(事件时序/tie-break/working-set:当前节点本步不可驱逐)。
# 边界:合成 workload 单 seed;B=12;C 比 0.69:0.72;结论限定 P3-A
# 固定实验域;P_pressure 通道照旧 raw 口径;不反推 P0.2/Track B。

import importlib.util
import os
import random
import sys
from collections import deque, Counter

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "sim3", os.path.join(_HERE, "residency_policy_simulator_v3.py"))
sim3 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sim3)

SEED = sim3.SEED
N_NODES = sim3.N_NODES
TRACE_LEN = sim3.TRACE_LEN
C_EXT, C_REHY = sim3.C_EXT, sim3.C_REHY
W_WINDOW = sim3.W_WINDOW
LFU_DECAY_INTERVAL = sim3.LFU_DECAY_INTERVAL
B = 12          # 固定基线预算(P3-A 模型验证冻结值)
H_MAIN = 8      # 主轮(P3 设计冻结)

# ---- P3-A PASS 冻结数字(RESIDENCY_P3A_RESULTS v2 判别表 + provenance stdout;
#      回归门比对基准;J 比较 round(...,1),rehy/ext 精确)----
FROZEN = {
    ("hot", "lru"): (973.1, 696, 684),
    ("hot", "lfu_aging"): (544.4, 392, 380),
    ("hot", "cost_aware_greedy"): (547.3, 394, 382),
    ("hot", "belady_greedy"): (475.3, 343, 331),
    ("tree", "lru"): (1422.9, 1015, 1003),
    ("tree", "lfu_aging"): (1085.9, 776, 764),
    ("tree", "cost_aware_greedy"): (1156.4, 826, 814),
    ("tree", "belady_greedy"): (740.4, 531, 519),
}
FROZEN_H = {4: (815.2, 584), 8: (547.3, 394), 16: (547.3, 394)}
FROZEN_PRESSURE = {  # (workload, k_c) -> steps_excess(三策略同值,结构性饱和)
    ("hot", 9): 1990, ("hot", 10): 1984, ("hot", 11): 1983,
    ("tree", 9): 1991, ("tree", 10): 1990, ("tree", 11): 1989,
}


def run_policy(policy, trace, budget, c_ext, c_rehy, H=H_MAIN, k_c=None,
               record_seq=False, cf_instrument=False):
    """与 v3 simulate_v3 同构的执行引擎。policy ∈
    {lru, lfu_aging, belady_greedy}(基线,语义=v3)或
    {V0, V1, V2, V3, V4}(P3-B 变体;V0 ≡ v3 cost_aware_greedy)。
    cf_instrument 仅对 V0:§3.1 单跑反事实 instrumentation,只观测。"""
    assert policy in ("lru", "lfu_aging", "belady_greedy",
                      "V0", "V1", "V2", "V3", "V4"), policy
    assert (not cf_instrument) or policy == "V0"
    resident = set()
    externalized = set()
    last_access = {}
    freq = {}
    window = deque()
    next_use_at = [0] * len(trace)
    last_pos = {}
    for idx in range(len(trace) - 1, -1, -1):
        node = trace[idx]
        next_use_at[idx] = last_pos.get(node, len(trace))
        last_pos[node] = idx
    node_next_use = {}

    ext_count = 0
    rehy_count = 0
    violations = 0
    steps_excess = 0
    stats = {"evict_events": 0, "tie_events": 0,
             "cf_tie_disagree": 0, "sat_collision": 0, "sat_flip": 0}
    seq = []
    has_score = policy in ("V0", "V1", "V2", "V3", "V4")

    def score(n, cnt):
        if policy in ("V0", "V1"):
            return c_rehy * min(1, cnt.get(n, 0) / H)
        if policy in ("V2", "V3"):
            return c_rehy * cnt.get(n, 0) / (cnt.get(n, 0) + H)
        if policy == "V4":
            return cnt.get(n, 0)
        return None

    def evict_victim(current, step, cnt):
        candidates = [n for n in resident if n != current]   # NORM③
        if not candidates:
            return None
        if policy == "belady_greedy":
            key = lambda n: (-node_next_use.get(n, len(trace)), n)
        elif policy == "lru":
            key = lambda n: (last_access[n], n)
        elif policy == "lfu_aging":
            key = lambda n: (freq.get(n, 0), last_access[n], n)
        elif policy == "V0":
            key = lambda n: (c_rehy * min(1, cnt.get(n, 0) / H), n)
        elif policy == "V1":
            key = lambda n: (c_rehy * min(1, cnt.get(n, 0) / H),
                             last_access[n], n)
        elif policy == "V2":
            key = lambda n: (c_rehy * cnt.get(n, 0) / (cnt.get(n, 0) + H), n)
        elif policy == "V3":
            key = lambda n: (c_rehy * cnt.get(n, 0) / (cnt.get(n, 0) + H),
                             last_access[n], n)
        else:  # V4
            key = lambda n: (cnt.get(n, 0), last_access[n], n)
        victim = min(candidates, key=key)
        stats["evict_events"] += 1
        if has_score:  # tie_rate(纯辅助,禁归因;§3.1)
            smin = min(score(n, cnt) for n in candidates)
            if sum(1 for n in candidates if score(n, cnt) == smin) >= 2:
                stats["tie_events"] += 1
        if cf_instrument:  # V0 轨迹内单跑反事实(§3.1;只观测)
            smin = min(c_rehy * min(1, cnt.get(n, 0) / H) for n in candidates)
            tie_set = [n for n in candidates
                       if c_rehy * min(1, cnt.get(n, 0) / H) == smin]
            if len(tie_set) >= 2:
                la_pick = min(tie_set, key=lambda n: last_access[n])
                if la_pick != victim:
                    stats["cf_tie_disagree"] += 1
            if all(cnt.get(n, 0) >= H for n in candidates):
                stats["sat_collision"] += 1
                sc_pick = min(candidates, key=lambda n: (cnt.get(n, 0), n))
                if sc_pick != victim:
                    stats["sat_flip"] += 1
        return victim

    for step, node in enumerate(trace):
        if policy == "lfu_aging" and step > 0 and step % LFU_DECAY_INTERVAL == 0:
            for k in list(freq):
                freq[k] //= 2
        # NORM①:touch(non-resident → REHYDRATE)
        if node not in resident:
            rehy_count += 1
            externalized.discard(node)
            resident.add(node)
        last_access[node] = step
        freq[node] = freq.get(node, 0) + 1
        window.append((step, node))
        while window and window[0][0] <= step - W_WINDOW:
            window.popleft()
        counts = Counter(node for _, node in window)
        if policy == "belady_greedy":
            node_next_use[node] = next_use_at[step]

        while len(resident) > budget:
            victim = evict_victim(node, step, counts)
            if victim is None:
                break
            resident.discard(victim)
            externalized.add(victim)
            ext_count += 1
            if record_seq:
                seq.append((step, victim))
        if len(resident) > budget:
            violations += 1
        if k_c is not None and len(resident) > k_c:
            steps_excess += 1

    out = {
        "violations": violations,
        "J": c_ext * ext_count + c_rehy * rehy_count,
        "rehy": rehy_count,
        "ext": ext_count,
        "resident_final": len(resident),
        "steps_excess": steps_excess,
        "stats": stats,
    }
    if record_seq:
        out["seq"] = seq
    return out


def core(m):
    """回归/等价比较用的核心字段。"""
    return (m["violations"], round(m["J"], 10), m["rehy"], m["ext"],
            m["resident_final"], m["steps_excess"])


def differing_decisions(seq_a, seq_b, trace_len):
    """不一致驱逐决策数(§3.1 下界的合法计数):逐步比较;一步内两侧
    各计自己那次不同决策(含一侧无驱逐)。定理:dd ≥ |Δrehy|。"""
    da = dict(seq_a)
    db = dict(seq_b)
    total = 0
    for t in range(trace_len):
        a = da.get(t)
        b = db.get(t)
        if a is None and b is None:
            continue
        if a is not None and a == b:
            continue
        total += (1 if a is not None else 0) + (1 if b is not None else 0)
    return total


def first_divergence(seq_a, seq_b, trace_len):
    da = dict(seq_a)
    db = dict(seq_b)
    for t in range(trace_len):
        if da.get(t) != db.get(t):
            return t
    return None


def main():
    rng = random.Random(SEED)
    parent8 = sim3.gen_topology(N_NODES, 8)
    traces = {
        "hot": sim3.gen_hot_trace(rng, N_NODES, TRACE_LEN),
        "tree": sim3.gen_tree_trace(rng, parent8, N_NODES, TRACE_LEN),
    }

    print("=== Residency Policy Simulator v4(P3-B 三因子消融;设计 v0.3 PASS)===")
    print(f"seed={SEED};nodes={N_NODES};trace={TRACE_LEN};B={B};H 主轮={H_MAIN};"
          f"C_ext={C_EXT};C_rehy={C_REHY};W={W_WINDOW};LFU_DECAY={LFU_DECAY_INTERVAL}")
    print("变体:V0=min(1,n/H)+id tie;V1=同 V0+recency tie;V2=S_cont=n/(n+H)+id tie;"
          "V3=S_cont+recency tie;V4=窗口原始计数+recency tie(底座控制组)\n")

    # ============ 1. V0 回归门(先于一切变体;设计 §3 条 1)============
    print("-- V0 回归门:v3 全格逐位复现 P3-A 冻结数字 + v4 引擎与 v3 全配置等价 --")
    gate_ok = True
    sim3_runs = {}
    for wname, trace in traces.items():
        for policy in ["lru", "lfu_aging", "cost_aware_greedy", "belady_greedy"]:
            m = sim3.simulate_v3(policy, trace, B, C_EXT, C_REHY, H=H_MAIN)
            sim3_runs[(wname, policy, H_MAIN)] = m
            j, r, x = FROZEN[(wname, policy)]
            ok = (round(m["J"], 1) == j and m["rehy"] == r and m["ext"] == x
                  and m["violations"] == 0)
            gate_ok &= ok
            print(f"  v3 {wname:>5}/{policy:>18}: J={m['J']:>7.1f} (rehy={m['rehy']:>4} "
                  f"ext={m['ext']:>3}) frozen={j} -> {'OK' if ok else 'FAIL'}")
    for h in (4, 16):
        m = sim3.simulate_v3("cost_aware_greedy", traces["hot"], B, C_EXT, C_REHY, H=h)
        sim3_runs[("hot", "cost_aware_greedy", h)] = m
        j, r = FROZEN_H[h]
        ok = (round(m["J"], 1) == j and m["rehy"] == r)
        gate_ok &= ok
        print(f"  v3 hot /cost_aware_greedy H={h:>2}: J={m['J']:>7.1f} frozen={j} -> "
              f"{'OK' if ok else 'FAIL'}")
    for (wname, k_c), fx in FROZEN_PRESSURE.items():
        for policy in ["lru", "lfu_aging", "cost_aware_greedy"]:
            m = sim3.simulate_v3(policy, traces[wname], B, C_EXT, C_REHY,
                                 H=H_MAIN, k_c=k_c)
            ok = m["steps_excess"] == fx
            gate_ok &= ok
            if policy == "lru":
                print(f"  v3 {wname:>5}/k_c={k_c}: pressure_raw={m['steps_excess']} "
                      f"frozen={fx} -> {'OK' if ok else 'FAIL'}(三策略同断言)")
    # v4 引擎 ≡ v3:全配置核心字段逐一相等(含 pressure 配置)
    equiv_fail = 0
    for wname, trace in traces.items():
        for policy in ["lru", "lfu_aging", "cost_aware_greedy", "belady_greedy"]:
            for h in ([H_MAIN] if policy != "cost_aware_greedy" else [4, 8, 16]):
                ep = "V0" if policy == "cost_aware_greedy" else policy
                ev = run_policy(ep, trace, B, C_EXT, C_REHY, H=h)
                sv = sim3.simulate_v3(policy, trace, B, C_EXT, C_REHY, H=h)
                if core(ev) != core(sv):
                    equiv_fail += 1
                    print(f"  ENGINE≠v3 {wname}/{policy} H={h}")
        for k_c in (9, 10, 11):
            for policy in ["lru", "lfu_aging", "cost_aware_greedy"]:
                ep = "V0" if policy == "cost_aware_greedy" else policy
                ev = run_policy(ep, trace, B, C_EXT, C_REHY, H=H_MAIN, k_c=k_c)
                sv = sim3.simulate_v3(policy, trace, B, C_EXT, C_REHY,
                                      H=H_MAIN, k_c=k_c)
                if core(ev) != core(sv):
                    equiv_fail += 1
                    print(f"  ENGINE≠v3 {wname}/{policy} k_c={k_c}")
    if equiv_fail:
        gate_ok = False
        print(f"  v4 引擎等价检查 FAIL x{equiv_fail}")
    else:
        print("  v4 引擎 ≡ v3:主表 8 格 + H 敏感性 + pressure 18 配置核心字段全部相等")
    if not gate_ok:
        print("*** V0 回归门 FAIL:停,不采任何变体数(设计 §3 条 1)***")
        sys.exit(1)
    print("*** V0 回归门 PASS(逐位复现 P3-A 冻结数字)***\n")

    # ============ 2. 消融采数(回归门 PASS 后;设计 §2 封闭变体集)============
    print("-- 消融组(分区呈现:V0–V3 = 消融;lfu_aging/V4 = 参照与控制,§2.2)--")
    res = {}
    for wname, trace in traces.items():
        # 消融组
        m0 = run_policy("V0", trace, B, C_EXT, C_REHY, H=H_MAIN,
                        record_seq=True, cf_instrument=True)
        res[(wname, "V0")] = m0
        print(f"  {wname:>5}/V0(H=8): J={m0['J']:>7.1f} (rehy={m0['rehy']:>4} "
              f"ext={m0['ext']:>3}) [instrumented;≡v3 已由回归门断言]")
        for pol in ["V1", "V2", "V3"]:
            m = run_policy(pol, trace, B, C_EXT, C_REHY, H=H_MAIN, record_seq=True)
            res[(wname, pol)] = m
            print(f"  {wname:>5}/{pol}(H=8): J={m['J']:>7.1f} (rehy={m['rehy']:>4} "
                  f"ext={m['ext']:>3})")
        # 参照与控制组
        ml = run_policy("lfu_aging", trace, B, C_EXT, C_REHY, H=H_MAIN,
                        record_seq=True)
        res[(wname, "lfu_aging")] = ml
        print(f"  {wname:>5}/lfu_aging(参照): J={ml['J']:>7.1f} (rehy={ml['rehy']:>4} "
              f"ext={ml['ext']:>3}) [≡P3-A 冻结]")
        m4 = run_policy("V4", trace, B, C_EXT, C_REHY, H=H_MAIN, record_seq=True)
        res[(wname, "V4")] = m4
        print(f"  {wname:>5}/V4(控制组): J={m4['J']:>7.1f} (rehy={m4['rehy']:>4} "
              f"ext={m4['ext']:>3})")
        mlru = run_policy("lru", trace, B, C_EXT, C_REHY, H=H_MAIN)
        print(f"  {wname:>5}/lru(baseline): J={mlru['J']:>7.1f} [≡P3-A 冻结]")
    print()
    print("-- V2/V3 H sensitivity(H=half-saturation scale;主轮 8)--")
    for wname, trace in traces.items():
        for pol in ["V2", "V3"]:
            for h in (4, 16):
                m = run_policy(pol, trace, B, C_EXT, C_REHY, H=h)
                print(f"  {wname:>5}/{pol} H={h:>2}: J={m['J']:>7.1f} "
                      f"(rehy={m['rehy']})")
    print()

    # ============ 3. 机制通道(§3.1;五通道封顶)============
    print("-- 机制通道(V0 轨迹内单跑反事实;tie_rate=纯辅助禁归因)--")
    for wname in ["hot", "tree"]:
        m0 = res[(wname, "V0")]
        st = m0["stats"]
        tie = st["tie_events"]
        sat = st["sat_collision"]
        print(f"  {wname}: evict_events={st['evict_events']} "
              f"tie_events={tie} (tie_rate={tie / st['evict_events']:.3f})")
        print(f"       F3 cf_tie_disagree={st['cf_tie_disagree']} "
              f"(占 tie 事件 {st['cf_tie_disagree'] / tie:.3f})" if tie else
              f"       F3 cf_tie_disagree={st['cf_tie_disagree']}(无 tie 事件)")
        print(f"       F1 sat_collision={sat} "
              f"(事件率 {sat / st['evict_events']:.3f}) sat_flip={st['sat_flip']}"
              + (f"(flip 率 {st['sat_flip'] / sat:.3f})" if sat else ""))
        for pol in ["V1", "V2", "V3", "V4"]:
            tie_v = res[(wname, pol)]["stats"]["tie_events"]
            ev_v = res[(wname, pol)]["stats"]["evict_events"]
            print(f"       {pol} 自报 tie_rate={tie_v / ev_v:.3f}(描述,禁归因)")
    print()

    print("-- F2 控制对(V4 ↔ lfu_aging,唯一合法;首分歧位=主信息)--")
    for wname in ["hot", "tree"]:
        s4 = res[(wname, "V4")]["seq"]
        sl = res[(wname, "lfu_aging")]["seq"]
        dd = differing_decisions(s4, sl, TRACE_LEN)
        fd = first_divergence(s4, sl, TRACE_LEN)
        dr = abs(res[(wname, "V4")]["rehy"] - res[(wname, "lfu_aging")]["rehy"])
        # 位置对齐 agreement(辅助描述;§3.1 定义 4)
        n = min(len(s4), len(sl))
        agree = sum(1 for i in range(n) if s4[i][1] == sl[i][1])
        print(f"  {wname}: V4 驱逐 {len(s4)} 次 / lfu_aging {len(sl)} 次; "
              f"位置对齐 agreement={agree}/{n}={agree / n:.3f}")
        print(f"       首分歧 step={fd};不一致驱逐决策 dd={dd};|Δrehy|={dr} "
              f"-> 下界 {'PASS' if dd >= dr else 'FAIL(实现错误)'}")
        assert dd >= dr, "行为一致性下界违反:实现/定义错误(§3.1 定义 5)"
    print()

    print("-- 行为一致性下界(定理形式;任意消融对;违反=实现错误)--")
    for wname in ["hot", "tree"]:
        for pa, pb in [("V1", "V0"), ("V2", "V0"), ("V3", "V0")]:
            dd = differing_decisions(res[(wname, pa)]["seq"],
                                     res[(wname, pb)]["seq"], TRACE_LEN)
            dr = abs(res[(wname, pa)]["rehy"] - res[(wname, pb)]["rehy"])
            print(f"  {wname:>5} {pa} vs {pb}: dd={dd:>4} |Δrehy|={dr:>3} "
                  f"-> {'PASS' if dd >= dr else 'FAIL(实现错误)'}")
            assert dd >= dr, "行为一致性下界违反:实现/定义错误(§3.1 定义 5)"
    print()

    print("-- 预注册反事实量级界(设计 §4 条件 2 原文;级联效应如实披露)--")
    for wname in ["hot", "tree"]:
        st = res[(wname, "V0")]["stats"]
        d1 = abs(res[(wname, "V1")]["rehy"] - res[(wname, "V0")]["rehy"])
        d2 = abs(res[(wname, "V2")]["rehy"] - res[(wname, "V0")]["rehy"])
        c1 = "PASS" if st["cf_tie_disagree"] >= d1 else \
             "不满足(反事实计数在 V0 轨迹上,分叉后 V1 自身轨迹的差异不入该计数——级联下界非定理,判读待审核)"
        c2 = "PASS" if st["sat_flip"] >= d2 else \
             "不满足(同上:级联效应;判读待审核)"
        print(f"  {wname:>5} F3: cf_tie_disagree={st['cf_tie_disagree']} vs "
              f"|Δrehy(V1,V0)|={d1} -> {c1}")
        print(f"  {wname:>5} F1: sat_flip={st['sat_flip']} vs "
              f"|Δrehy(V2,V0)|={d2} -> {c2}")
    print()

    # ============ 4. 确定性自检 ============
    m1 = run_policy("V3", traces["hot"], B, C_EXT, C_REHY, H=H_MAIN)
    m2 = run_policy("V3", traces["hot"], B, C_EXT, C_REHY, H=H_MAIN)
    det = core(m1) == core(m2) and m1["stats"] == m2["stats"]
    print(f"确定性自检(V3 同配置重跑): {'PASS' if det else 'FAIL'}")
    assert det

    print()
    print("*** P3-B 消融执行完成(回归门 PASS 后采数;变体=诊断工具非 target)。***")
    print("*** 判读按设计 §4 预注册规则 R1–R5,结果文档待审核终判。***")


if __name__ == "__main__":
    main()
