#!/usr/bin/env python3
# Copyright © 2026 SimiGo-Lab. H-P1 Hot Null v2 校准执行
# (2026-09-22;设计 RESIDENCY_H-P1_HOT_NULL_V2_DESIGN_20260922.md v1.0
#  远端审核 PASS / LOCKED 后的实现。实现四禁:permutation 方案、Q95、
#  invalid-rate 规则、sentinel 判定均锁死;运行中若发现规则需改 =
#  新 Design Revision,不是代码修正。)
#
# 预注册实现口径:
#   固定:seed42 hot trace / hot 自身 LRU∪C 去重 (node,t) 事件集(n=1061)/
#         Y / 事件时间与权重。随机:node↔topology 标号置换。
#   perm = random.Random(20260922).sample(range(32), 32);解释:拓扑
#         位置 j 现由 node 标号 perm[j] 占据(node n 的拓扑位置 =
#         perm.index(n);祖先/链成员 = 该位置的链上前缀/全链标号)。
#   N_perm=10000;逐类零分布 |ρ_perm|(平均秩 Spearman,双侧);
#   零方差抽样作废不入分布(不强行置 0);invalid/N_perm > 1% → 暂停
#   自动判定交审核(exit 3);Q95_c = sorted[ceil(0.95*N_used)-1];
#   sentinel:observed |ρ_hot,c| > Q95_c → 异常停机(exit 2);
#   观测 ρ 必须逐位回归 0cc6587 原始值(4 位小数),不一致即停机。
#   双源不变量:S_lru(n,t) ≡ S_C(n,t) 逐位断言(信号=统一在线历史)。

import importlib.util
import math
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
l1 = _load("l1mod", "hp1_tier1_l1.py")

SEED = sim3.SEED
N_NODES = sim3.N_NODES
TRACE_LEN = sim3.TRACE_LEN
C_EXT, C_REHY = sim3.C_EXT, sim3.C_REHY
B_BUDGET, H_MAIN = 12, 8
N_PERM = 10000
PERM_SEED = 20260922
INVALID_DISCLOSURE = 0.01

# 0cc6587 原始观测(raw 保存值;4 位小数回归基准)
RAW_HOT = {"S1": 0.0837, "S2": -0.1044, "S3": -0.2493}
RAW_TREE = {"S1": -0.5218, "S2": -0.4767, "S3": -0.3418}
RAW_EVENTS = {"hot": (1061, 681, 377, 3), "tree": (1752, 988, 749, 15)}


def window_counts(trace, t):
    """t 时刻窗口计数(仅 trace 前缀;policy 无关——双源恒等的根据)。"""
    lo = max(0, t - (sim3.W_WINDOW - 1))
    return Counter(trace[lo:t + 1])


def permuted_signal(n, counts, perm):
    """置换后拓扑位置 j=perm.index(n);返回 (S1',S2',S3')。
    S3 = 同链其他标号窗口访问和(self-excluded 恒保持)。"""
    j = perm.index(n)
    chain_labels = perm[(j // 4) * 4:(j // 4) * 4 + 4]
    anc_labels = chain_labels[:j % 4]
    s2 = sum(counts.get(a, 0) for a in anc_labels)
    s3 = sum(counts.get(m, 0) for m in chain_labels) - counts.get(n, 0)
    return (j, s2, s3)


def main():
    rng = random.Random(SEED)
    parent8 = sim3.gen_topology(N_NODES, 8)
    traces = {
        "hot": sim3.gen_hot_trace(rng, N_NODES, TRACE_LEN),
        "tree": sim3.gen_tree_trace(rng, parent8, N_NODES, TRACE_LEN),
    }
    print("=== H-P1 Hot Null v2 校准(设计 v1.0 PASS / LOCKED 后执行)===")
    print(f"N_perm={N_PERM};perm_seed={PERM_SEED};invalid 披露阈="
          f"{INVALID_DISCLOSURE:.0%};sentinel=observed |ρ|>Q95_c 停机\n")

    gate_ok = True

    # ---- 1. 事件级回归(event-level regression;远端增强项)----
    print("-- 事件级回归(vs 0cc6587 raw)与双源不变量 --")
    rows_by_wl = {}
    for wname, trace in traces.items():
        rows = l1.build_events(trace, wname)
        rows_by_wl[wname] = rows
        src = Counter(r[2] for r in rows)
        n_tot, n_lru, n_c, n_dual = RAW_EVENTS[wname]
        ok = (len(rows) == n_tot and src.get("lru", 0) == n_lru
              and src.get("+C", 0) == n_c and src.get("lru+C", 0) == n_dual)
        gate_ok &= ok
        print(f"  {wname}: n={len(rows)} lru={src.get('lru', 0)} "
              f"C={src.get('+C', 0)} dual={src.get('lru+C', 0)} "
              f"raw={RAW_EVENTS[wname]} -> {'OK' if ok else 'FAIL'}")
    # 双源不变量:S(lru) ≡ S(C)(需重取两套信号逐位比较)
    dual_eq = True
    for wname, trace in traces.items():
        _, ev_lru = l1.ref_run_instrumented(
            "lru", trace, B_BUDGET, C_EXT, C_REHY)
        _, ev_c = l1.ref_run_instrumented(
            "lfu_aging", trace, B_BUDGET, C_EXT, C_REHY)
        d_lru = {(n, t): sig for n, t, *sig in ev_lru}
        d_c = {(n, t): sig for n, t, *sig in ev_c}
        for e in set(d_lru) & set(d_c):
            if d_lru[e] != d_c[e]:
                dual_eq = False
    gate_ok &= dual_eq
    print(f"  双源不变量 S_lru≡S_C(全部双源事件逐位)-> "
          f"{'OK' if dual_eq else 'FAIL'}")
    if not gate_ok:
        print("*** 事件级回归 FAIL:停机 ***")
        sys.exit(1)

    # ---- 2. 观测 ρ 回归(0cc6587 raw;4 位小数)----
    print("-- 观测 ρ 回归(raw;4 位小数精确)--")
    obs = {}
    for wname in ("hot", "tree"):
        rows = rows_by_wl[wname]
        for ci, cname in enumerate(["S1", "S2", "S3"]):
            rho, n, _, _ = l1.spearman([r[3 + ci] for r in rows],
                                       [r[6] for r in rows])
            raw = (RAW_HOT if wname == "hot" else RAW_TREE)[cname]
            ok = rho is not None and round(rho, 4) == raw
            gate_ok &= ok
            if wname == "hot":
                obs[cname] = abs(rho)
            print(f"  {wname}/{cname}: ρ={rho:+.4f} raw={raw:+.4f} -> "
                  f"{'OK' if ok else 'FAIL'}")
    if not gate_ok:
        print("*** 观测 ρ 回归 FAIL:停机 ***")
        sys.exit(1)

    # ---- 3. Hot Null v2 permutation 校准(锁死方案)----
    print(f"-- permutation 校准:N={N_PERM},seed={PERM_SEED} --")
    labels = list(range(N_NODES))
    prng = random.Random(PERM_SEED)
    hot_rows = rows_by_wl["hot"]
    ys = [r[6] for r in hot_rows]
    ts = [r[1] for r in hot_rows]
    counts_cache = {t: window_counts(traces["hot"], t) for t in set(ts)}
    nulls = {"S1": [], "S2": [], "S3": []}
    invalid = {"S1": 0, "S2": 0, "S3": 0}
    for it in range(N_PERM):
        perm = prng.sample(labels, 32)
        sig_all = ([], [], [])
        for (row, t) in zip(hot_rows, ts):
            s = permuted_signal(row[0], counts_cache[t], perm)
            for ci in range(3):
                sig_all[ci].append(s[ci])
        for ci, cname in enumerate(["S1", "S2", "S3"]):
            rho, _, _, _ = l1.spearman(sig_all[ci], ys)
            if rho is None:
                invalid[cname] += 1
            else:
                nulls[cname].append(abs(rho))

    print("-- invalid-rate 与 Q95/sentinel --")
    all_pass = True
    for cname in ["S1", "S2", "S3"]:
        inv_rate = invalid[cname] / N_PERM
        used = len(nulls[cname])
        q95 = sorted(nulls[cname])[math.ceil(0.95 * used) - 1]
        anom = obs[cname] > q95
        print(f"  {cname}: invalid={invalid[cname]}({inv_rate:.2%}) "
              f"N_used={used} Q95={q95:.4f} observed={obs[cname]:.4f} "
              f"-> {'异常停机' if anom else 'sentinel 通过'}"
              f"{' [invalid>1% 暂停自动判定]' if inv_rate > INVALID_DISCLOSURE else ''}")
        if inv_rate > INVALID_DISCLOSURE:
            print("*** invalid-rate 超 1%:暂停自动判定,交审核(exit 3)***")
            sys.exit(3)
        if anom:
            all_pass = False
    print()
    if not all_pass:
        print("*** Hot Null v2 sentinel 异常:停机,交审核方 ***")
        sys.exit(2)
    print("*** hot calibration sentinel 三类全部通过 → 校准完成;"
          "进入 §6 完整 Tier-1 重跑(事件级回归已先行 PASS)***")

    # ---- 4. 完整 Tier-1 重跑(事件回归已过;tree ρ 回归断言)----
    print("-- Tier-1 完整重跑(tree ρ 逐位回归 raw)+ L1 逐类出口 --")
    l1_pass_any = False
    for cname in ["S1", "S2", "S3"]:
        rows = rows_by_wl["tree"]
        ci = ["S1", "S2", "S3"].index(cname)
        rho, n, tx, ty = l1.spearman([r[3 + ci] for r in rows],
                                     [r[6] for r in rows])
        assert round(rho, 4) == RAW_TREE[cname], "tree ρ≠raw"
        ok = abs(rho) >= 0.1
        l1_pass_any |= ok
        print(f"  {cname}: tree ρ={rho:+.4f}(raw 回归 OK,n={n},"
              f"ties_S={tx},ties_Y={ty})→ L1 {'PASS' if ok else 'FAIL'};"
              f"hot sentinel 已通过")
    print(f"  全局 L1(≥1 类 tree 过线):{'PASS' if l1_pass_any else 'FAIL'}")
    print("\n*** Hot Null v2 校准 + Tier-1 完整重跑完成;逐类 L1 出口"
          "归因待审核方最终署名;L3 仍按门位 ***")


if __name__ == "__main__":
    main()
