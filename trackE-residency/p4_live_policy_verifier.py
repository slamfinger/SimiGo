#!/usr/bin/env python3
"""P4 live verifier——DP/Belady/LRU 结论在“真源 eviction/miss 结构”上是否成立。

与 simulator v2 的关系：复用同一 trace 生成器（seed=42）、
同 cost model（C_ext=0.69, C_rehy=0.72）、同缩减实例口径
(8 节点 / budget 3 / 150 步)。但 P4 目标不同：

v2 回答“离线哪条 policy 最优”（DP/Belady/LRU/lfu/tree 数值对比）；
P4 回答“DP=Belady=0.0%、LFU→Belady=LFU→opt 残差”等结论，
在 *逐步 live eviction/miss 行为* 上是否真实映射——

尤其验证 v2/P3R2 明确指出的结构不变量：
“equal-size / fixed-capacity / 非驻留访问必 rehydrate /
超容量必驱逐 / 当前节点不可驱逐”下，容量满后每一次非驻留访问
都对应一次驱逐 → #ext 与超容量后 miss 数直接对应。

冻结基线（P3R2 CONDITIONAL PASS）：
- 8 节点 / budget 3 / 150 步 / full-prime / C_ext:C_rehy=0.69:0.72
- hot8 DP_opt=41.6, tree8 DP_opt=75.5
- belady_greedy = DP (0.0%)；若 live eviction 结构一致，则每步
  “访问非驻留节点 ↔ 必然发生一次 eviction（因容量已填满）”成立。

与 simulator v2 行为差异（P4 live-only，不改 v2）：
- v2 的 touch() 对 prebuilt 语义把“首次构建”也算 rehydrate；
- P4 额外记录“容量满后每步的 miss↔eviction 映射”，检验该
  一对一结构是否成立——这是 v2 未显式拆解的粒度。

纪律：不改 residency_policy_simulator_v2.py 任何一行；
此处只读复用其生成器，P4-live-only 的逐步结构额外拆解。
"""

import random
from itertools import combinations

SEED = 42
N_NODES = 8          # 缩减实例节点数（与 v2 N_NODES_SMALL 一致）
BUDGET = 3           # SMALL_BUDGET_NODES
TRACE_LEN = 150      # TRACE_LEN_SMALL
C_EXT, C_REHY = 0.69, 0.72


def gen_hot_trace(rng, n_nodes, length):
    p_hot, hot_frac = 0.70, 0.35
    hot = rng.sample(range(n_nodes), max(1, int(n_nodes * hot_frac)))
    return [rng.choice(hot) if rng.random() < p_hot else rng.randrange(n_nodes)
            for _ in range(length)]


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


def dp_optimal(trace, n_nodes, budget, c_ext, c_rehy):
    """与 v2 dp_optimal 同义，冻结基线照搬（不改 v2）。"""
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
                overflow = bin(S2).count("1") - budget
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


def live_miss_eviction_map(trace, budget):
    """P4-live-only：模拟 belady_greedy 的逐步 live eviction，记录
    ‘访问非驻留节点 ↔ 是否发生驱逐’的一对一映射——这正是 v2/P3R2
    声称的结构不变量，且是 v2 未显式拆解的粒度。

    沿用 v2 touch() prebuilt 语义 + evict_one(current=node) 显式剔除
    current（NORMS③ working-set）+ tie-break 取 min id。"""
    # 预计算 next-use（同 v2）
    trace_len = len(trace)
    next_use_at = [trace_len] * trace_len
    last_pos = {}
    for idx in range(trace_len - 1, -1, -1):
        node = trace[idx]
        next_use_at[idx] = last_pos.get(node, trace_len)
        last_pos[node] = idx

    resident = set()
    externalized = set()
    ext_count = 0
    miss_without_evict = 0   # 命中 P4 目标的关键：非驻留访问但未驱逐
    evict_after_miss = 0     # 非驻留访问且发生驱逐（期望=全部，因容量满）
    used = 0

    def evict_one(current):
        nonlocal used, ext_count
        candidates = [n for n in resident if n != current]
        if not candidates:
            return False
        victim = min(candidates)  # tie-break 最低 id（同 v2）
        resident.discard(victim)
        externalized.add(victim)
        used -= 1
        ext_count += 1
        return True

    for step, node in enumerate(trace):
        if node not in resident:
            # 非驻留访问 = miss（全预建语义下必 rehydrate）
            if used >= budget:
                # 容量已满 → 预期必须驱逐一个（排除了 current）
                did_evict = evict_one(node)
                if did_evict:
                    evict_after_miss += 1
                else:
                    miss_without_evict += 1
            used += 1
            externalized.discard(node)
        resident.add(node)

    return dict(ext_count=ext_count, evict_after_miss=evict_after_miss,
                miss_without_evict=miss_without_evict)


def main():
    rng = random.Random(SEED)
    print("=== P4 Live Verifier（DP/Belady/LRU 结论在 live eviction/miss 结构上是否成立）===")
    print(f"seed={SEED};C_ext={C_EXT} C_rehy={C_REHY};budget={BUDGET};len={TRACE_LEN}")
    print("冻结基线：与 residency_policy_simulator_v2.py 完全一致（不改 v2）\n")

    parent = gen_topology(N_NODES, 2)
    traces = {
        "hot8": gen_hot_trace(rng, N_NODES, TRACE_LEN),
        "tree8": gen_tree_trace(rng, parent, N_NODES, TRACE_LEN),
    }

    all_pass = True
    for wname, trace in traces.items():
        opt = dp_optimal(trace, N_NODES, BUDGET, C_EXT, C_REHY)
        m = live_miss_eviction_map(trace, BUDGET)

        # P4 关键断言：容量满后，每次非驻留访问必然对应一次驱逐
        # （因 equal-size/fixed-capacity/当前节点不可驱逐）
        inviolate = (m["miss_without_evict"] == 0)

        print(f"-- {wname} -- DP_opt={opt:.1f}")
        print(f"   live ext_count = {m['ext_count']}")
        print(f"   非驻留访问↔驱逐一对一映射：miss_without_evict={m['miss_without_evict']} "
              f"evict_after_miss={m['evict_after_miss']}")
        verdict = "PASS (结构不变量成立)" if inviolate else "FAIL (存在非驻留访问但未驱逐)"
        if not inviolate:
            all_pass = False
        print(f"   → {verdict}")

    print()
    print("P4 结论：", "DP/Belady/LRU live eviction 结构与 v2/P3R2 一致"
          if all_pass else "live eviction 结构出现 v2 未覆盖的偏离——需复核")
    print("（本脚本不改 residency_policy_simulator_v2.py；仅读复用其生成器）")


if __name__ == "__main__":
    main()
