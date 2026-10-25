#!/usr/bin/env python3
# Copyright © 2026 SimiGo-Lab. H-P1 Tier-1 L3 正式采数(2026-09-22)
# (设计 v0.1.2 §4/§7 预注册;远端已署名 L1 三类 PASS(seed-42
#  experimental-domain fact)+ L2 PASS + L3 三类 UNLOCK 后执行)
#
# 预注册判据(§4 锁定,不得实现中改写):
#   统一形态:驱逐=argmin key(NORM③),key 收尾 (last_access,id);
#   结构信号 keep-worthiness 首键:P_S1=−pos/P_S2=−A_anc/P_S3=
#   +A_chain(self-excluded);敏感方向=符号取反,同跑同报。
#   L3 PASS = 主方向形态 J < J(C) 于 tree(Tier-1;C=lfu_aging
#   冻结参照 1085.9;确定性域任何裕度=真实改进,幅度如实报告)。
#   仅敏感方向达成 = "PASS(敏感方向)"交审核,不自动等同 PASS。
#   hot 侧无判据仅披露(阴性对照域)。三类分开跑,禁止合并计分;
#   不改变 P3 冻结 cost 定义;不把 L1 ρ 大小当 L3 性能预测量;
#   L3 失败不回头否定 L1/L2。
#   机制哨兵(描述性):确定性重跑逐位一致;dd ≥ |Δrehy|(vs lru);
#   L2 运行时审计(v6 引擎)。

import importlib.util
import os
import sys

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
B_BUDGET, H_MAIN = 12, 8
J_C_TREE = 1085.9                      # C=lfu_aging 冻结参照(P3-A)
MAIN = {"S1": "P_S1", "S2": "P_S2", "S3": "P_S3"}
SENS = {"S1": "P_S1s", "S2": "P_S2s", "S3": "P_S3s"}


def main():
    rng = random_rng = __import__("random").Random(SEED)
    parent8 = sim3.gen_topology(N_NODES, 8)
    traces = {
        "hot": sim3.gen_hot_trace(rng, N_NODES, TRACE_LEN),
        "tree": sim3.gen_tree_trace(rng, parent8, N_NODES, TRACE_LEN),
    }
    print("=== H-P1 Tier-1 L3 正式采数(设计 v0.1.2 §4 预注册)===")
    print(f"seed={SEED};nodes={N_NODES};trace={TRACE_LEN};B={B_BUDGET};"
          f"H={H_MAIN};J(C) tree={J_C_TREE}(lfu_aging 冻结)")
    print("判据:主方向 J<J(C) tree;敏感方向同跑同报;hot 仅披露\n")

    gate_ok = True
    # C 参照重跑(回归断言:逐位等于冻结值)
    mc = v4.run_policy("lfu_aging", traces["tree"], B_BUDGET, C_EXT, C_REHY,
                       H=H_MAIN)
    c_ok = (round(mc["J"], 1) == J_C_TREE and mc["rehy"] == 776
            and mc["ext"] == 764)
    gate_ok &= c_ok
    print(f"-- C 参照重跑: tree J={mc['J']:.1f} ({mc['rehy']}/{mc['ext']}) "
          f"-> {'OK' if c_ok else 'FAIL'}(vs 冻结 1085.9/776/764)--\n")

    results = {}
    for wname, trace in traces.items():
        print(f"-- {wname}(-hot 侧仅披露-)" if wname == "hot"
              else f"-- {wname}(Tier-1 主判据域)--")
        mlru = v4.run_policy("lru", trace, B_BUDGET, C_EXT, C_REHY,
                             H=H_MAIN, record_seq=True)
        for cls in ["S1", "S2", "S3"]:
            for tag, pol in [("主", MAIN[cls]), ("敏感", SENS[cls])]:
                m1 = v6.run_policy_hp1(pol, trace, B_BUDGET, C_EXT, C_REHY,
                                       record_seq=True, audit=True)
                m2 = v6.run_policy_hp1(pol, trace, B_BUDGET, C_EXT, C_REHY,
                                       record_seq=True, audit=True)
                det = (v6.core(m1) == v6.core(m2)
                       and m1["seq"] == m2["seq"])
                dd = v4.differing_decisions(m1["seq"], mlru["seq"], TRACE_LEN)
                cons = dd >= abs(m1["rehy"] - mlru["rehy"])
                sentinels = det and m1["audit_ok"] and cons
                results[(wname, cls, tag)] = m1
                print(f"  {cls}/{tag}({pol}): J={m1['J']:.1f} "
                      f"({m1['rehy']}/{m1['ext']}) det={det} "
                      f"L2={m1['audit_ok']} dd={dd}≥|Δrehy|="
                      f"{abs(m1['rehy'] - mlru['rehy'])} -> "
                      f"{'OK' if sentinels else 'FAIL'}")
                gate_ok &= sentinels
        print()

    if not gate_ok:
        print("*** L3 采数哨兵 FAIL:停机交审核 ***")
        sys.exit(1)

    print("-- L3 逐类判定(§4/§7;正式署名待审核方)--")
    for cls in ["S1", "S2", "S3"]:
        jm = results[("tree", cls, "主")]["J"]
        js = results[("tree", cls, "敏感")]["J"]
        main_pass = jm < J_C_TREE
        sens_pass = js < J_C_TREE
        if main_pass:
            verdict = (f"L3 PASS(主方向 J={jm:.1f} < {J_C_TREE};"
                       f"裕度 {J_C_TREE - jm:.1f})")
        elif sens_pass:
            verdict = (f"PASS(敏感方向:敏感 J={js:.1f} < {J_C_TREE},"
                       f"主方向 J={jm:.1f} 未达)→ 交审核裁定")
        else:
            verdict = (f"L3 FAIL(主 J={jm:.1f},敏感 J={js:.1f},"
                       f"均 ≥ {J_C_TREE})→ 出口 C:未验证机制候选/"
                       f"诊断线索,不进已验证清单")
        print(f"  {cls}: {verdict}")
        print(f"      hot 披露: 主 J={results[('hot', cls, '主')]['J']:.1f} "
              f"敏感 J={results[('hot', cls, '敏感')]['J']:.1f}(无判据)")

    print("\n*** L3 采数完成(哨兵全过);逐类署名与 H-P1 出口(A–D 逐类"
          "汇总)待审核方最终裁定 ***")


if __name__ == "__main__":
    main()
