#!/usr/bin/env python3
# Copyright © 2026 SimiGo-Lab. nodes-out Experiment Runner v2
# Boundary: audit frozen baseline + Candidate A implementation; no effect verdict.

import importlib.util
import hashlib
import json
import os
import random
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
BASELINE_COMMIT = "17bde28"
BASELINE_REL = "trackE-residency/residency_policy_simulator_v3.py"
RUNNER_REL = "trackE-residency/nodes_out_experiment_runner.py"
BASELINE_VERSION = "v6-regression-snapshot"
RUN_IDENTITY = "simigo-nodes-out-v1"
SEED = 42
N_NODES = 32
TRACE_LEN = 2000
B_NODES = 12
B_UNITS = 24
GDN_KIB, ATT_KIB = 61440, 16806
FROZEN_LRU = {
    "hot": (973.1, 696, 684),
    "tree": (1422.9, 1015, 1003),
}


def git(*args):
    return subprocess.check_output(["git", *args], cwd=HERE, text=True).strip()


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_frozen_sim3():
    """Import simulator v3 from the audited commit, not the working tree."""
    blob = git("rev-parse", f"{BASELINE_COMMIT}:{BASELINE_REL}")
    text = git("show", f"{BASELINE_COMMIT}:{BASELINE_REL}")
    path = os.path.join(tempfile.mkdtemp(prefix="nodes-out-frozen-"), "sim3.py")
    with open(path, "w", encoding="utf-8") as f:
        f.write(text + "\n")
    spec = importlib.util.spec_from_file_location("frozen_sim3", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod, blob


sim3, BASELINE_BLOB = load_frozen_sim3()
C_EXT, C_REHY = sim3.C_EXT, sim3.C_REHY
TRACE_NAME = {}


def make_traces():
    rng = random.Random(SEED)
    parent = sim3.gen_topology(N_NODES, 8)
    traces = {
        "hot": sim3.gen_hot_trace(rng, N_NODES, TRACE_LEN),
        "tree": sim3.gen_tree_trace(rng, parent, N_NODES, TRACE_LEN),
    }
    TRACE_NAME.update({id(v): k for k, v in traces.items()})
    return traces


def five_tuple(step, trace, kv_versions):
    nxt = trace[step + 1] if step + 1 < len(trace) else None
    versions = tuple(kv_versions)
    return {
        "identity": RUN_IDENTITY,
        "position": step,
        "next_input": nxt,
        "kv_versions": versions,
        "continuation": ("advance", trace[step], nxt, versions),
    }


def baseline_logical_steps(trace):
    versions = [0] * N_NODES
    rows = []
    for step, node in enumerate(trace):
        versions[node] += 1
        rows.append(five_tuple(step, trace, versions))
    return rows


def run_baseline(trace):
    m = sim3.simulate_v3("lru", trace, B_NODES, C_EXT, C_REHY, H=8)
    j, rehy, ext = FROZEN_LRU[TRACE_NAME[id(trace)]]
    ok = (m["violations"] == 0 and round(m["J"], 1) == j
          and m["rehy"] == rehy and m["ext"] == ext)
    return m, ok


class CandidateA:
    """KV units are the minimum residency objects; logical KV is never lost."""

    def __init__(self, trace):
        self.trace = trace
        self.units = {(kind, n): {"res": False, "last": -1, "ver": 0}
                      for n in range(N_NODES) for kind in ("GDN", "ATT")}
        self.logical_versions = [0] * N_NODES
        self.events = []
        self.steps = []
        self.violations = []

    def fail(self, step, msg):
        self.violations.append({"step": step, "msg": msg})

    def run(self):
        for step, node in enumerate(self.trace):
            self.logical_versions[node] += 1
            for kind in ("GDN", "ATT"):
                unit = (kind, node)
                state = self.units[unit]
                if not state["res"]:
                    state["res"] = True
                    self.events.append(("rehydrate", step, unit))
                state["last"] = step
                state["ver"] += 1

            if any(not self.units[(kind, node)]["res"] for kind in ("GDN", "ATT")):
                self.fail(step, f"decode node {node} missing a KV unit")

            while True:
                resident = [u for u, state in self.units.items() if state["res"]]
                if len(resident) <= B_UNITS:
                    break
                candidates = [u for u in resident if u[1] != node]
                if not candidates:
                    self.fail(step, "no legal unit victim")
                    break
                victim = min(candidates,
                             key=lambda u: (self.units[u]["last"], u))
                self.units[victim]["res"] = False
                self.events.append(("externalize", step, victim))

            if sum(state["res"] for state in self.units.values()) > B_UNITS:
                self.fail(step, "resident units exceed budget")
            self.steps.append(five_tuple(step, self.trace, self.logical_versions))
        return self

    def final(self):
        return {
            "five_tuple": self.steps[-1] if self.steps else None,
            "ext_count": sum(op == "externalize" for op, _, _ in self.events),
            "rehy_count": sum(op == "rehydrate" for op, _, _ in self.events),
            "resident_units": sum(s["res"] for s in self.units.values()),
        }


def event_checks(run, baseline_steps):
    bad = list(run.violations)
    for op, step, unit in run.events:
        if run.steps[step] != baseline_steps[step]:
            bad.append({"step": step, "op": op, "unit": unit,
                        "msg": "event five_tuple != baseline"})
        if op == "externalize" and unit[1] == run.trace[step]:
            bad.append({"step": step, "op": op, "unit": unit,
                        "msg": "current node unit externalized"})
    return bad


def step_checks(run, baseline_steps):
    return [{"step": i, "msg": "step five_tuple != baseline"}
            for i, (candidate, baseline) in enumerate(zip(run.steps,
                                                          baseline_steps))
            if candidate != baseline]


def terminal_checks(run, baseline_steps):
    bad = [] if run.steps[-1] == baseline_steps[-1] else [
        {"msg": "terminal five_tuple != baseline"}]
    if run.final()["resident_units"] > B_UNITS:
        bad.append({"msg": "terminal resident units > budget"})
    return bad


def key_output(run):
    return {
        "events": run.events,
        "final": run.final(),
        "steps": run.steps,
        "violations": run.violations,
    }


def deterministic_diff(candidate_1, candidate_2):
    a, b = key_output(candidate_1), key_output(candidate_2)
    return sum(a[f] != b[f] for f in ("events", "final", "steps", "violations"))


def main():
    traces = make_traces()
    runs = {}
    audit = {
        "runner": {
            "path": RUNNER_REL,
            "sha256": sha256_file(os.path.join(HERE,
                                               os.path.basename(__file__))),
        },
        "input": {
            "GDN": GDN_KIB, "ATT": ATT_KIB, "seed": SEED,
            "nodes": N_NODES, "trace_len": TRACE_LEN,
            "budget_nodes": B_NODES, "budget_units": B_UNITS,
        },
        "assertions": {
            layer: {"pass": True, "violation_count": 0, "by_workload": {}}
            for layer in ("L1", "L2", "L3")
        },
        "deterministic": {"run_1": [], "run_2": [], "dd": 0,
                          "violation_count": 0},
    }
    baseline_fail = 0

    for name, trace in traces.items():
        baseline, ok = run_baseline(trace)
        baseline_fail += not ok
        print(f"baseline {name}/lru: J={baseline['J']:.1f} "
              f"rehy={baseline['rehy']} ext={baseline['ext']} "
              f"regression={'OK' if ok else 'FAIL'}")
        runs[name] = {
            "baseline_logical": baseline_logical_steps(trace),
            "candidate_1": CandidateA(trace).run(),
            "candidate_2": CandidateA(trace).run(),
        }

    audit["baseline"] = {
        "version": BASELINE_VERSION,
        "commit": BASELINE_COMMIT,
        "blob": BASELINE_BLOB,
        "source": f"git show {BASELINE_COMMIT}:{BASELINE_REL}; temp-file import",
        "regression": {"pass": not baseline_fail,
                       "violation_count": baseline_fail},
    }

    for name, item in runs.items():
        for layer, check in (("L1", event_checks), ("L2", step_checks),
                             ("L3", terminal_checks)):
            bad = check(item["candidate_1"], item["baseline_logical"])
            audit["assertions"][layer]["violation_count"] += len(bad)
            audit["assertions"][layer]["by_workload"][name] = {
                "pass": not bad, "violation_count": len(bad)}
            if bad:
                audit["assertions"][layer]["pass"] = False
            print(f"{name} {layer}: violations={len(bad)}")

    for name, item in runs.items():
        candidate_1, candidate_2 = item["candidate_1"], item["candidate_2"]
        dd = deterministic_diff(candidate_1, candidate_2)
        audit["deterministic"]["dd"] += dd
        audit["deterministic"]["violation_count"] += dd
        for slot, run in (("run_1", candidate_1), ("run_2", candidate_2)):
            final = run.final()
            audit["deterministic"][slot].append({
                "workload": name, "ext_count": final["ext_count"],
                "rehy_count": final["rehy_count"]})
        print(f"{name} deterministic: dd={dd}")

    total = (baseline_fail
             + sum(audit["assertions"][x]["violation_count"]
                   for x in ("L1", "L2", "L3"))
             + audit["deterministic"]["violation_count"])
    audit["FINAL"] = {"PASS": total == 0, "violation_count": total}

    out_dir = os.path.join(HERE, "runs", "NODES_OUT_RUNNER_AUDIT_20260922")
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, "runner_audit.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(audit, f, ensure_ascii=False, indent=2, sort_keys=True)

    det = audit["deterministic"]
    print("\nRUNNER AUDIT")
    print(f"├── baseline: {BASELINE_VERSION}@{BASELINE_COMMIT} "
          f"blob={BASELINE_BLOB[:12]}")
    print(f"│   └── regression={audit['baseline']['regression']['pass']} "
          f"violations={baseline_fail}")
    print(f"├── input: GDN={GDN_KIB} KiB, ATT={ATT_KIB} KiB")
    for layer in ("L1", "L2", "L3"):
        item = audit["assertions"][layer]
        print(f"├── {layer}: pass={item['pass']} "
              f"violations={item['violation_count']}")
    print(f"├── deterministic: dd={det['dd']} "
          f"violations={det['violation_count']}")
    print(f"└── FINAL: PASS={audit['FINAL']['PASS']} "
          f"violations={audit['FINAL']['violation_count']}")
    print(f"artifact: {out_path}")
    return 0 if audit["FINAL"]["PASS"] else 1


if __name__ == "__main__":
    sys.exit(main())
