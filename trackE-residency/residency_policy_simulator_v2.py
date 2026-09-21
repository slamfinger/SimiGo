#!/usr/bin/env python3
# Copyright © 2026 SimiGo-Lab. Track E(命名待定)Residency Policy Simulator v2
#
# 记录:SimiGo-Lab trackE-residency/(P3 首跑 CONDITIONAL PASS 终判定序:
# ①cost-aware reference 与 Belady 彻底分离;②structure-aware policy
# 正式检验 H-P1)
#
# NORMS(P0.1 终判注记,延续):
#   ① 事件计数时序:每访问步 = touch(外部节点→REHYDRATE,计 C_rehy)
#      → 容量检查 → 逐个 EXTERNALIZE(各计 C_ext);同步多事件逐一计数。
#   ② tie-break:victim 选择并列时固定取最低 node id。
#   ③ working-set 语义(显式):当前访问节点在同一步不可被驱逐
#      (active working-set item)。
#
# Objective(v0.1 字典序):可行性 + 最小化 C_ext×#ext + C_rehy×#rehy。
#
# v2 新增:
#   ① dp_optimal:缩减实例(8 节点/预算 3/150 步)上的子集 DP 精确
#      全局最优(全预建语义;贪心侧同语义 prebuilt=True 对齐,如实
#      披露)——回答"Belady-greedy 距真 cost-aware 最优多远"。
#   ② tree_lru:structure-aware policy(可实现:树邻近期活跃度优先
#      保留,其余按 LRU)——H-P1 正式检验(tree 域应获益,hot 域为
#      特异性对照)。
#
# 策略全集:lru / lfu_aging(v1) / tree_lru(NEW) / belady_greedy
#           (future-aware Belady reference,fault 数口径) / dp_optimal
#           (仅缩减实例)。
#
# 边界:等大小;C_resident 未入模(P0 capacity 视角);SKIP 未建模;
# 合成 workload 单 seed;DP 为全预建语义;regret 描述性;不预设
# H-P0/H-P1。

import random
from itertools import combinations

SEED = 42
N_NODES = 32
N_NODES_SMALL = 8
TRACE_LEN = 2000
TRACE_LEN_SMALL = 150
N_TREES = 8
SMALL_TREES = 2
BUDGETS = [0.20, 0.30, 0.40, 0.50, 0.60, 0.80]
SMALL_BUDGET_NODES = 3
C_EXT, C_REHY = 0.69, 0.72
LFU_DECAY_INTERVAL = 200
TREE_RECENCY_WINDOW = 50


def gen_hot_trace(rng, n_nodes, length):
    p_hot, hot_frac = 0.70, 0.35
    hot = rng.sample(range(n_nodes), max(1, int(n_nodes * hot_frac)))
    return [
        rng.choice(hot) if rng.random() < p_hot else rng.randrange(n_nodes)
        for _ in range(length)
    ]


def gen_topology(n_nodes, n_trees):
    parent = {}
    per = n_nodes // n_trees
    for t in range(n_trees):
        chain = [t * per + j for j in range(per)]
        for j in range(1, per):
            parent[chain[j]] = chain[j - 1]
    return parent


def gen_tree_trace(rng, parent, n_nodes, length):
    nodes = list(range(n_nodes))
    roots = [n for n in nodes if n not in parent]
    trace = []
    while len(trace) < length:
        if rng.random() < 0.70:
            cur = rng.choice(nodes)
            walk_len = rng.randint(2, 4)
            for _ in range(walk_len):
                trace.append(cur)
                cur = parent.get(cur, rng.choice(roots))
        else:
            trace.append(rng.choice(nodes))
    return trace[:length]


def tree_neighbors(parent, n_nodes):
    nb = {n: set() for n in range(n_nodes)}
    for child, par in parent.items():
        nb[child].add(par)
        nb[par].add(child)
    return nb


def simulate(policy, trace, budget_nodes, c_ext, c_rehy, neighbors=None, prebuilt=False):
    """等大小;budget_nodes = 可驻留节点数;返回 (rehy, ext, cost, viol)。
    prebuilt=True:全预建语义(非驻留访问一律 REHYDRATE;与 DP 对齐)"""
    resident = set()
    externalized = set()
    last_access = {}
    max_id = max(trace)
    counts = {n: 0 for n in range(max_id + 1)}
    next_use_at = [0] * len(trace)
    last_pos = {}
    for idx in range(len(trace) - 1, -1, -1):
        node = trace[idx]
        next_use_at[idx] = last_pos.get(node, len(trace))
        last_pos[node] = idx
    node_next_use = {}

    used = 0
    budget_bytes = budget_nodes  # 等大小:size=1/节点
    ext_count = 0
    rehy_count = 0
    violations = 0

    def touch(node, step):
        nonlocal used, rehy_count
        if node not in resident:
            if prebuilt or node in externalized:
                rehy_count += 1        # prebuilt:非驻留访问一律 REHYDRATE
                used += 1
                externalized.discard(node)
            else:
                used += 1              # 首次构建,无边界成本
            resident.add(node)
        last_access[node] = step
        counts[node] = counts.get(node, 0) + 1
        if policy == "belady_greedy":
            node_next_use[node] = next_use_at[step]

    def cold_nb_score(n, step):
        w0 = step - TREE_RECENCY_WINDOW
        nbs = neighbors.get(n, set()) if neighbors else set()
        return sum(1 for nb in nbs if last_access.get(nb, -1) >= w0)

    def evict_one(current, step):
        nonlocal used, ext_count
        candidates = [n for n in resident if n != current]  # NORM ③:working-set
        if not candidates:
            return
        if policy == "belady_greedy":
            key = lambda n: (-node_next_use.get(n, len(trace)), n)
        elif policy == "lfu_aging":
            key = lambda n: (counts.get(n, 0), last_access[n], n)
        elif policy == "tree_lru":
            key = lambda n: (cold_nb_score(n, step), last_access[n], n)
        else:  # lru
            key = lambda n: (last_access[n], n)
        victim = min(candidates, key=key)
        resident.discard(victim)
        externalized.add(victim)
        used -= 1
        ext_count += 1

    for step, node in enumerate(trace):
        touch(node, step)
        if policy == "lfu_aging" and step > 0 and step % LFU_DECAY_INTERVAL == 0:
            for k in list(counts):
                counts[k] //= 2
        while used > budget_bytes and len(resident) > 1:
            evict_one(node, step)      # NORM ①:同步多事件逐一计数
        if used > budget_bytes:
            violations += 1

    return rehy_count, ext_count, c_ext * ext_count + c_rehy * rehy_count, violations


def dp_optimal(trace, n_nodes, budget_nodes, c_ext, c_rehy):
    """精确离线最优(全预建语义):子集 DP。驱逐只在超容量时按需发生
    (正 C_ext 下提前驱逐无益且 DP 全路径可达,故不需主动驱逐转移)。"""
    states = {0: 0.0}
    for step, a in enumerate(trace):
        bit = 1 << a
        new_states = {}
        for S, cost in states.items():
            if S & bit:
                if S not in new_states or cost < new_states[S]:
                    new_states[S] = cost
            else:
                base = cost + c_rehy
                S2 = S | bit
                overflow = bin(S2).count("1") - budget_nodes
                if overflow <= 0:
                    if S2 not in new_states or base < new_states[S2]:
                        new_states[S2] = base
                else:
                    others = [i for i in range(n_nodes) if (S2 >> i) & 1 and i != a]
                    for evict in combinations(others, overflow):
                        S3 = S2
                        for e in evict:
                            S3 &= ~(1 << e)
                        nc = base + c_ext * overflow
                        if S3 not in new_states or nc < new_states[S3]:
                            new_states[S3] = nc
        states = new_states
    return min(states.values())


def main():
    rng = random.Random(SEED)
    print("=== Residency Policy Simulator v2(P3 后续:cost-aware reference + structure-aware policy)===")
    print(f"seed={SEED};C_ext={C_EXT} C_rehy={C_REHY};objective=字典序(v0.1);NORMS①②③已实现")
    print()

    parent32 = gen_topology(N_NODES, N_TREES)
    nb32 = tree_neighbors(parent32, N_NODES)
    parent8 = gen_topology(N_NODES_SMALL, SMALL_TREES)
    nb8 = tree_neighbors(parent8, N_NODES_SMALL)

    # ---- 大网格:主 32 节点(首触免费语义;无 DP)
    print("### 大网格(32 节点/2000 步;cost = C_ext×#ext + C_rehy×#rehy)")
    print("workload | budget | " + " | ".join(f"{p:>14}" for p in ["lru", "lfu_aging", "tree_lru", "belady_greedy"]))
    for wname, trace in [("hot", gen_hot_trace(rng, N_NODES, TRACE_LEN)),
                         ("tree", gen_tree_trace(rng, parent32, N_NODES, TRACE_LEN))]:
        for budget in BUDGETS:
            row = []
            for policy in ["lru", "lfu_aging", "tree_lru", "belady_greedy"]:
                _, _, c, v = simulate(policy, trace, int(budget * N_NODES), C_EXT, C_REHY, nb32)
                row.append(c)
            print(f"{wname:>8} | {budget:>6.2f} | " + " | ".join(f"{c:>14.1f}" for c in row))
        print()

    # ---- H-P1 正式检验:tree_lru vs lru(tree 域应获益;hot 域为特异性对照)
    print("### H-P1 检验:tree_lru 相对 lru(tree 域应获益;hot 域为特异性对照)")
    for wname, trace in [("tree", gen_tree_trace(rng, parent32, N_NODES, TRACE_LEN)),
                         ("hot", gen_hot_trace(rng, N_NODES, TRACE_LEN))]:
        for budget in [0.30, 0.40, 0.50]:
            lru = simulate("lru", trace, int(budget * N_NODES), C_EXT, C_REHY)[2]
            tl = simulate("tree_lru", trace, int(budget * N_NODES), C_EXT, C_REHY, nb32)[2]
            delta = (tl - lru) / max(lru, 1e-9) * 100
            print(f"  {wname}/budget={budget:.2f}: lru={lru:.1f} tree_lru={tl:.1f} → {delta:+.1f}%")
    print()

    # ---- 缩减实例:DP 精确最优 vs 贪心(全预建语义,双方一致)
    print("### 缩减实例(8 节点/预算 3/150 步/全预建;DP=精确离线最优)")
    small_hot = gen_hot_trace(rng, N_NODES_SMALL, TRACE_LEN_SMALL)
    small_tree = gen_tree_trace(rng, parent8, N_NODES_SMALL, TRACE_LEN_SMALL)
    for wname, trace in [("hot8", small_hot), ("tree8", small_tree)]:
        opt = dp_optimal(trace, N_NODES_SMALL, SMALL_BUDGET_NODES, C_EXT, C_REHY)
        row = {}
        for policy in ["lru", "lfu_aging", "tree_lru", "belady_greedy"]:
            _, _, c, _ = simulate(policy, trace, SMALL_BUDGET_NODES, C_EXT, C_REHY, nb8, prebuilt=True)
            row[policy] = c
        cells = " | ".join(f"{p}:{row[p]:>7.1f}({(row[p] - opt) / max(opt, 1e-9) * 100:>5.1f}%)" for p in row)
        print(f"-- {wname} -- DP_opt={opt:.1f}")
        print(f"   {cells}")
    print()
    print("注:DP=精确全局最小(全预建语义);belady_greedy 与 DP 的差距 = ")
    print("fault 数最优 ≠ total boundary cost 最优的直接实测。regret 描述性。")


if __name__ == "__main__":
    main()
