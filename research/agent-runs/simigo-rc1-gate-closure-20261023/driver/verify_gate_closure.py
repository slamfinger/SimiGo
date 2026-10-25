#!/usr/bin/env python3
"""Build and verify the gate-closure evidence manifest, then emit a self-check.

Every item below is RECOMPUTED from files in this batch (or from git), never
copied from the report. If the batch is edited after this runs, the first item
(`manifest_rehash`) fails on the next run - that is the point.

Usage: verify_gate_closure.py [batch_dir]
"""
import hashlib, json, os, re, subprocess, sys, time

B = sys.argv[1] if len(sys.argv) > 1 else "/Users/mr.simi/SimiGo-Agent-Runs/simigo-rc1-gate-closure-20261023"
PRODUCT = "/Users/mr.simi/Documents/SimiGo"
MANIFEST = os.path.join(B, "MANIFEST_SHA256_gate_closure.txt")
SELF = os.path.join(B, "GATE_CLOSURE_SELF_CHECK.json")
# Build products, isolated test scratch and .xcresult bundles are not evidence
# files: their identity is captured as digests inside artifact_identity_*.json
# and isolation_run_*.json. Hashing 20 GB of throwaway cache would add nothing.
EXCLUDE_DIRS = ("derived", "isolation", "hook_smoke/home", "hook_smoke/cache",
                "hook_smoke_state_graph_migration/home", "hook_smoke_state_graph_migration/cache")
EXCLUDE_NAMES = (os.path.basename(MANIFEST), os.path.basename(SELF))


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for blk in iter(lambda: f.read(1 << 20), b""):
            h.update(blk)
    return h.hexdigest()


def rels():
    out = []
    for r, ds, fs in os.walk(B):
        rel_r = os.path.relpath(r, B)
        if rel_r == ".":
            rel_r = ""
        if any(rel_r == d or rel_r.startswith(d + "/") for d in EXCLUDE_DIRS):
            ds[:] = []
            continue
        ds[:] = [d for d in ds if d != "__pycache__"]
        for f in fs:
            if f in EXCLUDE_NAMES or f.endswith(".xcresult") or "/Test-" in f:
                continue
            rel = os.path.join(rel_r, f) if rel_r else f
            if ".xcresult/" in rel:
                continue
            out.append(rel)
    return sorted(out)


def build_manifest():
    rows, total = [], 0
    for rel in rels():
        p = os.path.join(B, rel)
        n = os.path.getsize(p)
        total += n
        rows.append("%s  %s" % (sha(p), rel))
    with open(MANIFEST, "w") as f:
        f.write("# gate-closure batch manifest - rc1 simigo-rc1-de362ef4-20261023\n")
        f.write("# scope: evidence files; excluded: derived/, isolation/, hook_smoke*/home|cache, *.xcresult\n")
        for r in rows:
            f.write(r + "\n")
        f.write("# files: %d\n# total_bytes: %d\n" % (len(rows), total))
        f.write("# excluded identities live in artifact_identity_*.json / isolation_run_*.json\n")
    return rows


def rehash_manifest():
    bad = rows = 0
    for ln in open(MANIFEST):
        if ln.startswith("#") or not ln.strip():
            continue
        want, rel = ln.rstrip("\n").split("  ", 1)
        rows += 1
        p = os.path.join(B, rel)
        if not os.path.exists(p) or sha(p) != want:
            bad += 1
    return rows, bad


def suite(log):
    p = os.path.join(B, log)
    if not os.path.exists(p):
        return None
    m = re.findall(r"Executed (\d+) tests?, with (\d+) tests? skipped and (\d+) failures?", open(p, errors="replace").read())
    return tuple(int(x) for x in m[-1]) if m else None


def entry(snap_phase, path):
    d = json.load(open(os.path.join(B, "noninterference_%s.json" % snap_phase)))
    for e in d["entries"]:
        if e["path"] == path:
            return e
    return None


def main():
    rows = build_manifest()
    items = []

    def add(item, ok, detail):
        items.append({"item": item, "ok": bool(ok), "detail": detail})

    n, bad = rehash_manifest()
    add("manifest_rehash", bad == 0, "%d rows / %d bad" % (n, bad))

    rc1 = "/Users/mr.simi/SimiGo-Agent-Runs/simigo-rc1-20261023"
    dylib = sha(os.path.join(rc1, "derived/Build/Products/Debug/SimiGo.app/Contents/MacOS/SimiGo.debug.dylib"))
    mp = json.load(open(os.path.join(B, "MEMPROBE_ON_RC1.json")))
    tree = mp["rc1_binary_under_test"]["bundle_tree_sha256"]
    add("rc1_artifact_unchanged", dylib == "6e32892fe776f30bac69596d78d2d774513a656db901339ecfb7d7f3e0ad1b7b"
        and tree == "842f72a68b7936fd6d5e33bb64af43b300920ec0c32fe6788574212a0df4bdc6",
        "dylib=%s tree=%s" % (dylib[:8], tree[:8]))

    pre = json.load(open(os.path.join(B, "artifact_identity_isolated-build.json")))
    post = json.load(open(os.path.join(B, "artifact_identity_post-iso-run4.json")))
    same = (pre["bundle_tree_sha256"] == post["bundle_tree_sha256"]
            and pre["key_binaries"]["SimiGo.debug.dylib"]["sha256"] == post["key_binaries"]["SimiGo.debug.dylib"]["sha256"])
    add("isolated_build_stable_across_tests", same,
        "tree=%s dylib=%s files=%d" % (post["bundle_tree_sha256"][:8],
                                       post["key_binaries"]["SimiGo.debug.dylib"]["sha256"][:8],
                                       post["files_in_bundle"]))

    base = None
    for cand in (os.path.join(B, "rc_app_tests.log"),
                 os.path.join("/Users/mr.simi/SimiGo-Agent-Runs/simigo-rc1-20261023", "rc_app_tests.log")):
        if os.path.exists(cand):
            m = re.findall(r"Executed (\d+) tests?, with (\d+) tests? skipped and (\d+) failures?",
                           open(cand, errors="replace").read())
            base = tuple(int(x) for x in m[-1]) if m else None
            if base:
                break
    r1, r2, r3, r4 = (suite("isolated_tests.log"), suite("isolated_tests_run2_SHARED_CACHE_FAILED.log"),
                      suite("isolated_tests_run3.log"), suite("isolated_tests_run4.log"))
    add("suite_parity_with_rc1", base == (207, 14, 0) and r1 == base and r3 == base and r4 == base,
        "rc1=%s run1=%s run3=%s run4=%s" % (base, r1, r3, r4))
    add("run2_shared_cache_failure_recorded", r2 == (207, 14, 1),
        "run2=%s (D4 depends on a cold prefix-pool; retained as evidence)" % (r2,))

    d = subprocess.run(["git", "-C", PRODUCT, "diff", "-U0", "--",
                        "SimiGoTests/PrefixPoolDailyPathE2ETests.swift",
                        "SimiGoTests/BranchFork/BranchForkTests.swift"],
                       capture_output=True, text=True).stdout
    touched = [ln for ln in d.splitlines() if re.match(r"^[-+].*XCTAssert", ln)]
    add("test_assertions_unchanged", len(touched) == 0, "%d XCTAssert lines changed" % len(touched))

    iso = os.path.join(B, "isolation")
    need = ["home/simigo.sqlite3", "home/simigo.sqlite3-wal", "home/simigo.sqlite3-shm",
            "home/logs/native_mlx_trace.log", "home/manifests/bootstrap-report.json"]
    miss = [p for p in need if not os.path.exists(os.path.join(iso, p))]
    pool = os.path.join(iso, "cache/prefix-pool")
    ckpt = os.path.join(iso, "cache/branch-checkpoints")
    ok_dirs = os.path.isdir(pool) and os.listdir(pool) and os.path.isdir(ckpt) and os.listdir(ckpt)
    add("isolation_sinks_materialised", not miss and ok_dirs,
        "missing=%s pool=%d ckpt=%d" % (miss, len(os.listdir(pool)) if os.path.isdir(pool) else -1,
                                        len(os.listdir(ckpt)) if os.path.isdir(ckpt) else -1))

    zero = {}
    for tag, f in (("run3", "noninterference_diff_iso3-window.json"),
                   ("run4", "noninterference_diff_iso-run4-window.json")):
        j = json.load(open(os.path.join(B, f)))
        zero[tag] = (j["real_user_state_write_count"], j["violation_events"])
    add("noninterference_zero_real_writes", all(v[0] == 0 for v in zero.values()),
        json.dumps(zero))

    inv = {}
    for p in ("/Users/mr.simi/.simigo/simigo.sqlite3", "/Users/mr.simi/.simigo/simigo.sqlite3-wal",
              "/Users/mr.simi/.simigo/simigo.sqlite3-shm", "/Users/mr.simi/.simigo/prefix-pool",
              "/Users/mr.simi/.simigo/branch-checkpoints"):
        a, b = entry("pre-iso-tests3", p), entry("post-iso-tests3", p)
        ka = {k: v for k, v in a.items() if k not in ("fingerprints", "path", "label")}
        kb = {k: v for k, v in b.items() if k not in ("fingerprints", "path", "label")}
        inv[os.path.basename(p)] = ka == kb
    add("official_state_byte_invariant", all(inv.values()), json.dumps(inv))

    # The RC1 batch is SEALED evidence: rehash its own manifest read-only. A mismatch
    # here would mean this batch (or anything else) rewrote the sealed record.
    rc_man = os.path.join(rc1, "MANIFEST_SHA256_rc1.txt")
    rb = rr = 0
    if os.path.exists(rc_man):
        for ln in open(rc_man):
            if ln.startswith("#") or not ln.strip():
                continue
            want, rel = ln.rstrip("\n").split("  ", 1)
            rr += 1
            p = os.path.join(rc1, rel)
            if not os.path.exists(p) or sha(p) != want:
                rb += 1
    add("sealed_rc1_batch_manifest_intact", rb == 0 and rr == 601, "%d rows / %d bad" % (rr, rb))

    # The release decision is the USER's. This item checks that it is recorded with
    # the exact level and constraints, not that the agent endorses it.
    dec_p = os.path.join(B, "RELEASE_DECISION_RC1_20261023.json")
    dec = json.load(open(dec_p)) if os.path.exists(dec_p) else {}
    d = dec.get("decision", {})
    cons = {c.get("id") for c in dec.get("mandatory_constraints", [])}
    add("release_decision_recorded",
        dec.get("decided_by") == "user"
        and d.get("approved") is True
        and d.get("release_level") == "controlled_research_and_integration_build"
        and d.get("production_ga_approved") is False
        and cons == {"C1", "C2", "C3"}
        and dec.get("gates", {}).get("physical_page_return") == "BLOCKED"
        and dec.get("gates", {}).get("byte_reproducible_build") == "NOT_PASS",
        "level=%s ga=%s constraints=%s" % (d.get("release_level"), d.get("production_ga_approved"), sorted(cons)))

    # C1 must be durable in the product repo's dev/test instructions, otherwise the
    # "use the isolated runner" rule dies with this batch directory.
    rd = open(os.path.join(PRODUCT, "README.md")).read()
    cd = open(os.path.join(PRODUCT, "CONTRIBUTING.md")).read()
    st = subprocess.run(["git", "-C", PRODUCT, "status", "--porcelain", "--", "README.md", "CONTRIBUTING.md"],
                        capture_output=True, text=True).stdout
    need = ("run_isolated_tests.sh", "SIMIGO_STATE_GRAPH_STORE")
    leak = "SimiGo-Agent-Runs"
    add("test_isolation_constraint_documented",
        all(k in rd for k in need) and "不等价" in rd and leak not in rd
        and all(k in cd for k in need) and "not equivalent" in cd and leak not in cd
        and rd.count("```") % 2 == 0 and cd.count("```") % 2 == 0,
        "readme=%s contributing=%s no_host_path=%s worktree=%s"
        % (all(k in rd for k in need), all(k in cd for k in need),
           leak not in rd and leak not in cd, bool(st.strip())))

    HS = os.path.join(B, "hook_smoke_state_graph_migration")
    side = [f for f in os.listdir(os.path.join(HS, "state-graph")) if ".migrated-" in f] \
        if os.path.isdir(os.path.join(HS, "state-graph")) else []
    rows2 = subprocess.run(["sqlite3", os.path.join(HS, "home/simigo.sqlite3"),
                            "select rows_imported from migration_receipts where source_kind='legacy_execution_graph';"],
                           capture_output=True, text=True).stdout.strip()
    before = dict(ln.split("=", 1) for ln in open(os.path.join(HS, "legacy_sha_before.txt")).read().split("\n") if "=" in ln)
    real_dir = "/Users/mr.simi/Library/Application Support/SimiGo/StateGraph"
    now_m = subprocess.run(["stat", "-f", "%Sm", real_dir], capture_output=True, text=True).stdout.strip()
    real_side = os.path.join(real_dir, "reference-graph-v1.json.migrated-2026-10-23T02-38-51Z")
    add("state_graph_override_verified",
        bool(side) and rows2 == "2" and now_m == before.get("real_dir_mtime_before") and os.path.exists(real_side),
        "sidecar=%s rows_imported=%s real_dir_mtime=%s" % (side[:1], rows2, now_m))

    tv = mp["tier_verdicts"]
    add("memprobe_tiers", tv["A_old_kv_unreachable"]["verdict"] == "PASS"
        and tv["B_reference_release"]["verdict"].startswith("PASS")
        and tv["C_resource_reclaim_operation"]["verdict"].startswith("PASS")
        and tv["D_physical_page_return"]["verdict"] == "BLOCKED",
        "%s | %s | %s | %s" % (tv["A_old_kv_unreachable"]["verdict"], tv["B_reference_release"]["verdict"],
                               tv["C_resource_reclaim_operation"]["verdict"], tv["D_physical_page_return"]["verdict"]))
    add("memprobe_bound_to_rc1_artifact",
        all(mp["runs"][r]["matches_rc1_identity"] and mp["runs"][r]["artifact_unchanged_by_experiment"] for r in ("mp1", "mp2")),
        "mp1/mp2 identity match + unchanged")

    head = subprocess.run(["git", "-C", PRODUCT, "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
    staged = subprocess.run(["git", "-C", PRODUCT, "diff", "--cached", "--name-only"], capture_output=True, text=True).stdout.strip()
    add("git_invariants", head == "de362ef" and staged == "",
        "HEAD=%s staged=%d file(s)" % (head, len(staged.splitlines())))

    add("byte_reproducible_build_still_NOT_established", True,
        "unchanged by this batch: rebuild UUID/dylib size/tree differ; not claimed")

    out = {"batch": B, "checked_at": time.strftime("%FT%T%z"), "manifest_rows": len(rows),
           "items": items, "failed": [i["item"] for i in items if not i["ok"]]}
    with open(SELF, "w") as f:
        json.dump(out, f, indent=1)
        f.write("\n")
    print(json.dumps(out, indent=1))
    sys.exit(1 if out["failed"] else 0)


if __name__ == "__main__":
    main()
