#!/usr/bin/env python3
"""ES/IS 组成性探针 P0（CLI + sqlite，不加载模型）。

问的问题：
  E1  一个空间内，同一 demand 有两个权威，系统给的是一个判定还是两个判定？
  E2  一个空间的撤回能不能到达另一个空间？跨空间靠边传播，还是靠重算？

记法：不解释语义，只记「哪本账多了一行」——每一步前后对每张表取行数差。
      语义归报告，读数归账本。

用法：
  compose_probe.py --cli PATH [--work DIR]   # 正式跑
  compose_probe.py --self-check              # stub CLI 试跑，验证读数与分类会红也会绿
"""
import argparse, json, os, shutil, sqlite3, subprocess, sys, tempfile

LEDGER = []

def log(ev, **f):
    rec = {"event": ev, **f}; LEDGER.append(rec)
    print(json.dumps(rec, ensure_ascii=False), flush=True)

def tables(db):
    if not os.path.exists(db): return {}
    con = sqlite3.connect("file:%s?mode=ro" % db, uri=True)
    try:
        names = [r[0] for r in con.execute(
            "select name from sqlite_master where type='table' and name not like 'sqlite_%'")]
        return {n: con.execute('select count(*) from "%s"' % n).fetchone()[0] for n in names}
    finally:
        con.close()

def snap(dbs): return {k: tables(v) for k, v in dbs.items()}

def delta(b, a):
    return {k: {t: a[k][t] - b.get(k, {}).get(t, 0) for t in a[k]
                if a[k][t] - b.get(k, {}).get(t, 0)} for k in a}

class Probe:
    def __init__(self, cli, work): self.cli, self.work, self.dbs, self.steps = cli, work, {}, []
    def db(self, tag, name):
        self.dbs[tag] = os.path.join(self.work, name + ".sqlite"); return self.dbs[tag]
    def c(self, *a):
        p = subprocess.run([self.cli, *a], capture_output=True, text=True)
        return {"rc": p.returncode,
                "out": (p.stdout or "").strip(),
                "err": ((p.stderr or "").strip().splitlines() or [""])[-1]}
    def step(self, name, fn):
        b = snap(self.dbs); res = fn(); a = snap(self.dbs)
        s = {"step": name, "result": res, "delta": delta(b, a)}
        self.steps.append(s); log("step", **s); return res

def facts(db):
    """撤回机制能不能被这台仪器测到，先看图上有没有边。"""
    if not os.path.exists(db): return {}
    con = sqlite3.connect("file:%s?mode=ro" % db, uri=True)
    def n(sql):
        try: return con.execute(sql).fetchone()[0]
        except Exception: return None
    out = {"edges": n("select count(*) from dependency_edges"),
           "bindings": n("select count(*) from settlement_bindings"),
           "invalid": n("select count(*) from settlements where validity<>'valid'")}
    try:
        out["binding_names"] = sorted({r[0] for r in con.execute("select name from settlement_bindings")})
    except Exception:
        out["binding_names"] = None
    con.close(); return out

def value(res):
    """成功 → (value, None)；失败 → (None, 末行 stderr)。"""
    if res.get("rc") != 0: return None, res.get("err") or "rc!=0"
    try: return json.loads(res["out"]).get("value"), None
    except Exception: return None, "unparsed:" + res["out"][:60]

def classify(steps):
    by = {s["step"]: s for s in steps}
    v = lambda n: value(by[n]["result"]) if n in by else (None, "missing")
    out = {}

    if "e1.state_b" in by:
        a, b = v("e1.state_a"), v("e1.state_b")
        if a[0] is not None and b[0] is not None and a[0] != b[0]:
            out["E1"] = "epsilon: 两判定并存，选择权在调用方（无冲突表示）"
        elif a[0] is not None and b[0] is None:
            out["E1"] = "beta: 首写独占，第二权威被拒（原因=已结算）"
        elif a[0] is None and b[0] is None:
            out["E1"] = "beta': 两权威俱不可读（被更早的闸拦住）"
        else:
            out["E1"] = "unknown: 形状超出预注册四类"

    f = by.get("facts", {}).get("result") or {}
    out["EDGES"] = f.get("edges")
    pos_a, pos_k = v("pos.after_control_change"), v("pos.scope_kept")
    if f.get("edges") == 0:
        out["POS"] = "EDGES-ABSENT: 该路径未写任何依赖边（bindings 只有 %s），撤回机制在这里不可测" % (f.get("binding_names"),)
    elif pos_a[0] is not None:
        out["POS"] = "BLIND: 控制文件变更后仍返回值——探针看不见撤回，E2 作废"
    elif pos_k[0] is None:
        out["POS"] = "OVERBROAD: 控制臂拒绝，但未变更的依赖也被拒——撤回不分区，E2 读数不可解释"
    else:
        out["POS"] = "fired: 控制臂拒绝且未变更臂仍服务（撤回真被观测到且分区）"

    s1, s2 = v("e2.s1_after"), v("e2.s2_after")
    if not out["POS"].startswith("fired"):
        out["E2"] = "void: 阳性对照未以预期形态响起"
    elif s1[0] is None and s2[0] is None:
        out["E2"] = "delta: 两空间俱拒——撤回靠重算抵达，不靠边"
    elif s1[0] is None and s2[0] is not None:
        out["E2"] = "gamma: 不对称——被观测者拒，旁观者仍服务旧值"
    elif s1[0] is not None and s2[0] is None:
        out["E2"] = "gamma': 不对称（反向）"
    elif s1[0] is not None and s2[0] is not None:
        out["E2"] = "alpha: 两空间俱放行——撤回未越界"
    else:
        out["E2"] = "unknown"

    touched = {"S1": set(), "S2": set()}
    for st, tag in (("e2.s1_after", "S1"), ("e2.s2_after", "S2")):
        for books in by.get(st, {}).get("delta", {}).get(tag, {}):
            touched[tag].add(books)
    both = sorted(touched["S1"] & touched["S2"])
    out["SHARED_BOOKS"] = both or "none"
    return out

STUB = r'''#!/bin/sh
db=""; mode=""; state=""
while [ $# -gt 0 ]; do case "$1" in
  --db) db="$2"; shift 2;; --state) state="$2"; shift 2;;
  init|stage|get-value|declare) mode="$1"; shift;; *) shift;; esac; done
case "$mode" in
  init) echo INIT;;
  stage) echo "STAGED id-$state";;
  get-value)
    if printf '%s' "${STUB_REFUSE:-}" | tr ',' '\n' | grep -qx "$state"; then
      echo "typed refusal: DEPENDENCY_CHANGED" >&2; exit 3; fi
    echo "{\"value\": \"V-$state\"}";;
esac
'''

def self_check():
    """四组 fixture：分类必须给出预期类，且盲化必须被 POS 抓住。"""
    root = tempfile.mkdtemp(prefix="compose-selftest-")
    stub = os.path.join(root, "stub.sh")
    open(stub, "w").write(STUB); os.chmod(stub, 0o755)
    tpl = os.path.join(root, "tpl.sqlite")
    con = sqlite3.connect(tpl); con.execute("create table settlements(id text)"); con.commit(); con.close()

    # (fixture 名, {步骤: 是否应被拒})
    fixtures = {
        "epsilon+delta": {"e1.state_a": 0, "e1.state_b": 0, "pos.after_control_change": 1,
                          "pos.scope_kept": 0, "e2.s1_after": 1, "e2.s2_after": 1},
        "beta+gamma":    {"e1.state_a": 0, "e1.state_b": 1, "pos.after_control_change": 1,
                          "pos.scope_kept": 0, "e2.s1_after": 1, "e2.s2_after": 0},
        "epsilon+alpha": {"e1.state_a": 0, "e1.state_b": 0, "pos.after_control_change": 1,
                          "pos.scope_kept": 0, "e2.s1_after": 0, "e2.s2_after": 0},
        "blind":         {"e1.state_a": 0, "e1.state_b": 0, "pos.after_control_change": 0,
                          "pos.scope_kept": 0, "e2.s1_after": 0, "e2.s2_after": 0},
    }
    steps = ["e1.state_a", "e1.state_b", "pos.after_control_change", "pos.scope_kept",
             "e2.s1_after", "e2.s2_after"]
    state_of = {"e1.state_a": "a1", "e1.state_b": "a2", "pos.after_control_change": "a3",
                "pos.scope_kept": "a1", "e2.s1_after": "a1", "e2.s2_after": "a2"}
    expect = {"epsilon+delta": ("epsilon", "delta"), "beta+gamma": ("beta", "gamma"),
              "epsilon+alpha": ("epsilon", "alpha"), "blind": (None, "void")}
    bad = []
    for name, refusals in fixtures.items():
        p = Probe(stub, tempfile.mkdtemp(dir=root))
        for tag in ("S0", "S1", "S2"):
            dst = p.db(tag, tag.lower()); shutil.copy(tpl, dst)
        for st in steps:
            os.environ["STUB_REFUSE"] = "a3" if refusals[st] and state_of[st] == "a3" else (
                state_of[st] if refusals[st] else "")
            p.step(st, lambda s=state_of[st]: p.c("get-value", "--db", p.dbs["S1"], "--state", s))
        cls = classify(p.steps)
        e1, e2 = expect[name]
        ok = cls["E2"].startswith(e2) and (e1 is None or cls["E1"].startswith(e1))
        blind_ok = cls["POS"].startswith("BLIND") == (name == "blind")
        ok = ok and blind_ok
        print(("PASS " if ok else "FAIL ") + name + " -> " + json.dumps(cls, ensure_ascii=False))
        if not ok: bad.append(name)
    return bad

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cli"); ap.add_argument("--work"); ap.add_argument("--self-check", action="store_true")
    a = ap.parse_args()
    if a.self_check:
        bad = self_check()
        print("SELFCHECK " + ("PASS" if not bad else "FAIL " + ",".join(bad)))
        return 0 if not bad else 1
    if not a.cli: print("need --cli or --self-check"); return 2

    work = a.work or tempfile.mkdtemp(prefix="compose-")
    R  = os.path.join(work, "shared_root");  os.makedirs(R, exist_ok=True)
    R2 = os.path.join(work, "control_root"); os.makedirs(R2, exist_ok=True)
    open(os.path.join(R,  "doc.txt"),   "w").write("V1")
    open(os.path.join(R2, "other.txt"), "w").write("C1")

    p = Probe(a.cli, work); Q = "summarise doc.txt"
    for tag in ("S0", "S1", "S2"): p.c("init", "--db", p.db(tag, tag.lower()))

    def stage(tag, root, out, state, value_):
        return lambda: p.c("stage", "--db", p.dbs[tag], "--root-url", root,
                           "--value", value_, "--query", Q, "--state-id", state,
                           "--root-id", out)
    # E1：同一空间两个权威
    p.step("e1.stage_A", stage("S0", R, "shared", "a1", "ANSWER-A"))
    p.step("e1.state_a", lambda: p.c("get-value", "--db", p.dbs["S0"], "--state", "a1"))
    p.step("e1.stage_B", stage("S0", R, "shared", "a2", "ANSWER-B"))
    p.step("e1.state_b", lambda: p.c("get-value", "--db", p.dbs["S0"], "--state", "a2"))
    # E2 装置
    p.step("setup.s1", stage("S1", R,  "shared",  "a1", "ANSWER-A"))
    p.step("setup.s1c", stage("S1", R2, "control", "a3", "CONTROL"))
    p.step("setup.s2", stage("S2", R,  "shared",  "a2", "ANSWER-B"))
    p.step("pre.s1", lambda: p.c("get-value", "--db", p.dbs["S1"], "--state", "a1"))
    p.step("pre.s2", lambda: p.c("get-value", "--db", p.dbs["S2"], "--state", "a2"))
    p.steps.append({"step": "facts", "result": facts(p.dbs["S1"]), "delta": {}})
    log("step", **p.steps[-1])
    # 阳性对照：改控制文件，a3 必须拒，a1 必须仍服务
    open(os.path.join(R2, "other.txt"), "w").write("C2-CHANGED")
    p.step("pos.after_control_change", lambda: p.c("get-value", "--db", p.dbs["S1"], "--state", "a3"))
    p.step("pos.scope_kept", lambda: p.c("get-value", "--db", p.dbs["S1"], "--state", "a1"))
    # E2：改共享文件，两空间各看一眼
    open(os.path.join(R, "doc.txt"), "w").write("V2-CHANGED")
    p.step("e2.s1_after", lambda: p.c("get-value", "--db", p.dbs["S1"], "--state", "a1"))
    p.step("e2.s2_after", lambda: p.c("get-value", "--db", p.dbs["S2"], "--state", "a2"))
    # E2b：依赖不可读（不是变了，是不在了）
    os.rename(os.path.join(R, "doc.txt"), os.path.join(R, "doc.txt.away"))
    p.step("e2b.s1_unreadable", lambda: p.c("get-value", "--db", p.dbs["S1"], "--state", "a1"))
    p.step("e2b.s2_unreadable", lambda: p.c("get-value", "--db", p.dbs["S2"], "--state", "a2"))

    print("\n=== CLASS ===\n" + json.dumps(classify(p.steps), ensure_ascii=False, indent=1))
    out = os.path.join(work, "ledger.jsonl")
    with open(out, "w") as fh:
        for r in LEDGER: fh.write(json.dumps(r, ensure_ascii=False) + "\n")
    print("ledger:", out)
    return 0

if __name__ == "__main__":
    sys.exit(main())
