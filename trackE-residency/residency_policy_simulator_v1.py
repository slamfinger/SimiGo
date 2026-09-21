#!/usr/bin/env python3
# Copyright © 2026 SimiGo-Lab. Track E(命名待定)Residency Policy Simulator v1
#
# 记录:SimiGo-Lab trackE-residency/(P0.1 PASS v0.1 Policy Objective
# Definition 解锁;两条实现规范注记已实现,见 NORMS)
#
# NORMS(P0.1 终判非阻断注记,正式实现):
#   ① 事件计数时序:每访问步 = touch(外部节点→REHYDRATE,计 C_rehy)
#      → 容量检查 → 逐个 EXTERNALIZE(各计 C_ext);同步多事件逐一计数。
#   ② 字典序 tie-break:victim 选择并列时固定取最低 node id(确定性,
#      oracle 结果不依赖实现顺序)。
#
# Objective(v0.1 Policy Objective Definition,字典序):
#   第一层:resident_bytes ≤ budget(等大小 ⇒ violations 只可能出现在
#           always 策略;其余策略强制合规,violation=0 即可行)
#   第二层:minimize C_ext×#ext + C_rehy×#rehy(token-equivalent)
#   描述层:byte-steps(等大小下 = resident_count×steps,略)
#
# 策略:
#   lru        —— baseline(纯 recency)
#   lfu_aging  —— NEW,可实现 future-reuse 启发式(计数 + 周期减半
#                 aging,防陈旧高频独占;victim = min(count, tie→低 id),
#                 count 相同再按 last_access)
#   oracle     —— future-aware Belady reference(针对 rehydrate/
#                 page-fault 数;等大小 farthest-next-use;tie→低 id;
#                 非当前字典序 objective 的 cost-aware oracle)
#
# Workload 两域(H-P0 / H-P1 setup):
#   hot  —— 热集(与 v0 同构;H-P0 域:pressure + reuse 信息)
#   tree —— 8 树 × 4 节点,访问以 0.7 概率沿树边连续行走(**child→
#           parent 向祖先方向回溯**的相关访问序列)、0.3 均匀(H-P1
#           setup:结构是否携带 recency 之外的可利用信息;方向为
#           child→ancestor,非 parent→child——语义注记见结果文档)
#
# 边界:等大小;C_resident 未入模(P0 capacity 视角);SKIP 未建模;
# 合成 workload 单 seed;regret 描述性;不预设 H-P0/H-P1 结果。

import random

SEED = 42
N_NODES = 32
TRACE_LEN = 2000
N_TREES = 8
BUDGETS = [0.20, 0.30, 0.40, 0.50, 0.60, 0.80]
C_EXT, C_REHY = 0.69, 0.72
LFU_DECAY_INTERVAL = 200


def gen_sizes():
    return [1] * N_NODES  # v0 纪律:等大小(size 轴属 H-P1 sensitivity)


def gen_hot_trace(rng):
    p_hot, hot_frac = 0.70, 0.35
    hot = rng.sample(range(N_NODES), max(1, int(N_NODES * hot_frac)))
    return [
        rng.choice(hot) if rng.random() < p_hot else rng.randrange(N_NODES)
        for _ in range(TRACE_LEN)
    ]


def gen_tree_topology():
    # 8 棵树,每棵 4 节点的链:P_i → C_i1 → C_i2 → C_i3
    parent = {}
    for t in range(N_TREES):
        chain = [t * 4 + j for j in range(4)]
        for j in range(1, 4):
            parent[chain[j]] = chain[j - 1]
    return parent


def gen_tree_trace(rng, parent):
    nodes = list(range(N_NODES))
    roots = [n for n in nodes if n not in parent]
    trace = []
    for _ in range(TRACE_LEN):
        if rng.random() < 0.70:
            # 沿树边连续行走:从随机节点向根回溯 2–4 步(相关访问序列)
            cur = rng.choice(nodes)
            walk_len = rng.randint(2, 4)
            for _ in range(walk_len):
                trace.append(cur)
                if cur in parent:
                    cur = parent[cur]
                else:
                    cur = rng.choice(roots)
        else:
            trace.append(rng.choice(nodes))
    return trace[:TRACE_LEN]


def simulate(policy, trace, budget, c_ext, c_rehy):
    resident = set()
    externalized = set()
    last_access = {}
    counts = {n: 0 for n in range(N_NODES)}
    # Belady next-use
    next_use_at = [0] * len(trace)
    last_pos = {}
    for idx in range(len(trace) - 1, -1, -1):
        node = trace[idx]
        next_use_at[idx] = last_pos.get(node, len(trace))
        last_pos[node] = idx
    node_next_use = {}

    used = 0
    budget_bytes = budget * N_NODES
    ext_count = 0
    rehy_count = 0
    violations = 0

    def touch(node, step):
        nonlocal used, rehy_count
        if node not in resident:
            if node in externalized:
                rehy_count += 1        # NORM ①:REHYDRATE 事件
                used += 1
                externalized.discard(node)
            else:
                used += 1              # 首次构建,无边界成本
            resident.add(node)
        last_access[node] = step
        counts[node] += 1
        if policy == "oracle":
            node_next_use[node] = next_use_at[step]

    def evict_one(current):
        nonlocal used, ext_count
        candidates = [n for n in resident if n != current]
        if not candidates:
            return
        if policy == "oracle":
            key = lambda n: (-node_next_use.get(n, len(trace)), n)   # NORM ②
        elif policy == "lfu_aging":
            key = lambda n: (counts[n], last_access[n], n)           # NORM ②
        else:  # lru
            key = lambda n: (last_access[n], n)                      # NORM ②
        victim = min(candidates, key=key)
        resident.discard(victim)
        externalized.add(victim)
        used -= 1
        ext_count += 1

    for step, node in enumerate(trace):
        if policy == "lfu_aging" and step > 0 and step % LFU_DECAY_INTERVAL == 0:
            for k in counts:
                counts[k] //= 2                                      # aging
        touch(node, step)
        if policy == "always":
            if used > budget_bytes:
                violations += 1
        else:
            while used > budget_bytes and len(resident) > 1:
                evict_one(node)                                       # NORM ①
            if used > budget_bytes:
                violations += 1

    return {
        "rehy": rehy_count,
        "ext": ext_count,
        "cost": c_ext * ext_count + c_rehy * rehy_count,
        "violations": violations,
    }


def main():
    sizes = gen_sizes()
    assert sum(sizes) == N_NODES
    rng = random.Random(SEED)
    parent = gen_tree_topology()
    traces = {
        "hot": gen_hot_trace(rng),
        "tree": gen_tree_trace(rng, parent),
    }
    print("=== Residency Policy Simulator v1(P3:New Policy Discrimination)===")
    print(f"nodes={N_NODES}(等大小) trace={TRACE_LEN} seed={SEED} "
          f"C_ext={C_EXT} C_rehy={C_REHY};objective=字典序(v0.1 定义)")
    print("policies: lru(baseline) / lfu_aging(NEW 可实现) / oracle(reference)")
    print()

    results = []
    for wname, trace in traces.items():
        for budget in BUDGETS:
            for policy in ["lru", "lfu_aging", "oracle"]:
                m = simulate(policy, trace, budget, C_EXT, C_REHY)
                results.append((wname, budget, policy, m))

    print("### 表:budget × workload(格式: policy=rehy/cost)")
    for wname in ["hot", "tree"]:
        print(f"-- workload={wname} --")
        print("budget | " + " | ".join(f"{p:>16}" for p in ["lru", "lfu_aging", "oracle"]))
        for budget in BUDGETS:
            cells = []
            for policy in ["lru", "lfu_aging", "oracle"]:
                m = next(r[3] for r in results
                         if r[0] == wname and r[1] == budget and r[2] == policy)
                cells.append(f"{m['rehy']:>5}/{m['cost']:>7.1f}")
            print(f"{budget:>6.2f} | " + " | ".join(f"{c:>16}" for c in cells))
        print()

    print("### H-P0 域判读(hot):LFU-aging 相对 LRU 的成本变化")
    for budget in BUDGETS:
        lru = next(r[3] for r in results if r[0] == "hot" and r[1] == budget and r[2] == "lru")
        lfu = next(r[3] for r in results if r[0] == "hot" and r[1] == budget and r[2] == "lfu_aging")
        delta = (lfu["cost"] - lru["cost"]) / max(lru["cost"], 1e-9) * 100
        print(f"  budget={budget:.2f}: lru={lru['cost']:.1f} lfu={lfu['cost']:.1f} → lfu 相对 lru {delta:+.1f}%")

    print()
    print("### H-P1 setup(tree):LFU-aging 相对 LRU 的成本变化")
    for budget in BUDGETS:
        lru = next(r[3] for r in results if r[0] == "tree" and r[1] == budget and r[2] == "lru")
        lfu = next(r[3] for r in results if r[0] == "tree" and r[1] == budget and r[2] == "lfu_aging")
        delta = (lfu["cost"] - lru["cost"]) / max(lru["cost"], 1e-9) * 100
        print(f"  budget={budget:.2f}: lru={lru['cost']:.1f} lfu={lfu['cost']:.1f} → lfu 相对 lru {delta:+.1f}%")

    print()
    print("### 残差(lfu 相对 oracle 的未捕获差距;结构策略的潜在空间)")
    for wname in ["hot", "tree"]:
        for budget in [0.30, 0.40, 0.50]:
            lfu = next(r[3] for r in results if r[0] == wname and r[1] == budget and r[2] == "lfu_aging")
            orc = next(r[3] for r in results if r[0] == wname and r[1] == budget and r[2] == "oracle")
            if orc["cost"] > 0:
                gap = (lfu["cost"] - orc["cost"]) / max(orc["cost"], 1e-9) * 100
                print(f"  {wname}/budget={budget:.2f}: lfu 高于 oracle {gap:.1f}%")
    print()
    print("注:regret 描述性;C_resident 未入模(P0 capacity 视角);合成 workload")
    print("单 seed;结论不预设 H-P0/H-P1——正式判读见结果文档。")


if __name__ == "__main__":
    main()
