#!/usr/bin/env python3
# Copyright © 2026 SimiGo-Lab. H-P1 Tier-1 L1 采数(2026-09-22;设计
# RESIDENCY_H-P1_DESIGN_20260922.md v0.1.2 PASS + v6 回归门 PASS +
# 远端代码级复审 PASS / Tier-1 L1 放行后的正式采数轮)。
#
# 预注册口径(设计 §2/§3 冻结,不得实现中改写):
#   事件集 = 各 workload 自身的 lru 与 C(lfu_aging)参照运行驱逐事件
#     之并集,且为 (node,t) 二元组去重集合;来源记 provenance 不改权重。
#   信号(在线单形式 O1;驱逐时刻 t,仅 [0,t] 窗口 + 静态拓扑):
#     S1=pos(n);S2=A_anc(n,t);S3=A_chain(n,t)(self-excluded)。
#   oracle Y = F(n,t) = n 在 (t,T] 的再访问次数(纯 oracle 只上 Y 侧)。
#   Spearman ρ 双侧(描述性约定,非统计检验);存在性线 tree |ρ|≥0.1;
#   L1 PASS = ≥1 类 tree |ρ|≥0.1。hot = 阴性对照(同构造/统计/信号
#   路径);hot 侧 |ρ|≥0.1 = 触线 → 停机查实现。
# 实现口径声明(提交审核方确认项):同一 (n,t) 双源(lru+C)事件,
#   信号历史取 lru 参照运行(事件集命名序 lru∪C 之先序),provenance
#   如实记录;另按来源分解做描述性补充报告,不改主判定权重。
# 本轮只采 L1;L3 不执行;正式研究结论在 L1 出口归因(审核方确认)前
# 不产生。

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
v6 = _load("v6mod", "residency_policy_simulator_v6.py")

SEED = sim3.SEED
N_NODES = sim3.N_NODES
TRACE_LEN = sim3.TRACE_LEN
C_EXT, C_REHY = sim3.C_EXT, sim3.C_REHY
B_BUDGET = 12
H_MAIN = 8
POS, ANCESTORS, CHAIN = v6.POS, v6.ANCESTORS, v6.CHAIN
LINE = 0.1


def signals_at(n, counts):
    """纯函数:驱逐时刻 t 的三类在线信号(窗口计数 × 静态拓扑)。"""
    s1 = POS[n]
    s2 = sum(counts.get(a, 0) for a in ANCESTORS[n])
    s3 = sum(counts.get(m, 0) for m in CHAIN[n]) - counts.get(n, 0)
    return (s1, s2, s3)


def ref_run_instrumented(policy, trace, budget, c_ext, c_rehy):
    """参照运行(lru / lfu_aging)含逐驱逐信号捕获。
    循环与 v4.run_policy 同构(NORM①②③;lfu_aging 含 200 步半衰);
    出口处与 v4 引擎断言等价(core + seq 逐位),否则抛异常停机。"""
    resident = set()
    externalized = set()
    last_access = {}
    freq = {}
    window = []
    ext_count = rehy_count = violations = 0
    steps_excess = 0
    seq = []
    events = []                      # (victim, t, S1, S2, S3)
    for step, node in enumerate(trace):
        if policy == "lfu_aging" and step > 0 and step % sim3.LFU_DECAY_INTERVAL == 0:
            for k in list(freq):
                freq[k] //= 2
        if node not in resident:
            rehy_count += 1
            externalized.discard(node)
            resident.add(node)
        last_access[node] = step
        freq[node] = freq.get(node, 0) + 1
        window.append((step, node))
        while window and window[0][0] <= step - sim3.W_WINDOW:
            window.pop(0)
        while len(resident) > budget:
            candidates = [n for n in resident if n != node]   # NORM③
            if not candidates:
                break
            if policy == "lru":
                key = lambda n: (last_access[n], n)
            else:  # lfu_aging
                key = lambda n: (freq.get(n, 0), last_access[n], n)
            victim = min(candidates, key=key)
            counts = Counter(nd for _, nd in window)
            events.append((victim, step) + signals_at(victim, counts))
            resident.discard(victim)
            externalized.add(victim)
            ext_count += 1
            seq.append((step, victim))
        if len(resident) > budget:
            violations += 1
    out = {"violations": violations,
           "J": c_ext * ext_count + c_rehy * rehy_count,
           "rehy": rehy_count, "ext": ext_count,
           "resident_final": len(resident), "steps_excess": steps_excess,
           "seq": seq}
    ref = v4.run_policy(policy, trace, budget, c_ext, c_rehy, H=H_MAIN,
                        record_seq=True)
    assert v4.core(out) == v4.core(ref), f"engine≠v4 {policy}"
    assert out["seq"] == ref["seq"], f"seq≠v4 {policy}"
    return out, events


def rankdata(xs):
    order = sorted(range(len(xs)), key=lambda i: xs[i])
    ranks = [0.0] * len(xs)
    i = 0
    tie_pairs = 0
    while i < len(xs):
        j = i
        while j + 1 < len(xs) and xs[order[j + 1]] == xs[order[i]]:
            j += 1
        tie_pairs += (j - i) * (j - i + 1) // 2
        avg = (i + j) / 2 + 1
        for k in range(i, j + 1):
            ranks[order[k]] = avg
        i = j + 1
    return ranks, tie_pairs


def spearman(xs, ys):
    """标准 Spearman(平均秩);返回 (rho, n, tie_pairs_x, tie_pairs_y)。
    常数秩 → rho=None(无定义,如实报告)。"""
    n = len(xs)
    if n < 2:
        return None, n, 0, 0
    rx, tx = rankdata(xs)
    ry, ty = rankdata(ys)
    mx, my = sum(rx) / n, sum(ry) / n
    num = sum((a - mx) * (b - my) for a, b in zip(rx, ry))
    dx = sum((a - mx) ** 2 for a in rx)
    dy = sum((b - my) ** 2 for b in ry)
    rho = None if dx == 0 or dy == 0 else num / (dx * dy) ** 0.5
    return rho, n, tx, ty


def build_events(trace, wname):
    """§3 事件集:各 workload 自身 lru ∪ C(lfu_aging)去重 (node,t)。"""
    _, ev_lru = ref_run_instrumented("lru", trace, B_BUDGET, C_EXT, C_REHY)
    _, ev_c = ref_run_instrumented("lfu_aging", trace, B_BUDGET, C_EXT, C_REHY)
    d_lru = {(n, t): sig for n, t, *sig in ev_lru}
    d_c = {(n, t): sig for n, t, *sig in ev_c}
    union = sorted(set(d_lru) | set(d_c), key=lambda e: (e[1], e[0]))
    rows = []
    for (n, t) in union:
        src = ("lru" if (n, t) in d_lru else "") + \
              ("+C" if (n, t) in d_c else "")
        sig = d_lru[(n, t)] if (n, t) in d_lru else d_c[(n, t)]
        y = trace[t + 1:].count(n)               # oracle Y(只上 Y 侧)
        rows.append((n, t, src, sig[0], sig[1], sig[2], y))
    return rows


def main():
    rng = random.Random(SEED)
    parent8 = sim3.gen_topology(N_NODES, 8)
    traces = {
        "hot": sim3.gen_hot_trace(rng, N_NODES, TRACE_LEN),
        "tree": sim3.gen_tree_trace(rng, parent8, N_NODES, TRACE_LEN),
    }
    print("=== H-P1 Tier-1 L1 采数(设计 v0.1.2 §3 预注册;放行轮)===")
    print(f"seed={SEED};nodes={N_NODES};trace={TRACE_LEN};B={B_BUDGET};"
          f"W={sim3.W_WINDOW};存在性线 tree |ρ|≥{LINE};hot 触线={LINE}")
    print("双源 (n,t) 信号历史 = lru 先序(provenance 如实;口径声明见脚本头)\n")

    results = {}
    triggered = False
    for wname, trace in traces.items():
        rows = build_events(trace, wname)
        src_stat = Counter(r[2] for r in rows)
        print(f"-- {wname}:事件集 n={len(rows)}(来源:{dict(src_stat)})--")
        for ci, cname in enumerate(["S1", "S2", "S3"]):
            xs = [r[3 + ci] for r in rows]
            ys = [r[6] for r in rows]
            rho, n, tx, ty = spearman(xs, ys)
            results[(wname, cname)] = (rho, n, tx, ty)
            rho_s = "None(常数秩)" if rho is None else f"{rho:+.4f}"
            over = rho is not None and abs(rho) >= LINE
            if wname == "hot" and over:
                triggered = True
            tag = ("触线!" if (wname == "hot" and over)
                   else ("过线" if over else "未过线"))
            print(f"  {cname}: ρ={rho_s} n={n} ties_S={tx} ties_Y={ty} "
                  f"[{tag}]" + ("(hot=阴性对照)" if wname == "hot" else ""))
        # 来源分解(描述性补充,不改主判定)
        for ci, cname in enumerate(["S1", "S2", "S3"]):
            for src in ("lru", "C", "lru+C"):
                sub = [r for r in rows if r[2] == src]
                if len(sub) >= 2:
                    rho, n, _, _ = spearman([r[3 + ci] for r in sub],
                                            [r[6] for r in sub])
                    rho_s = "None" if rho is None else f"{rho:+.4f}"
                    print(f"    [来源分解·描述性] {cname}/{src}: "
                          f"ρ={rho_s} n={n}")
        print()

    print("-- L1 逐类出口归因(§3/§7;正式结论待审核方确认)--")
    l1_pass_any = False
    for cname in ["S1", "S2", "S3"]:
        rho_t = results[("tree", cname)][0]
        ok = rho_t is not None and abs(rho_t) >= LINE
        l1_pass_any |= ok
        print(f"  {cname}: tree |ρ|={'None' if rho_t is None else format(abs(rho_t), '.4f')} "
              f"→ L1 {'PASS' if ok else 'FAIL'}(hot ρ="
              f"{results[('hot', cname)][0]})")
    print(f"  全局 L1(≥1 类 tree 过线):{'PASS' if l1_pass_any else 'FAIL'}")
    if triggered:
        print("\n*** hot 阴性对照触线:停机,先查实现再判读(设计 §3)***")
        sys.exit(2)
    print("\n*** Tier-1 L1 采数完成(hot 对照未触线);L3 未执行;"
          "逐类出口归因待审核方确认后进 §4/§7 流程 ***")


if __name__ == "__main__":
    main()
