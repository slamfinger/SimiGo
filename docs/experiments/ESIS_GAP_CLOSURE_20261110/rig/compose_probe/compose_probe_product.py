#!/usr/bin/env python3
"""组成性探针 E1/E2 —— 产品路径重跑（scan/resolve/settleTurn，不加载模型）。

与 compose_probe.py（预注册装置）的关系：
  * 复用同一台仪器：Probe（表行数差记账）、facts()（图上有没有边）、
    classify()（预注册分类词表：epsilon/beta/beta' × fired/BLIND/OVERBROAD ×
    delta/gamma/gamma'/alpha/void）。本文件不改分类器语义。
  * 换被试路径：run-b（2026-11-08）的 stage 路径不写依赖边（facts.edges=0 →
    POS=BLIND → E2=void），撤回机制在那里不可测。本驱动把每个权威的诞生
    换成产品生成路径的真实组成：
        settleWorkRootContents（根索引）
        → SimiGoInformationLoop.resolve（检索结算 + 文件绑定）
        → SimiGoInformationLoop.settleTurn（模型结算 + advancement 依赖边）
  * 产品路径的"文件变了"入口是 scan（P1 实测），所以撤回事件 = 改文件后
    对该空间、该根执行 scan；POS/E2 各步均在改文件与读数之间插显式 scan 步。
    未 scan 的旁观空间读数（e2.s2_after）单独保留——它回答"撤回跨空间是
    靠边传播还是靠重算"的前半问。

E1：同一空间、同一 demand 两个权威——显式同一 --request 两次 turn（不同
    stateID）。demand 身份不含 stateID，故两权威确属同一 demand。
E2：两个空间（独立 sqlite）指向同一共享根；改共享文件后逐空间读数。
E2b：共享文件被移走（不可读，不是变更）后的逐空间读数。

用法：compose_probe_product.py --cli PATH [--work DIR]
"""
import argparse, json, os, shutil, sys, tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import compose_probe as device  # 预注册仪器：Probe / facts / classify / log / LEDGER


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cli", required=True)
    ap.add_argument("--work")
    a = ap.parse_args()

    work = a.work or tempfile.mkdtemp(prefix="compose-product-")
    R  = os.path.join(work, "shared_root");  os.makedirs(R, exist_ok=True)
    R2 = os.path.join(work, "control_root"); os.makedirs(R2, exist_ok=True)
    open(os.path.join(R,  "doc.txt"),   "w").write("alpha V1")
    open(os.path.join(R2, "other.txt"), "w").write("gamma C1")

    p = device.Probe(a.cli, work)
    for tag in ("S0", "S1", "S2"):
        p.c("init", "--db", p.db(tag, tag.lower()))

    Q  = "alpha"
    QC = "gamma"

    def turn(tag, root_id, root, request, state, value_, query):
        return lambda: p.c("turn", "--db", p.dbs[tag], "--root-id", root_id,
                           "--root-url", root, "--request", request,
                           "--state-id", state, "--value", value_, "--query", query)

    def scan(tag, root_id, root):
        return lambda: p.c("scan", "--db", p.dbs[tag], "--root-id", root_id,
                           "--root-url", root)

    def get(tag, state):
        return lambda: p.c("get-value", "--db", p.dbs[tag], "--state", state)

    # ── E1：同一空间（S0）、同一 demand（显式同一 request）两个权威 ──
    p.step("e1.stage_A", turn("S0", "shared", R, "req-e1", "a1", "ANSWER-A", Q))
    p.step("e1.state_a", get("S0", "a1"))
    p.step("e1.stage_B", turn("S0", "shared", R, "req-e1", "a2", "ANSWER-B", Q))
    p.step("e1.state_b", get("S0", "a2"))

    # ── E2 装置：S1（被观测空间：共享根 + 控制根）、S2（旁观空间：同一共享根）──
    p.step("setup.s1",  turn("S1", "shared",  R,  "req-s1", "a1", "ANSWER-A", Q))
    p.step("setup.s1c", turn("S1", "control", R2, "req-c",  "a3", "CONTROL",   QC))
    p.step("setup.s2",  turn("S2", "shared",  R,  "req-s2", "a2", "ANSWER-B", Q))
    p.step("pre.s1", get("S1", "a1"))
    p.step("pre.s2", get("S2", "a2"))
    p.steps.append({"step": "facts", "result": device.facts(p.dbs["S1"]), "delta": {}})
    device.log("step", **p.steps[-1])

    # ── 阳性对照：改控制文件 → scan（撤回事件）→ a3 必须拒、a1 必须仍服务 ──
    open(os.path.join(R2, "other.txt"), "w").write("gamma C2-CHANGED")
    p.step("pos.scan_control", scan("S1", "control", R2))
    p.step("pos.after_control_change", get("S1", "a3"))
    p.step("pos.scope_kept", get("S1", "a1"))

    # ── E2：改共享文件 → S1 scan 后读（撤回被观测）；S2 未 scan 直接读（旁观者）──
    open(os.path.join(R, "doc.txt"), "w").write("alpha V2-CHANGED")
    p.step("e2.scan_s1", scan("S1", "shared", R))
    p.step("e2.s1_after", get("S1", "a1"))
    p.step("e2.s2_after", get("S2", "a2"))          # S2 尚未 scan：靠边还是靠重算的前半问
    p.step("e2.scan_s2", scan("S2", "shared", R))
    p.step("e2.s2_rescan", get("S2", "a2"))          # S2 自己重算后的读数

    # ── E2b：共享文件被移走（不可读）──
    os.rename(os.path.join(R, "doc.txt"), os.path.join(R, "doc.txt.away"))
    p.step("e2b.scan_s1", scan("S1", "shared", R))
    p.step("e2b.s1_unreadable", get("S1", "a1"))
    p.step("e2b.scan_s2", scan("S2", "shared", R))
    p.step("e2b.s2_unreadable", get("S2", "a2"))

    cls = device.classify(p.steps)
    print("\n=== CLASS ===\n" + json.dumps(cls, ensure_ascii=False, indent=1))

    out = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "ledger-run-product-20261110.jsonl")
    with open(out, "w") as fh:
        for r in device.LEDGER:
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")
    print("ledger:", out)
    print("work:", work)
    return 0


if __name__ == "__main__":
    sys.exit(main())
