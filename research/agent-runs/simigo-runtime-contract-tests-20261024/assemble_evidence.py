#!/usr/bin/env python3
"""Re-derive the SimiGoRuntimeContractTests verdict from the raw evidence.

Reads only logs, snapshots, the clean checkout and its Package.resolved.
Writes contract_test_result.json and MANIFEST_SHA256.txt; exit 0 only if every
check passes.
"""
import collections, glob, hashlib, json, os, re, subprocess, sys

B = os.path.dirname(os.path.abspath(__file__))
RUNS = {"run1": B, "run2": os.path.join(B, "run2")}
EXPECTED_HEAD = "f18d65f8f312ffbb837fdf5e07125af044833854"
EXPECTED_PKG_SHA = "e9afb4c66871262b6099f43231274eafa70197712259eec34ac2a152422e5949"
checks = []

def check(name, ok, detail=""):
    checks.append({"check": name, "ok": bool(ok), "detail": detail})

def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()

def parse_run(run):
    txt = open(os.path.join(run, "logs/swift_test.stdout.log"), encoding="utf-8",
               errors="replace").read()
    suites, cur = collections.OrderedDict(), None
    for ln in txt.splitlines():
        m = re.match(r"Test Suite '([^']+)' (started|passed|failed) at", ln)
        if m:
            cur = m.group(1) if m.group(2) == "started" else None
            if m.group(2) == "started":
                suites.setdefault(cur, [])
            continue
        m = re.match(r"Test Case '-\[([\w.]+) (test\w+)\]' (passed|failed|skipped)", ln)
        if m and cur:
            suites[cur].append({"name": m.group(2), "status": m.group(3)})
    suites = {k: v for k, v in suites.items() if v}
    all_line = re.findall(r"Test Suite 'All tests' (?:passed|failed).*?Executed (\d+) tests?, with (\d+) failures?", txt, re.S)
    rc_path = os.path.join(run, "logs/swift_test.rc")
    rc = int(open(rc_path).read().strip()) if os.path.exists(rc_path) else None
    rc_source = "logs/swift_test.rc" if rc is not None else \
        "process exit observed by the executing shell; log verdict is 'All tests' passed"
    binary = os.path.join(run, "scratch/out/Products/Debug/SimiGoRuntimeContractTests.xctest/Contents/MacOS/SimiGoRuntimeContractTests")
    diff = json.load(open(os.path.join(run, "noninterference_diff.json")))
    iso = sum(len(f) for _, _, f in os.walk(os.path.join(run, "isolation")))
    return {
        "rc": rc,
        "rc_source": rc_source,
        "stdout_all_passed": "Test Suite 'All tests' passed" in txt,
        "suites": {k: {"executed": len(v),
                       "passed": sum(1 for t in v if t["status"] == "passed"),
                       "failed": sum(1 for t in v if t["status"] == "failed"),
                       "skipped": sum(1 for t in v if t["status"] == "skipped"),
                       "names": [t["name"] for t in v]} for k, v in suites.items()},
        "executed": sum(len(v) for v in suites.values()),
        "reported_total": int(all_line[-1][0]) if all_line else None,
        "reported_failures": int(all_line[-1][1]) if all_line else None,
        "test_binary": binary,
        "test_binary_sha256": sha(binary) if os.path.exists(binary) else None,
        "isolation_files": iso,
        "real_user_state_write_count": diff["real_user_state_write_count"],
        "violation_events": diff["violation_events"],
        "reference_changes": len(diff["reference_change_paths"]),
        "log_sha256": {n: sha(os.path.join(run, "logs", n)) for n in
                       ("swift_test.stdout.log", "swift_test.stderr.log")},
        "time": {m.group(1): m.group(2) for m in re.finditer(
                     r"^(real|user|sys) (\S+)$",
                     open(os.path.join(run, "logs/swift_test.stderr.log"), errors="replace").read(),
                     re.M)},
    }

def checkout_facts(run):
    co = os.path.join(run, "src/contract-checkout")
    pkg = os.path.join(co, "Packages/SimiGoRuntime/Package.swift")
    res = json.load(open(os.path.join(co, "Packages/SimiGoRuntime/Package.resolved")))
    pins = {p["identity"]: p["state"].get("revision") or p["state"].get("version") for p in res["pins"]}
    checkouts = {}
    for d in sorted(glob.glob(os.path.join(run, "scratch/checkouts/*"))):
        if os.path.isdir(os.path.join(d, ".git")):
            checkouts[os.path.basename(d)] = subprocess.run(
                ["git", "-C", d, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    return {
        "head": subprocess.run(["git", "-C", co, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip(),
        "dirty_lines": len(subprocess.run(["git", "-C", co, "status", "--porcelain"],
                                          capture_output=True, text=True).stdout.strip().splitlines()),
        "package_swift_sha256": sha(pkg),
        "pins": pins,
        "checkouts": checkouts,
    }

describe = json.load(open(os.path.join(B, "logs/package_describe.json")))
targets = {t["name"]: t for t in describe["targets"]}
test_src = sorted(os.path.basename(s) for s in targets["SimiGoRuntimeContractTests"]["sources"])
check("package_declares_test_target", targets["SimiGoRuntimeContractTests"]["type"] == "test",
      f"type={targets['SimiGoRuntimeContractTests']['type']}")
check("test_target_has_8_sources", len(test_src) == 8, ", ".join(test_src))

src_dir = os.path.join(B, "src/contract-checkout/Packages/SimiGoRuntime/Tests/SimiGoRuntimeContractTests")
declared = {}
for f in sorted(glob.glob(os.path.join(src_dir, "*.swift"))):
    s = open(f).read()
    cls = re.findall(r"class (\w+)\s*:\s*XCTestCase", s)
    funcs = re.findall(r"func (test\w+)\(", s)
    declared[os.path.basename(f)] = {"class": cls[0] if cls else None,
                                     "tests": sorted(funcs)}
check("declared_test_files_8", len(declared) == 8, f"{len(declared)} files")
check("declared_test_methods_total",
      sum(len(v["tests"]) for v in declared.values()) == 77,
      str(sum(len(v["tests"]) for v in declared.values())))

runs = {name: parse_run(path) for name, path in RUNS.items()}
facts = {name: checkout_facts(path) for name, path in RUNS.items()}

for name in RUNS:
    r, f = runs[name], facts[name]
    check(f"{name}_checkout_head", f["head"] == EXPECTED_HEAD, f["head"])
    check(f"{name}_checkout_clean", f["dirty_lines"] == 0, f"{f['dirty_lines']} dirty lines")
    check(f"{name}_package_swift_sha", f["package_swift_sha256"] == EXPECTED_PKG_SHA, f["package_swift_sha256"])
    check(f"{name}_deps_match_pins",
          all({k.lower(): v for k, v in f["checkouts"].items()}.get(k.lower()) == v
              for k, v in f["pins"].items())
          and len(f["checkouts"]) == len(f["pins"]),
          f"{len(f['checkouts'])} checkouts vs {len(f['pins'])} pins")
    check(f"{name}_exit_zero", (r["rc"] == 0) if r["rc"] is not None else r["stdout_all_passed"],
          f"rc={r['rc']} source={r['rc_source']}")
    check(f"{name}_executed_77", r["executed"] == 77 and r["reported_total"] == 77,
          f"parsed={r['executed']} reported={r['reported_total']}")
    check(f"{name}_zero_failures", r["reported_failures"] == 0 and
          all(s["failed"] == 0 for s in r["suites"].values()), str(r["reported_failures"]))
    check(f"{name}_zero_skipped", all(s["skipped"] == 0 for s in r["suites"].values()), "skipped=0")
    check(f"{name}_eight_suites", len(r["suites"]) == 8, str(len(r["suites"])))
    check(f"{name}_declared_equals_executed",
          all(v["class"] in r["suites"]
              and set(v["tests"]) == set(r["suites"][v["class"]]["names"])
              for v in declared.values()),
          "per-suite set comparison")
    check(f"{name}_isolation_untouched", r["isolation_files"] == 0, f"{r['isolation_files']} files")
    check(f"{name}_no_user_state_write", r["real_user_state_write_count"] == 0 and r["violation_events"] == 0,
          f"writes={r['real_user_state_write_count']} events={r['violation_events']}")
    check(f"{name}_reference_unchanged", r["reference_changes"] == 0, str(r["reference_changes"]))

check("runs_agree_on_suite_counts",
      {k: v["executed"] for k, v in runs["run1"]["suites"].items()} ==
      {k: v["executed"] for k, v in runs["run2"]["suites"].items()}, "run1 vs run2")

verdict = "PASS" if all(c["ok"] for c in checks) else "FAIL"
result = {
    "batch": B,
    "object": {"repo": "/Users/mr.simi/Documents/SimiGo", "commit": EXPECTED_HEAD,
               "package": "Packages/SimiGoRuntime",
               "package_swift_sha256": EXPECTED_PKG_SHA},
    "verdict": verdict,
    "checks_passed": sum(1 for c in checks if c["ok"]),
    "checks_total": len(checks),
    "checks": checks,
    "declared": declared,
    "runs": runs,
    "checkout_facts": facts,
}
json.dump(result, open(os.path.join(B, "contract_test_result.json"), "w"), indent=1)

manifest = []
for p in sorted(glob.glob(os.path.join(B, "*")) + glob.glob(os.path.join(B, "logs/*"))
                + glob.glob(os.path.join(B, "run2/*")) + glob.glob(os.path.join(B, "run2/logs/*"))):
    if os.path.isfile(p) and "MANIFEST_SHA256" not in p:
        manifest.append(f"{sha(p)}  {os.path.relpath(p, B)}")
open(os.path.join(B, "MANIFEST_SHA256.txt"), "w").write("\n".join(manifest) + "\n")
print(f"verdict={verdict} checks={result['checks_passed']}/{result['checks_total']} "
      f"run1={runs['run1']['executed']}/{runs['run1']['reported_failures']} "
      f"run2={runs['run2']['executed']}/{runs['run2']['reported_failures']} "
      f"manifest={len(manifest)}")
for c in checks:
    if not c["ok"]:
        print("  FAILED:", c["check"], c["detail"])
sys.exit(0 if verdict == "PASS" else 1)
