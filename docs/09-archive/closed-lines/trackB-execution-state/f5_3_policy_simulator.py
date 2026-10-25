#!/usr/bin/env python3
# F5-3 Step 1 — Adaptive Representation Transition Policy: Simulator
# SimiGo-Lab 2.0 Track B(2026-09-21;承外部审核三步法的第一步)
#
# 目的:在纯数据层验证策略逻辑(不引入 runtime / 预测误差 / 模型行为):
#   E[T_remaining] × τ̂_tax > Ĉ_reattach ⇒ reattach,否则保持 segmented COW。
# 四策略对照(审核要求,含 Oracle hindsight):
#   always-COW / always-reattach / adaptive / oracle(知道完整 continuation)
# 成本模型参数全部来自实测(F5-2 矩阵 + F4-E + F5-1),显式标注;
# 税的跨 run 波动(±0.1–0.5)直接建模为 τ 的先验分布与在线估计噪声。
#
# 运行:python3 f5_3_policy_simulator.py [--trials 2000] [--seed 42]

import argparse
import random
import statistics

# ---- 实测参数(来源标注)----

# C_fresh(D) = W + α·D:两点标定
#   (4,224 → 50.8ms, F3-E7 控制组) 与 (65,566 → 76.1ms, F5-1 P 侧)
ALPHA = (76.1 - 50.8) / (65_566 - 4_224)  # ms / token-of-depth
W = 50.8 - ALPHA * 4_224  # ms(每 token 权重/固定项,M5 Air,35B oQ4e)

def fresh_ms(depth):  # 稳态 fresh 每 token 成本
    return W + ALPHA * depth

# τ_pre 实测(F5-2 本轮 与 F4-E 轮,两值构成跨 run 波动范围;
# None = 该轮未测)
TAX_OBSERVED = {
    # (depth, S): (F5-2 轮, F4-E 轮)
    (18_432, 2): (1.068, 1.158),
    (18_432, 4): (1.219, 1.089),
    (16_384, 8): (0.992, 1.123),  # F4-E 为 16,384@S8 同格
    (32_768, 2): (1.250, None),
    (32_768, 4): (1.045, 1.137),
    (32_768, 8): (1.130, None),
    (65_536, 2): (1.785, None),
    (65_536, 4): (1.429, 1.256),  # F4-E;F5-1 同格 1.219
    (65_536, 8): (1.600, None),
}

# merge 实测 ms(F5-2);首 token 额外惩罚 ≈ 一次 step 增长拼接,
# 实测 F5-1:首 token 158.6 − 稳态 76.1 ≈ 82ms ≈ merge 成本同阶
MERGE_MS = {
    (18_432, 2): 16, (18_432, 4): 44, (16_384, 8): 24,
    (32_768, 2): 35, (32_768, 4): 39, (32_768, 8): 43,
    (65_536, 2): 75, (65_536, 4): 65, (65_536, 8): 105,
}

CONFIGS = [(65_536, 2), (65_536, 4), (65_536, 8),
           (32_768, 2), (32_768, 4), (32_768, 8),
           (18_432, 2), (18_432, 4), (16_384, 8)]

# 分支长度分布(审核:混合,勿只测长分支)
BUCKETS = [(2, 8), (16, 32), (64, 128), (256, 512)]
BUCKET_NAMES = ["short(2-8)", "mid(16-32)", "long(64-128)", "xlong(256-512)"]

# adaptive 观察窗:前 k 步 COW 上在线估 τ̂,再决策
OBSERVE_K = 4
# 在线估计噪声:k 步均值的标准差相对量(保守取 12%/√k)
EST_NOISE = 0.12


def sample_tau(rng, key):
    """真实 τ:两轮观测区间内均匀采样(跨 run 波动建模)"""
    lo, hi = TAX_OBSERVED[key]
    others = [v for v in (lo, hi) if v is not None]
    if len(others) == 1:
        lo = hi = others[0]
    return rng.uniform(lo, hi)


def simulate(key, N, budget, rng):
    depth, S = key
    c_fresh = fresh_ms(depth)
    merge = MERGE_MS[key]
    tau_true = sample_tau(rng, key)
    c_cow = c_fresh * tau_true

    # always-COW
    cost_cow = N * c_cow
    # always-reattach(立即迁移,含首 token 惩罚)
    cost_always = merge + merge + N * c_fresh  # merge + first-token extra(≈merge)
    # oracle(hindsight:知 N)
    cost_oracle = min(cost_cow, 2 * merge + N * c_fresh)
    reatt_oracle = cost_oracle < cost_cow

    # adaptive:前 k 步观察(付 COW 价)估 τ̂;此后**每步滚动重估**,
    # E[T_rem] = 已生成长度 n(渐进揭示:分支活得越久,预期剩余越长;
    # 上限 budget)。修正 v1 的结构性缺陷:固定 budget 高估短分支。
    obs = [rng.gauss(c_cow, EST_NOISE * c_cow) for _ in range(min(OBSERVE_K, N))]
    tau_hat = statistics.mean(obs) / c_fresh
    reatt_ad = False
    switch_at = None
    for n in range(OBSERVE_K, N):
        remaining_est = min(max(n, 1), budget)
        if remaining_est * (tau_hat - 1.0) * c_fresh > 2 * merge:
            reatt_ad = True
            switch_at = n
            break
    if reatt_ad:
        # 观察窗(k 步)与滚动决策段合并计价:切换点前的全部步付 COW 价
        cost_ad = switch_at * c_cow + 2 * merge + (N - switch_at) * c_fresh
    else:
        cost_ad = N * c_cow

    return cost_cow, cost_always, cost_ad, cost_oracle, reatt_ad, reatt_oracle


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--trials", type=int, default=2000)
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()
    rng = random.Random(args.seed)

    print(f"F5-3 Step1 simulator: trials={args.trials}/config, "
          f"observe_k={OBSERVE_K}, est_noise={EST_NOISE:.0%}")
    print(f"C_fresh(D) = {W:.1f}ms + {ALPHA*1e3:.3f}us/token×D(两点标定:F3-E7/F5-1)")
    print()

    budget_variants = [64, 256, 512]

    grand = {p: 0.0 for p in ("cow", "always", "ad", "oracle")}
    grand_n = 0
    for key in CONFIGS:
        depth, S = key
        c_fresh = fresh_ms(depth)
        print(f"--- D{depth//1024}K@S{S}(fresh {c_fresh:.1f}ms/tok,"
              f"merge {MERGE_MS[key]}ms,τ∈[{min(v for v in TAX_OBSERVED[key] if v):.3f},"
              f"{max(v for v in TAX_OBSERVED[key] if v):.3f}]) ---")
        for bi, (blo, bhi) in enumerate(BUCKETS):
            for budget in budget_variants:
                tot = {"cow": 0.0, "always": 0.0, "ad": 0.0, "oracle": 0.0}
                reatt_ad = 0
                reatt_or = 0
                wins_both = 0  # ad 同时 ≤ 两极端
                for _ in range(args.trials):
                    N = rng.randint(blo, bhi)
                    cc, ca, cad, co, ra, ro = simulate(key, N, budget, rng)
                    tot["cow"] += cc; tot["always"] += ca
                    tot["ad"] += cad; tot["oracle"] += co
                    reatt_ad += ra; reatt_or += ro
                    if cad <= min(cc, ca):
                        wins_both += 1
                m = {k: v / args.trials for k, v in tot.items()}
                # 只详印 budget=256(敏感性行汇总)
                if budget == 256:
                    print(f"  {BUCKET_NAMES[bi]:>15} B={budget}: "
                          f"COW {m['cow']:7.0f}ms | always {m['always']:7.0f} | "
                          f"adaptive {m['ad']:7.0f} | oracle {m['oracle']:7.0f} | "
                          f"ad regret {m['ad']-m['oracle']:+6.0f} "
                          f"({(m['ad']-m['oracle'])/m['oracle']:+.1%}) | "
                          f"reatt ad/oracle {reatt_ad/args.trials:.0%}/"
                          f"{reatt_or/args.trials:.0%} | ad≤两极端 "
                          f"{wins_both/args.trials:.0%}")
                for k in grand:
                    grand[k] += m[k]
                grand_n += 1

    g = {k: v / grand_n for k, v in grand.items()}
    print()
    print(f"=== 总平均(全配置×全 bucket×全 budget) ===")
    print(f"always-COW {g['cow']:.0f}ms | always-reattach {g['always']:.0f} | "
          f"adaptive {g['ad']:.0f} | oracle {g['oracle']:.0f}")
    print(f"adaptive vs COW: {(g['ad']/g['cow']-1):+.1%} | "
          f"vs always: {(g['ad']/g['always']-1):+.1%} | "
          f"regret vs oracle: {(g['ad']/g['oracle']-1):+.1%}")

    # budget 敏感性(汇总)
    print()
    print("=== budget 敏感性(全配置×bucket 平均,ad 相对 oracle regret)===")
    for budget in budget_variants:
        tots = {"ad": 0.0, "oracle": 0.0, "cow": 0.0, "always": 0.0}
        cnt = 0
        rng2 = random.Random(args.seed + 1)
        for key in CONFIGS:
            for blo, bhi in BUCKETS:
                for _ in range(args.trials // 4):
                    N = rng2.randint(blo, bhi)
                    cc, ca, cad, co, _, _ = simulate(key, N, budget, rng2)
                    tots["ad"] += cad; tots["oracle"] += co
                    tots["cow"] += cc; tots["always"] += ca
                    cnt += 1
        print(f"  B={budget:3d}: ad/oracle = {tots['ad']/tots['oracle']:.3f} "
              f"(ad/COW {tots['ad']/tots['cow']:.3f}, ad/always "
              f"{tots['ad']/tots['always']:.3f})")


if __name__ == "__main__":
    main()
