#!/usr/bin/env python3
# Copyright © 2026 SimiGo-Lab. Track E(命名待定)Residency Policy Simulator v0
#
# 记录:SimiGo-Lab trackE-residency/(RESIDENCY_POLICY_OPENING v2,承 M4 终判)
# 边界:合成 workload;boundary-cost 视角(C_resident=0 未建模,P0
# prerequisite);SKIP 未建模(访问外部节点=强制 rehydrate);无 GPU/
# 无 SimiGo runtime——数字先于 live,差异>噪声才进 P4。
#
# Baselines/reference(v0 不含 new policy):
#   always   —— 永不外化;预算不足时逐 step 记 violation
#   pressure —— 用量 ≥ 90% 预算即按 LRU 序主动外化至阈值下
#   lru      —— 被动:准入需空间时外化最久未用(刚访问者除外)
#   oracle   —— 预知 next_access,外化最远者(reference bound)
#
# 成本:C_ext / C_rehy 为 token-equivalent 参数(默认 0.69 / 0.72,
# M4 拆分参考);C_resident=0 未建模(P0 prerequisite)。
# 输出:三重 sweep(budget × locality × C_rehy)的表格 + 可观测差异
# 区域摘要。regret = 描述性,不是胜负分。

import random
from statistics import median

SEED = 42
N_NODES = 32
TRACE_LEN = 2000
NODE_SIZE_RANGE = (1, 10)  # 以"页单位"计,相对大小
TOTAL_SIZE = None  # 运行时 = sum(sizes)
LOCALITIES = ["short", "medium", "long", "very-long"]
LOCALITY_PARAMS = {  # (p_hot, hot_frac)
    "short": (0.90, 0.15),
    "medium": (0.70, 0.35),
    "long": (0.45, 0.60),
    "very-long": (0.20, 0.90),
}
BUDGETS = [0.20, 0.30, 0.40, 0.50, 0.60, 0.80, 1.00]
C_REHY_SWEEP = [0.25, 0.5, 0.72, 1.0, 2.0, 4.0, 8.0]
C_EXT_DEFAULT = 0.69
C_REHY_DEFAULT = 0.72


def gen_sizes(rng):
    return [rng.randint(*NODE_SIZE_RANGE) for _ in range(N_NODES)]


def gen_trace(rng, locality):
    p_hot, hot_frac = LOCALITY_PARAMS[locality]
    hot = rng.sample(range(N_NODES), max(1, int(N_NODES * hot_frac)))
    return [
        rng.choice(hot) if rng.random() < p_hot else rng.randrange(N_NODES)
        for _ in range(TRACE_LEN)
    ]


def simulate(policy, trace, sizes, budget, c_ext, c_rehy):
    """返回 dict:rehy(次数)/ext/总成本/峰值/violation"""
    resident = set()          # 已构建(首次访问=构建,无成本;prefill 未建模)
    externalized = set()      # 构建过但当前外化
    last_access = {}
    # Belady 式 next-use:trace[i] 处的节点,下一次出现的 index(无则 len)
    next_use_at = [0] * len(trace)
    last_pos = {}
    for idx in range(len(trace) - 1, -1, -1):
        node = trace[idx]
        next_use_at[idx] = last_pos.get(node, len(trace))
        last_pos[node] = idx
    node_next_use = {}        # 每个已构建节点当前状态下的下次使用位置(oracle 用)
    used = 0
    ext_count = 0
    rehy_count = 0
    violations = 0
    peak = 0

    def touch(node, step):
        nonlocal used, ext_count, rehy_count
        if node not in resident:
            if node in externalized:
                rehy_count += 1      # 强制 rehydrate(SKIP 未建模)
                used += sizes[node]
                externalized.discard(node)
            else:
                used += sizes[node]  # 首次构建,无边界成本
            resident.add(node)
        node_next_use[node] = next_use_at[step]
        last_access[node] = step

    def evict_one(current):
        nonlocal used, ext_count
        if policy == "oracle":
            victim = max(
                (n for n in resident if n != current),
                key=lambda n: node_next_use.get(n, len(trace)),
            )
        else:
            victim = min(
                (n for n in resident if n != current),
                key=lambda n: last_access[n],
            )
        resident.discard(victim)
        externalized.add(victim)
        used -= sizes[victim]
        ext_count += 1

    for step, node in enumerate(trace):
        touch(node, step)
        peak = max(peak, used)

        if policy == "always":
            if used > budget:
                violations += 1          # 逐 step 记 violation
        elif policy == "pressure":
            while used > budget * 0.9 and len(resident) > 1:
                evict_one(node)
            if used > budget:
                violations += 1
        else:  # lru / oracle:被动,超预算即外化至合规
            while used > budget and len(resident) > 1:
                evict_one(node)
            if used > budget:
                violations += 1

    return {
        "rehy": rehy_count,
        "ext": ext_count,
        "cost": c_ext * ext_count + c_rehy * rehy_count,
        "peak": peak,
        "violations": violations,
    }


def main():
    rng = random.Random(SEED)
    sizes = gen_sizes(rng)
    global TOTAL_SIZE
    TOTAL_SIZE = sum(sizes)
    print(f"=== Residency Policy Simulator v0 ===")
    print(
        f"nodes={N_NODES} total_size={TOTAL_SIZE} trace={TRACE_LEN} seed={SEED}"
    )
    print(
        f"cost params: C_ext={C_EXT_DEFAULT} C_rehy default={C_REHY_DEFAULT}"
        "(C_resident=0 未建模——P0 prerequisite;boundary-cost 视角)"
    )
    print()

    results = []  # (budget, locality, c_rehy, policy, metrics)
    for li, locality in enumerate(LOCALITIES):
        trace = gen_trace(random.Random(SEED + 1000 + li), locality)  # 稳定种子(勿用 hash)
        for budget in BUDGETS:
            budget_bytes = TOTAL_SIZE * budget
            for c_rehy in C_REHY_SWEEP:
                for policy in ["always", "pressure", "lru", "oracle"]:
                    m = simulate(policy, trace, sizes, budget_bytes, C_EXT_DEFAULT, c_rehy)
                    results.append((budget, locality, c_rehy, policy, m))

    # ---- 表 1:C_rehy=0.72 下 budget × locality(各策略 rehy 次数 / 成本 / violation)
    print("### 表 1:C_rehy=0.72,budget × locality(格式: policy=rehy/cost/viol)")
    for locality in LOCALITIES:
        print(f"-- locality={locality} --")
        header = "budget | " + " | ".join(f"{p:>14}" for p in ["always", "pressure", "lru", "oracle"])
        print(header)
        for budget in BUDGETS:
            cells = []
            for policy in ["always", "pressure", "lru", "oracle"]:
                m = next(
                    r[4] for r in results
                    if r[0] == budget and r[1] == locality and r[2] == C_REHY_DEFAULT and r[3] == policy
                )
                cells.append(f"{m['rehy']:>4}/{m['cost']:>6.1f}/{m['violations']:>4}")
            print(f"{budget:>6.2f} | " + " | ".join(f"{c:>14}" for c in cells))
        print()

    # ---- 表 2:C_rehy sweep(budget=0.40, locality=medium)
    print("### 表 2:C_rehydrate sweep(budget=0.40, locality=medium;cost 总量)")
    print("C_rehy | " + " | ".join(f"{p:>10}" for p in ["always", "pressure", "lru", "oracle"]))
    for c_rehy in C_REHY_SWEEP:
        cells = []
        for policy in ["always", "pressure", "lru", "oracle"]:
            m = next(
                r[4] for r in results
                if r[0] == 0.40 and r[1] == "medium" and r[2] == c_rehy and r[3] == policy
            )
            cells.append(f"{m['cost']:>10.1f}")
        print(f"{c_rehy:>6} | " + " | ".join(f"{c:>10}" for c in cells))
    print()

    # ---- 可观测差异区域摘要:LRU(通用基线)vs Oracle(reference bound)
    print("### 摘要:决策空间是否可观测(LRU 相对 Oracle 的成本差倍数)")
    print("budget | locality | lru_cost | oracle_cost | lru/oracle")
    ratios = []
    for locality in LOCALITIES:
        for budget in BUDGETS:
            lru = next(
                r[4] for r in results
                if r[0] == budget and r[1] == locality and r[2] == C_REHY_DEFAULT and r[3] == "lru"
            )
            orc = next(
                r[4] for r in results
                if r[0] == budget and r[1] == locality and r[2] == C_REHY_DEFAULT and r[3] == "oracle"
            )
            if orc["cost"] > 0:
                ratio = lru["cost"] / orc["cost"]
                ratios.append((budget, locality, ratio))
                print(f"{budget:>6.2f} | {locality:>9} | {lru['cost']:>8.1f} | {orc['cost']:>11.1f} | {ratio:>10.2f}")
    interesting = [r for r in ratios if r[2] >= 1.10]
    print()
    print(f"lru/oracle ≥ 1.10 的 (budget, locality) 组合:{len(interesting)}/{len(ratios)}")
    for budget, locality, ratio in sorted(interesting, key=lambda x: -x[2])[:8]:
        print(f"  差异显著:budget={budget:.2f} locality={locality} lru/oracle={ratio:.2f}")
    print()
    print("注:regret/C_resident 均未建模;数字=合成 workload+boundary-cost 视角,")
    print("优劣判断不做(H-P0/H-P1 判读待 P3)。")


if __name__ == "__main__":
    main()
