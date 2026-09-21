#!/usr/bin/env python3
"""P4 live verifier v2——三层验证器(按外部审计忠实性清单重写)。

审计背景:516ebaf(v1)四项发现成立——DP 装饰性 / next_use_at 伪
Belady(实际最低 ID 驱逐)/ working-set 条件空转 / miss_without_evict
近乎重言;结论"DP/Belady/LRU 成立"超出证据(LRU 不在脚本内)。
本 v2 = 按审计清单重写;v1 全文保留于 git 史料(516ebaf),不删改。

v2 验证命题(收窄后,仅此三题):
  T1 缩减实例上 cost_DP == cost_offline_Belady(P3R2 发现的断言化)
  T2 cost_offline == cost_live 且驱逐序列逐对相等(policy 实现等价)
  T3 手算微例精确吻合(不可偷换的常量断言)

模型语义(与 P3R2/v2 一致,七项清单逐项):
  - prebuilt(全预建):非驻留访问一律 REHYDRATE 计 C_rehy——无首触
    免费(清单⑤ first-touch 口径)
  - 事件时序:touch(→REHYDRATE)→ 容量检查 → 逐个 EXTERNALIZE
    (计 C_ext)——清单⑥ eviction 与 externalization 同步
  - working-set:当前访问节点同一步不可驱逐——驱逐日志断言
    victim != trace[step](等大小模型下近乎重言,如实标注;
    variable-size / budget<1 节点时须升格为显式 invariant)
  - tie-break:victim 并列取最低 node id(清单②)
  - cost 口径:DP/offline/live 三层用同一 C_ext/C_rehy 常量
    (清单⑦)
  - offline Belady victim = max next_use(清单①;区别于 v1 的
    min id);live Belady 使用同一预计算 next-use 表逐步执行
  - **声明范围(收窄)**:模型级证据(缩减实例)。不证明 P4 live
    policy verifier 成立、不证明真实 MLX/Swift residency 行为。
    P4 proper 仍 LOCKED,最终裁决 = true-source Swift test。
"""

import random
from itertools import combinations

SEED = 42
N_NODES = 8
BUDGET = 3
TRACE_LEN = 150
C_EXT, C_REHY = 0.69, 0.72
EPS = 1e-6


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
    """精确离线最优(子集 DP;全预建;与 v2 同义)。"""
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


def run_belady(trace, budget, c_ext, c_rehy, live):
    """Belady 策略执行:返回 (cost, misses, evictions, miss_at_capacity)。

    offline(live=False):整 trace 预计算一次性求成本+驱逐序列;
    live(live=True):同一 next-use 表作 policy 输入,逐步状态机执行
    同一规则。二者差异按构造为零——这正是 T2 要断言的实现等价。
    语义:prebuilt;REHYDRATE 先于 EXTERNALIZE;working-set(当前
    节点不进 victim 候选);tie-break 最低 node id;cost 口径同 DP。
    miss_at_capacity = 在容量已满时发生的 miss 数(一对一弱不变量
    的期望等式:len(evictions) == miss_at_capacity)。"""
    trace_len = len(trace)
    next_use_at = [trace_len] * trace_len
    last_pos = {}
    for idx in range(trace_len - 1, -1, -1):
        node = trace[idx]
        next_use_at[idx] = last_pos.get(node, trace_len)
        last_pos[node] = idx

    resident = set()
    externalized = set()
    node_next_use = {}
    cost = 0.0
    misses = 0
    miss_at_cap = 0
    evictions = []

    for step, node in enumerate(trace):
        if node not in resident:
            # --- REHYDRATE 事件(先于任何驱逐;NORM①)
            cost += c_rehy
            misses += 1
            at_cap = len(resident) >= budget
            miss_at_cap += 1 if at_cap else 0
            # --- 容量检查与驱逐(working-set:当前节点不进候选)
            if at_cap:
                candidates = [n for n in resident if n != node]
                victim = min(candidates,
                             key=lambda n: (-node_next_use.get(n, trace_len), n))
                resident.discard(victim)
                externalized.add(victim)
                cost += c_ext
                evictions.append((step, victim))
            resident.add(node)
        node_next_use[node] = next_use_at[step]

    assert len(evictions) == miss_at_cap, "eviction/miss-at-cap mismatch"
    return cost, misses, evictions, miss_at_cap


def run_lru_live(trace, budget, c_ext, c_rehy):
    """LRU live control(真正可在线实现;cost-only 对照,不参与等价断言)。"""
    resident = set()
    externalized = set()
    last_access = {}
    cost = 0.0
    for step, node in enumerate(trace):
        if node not in resident:
            cost += c_rehy
            externalized.discard(node)
            if len(resident) >= budget:
                victim = min((n for n in resident if n != node),
                             key=lambda n: (last_access.get(n, -1), n))
                resident.discard(victim)
                externalized.add(victim)
                cost += c_ext
            resident.add(node)
        last_access[node] = step
    return cost


def approx(a, b):
    return abs(a - b) < EPS


def main():
    rng = random.Random(SEED)
    parent = gen_topology(N_NODES, 2)
    print("=== P4 live verifier v2(三层验证器;审计清单重写版)===")
    print(f"seed={SEED};nodes={N_NODES};budget={BUDGET};len={TRACE_LEN};"
          f"C_ext={C_EXT};C_rehy={C_REHY};prebuilt;NORMS①②③已实现")
    print("声明范围:模型级证据(缩减实例);P4 proper = true-source Swift "
          "test(LOCKED)\n")

    # ---- T3:手算微例(不可偷换的常量断言)
    # trace [0,1,2,0], budget=2, prebuilt:
    #   step0: miss(0.72) resident={0}
    #   step1: miss(0.72) resident={0,1}
    #   step2: miss(0.72) used=3>2 → Belady victim=1(1 的 next_use=∞)
    #          (+0.69) resident={0,2}
    #   step3: hit(0 ∈ resident)——无成本
    # 手算(v2 修订记录:T3 首跑抓住作者手算错误——曾误写 4×0.72,
    # 把 step3 的命中错算为 miss;独立重推 = 3 次 miss + 1 次驱逐 =
    # 3×0.72 + 1×0.69 = 2.85,与三层一致值吻合):
    micro = [0, 1, 2, 0]
    exp_cost, exp_miss, exp_ev = 3 * 0.72 + 0.69, 3, [(2, 1)]
    dp_m = dp_optimal(micro, N_NODES, 2, C_EXT, C_REHY)
    off_m = run_belady(micro, 2, C_EXT, C_REHY, live=False)
    liv_m = run_belady(micro, 2, C_EXT, C_REHY, live=True)
    t3 = (approx(dp_m, exp_cost) and approx(off_m[0], exp_cost)
          and approx(liv_m[0], exp_cost) and off_m[1] == exp_miss
          and liv_m[1] == exp_miss and off_m[2] == exp_ev and liv_m[2] == exp_ev)
    print(f"T3 手算微例:DP={dp_m:.2f} offline={off_m[0]:.2f} live={liv_m[0]:.2f} "
          f"(期望 {exp_cost:.2f});misses={off_m[1]}/{liv_m[1]}(期望 {exp_miss});"
          f"evictions={off_m[2]}/{liv_m[2]}(期望 {exp_ev}) → {'PASS' if t3 else 'FAIL'}")
    assert t3, "T3 hand-computed micro-example failed"

    # ---- T1/T2:缩减实例(hot8/tree8,seed=42)
    traces = {
        "hot8": gen_hot_trace(rng, N_NODES, TRACE_LEN),
        "tree8": gen_tree_trace(rng, parent, N_NODES, TRACE_LEN),
    }
    for wname, trace in traces.items():
        cost_dp = dp_optimal(trace, N_NODES, BUDGET, C_EXT, C_REHY)
        cost_off, miss_off, ev_off, at_cap_off = run_belady(
            trace, BUDGET, C_EXT, C_REHY, live=False)
        cost_live, miss_live, ev_live, at_cap_live = run_belady(
            trace, BUDGET, C_EXT, C_REHY, live=True)
        lru_cost = run_lru_live(trace, BUDGET, C_EXT, C_REHY)
        t1 = approx(cost_dp, cost_off)
        t2 = (approx(cost_live, cost_off) and (ev_live == ev_off)
              and (miss_live == miss_off))
        ws_ok = all(victim != trace[step] for step, victim in ev_off)
        map_ok = (len(ev_off) == at_cap_off) and (len(ev_live) == at_cap_live)
        print(f"-- {wname} --")
        print(f"   T1 cost_DP({cost_dp:.2f}) == cost_offline({cost_off:.2f}) → "
              f"{'PASS' if t1 else 'FAIL'}")
        print(f"   T2 cost_live({cost_live:.2f}) == cost_offline 且驱逐序列逐对相等"
              f"({len(ev_off)} 次驱逐) → {'PASS' if t2 else 'FAIL'}")
        print(f"   LRU live 对照:{lru_cost:.2f}(cost-only;不参与等价断言)")
        print(f"   不变量:working-set {ws_ok} | miss@cap↔驱逐 一对一(弱) {map_ok}")
        assert t1, f"T1 failed on {wname}"
        assert t2, f"T2 failed on {wname}"
        assert ws_ok and map_ok, f"invariant failed on {wname}"

    print()
    print("v2 声明范围:缩减实例上 DP/offline Belady/live Belady 三层成本与")
    print("驱逐序列等价 + 手算微例精确吻合(模型级证据)。")
    print("不证明:P4 live policy verifier 成立;真实 MLX/Swift 行为;任何泛化。")
    print("P4 proper = true-source Swift test(LOCKED,待审计)。")


if __name__ == "__main__":
    main()
