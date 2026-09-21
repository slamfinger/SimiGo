#!/usr/bin/env python3
"""P4 live verifier v3.1——P4-B 复审落地(逐步不变式 + tie-break 随机断言)。

审计背景:v3(d5a7c5f)CONDITIONAL PASS(模型级过渡验证器),三条遗留
全部本轮落地:
  ① SEM 不变式升级为**每步断言**(不再只查最终状态);
  ② offline 实现与 stream 实现**对称覆盖**(同为 hook 逐步检查);
  ③ tie-break 规则在随机测试中**独立重推断言**(不依赖人工微例):
     若候选节点的 next_use 相同,实际 victim 必须等于候选集合中
     具有最大 next_use 的最小 id 节点。
不变式同时升级为正向形式:每步完成后 current ∈ resident
(working-set 的正向检查,而非仅"不被驱逐")。

形式化语义(SEM-1..5,延续):
  SEM-1 初始:resident=∅;全体节点初始 ∈ externalized
  SEM-2 访问非驻留节点 → REHYDRATE,付 C_rehy
  SEM-3 |resident| > budget → EXTERNALIZE 至合规;当前节点本步不可驱逐
  SEM-4 victim 并列 → 最低 node id
  SEM-5 三层同一 C_ext/C_rehy
  externalized = 模型状态:resident ∪ externalized = 全体 且 互斥
  (不变式在两个实现的每一步后断言——P4-B 复审要求)

声明范围(冻结):模型级证据(缩减模型/参数/随机轨迹内三实现一致);
不证明规格本身正确(规格正确性由 SEM 形式化+外部审计把守);不证明
Swift/MLX 真源一致。P4 proper = true-source Swift test(LOCKED)。"""

import random
from itertools import combinations

SEED = 42
N_NODES = 8
BUDGET = 3
TRACE_LEN = 150
C_EXT, C_REHY = 0.69, 0.72
EPS = 1e-6


def approx(a, b):
    return abs(a - b) < EPS


# ---------- 独立实现 1:offline_belady_batch(批处理式) ----------
def offline_belady_batch(trace, n_nodes, budget, c_ext, c_rehy,
                         step_hook=None, evict_hook=None):
    """批处理实现(驱逐时向未来线性扫描;无逐点表)。
    step_hook(step, resident, externalized, current) 每步后调用;
    evict_hook(step, current, victim, candidates) 每次驱逐前调用。"""
    n_total = len(trace)
    resident = set()
    externalized = set(range(n_nodes))  # SEM-1
    cost = 0.0
    misses = 0
    evictions = []

    def scan_next(pos, node):
        for j in range(pos + 1, n_total):
            if trace[j] == node:
                return j
        return n_total

    for t, node in enumerate(trace):
        if node not in resident:
            cost += c_rehy            # SEM-2
            misses += 1
            externalized.discard(node)
            resident.add(node)
            while len(resident) > budget:                 # SEM-3
                candidates = frozenset(n for n in resident if n != node)
                victim = max(candidates,
                             key=lambda n: (scan_next(t, n), -n))  # SEM-4
                if evict_hook:
                    evict_hook(t, node, victim, candidates)
                resident.discard(victim)
                externalized.add(victim)
                cost += c_ext
                evictions.append((t, victim))
        if step_hook:
            step_hook(t, frozenset(resident), frozenset(externalized), node)
    return cost, misses, evictions


# ---------- 独立实现 2:live_belady_stream(流式类) ----------
class LiveBeladyStream:
    def __init__(self, trace, n_nodes, budget, c_ext, c_rehy,
                 step_hook=None, evict_hook=None):
        self.trace = trace
        self.n_nodes = n_nodes
        self.budget = budget
        self.c_ext = c_ext
        self.c_rehy = c_rehy
        self.step_hook = step_hook
        self.evict_hook = evict_hook
        n_total = len(trace)
        self.next_use_at = [n_total] * n_total
        last_pos = {}
        for idx in range(n_total - 1, -1, -1):
            node = trace[idx]
            self.next_use_at[idx] = last_pos.get(node, n_total)
            last_pos[node] = idx
        self.resident = set()
        self.externalized = set(range(n_nodes))  # SEM-1
        self.node_next_use = {}
        self.cost = 0.0
        self.misses = 0
        self.evictions = []
        self.violations = 0
        self.pos = 0

    def step(self):
        node = self.trace[self.pos]
        if node not in self.resident:
            self.cost += self.c_rehy                     # SEM-2
            self.misses += 1
            self.externalized.discard(node)
            self.resident.add(node)
            if len(self.resident) > self.budget:         # SEM-3
                candidates = frozenset(n for n in self.resident if n != node)
                victim = min(candidates,
                             key=lambda n: (-self.node_next_use.get(
                                 n, len(self.trace)), n))  # SEM-4
                if self.evict_hook:
                    self.evict_hook(self.pos, node, victim, candidates)
                self.resident.discard(victim)
                self.externalized.add(victim)
                self.cost += self.c_ext
                self.evictions.append((self.pos, victim))
            if len(self.resident) > self.budget:
                self.violations += 1
        if self.step_hook:
            self.step_hook(self.pos, frozenset(self.resident),
                           frozenset(self.externalized), node)
        self.node_next_use[node] = self.next_use_at[self.pos]
        self.pos += 1

    def run_all(self):
        while self.pos < len(self.trace):
            self.step()
        return self.cost, self.misses, self.evictions, self.violations


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


def main():
    rng = random.Random(SEED)
    parent8 = gen_topology(N_NODES, 2)
    print("=== P4 live verifier v3.1(P4-B 复审落地:逐步不变式 + tie-break 随机断言)===")
    print(f"seed={SEED};nodes={N_NODES};budget={BUDGET};len={TRACE_LEN};"
          f"C_ext={C_EXT};C_rehy={C_REHY};SEM-1..5;不变式=每步断言(双实现对称)\n")

    # ---- T3 扩展:三个手算微例(v3 保留,回归锚点)
    print("T3 手算微例(三例;回归锚点):")
    m1 = ([0, 1, 2, 0], 2, 3 * 0.72 + 0.69, 3, [(2, 1)])
    m2 = ([0, 1, 2, 3], 2, 4 * 0.72 + 2 * 0.69, 4, [(2, 0), (3, 1)])
    m3 = ([0, 1, 0, 1], 1, 4 * 0.72 + 3 * 0.69, 4, [(1, 0), (2, 1), (3, 0)])
    for name, (tr, bd, ec, em, ee) in [("M1 基础", m1), ("M2 tie-break", m2),
                                       ("M3 budget=1 thrash", m3)]:
        dp_c = dp_optimal(tr, N_NODES, bd, C_EXT, C_REHY)
        off_c, off_m, off_e = offline_belady_batch(tr, N_NODES, bd, C_EXT, C_REHY)
        eng = LiveBeladyStream(tr, N_NODES, bd, C_EXT, C_REHY)
        liv_c, liv_m, liv_e, viol = eng.run_all()
        ok = (approx(dp_c, ec) and approx(off_c, ec) and approx(liv_c, ec)
              and off_m == em and liv_m == em and off_e == ee and liv_e == ee
              and viol == 0)
        print(f"  {name}: DP={dp_c:.2f} batch={off_c:.2f} stream={liv_c:.2f} "
              f"(期望 {ec:.2f});ev={off_e}/{liv_e}(期望 {ee}) → "
              f"{'PASS' if ok else 'FAIL'}")
        assert ok, f"T3 {name} failed"

    # ---- T1/T2:标准缩减实例(hot8/tree8)
    traces = {
        "hot8": gen_hot_trace(rng, N_NODES, TRACE_LEN),
        "tree8": gen_tree_trace(rng, parent8, N_NODES, TRACE_LEN),
    }
    for wname, trace in traces.items():
        cost_dp = dp_optimal(trace, N_NODES, BUDGET, C_EXT, C_REHY)
        off_c, off_m, off_e = offline_belady_batch(trace, N_NODES, BUDGET, C_EXT, C_REHY)
        eng = LiveBeladyStream(trace, N_NODES, BUDGET, C_EXT, C_REHY)
        liv_c, liv_m, liv_e, viol = eng.run_all()
        t1 = approx(cost_dp, off_c)
        t2 = (approx(liv_c, off_c) and liv_e == off_e and liv_m == off_m)
        print(f"-- {wname} --")
        print(f"   T1 cost_DP({cost_dp:.2f}) == offline_batch({off_c:.2f}) → "
              f"{'PASS' if t1 else 'FAIL'}")
        print(f"   T2 stream({liv_c:.2f}) == batch 且驱逐序列逐对相等"
              f"({len(off_e)} 次驱逐) → {'PASS' if t2 else 'FAIL'}")
        assert t1 and t2, f"T1/T2 failed on {wname}"

    # ---- Property test v3.1:随机小迹;逐步不变式(双实现对称)+
    #      tie-break 独立重推断言
    print("Property test v3.1(随机小迹;逐步 SEM 不变式 × 双实现 + "
          "tie-break 独立重推):")

    def next_use_after(trace, pos, node):
        """独立重推:trace 中 pos 之后 node 的下一次出现(无则 len)。"""
        for j in range(pos + 1, len(trace)):
            if trace[j] == node:
                return j
        return len(trace)

    n_tr = 150
    fails = 0
    hook_steps_total = 0
    hook_evicts_total = 0
    dp_fails = 0
    for pt in range(n_tr):
        r = random.Random(SEED * 100003 + pt)
        n = r.choice([4, 6, 8])
        budget = r.randint(1, min(3, n))
        length = r.randint(0, 40)
        use_tree = (pt % 2 == 0)
        par = gen_topology(n, max(1, n // 4))
        tr = (gen_tree_trace(r, par, n, length) if use_tree
              else gen_hot_trace(r, n, length))

        def make_hooks():
            st = {"steps": 0, "evicts": 0, "errors": []}

            def step_hook(step, resident, externalized, current):
                st["steps"] += 1
                if resident & externalized:
                    st["errors"].append(f"step{step}: resident∩externalized 非空")
                if len(resident) + len(externalized) != n:
                    st["errors"].append(f"step{step}: 并集未覆盖全体节点")
                if len(resident) > budget:
                    st["errors"].append(f"step{step}: 容量超限")
                if current not in resident:
                    st["errors"].append(f"step{step}: working-set 正向违反")

            def evict_hook(step, current, victim, candidates):
                st["evicts"] += 1
                if victim == current:
                    st["errors"].append(f"step{step}: working-set(驱逐 current)")
                if victim not in candidates:
                    st["errors"].append(f"step{step}: victim ∉ candidates")
                # SEM-4 独立重推:victim = 最大 next_use 中最小 id
                best = max(next_use_after(tr, step, n2) for n2 in candidates)
                expected = min(n2 for n2 in candidates
                               if next_use_after(tr, step, n2) == best)
                if victim != expected:
                    st["errors"].append(
                        f"step{step}: tie-break 违反(victim={victim}, 期望={expected})")

            return step_hook, evict_hook, st

        for impl in ["batch", "stream"]:
            sh, eh, st = make_hooks()
            if impl == "batch":
                offline_belady_batch(tr, n, budget, C_EXT, C_REHY,
                                     step_hook=sh, evict_hook=eh)
            else:
                eng = LiveBeladyStream(tr, n, budget, C_EXT, C_REHY,
                                       step_hook=sh, evict_hook=eh)
                eng.run_all()
            if st["errors"]:
                fails += 1
                print(f"  FAIL @pt{pt}/{impl}: {st['errors'][:3]}")
            hook_steps_total += st["steps"]
            hook_evicts_total += st["evicts"]

        # DP 成本交叉
        dp_c = dp_optimal(tr, n, budget, C_EXT, C_REHY)
        off_c = offline_belady_batch(tr, n, budget, C_EXT, C_REHY)[0]
        eng2 = LiveBeladyStream(tr, n, budget, C_EXT, C_REHY)
        liv_c = eng2.run_all()[0]
        if not (approx(off_c, dp_c) and approx(liv_c, dp_c)):
            dp_fails += 1

    print(f"  逐步不变式:{n_tr} 迹 × 2 实现,step_hook 共 {hook_steps_total} 次/"
          f"evict_hook 共 {hook_evicts_total} 次,失败 {fails}")
    print(f"  DP 成本交叉:{n_tr - dp_fails}/{n_tr} 迹一致")
    assert fails == 0 and dp_fails == 0, "property test v3.1 failed"

    print()
    print("声明范围(冻结):所测试缩减模型/参数/随机轨迹内,三实现逐步")
    print("SEM 不变式 + 成本/序列一致性成立(模型级证据);不证明规格本身")
    print("正确;不证明 Swift/MLX 真源一致;P4 proper = true-source Swift")
    print("test(LOCKED)。")


if __name__ == "__main__":
    main()
