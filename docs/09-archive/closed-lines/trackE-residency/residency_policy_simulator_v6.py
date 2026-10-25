#!/usr/bin/env python3
# Copyright © 2026 SimiGo-Lab. Track E Residency Policy Simulator v6
# (H-P1 结构策略引擎 + 全冻结参照回归门;设计 RESIDENCY_H-P1_DESIGN_
#  20260922.md v0.1.2 PASS,2026-09-22 远端复审 PASS / Implementation
#  UNLOCKED → 回归门 → 才准采数)
#
# 冻结规范(H-P1 Design v0.1.2):
#   信号(在线单形式 O1;驱逐时刻 t,仅 [0,t] 窗口 + 静态拓扑):
#     S1 pos(n)∈{0..3} 静态;S2 A_anc(n,t)=Σ_{a∈ancestors(n)} visits(a,W);
#     S3 A_chain(n,t)=Σ_{m∈chain(n),m≠n} visits(m,W) —— self-excluded
#     是全文档唯一含义(v0.1.2 BLOCKER① 钉死)。
#   策略(NORM①②③ 延续;驱逐=argmin key,key 收尾 (last_access,id)):
#     P_S1 K=−pos / P_S2 K=−A_anc / P_S3 K=+A_chain;敏感方向 = K 取反。
#     P_S3 两层语义(v0.1.2 BLOCKER①):跨链按自排除链活跃度(不相消),
#     同链内等价于按自身窗口访问降序;禁止全局"自身访问最多优先"读法。
#   L1 事件集 = 各自 workload 的 lru/C 参照运行 (node,t) 去重并集
#     (v0.1.2 BLOCKER②;本文件不含 L1 统计——采数门在回归门之后)。
#   L2 = 构造审计:结构策略引擎不预计算 next_use(无 oracle 入内存),
#     信号仅为 (窗口计数, 静态拓扑) 纯函数;运行时断言窗口 max step ≤ t。
# 门位:本文件 main() = 回归门(P3-A/B/C 冻结逐位 + 结构策略自检),
#   全 PASS 才 UNLOCK H-P1 采数;结构策略读数 = 门禁自检,禁止判读。

import importlib.util
import os
import random
import sys
from collections import Counter

_HERE = os.path.dirname(os.path.abspath(__file__))


def _load(name, fname):
    spec = importlib.util.spec_from_file_location(
        name, os.path.join(_HERE, fname))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


sim3 = _load("sim3", "residency_policy_simulator_v3.py")
v4 = _load("v4mod", "residency_policy_simulator_v4.py")
v5 = _load("v5mod", "residency_policy_simulator_v5.py")

SEED = sim3.SEED
N_NODES = sim3.N_NODES
TRACE_LEN = sim3.TRACE_LEN
C_EXT, C_REHY = sim3.C_EXT, sim3.C_REHY
B_BUDGET = 12
H_MAIN = 8

# ---- 冻结参照(P3-A v4.FROZEN/FROZEN_H/FROZEN_PRESSURE;P3-B V4≡V3
#      逐位/hot V2≡V0;P3-C A/D/C=v5 冻结 + B=P3-C 采数定格,
#      provenance = runs/P3C_F2_DECOMPOSITION_PROVENANCE_20260921 +
#      2026-09-22 post-802e150 v5 复跑逐位一致)----
FROZEN_B = {"hot": (554.3, 399, 387), "tree": (1145.1, 818, 806)}

# ---- H-P1 静态拓扑(链 8×4;pos=n%4;ancestors=同链更浅;chain=同链全体)----
PARENT8 = sim3.gen_topology(N_NODES, 8)
POS = {n: n % 4 for n in range(N_NODES)}
ANCESTORS = {n: tuple(n - k for k in range(1, POS[n] + 1))
             for n in range(N_NODES)}
CHAIN = {n: tuple(n - POS[n] + j for j in range(4)) for n in range(N_NODES)}

HP1_POLICIES = ("P_S1", "P_S1s", "P_S2", "P_S2s", "P_S3", "P_S3s")


def run_policy_hp1(policy, trace, budget, c_ext, c_rehy, record_seq=False,
                   audit=False):
    """H-P1 结构策略引擎(NORM①②③ 与 v4.run_policy 同构;无 oracle)。
    policy ∈ HP1_POLICIES;s 后缀 = 敏感方向(K 取反)。信号 = 窗口计数
    与静态拓扑的纯函数;audit=True 时逐驱逐断言窗口 max step ≤ t
    (L2 构造审计运行时部分)。"""
    assert policy in HP1_POLICIES, policy
    sens = policy.endswith("s")
    base = policy[:4]
    resident = set()
    externalized = set()
    last_access = {}
    window = []                      # (step,node);列表+原地剪枝,语义≡deque
    ext_count = rehy_count = violations = 0
    evict_events = 0
    audit_max_window_step_ok = True
    seq = []

    def signal(n, counts):
        # 纯函数:仅 (counts, 静态拓扑)。无 trace/未来引用(代码级审计)。
        if base == "P_S1":
            return POS[n]
        if base == "P_S2":
            return sum(counts.get(a, 0) for a in ANCESTORS[n])
        return sum(counts.get(m, 0) for m in CHAIN[n]) - counts.get(n, 0)

    def sign_key(n, counts):
        # P_S1:主 −pos / 敏感 +pos;P_S2:主 −A_anc / 敏感 +A_anc;
        # P_S3:主 +A_chain / 敏感 −A_chain
        k = signal(n, counts)
        if base == "P_S1":
            k = -k if not sens else k
        elif base == "P_S2":
            k = -k if not sens else k
        else:  # P_S3
            k = k if not sens else -k
        return (k, last_access[n], n)

    for step, node in enumerate(trace):
        # NORM①:touch(non-resident → REHYDRATE)
        if node not in resident:
            rehy_count += 1
            externalized.discard(node)
            resident.add(node)
        last_access[node] = step
        window.append((step, node))
        while window and window[0][0] <= step - sim3.W_WINDOW:
            window.pop(0)
        while len(resident) > budget:
            if audit:
                # L2 运行时审计:窗口内**全部**时间坐标 ≤ t(v0.1.2);
                # 累积式——任一次违反即保持 False(修复审核方 f1eb28d
                # BLOCKER:原 window[-1][0]>step 为永真假检查)。
                audit_max_window_step_ok = (
                    audit_max_window_step_ok
                    and (not window or max(s for s, _ in window) <= step)
                )
            candidates = [n for n in resident if n != node]   # NORM③
            if not candidates:
                break
            counts = Counter(nd for _, nd in window)
            victim = min(candidates, key=lambda n: sign_key(n, counts))
            evict_events += 1
            resident.discard(victim)
            externalized.add(victim)
            ext_count += 1
            if record_seq:
                seq.append((step, victim))
        if len(resident) > budget:
            violations += 1
    out = {"violations": violations,
           "J": c_ext * ext_count + c_rehy * rehy_count,
           "rehy": rehy_count, "ext": ext_count,
           "resident_final": len(resident),
           "evict_events": evict_events,
           "audit_ok": audit_max_window_step_ok,
           "seq": seq if record_seq else None}
    return out


def core(m):
    return (m["violations"], round(m["J"], 1), m["rehy"], m["ext"])


def main():
    rng = random.Random(SEED)
    parent8 = sim3.gen_topology(N_NODES, 8)
    traces = {
        "hot": sim3.gen_hot_trace(rng, N_NODES, TRACE_LEN),
        "tree": sim3.gen_tree_trace(rng, parent8, N_NODES, TRACE_LEN),
    }

    print("=== Residency Policy Simulator v6(H-P1 引擎 + 全冻结回归门)===")
    print(f"seed={SEED};nodes={N_NODES};trace={TRACE_LEN};B={B_BUDGET};"
          f"H={H_MAIN};C_ext={C_EXT};C_rehy={C_REHY};W={sim3.W_WINDOW}")
    print("门位:v0.1.2 设计 PASS → 本门全 PASS 才 UNLOCK H-P1 采数;"
          "结构策略读数 = 门禁自检,禁止判读\n")

    gate_ok = True

    def check(label, ok):
        nonlocal gate_ok
        gate_ok &= ok
        print(f"  {label} -> {'OK' if ok else 'FAIL'}")

    # ============ 1. P3-A 冻结参照(v3 基线 + v4 引擎等价)============
    print("-- P3-A:lru/lfu_aging/V0(cag)/belady 主表 + H 敏感性 + pressure --")
    for wname, trace in traces.items():
        for policy in ["lru", "lfu_aging", "cost_aware_greedy", "belady_greedy"]:
            m = sim3.simulate_v3(policy, trace, B_BUDGET, C_EXT, C_REHY,
                                 H=H_MAIN)
            j, r, x = v4.FROZEN[(wname, policy)]
            check(f"P3-A {wname}/{policy}: J={m['J']:.1f} ({m['rehy']}/{m['ext']})",
                  round(m["J"], 1) == j and m["rehy"] == r and m["ext"] == x
                  and m["violations"] == 0)
    for h in (4, 16):
        m = sim3.simulate_v3("cost_aware_greedy", traces["hot"], B_BUDGET,
                             C_EXT, C_REHY, H=h)
        j, r = v4.FROZEN_H[h]
        check(f"P3-A hot/V0 H={h}: J={m['J']:.1f} ({m['rehy']})",
              round(m["J"], 1) == j and m["rehy"] == r)
    for (wname, k_c), fx in v4.FROZEN_PRESSURE.items():
        vals = [sim3.simulate_v3(p, traces[wname], B_BUDGET, C_EXT, C_REHY,
                                 H=H_MAIN, k_c=k_c)["steps_excess"]
                for p in ["lru", "lfu_aging", "cost_aware_greedy"]]
        check(f"P3-A pressure {wname}/k_c={k_c}: {vals}", all(v == fx for v in vals))
    equiv_fail = 0
    for wname, trace in traces.items():
        for policy in ["lru", "lfu_aging", "cost_aware_greedy", "belady_greedy"]:
            for h in ([H_MAIN] if policy != "cost_aware_greedy" else [4, 8, 16]):
                ep = "V0" if policy == "cost_aware_greedy" else policy
                if v4.core(v4.run_policy(ep, trace, B_BUDGET, C_EXT, C_REHY, H=h)) != \
                        v4.core(sim3.simulate_v3(policy, trace, B_BUDGET, C_EXT,
                                                 C_REHY, H=h)):
                    equiv_fail += 1
    check(f"P3-A v4 引擎 ≡ v3(主表+H+pressure 全配置;FAIL x{equiv_fail})",
          equiv_fail == 0)

    # ============ 2. P3-B 冻结事实(V0 数字 + V4≡V3 / hot V2≡V0 逐位)============
    print("-- P3-B:V0 冻结数字 + 序列逐位(V4≡V3;hot V2≡V0)--")
    for wname, trace in traces.items():
        mv0 = v4.run_policy("V0", trace, B_BUDGET, C_EXT, C_REHY, H=H_MAIN)
        j, r, x = v4.FROZEN[(wname, "cost_aware_greedy")]
        check(f"P3-B {wname}/V0: J={mv0['J']:.1f} ({mv0['rehy']}/{mv0['ext']})",
              round(mv0["J"], 1) == j and mv0["rehy"] == r and mv0["ext"] == x)
        mv3 = v4.run_policy("V3", trace, B_BUDGET, C_EXT, C_REHY, H=H_MAIN,
                            record_seq=True)
        mv4 = v4.run_policy("V4", trace, B_BUDGET, C_EXT, C_REHY, H=H_MAIN,
                            record_seq=True)
        dd34 = v4.differing_decisions(mv3["seq"], mv4["seq"], TRACE_LEN)
        check(f"P3-B {wname}: V4≡V3 序列逐位 dd={dd34}", dd34 == 0)
        if wname == "hot":
            mv2 = v4.run_policy("V2", trace, B_BUDGET, C_EXT, C_REHY, H=H_MAIN,
                                record_seq=True)
            dd20 = v4.differing_decisions(mv2["seq"], mv0 and
                                          v4.run_policy("V0", trace, B_BUDGET,
                                                        C_EXT, C_REHY, H=H_MAIN,
                                                        record_seq=True)["seq"],
                                          TRACE_LEN)
            check(f"P3-B hot: V2≡V0 序列逐位 dd={dd20}(sat=0 结构产物)",
                  dd20 == 0)

    # ============ 3. P3-C 冻结参照(A/D/C v5 冻结 + B 采数定格)============
    print("-- P3-C:A≡V4 / D≡lfu_aging 序列逐位;C 诊断;B 采数定格 --")
    for wname, trace in traces.items():
        ma = v5.run_cell("window", False, trace, B_BUDGET, C_EXT, C_REHY,
                         record_seq=True)
        mv4 = v4.run_policy("V4", trace, B_BUDGET, C_EXT, C_REHY, H=H_MAIN,
                            record_seq=True)
        fa = v5.FROZEN_A[wname]
        ok = (v5.core(ma) == (ma["violations"], fa[0], fa[1], fa[2])
              and v4.differing_decisions(ma["seq"], mv4["seq"], TRACE_LEN) == 0)
        check(f"P3-C {wname}/A≡V4: J={ma['J']:.1f} frozen={fa}", ok)
        md = v5.run_cell("cum", True, trace, B_BUDGET, C_EXT, C_REHY,
                         record_seq=True)
        mlfu = v4.run_policy("lfu_aging", trace, B_BUDGET, C_EXT, C_REHY,
                             H=H_MAIN, record_seq=True)
        fd = v5.FROZEN_D[wname]
        ok = (v5.core(md) == (md["violations"], fd[0], fd[1], fd[2])
              and v4.differing_decisions(md["seq"], mlfu["seq"], TRACE_LEN) == 0)
        check(f"P3-C {wname}/D≡lfu_aging: J={md['J']:.1f} frozen={fd}", ok)
        mc = v5.run_cell("cum", False, trace, B_BUDGET, C_EXT, C_REHY)
        fc = v5.DIAG_C[wname]
        check(f"P3-C {wname}/C≡诊断: J={mc['J']:.1f} frozen={fc}",
              v5.core(mc) == (mc["violations"], fc[0], fc[1], fc[2]))
        mb = v5.run_cell("window", True, trace, B_BUDGET, C_EXT, C_REHY)
        fb = FROZEN_B[wname]
        check(f"P3-C {wname}/B 定格: J={mb['J']:.1f} ({mb['rehy']}/{mb['ext']}) "
              f"frozen={fb}",
              v5.core(mb) == (mb["violations"], fb[0], fb[1], fb[2]))

    # ============ 4. H-P1 结构策略门禁自检(非采数,禁止判读)============
    print("-- H-P1 结构策略:确定性/L2 审计/一致性下界 dd≥|Δrehy| --")
    for wname, trace in traces.items():
        mlru = v4.run_policy("lru", trace, B_BUDGET, C_EXT, C_REHY, H=H_MAIN,
                             record_seq=True)
        for policy in HP1_POLICIES:
            m1 = run_policy_hp1(policy, trace, B_BUDGET, C_EXT, C_REHY,
                                record_seq=True, audit=True)
            m2 = run_policy_hp1(policy, trace, B_BUDGET, C_EXT, C_REHY,
                                record_seq=True, audit=True)
            det = (core(m1) == core(m2) and m1["seq"] == m2["seq"])
            dd = v4.differing_decisions(m1["seq"], mlru["seq"], TRACE_LEN)
            ok = (det and m1["audit_ok"] and m1["violations"] == 0
                  and dd >= abs(m1["rehy"] - mlru["rehy"]) and m1["J"] > 0)
            check(f"H-P1 {wname}/{policy}: J={m1['J']:.1f} "
                  f"({m1['rehy']}/{m1['ext']}) det={det} L2audit={m1['audit_ok']} "
                  f"dd={dd}≥|Δrehy|={abs(m1['rehy'] - mlru['rehy'])}", ok)

    print()
    if not gate_ok:
        print("*** v6 Regression Gate FAIL:停,不采任何 H-P1 数据"
              "(设计 §6 门位)***")
        sys.exit(1)
    print("*** v6 Regression Gate PASS:P3-A/B/C 冻结逐位复现 + 结构策略"
          "自检全过 → H-P1 Implementation 采数 UNLOCK(Tier-1 按 §3/§4 "
          "预注册执行;结构策略本轮读数仍禁止判读)***")


if __name__ == "__main__":
    main()
