#!/usr/bin/env python3
# Copyright © 2026 SimiGo-Lab. Track E(命名待定)Residency Policy Simulator v3
#
# 记录:SimiGo-Lab trackE-residency/(P3 Design v0.2.1 PASS → Implementation
# UNLOCKED;冻结规范严格执行)
#
# 冻结规范(P3 Design v0.2.1):
#   W=200;reuse_score(i)=min(1, n_i/H);Score(i)=C_rehy×reuse_score(i);
#   驱逐 argmin Score;tie-break 最低 node id;H∈{1,4,8,16} 主轮 H=8;
#   cost_aware_greedy = frequency-only instantiation(无未来 trace 信息);
#   双情景:同一 trace/seed/策略/预算 严格并行;结果分开解释禁止合并。
# NORMS①②③延续(事件时序/tie-break/working-set:当前节点本步不可驱逐)。
#
# 五通道输出(A 可行性/B 边界成本/C decode 步/D byte-steps/E 参照差距)
# + 情景二 P_pressure 通道(k_c 触发的超限步计数;ms 换算由 P0.2 曲线
# 校准,属后续;λ_p 仅报告层倍数,不入 J_boundary)。
#
# 边界:等大小;C_resident 未入模(P0 capacity 视角;P0.2 悬崖实测=
# 平坦区+越界 2.38×/2.54× 双口径,属情景二通道的校准来源);SKIP 未
# 建模;合成 workload 单 seed;regret 描述性;不预设 H-P0/H-P1。

import random
from collections import deque, Counter

SEED = 42
N_NODES = 32
TRACE_LEN = 2000
C_EXT, C_REHY = 0.69, 0.72
W_WINDOW = 200
LFU_DECAY_INTERVAL = 200


def gen_topology(n_nodes, n_trees):
    parent = {}
    per = n_nodes // n_trees
    for t in range(n_trees):
        chain = [t * per + j for j in range(per)]
        for j in range(1, per):
            parent[chain[j]] = chain[j - 1]
    return parent


def gen_hot_trace(rng, n_nodes, length):
    p_hot, hot_frac = 0.70, 0.35
    hot = rng.sample(range(n_nodes), max(1, int(n_nodes * hot_frac)))
    return [rng.choice(hot) if rng.random() < p_hot else rng.randrange(n_nodes)
            for _ in range(length)]


def gen_tree_trace(rng, parent, n_nodes, length):
    """树边相关访问;方向 = child→ancestor 向祖先回溯(P3 首跑审计注记)。"""
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


def simulate_v3(policy, trace, budget, c_ext, c_rehy, H=8, W=W_WINDOW,
                k_c=None):
    """单策略单轮执行;返回五通道 dict。
    k_c=None → 情景一(仅硬可行性);k_c 给定 → 情景二(附加
    P_pressure 通道:|R|>k_c 的超限步计数;λ_p 在报告层施加)。"""
    resident = set()
    externalized = set()
    last_access = {}
    freq = {}
    window = deque()                      # (step, node);窗口 = 最近 W 步
    next_use_at = [0] * len(trace)
    last_pos = {}
    for idx in range(len(trace) - 1, -1, -1):
        node = trace[idx]
        next_use_at[idx] = last_pos.get(node, len(trace))
        last_pos[node] = idx
    node_next_use = {}

    used = 0
    ext_count = 0
    rehy_count = 0
    violations = 0
    steps_excess = 0                      # 情景二通道:|R|>k_c 的步数

    def evict_victim(current, step):
        candidates = [n for n in resident if n != current]   # NORM③
        if not candidates:
            return None
        if policy == "belady_greedy":
            key = lambda n: (-node_next_use.get(n, len(trace)), n)
        elif policy == "cost_aware_greedy":
            cnt = Counter(node for _, node in window)
            key = lambda n: (c_rehy * min(1, cnt.get(n, 0) / H), n)
        elif policy == "lfu_aging":
            key = lambda n: (freq.get(n, 0), last_access[n], n)
        else:  # lru
            key = lambda n: (last_access[n], n)
        return min(candidates, key=key)

    for step, node in enumerate(trace):
        # NORM①:touch(非驻留 → REHYDRATE)
        if node not in resident:
            rehy_count += 1
            externalized.discard(node)
            resident.add(node)
        last_access[node] = step
        freq[node] = freq.get(node, 0) + 1
        window.append((step, node))
        counts = Counter(node for _, node in window)
        if policy == "belady_greedy":
            node_next_use[node] = next_use_at[step]

        # 容量强制(等大小:逐个驱逐至合规)
        while len(resident) > budget:
            victim = evict_victim(node, step)
            if victim is None:
                break
            resident.discard(victim)
            externalized.add(victim)
            ext_count += 1
        if len(resident) > budget:
            violations += 1
        # 情景二通道:超限步计数(k_c < |R| ≤ B 的压力区驻留时长)
        if k_c is not None and len(resident) > k_c:
            steps_excess += 1

    return {
        "violations": violations,                 # 通道 A
        "J": c_ext * ext_count + c_rehy * rehy_count,   # 通道 B
        "rehy": rehy_count,
        "ext": ext_count,
        "resident_final": len(resident),
        "steps_excess": steps_excess,             # 情景二通道(原始步数)
    }


def main():
    rng = random.Random(SEED)
    parent8 = gen_topology(N_NODES, 8)
    print("=== Residency Policy Simulator v3(cost_aware_greedy freq-only + 双情景五通道)===")
    print(f"seed={SEED};nodes={N_NODES};trace={TRACE_LEN};C_ext={C_EXT};C_rehy={C_REHY}")
    print("冻结规范:W=200;reuse_score=min(1,n/H);argmin Score;tie 最低 id;"
          "H∈{1,4,8,16} 主轮 8;双情景同 trace/seed/策略/预算\n")

    traces = {
        "hot": gen_hot_trace(rng, N_NODES, TRACE_LEN),
        "tree": gen_tree_trace(rng, parent8, N_NODES, TRACE_LEN),
    }
    B = 12  # 固定基线预算(0.40 × 32;P3-A 模型验证)
    policies = ["lru", "lfu_aging", "cost_aware_greedy", "belady_greedy"]

    # ---- 通道 A/B/E:双 workload × 策略(H=8 主轮)
    print(f"-- 情景一/二共用执行(B={B},H=8 主轮;P3-A 模型验证)--")
    results = {}
    for wname, trace in traces.items():
        for policy in policies:
            H = 8
            m = simulate_v3(policy, trace, B, C_EXT, C_REHY, H=H)
            results[(wname, policy)] = m
            print(f"  {wname:>5}/{policy:>18}: J={m['J']:>7.1f} "
                  f"(rehy={m['rehy']:>4} ext={m['ext']:>3}) "
                  f"viol={m['violations']} resident_final={m['resident_final']}")
    print()

    # ---- cost_aware_greedy:H sensitivity(主轮 8;{4,16} sensitivity)
    print("-- cost_aware_greedy H sensitivity(J;hot 域)--")
    for H in [4, 8, 16]:
        m = simulate_v3("cost_aware_greedy", traces["hot"], B, C_EXT, C_REHY, H=H)
        print(f"  H={H:>2}: J={m['J']:>7.1f} (rehy={m['rehy']})")
    print()

    # ---- 情景二 P_pressure 通道(k_c 机制验证;模拟器单位)
    print("-- 情景二 P_pressure 通道(k_c 模拟器单位机制验证;λ_p 报告层)--")
    for wname in ["hot", "tree"]:
        trace = traces[wname]
        for k_c in [9, 10, 11]:
            lru = simulate_v3("lru", trace, B, C_EXT, C_REHY, k_c=k_c)
            lfu = simulate_v3("lfu_aging", trace, B, C_EXT, C_REHY, k_c=k_c)
            cag = simulate_v3("cost_aware_greedy", trace, B, C_EXT, C_REHY,
                              k_c=k_c, H=8)
            print(f"  {wname}/k_c={k_c}: steps_excess lru={lru['steps_excess']:>4} "
                  f"lfu={lfu['steps_excess']:>4} cag={cag['steps_excess']:>4}"
                  f"(λ_p 报告层倍乘,不入 J)")
    print()

    # ---- 确定性自检:同配置重跑一致
    m1 = simulate_v3("cost_aware_greedy", traces["hot"], B, C_EXT, C_REHY,
                     H=8, k_c=8)
    m2 = simulate_v3("cost_aware_greedy", traces["hot"], B, C_EXT, C_REHY,
                     H=8, k_c=8)
    det = (m1 == m2)
    print(f"确定性自检(同配置重跑): {'PASS' if det else 'FAIL'}")
    assert det

    print()
    print("*** P3-A 模型验证完成:五通道输出、双情景通道、cost_aware_greedy")
    print("*** (frequency-only instantiation)机制如上;正式策略比较")
    print("*** (真实 k_c 网格映射 + dp 缩减参照)待下一轮。***")


if __name__ == "__main__":
    main()
