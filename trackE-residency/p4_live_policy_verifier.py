#!/usr/bin/env python3
"""P4 live verifier v3——P4-A→P4-B 过渡版(审计:T2 独立性修复)。

审计背景:v2(5916acb)七项确认 + 一个实质缺陷——`live` 参数无实效,
T2 = 同一函数调用两次,不构成 offline/live 独立实现等价验证。
v3 修复原则:**实现独立(两套互不共享函数的 Belady)+ 规格共享
(SEM-1..5 即策略定义)+ 三实现交叉(DP/offline/live)+ property
test(随机小迹断言)+ 手算微例扩到三个(含 tie-break/budget=1/thrash)。

形式化语义(SEM,审计问题④的正式规则):
  SEM-1 初始状态:resident = ∅;**所有节点初始 ∈ externalized**
        (全预建 = 全外化起点;首触访问即 REHYDRATE,收费——
        消除 v2"prebuilt 但 resident=∅"的歧义)
  SEM-2 访问非驻留节点 → REHYDRATE 事件,付 C_rehy
  SEM-3 |resident| > budget 时必须 EXTERNALIZE(付 C_ext/次)至合规;
        当前访问节点本步不可驱逐(working-set)
  SEM-4 victim 并列 → 最低 node id
  SEM-5 成本口径:三层同一 C_ext/C_rehy 常量
  externalized = **模型状态的一部分**(SEM-1 起):不变式
        resident ∪ externalized = 全体节点 且 互斥——property test 逐迹断言。

声明范围(v2 收窄延续):模型级证据;P4 proper = true-source
Swift test(LOCKED)。"""

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
# 特点:不维护逐点 next-use 表;每次驱逐时**向未来线性扫描**求
# next-use;并列取最低 id。与实现 2 无共享函数。
def offline_belady_batch(trace, n_nodes, budget, c_ext, c_rehy):
    n_total = len(trace)
    resident = set()
    externalized = set(range(n_nodes))  # SEM-1:全体初始外化
    cost = 0.0
    misses = 0
    evictions = []

    def scan_next(pos, node):
        for j in range(pos + 1, n_total):
            if trace[j] == node:
                return j
        return n_total

    for t, node in enumerate(trace):
        if node in resident:
            continue
        # SEM-2:REHYDRATE
        cost += c_rehy
        misses += 1
        externalized.discard(node)
        resident.add(node)
        # SEM-3:容量强制(working-set:node 不可驱逐)
        while len(resident) > budget:
            # max(scan_next, -id):并列 scan_next 时 id 最小者优先
            victim = max((n for n in resident if n != node),
                         key=lambda n: (scan_next(t, n), -n))
            resident.discard(victim)
            externalized.add(victim)
            cost += c_ext
            evictions.append((t, victim))
    return cost, misses, evictions


# ---------- 独立实现 2:live_belady_stream(流式类) ----------
# 特点:类封装 step() 逐推进;使用**预计算 per-position 表**(policy
# 输入);victim = max next-use,tie→最低 id。与实现 1 无共享函数。
class LiveBeladyStream:
    def __init__(self, trace, n_nodes, budget, c_ext, c_rehy):
        self.trace = trace
        self.n_nodes = n_nodes
        self.budget = budget
        self.c_ext = c_ext
        self.c_rehy = c_rehy
        n_total = len(trace)
        self.next_use_at = [n_total] * n_total
        last_pos = {}
        for idx in range(n_total - 1, -1, -1):
            node = trace[idx]
            self.next_use_at[idx] = last_pos.get(node, n_total)
            last_pos[node] = idx
        self.resident = set()
        self.externalized = set(range(self.n_nodes))  # SEM-1
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
                candidates = [n for n in self.resident if n != node]
                victim = min(candidates,
                             key=lambda n: (-self.node_next_use.get(
                                 n, len(self.trace)), n))  # SEM-4
                self.resident.discard(victim)
                self.externalized.add(victim)
                self.cost += self.c_ext
                self.evictions.append((self.pos, victim))
            if len(self.resident) > self.budget:
                self.violations += 1                     # 可行性(第一层)
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
    print("=== P4 live verifier v3(P4-A→P4-B 过渡;T2 独立性修复)===")
    print(f"seed={SEED};nodes={N_NODES};budget={BUDGET};len={TRACE_LEN};"
          f"C_ext={C_EXT};C_rehy={C_REHY};SEM-1..5 形式化;NORMS 已实现")
    print("实现独立性:offline_belady_batch(扫描式)与 "
          "LiveBeladyStream(表格流式)无共享函数;规格共享 = SEM-1..5\n")

    # ---- T3 扩展:三个手算微例(不可偷换的常量断言)
    print("T3 手算微例(三例):")
    # 微例 1(基础;step3 命中):
    m1 = ([0, 1, 2, 0], 2, 3 * 0.72 + 0.69, 3, [(2, 1)])
    # 微例 2(tie-break:v2 次抓作者错误——step2 时 0/1 的 next_use 同为
    #   ∞,SEM-4 应逐最低 id=0(非 1);step3 同理逐 1。正确序列:
    #   [(2,0),(3,1)]):
    m2 = ([0, 1, 2, 3], 2, 4 * 0.72 + 2 * 0.69, 4, [(2, 0), (3, 1)])
    # 微例 3(budget=1 thrash;v3 三抓作者错误——曾写 victim=[1,0,1],
    #   违反 SEM-3:step1 时 current=1 不可驱逐,唯一候选=0。正确:
    #   [0,1,0,1]/budget1 → 4 miss + 3 evict = 4×0.72+3×0.69 = 4.95):
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

    # ---- Property test:随机小迹三实现交叉(DP/batch/stream)
    print("Property test(随机小迹;三实现交叉 + SEM 不变式):")
    n_tr = 150
    fails = 0
    for pt in range(n_tr):
        r = random.Random(SEED * 100003 + pt)
        n = r.choice([4, 6, 8])
        budget = r.randint(1, min(3, n))
        length = r.randint(0, 40)
        use_tree = (pt % 2 == 0)
        par = gen_topology(n, max(1, n // 4))
        tr = (gen_tree_trace(r, par, n, length) if use_tree
              else gen_hot_trace(r, n, length))
        dp_c = dp_optimal(tr, n, budget, C_EXT, C_REHY)
        off_c, off_m, off_e = offline_belady_batch(tr, n, budget, C_EXT, C_REHY)
        eng = LiveBeladyStream(tr, n, budget, C_EXT, C_REHY)
        liv_c, liv_m, liv_e, viol = eng.run_all()
        # SEM 不变式:resident ∪ externalized = 全体 且互斥
        union_ok = (eng.resident & eng.externalized == set()
                    and len(eng.resident) + len(eng.externalized) == n)
        ok = (approx(off_c, dp_c) and approx(liv_c, dp_c)
              and off_e == liv_e and off_m == liv_m and viol == 0 and union_ok)
        if not ok:
            fails += 1
            print(f"  FAIL @pt{pt}(n={n},budget={budget},len={length}):"
                  f"dp={dp_c:.2f} off={off_c:.2f} live={liv_c:.2f} union={union_ok}")
    print(f"  {n_tr - fails}/{n_tr} 随机小迹:DP == batch == stream 且 SEM 不变式成立"
          + ("" if fails == 0 else f"({fails} FAIL)"))
    assert fails == 0, "property test failed"

    print()
    print("声明范围(v2 延续):模型级证据;P4 proper = true-source Swift")
    print("test(LOCKED)。v3 证明:两套独立实现在全部随机小迹与标准实例")
    print("上成本与驱逐序列一致,且与 DP 最优成本一致(T1 交叉一致性)。")


if __name__ == "__main__":
    main()
