#!/usr/bin/env python3
"""Record two facts the report leans on, from the files themselves.

1. evidence/instrumentation_inventory.json
   The per-layer forward-count instrumentation was already shipped in the runtime
   package before this batch. The old gate text says "No per-layer forward-count
   instrumentation exists in the product", so the report has to show what does
   exist and - separately - that nothing outside that directory drove it. Both
   are measured here: file digests and line counts, plus every reference to the
   pilot/probe symbols outside the Instrumentation directory.

2. evidence/ledger_untouched.json
   This batch does not rewrite the acceptance ledger. The ledger's digest and
   verdict counts are recorded here so a reader can confirm it was not edited
   after the fact, and so the expected post-merge counts (if the operator ever
   authorises the merge) are stated with their arithmetic attached.

usage: inventory_instrumentation.py
Exit codes: 0 ok, 3 input missing.
"""
import hashlib
import json
import os
import subprocess
import sys

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = "/Users/mr.simi/Documents/SimiGo"
INST = os.path.join(REPO, "Packages/SimiGoRuntime/Sources/SimiGo2Experimental/Instrumentation")
LEDGER = ("/Users/mr.simi/SimiGo-Agent-Runs/"
          "simigo-v2.2.0rc1-local-acceptance-20261024/acceptance_report.json")
SYMBOLS = ("ExecutionTracePilot", "GroupExecutionTraceProbe", "MeasuredTraceCollection")


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def inventory():
    if not os.path.isdir(INST):
        print("instrumentation directory missing: %s" % INST, file=sys.stderr)
        return None
    files = []
    for name in sorted(os.listdir(INST)):
        if not name.endswith(".swift"):
            continue
        path = os.path.join(INST, name)
        with open(path) as handle:
            text = handle.read()
        files.append({
            "name": name,
            "path": os.path.relpath(path, REPO),
            "lines": text.count("\n") + (0 if text.endswith("\n") else 1),
            "sha256": sha(path),
        })

    refs = []
    for symbol in SYMBOLS:
        proc = subprocess.run(["grep", "-rln", symbol, REPO,
                               "--include=*.swift", "--include=*.md"],
                              capture_output=True, text=True)
        for line in proc.stdout.splitlines():
            rel = os.path.relpath(line, REPO)
            if rel.startswith(os.path.relpath(INST, REPO)):
                continue
            refs.append({"symbol": symbol, "path": rel})
    refs.sort(key=lambda r: (r["path"], r["symbol"]))

    # Same question against the committed tree, so "nothing drove it" is measured
    # rather than asserted: no worktree edit of ours can move this baseline.
    head_refs = []
    for symbol in SYMBOLS:
        proc = subprocess.run(["git", "-C", REPO, "grep", "-l", symbol, "HEAD",
                               "--", "*.swift"], capture_output=True, text=True)
        for line in proc.stdout.splitlines():
            rel = line.split("HEAD:", 1)[-1]
            if rel.startswith(os.path.relpath(INST, REPO)):
                continue
            head_refs.append({"symbol": symbol, "path": rel})
    head_refs.sort(key=lambda r: (r["path"], r["symbol"]))

    return {
        "gate_wording_under_review": ("No per-layer forward-count instrumentation "
                                      "exists in the product."),
        "where_it_actually_lives": os.path.relpath(INST, REPO),
        "files": files,
        "total_lines": sum(f["lines"] for f in files),
        "observation_points": ["layers.*.mlp.down_proj", "layers.*.mlp.switch_mlp.down_proj"],
        "event_semantics": ("one `layerEntered` event per (forward pass, decoder layer); "
                            "`passCount` counts layer-0 appearances"),
        "references_outside_instrumentation_dir": refs,
        "references_outside_instrumentation_dir_at_head": head_refs,
        "head": subprocess.run(["git", "-C", REPO, "rev-parse", "HEAD"],
                               capture_output=True, text=True).stdout.strip(),
        "reading": ("At HEAD the only references to these symbols live inside the "
                    "Instrumentation directory itself: the instrumentation is "
                    "compiled into the runtime package but nothing drives it, so no "
                    "per-layer numbers had ever been produced. The gate text "
                    "conflated 'nothing drives it' with 'it does not exist'. This "
                    "batch adds the driver (SimiGo/Headless/SimiGoG1G3Entry.swift, "
                    "role `tracepilot`) and a test for its role resolution; the "
                    "observer itself is unchanged."),
    }


def ledger():
    if not os.path.exists(LEDGER):
        print("ledger missing: %s" % LEDGER, file=sys.stderr)
        return None
    doc = json.load(open(LEDGER))
    verdicts = {k: v.get("verdict") for k, v in doc["gates"].items()}
    return {
        "path": LEDGER,
        "sha256": sha(LEDGER),
        "counts": doc["counts"],
        "overall": doc["overall"],
        "gates": verdicts,
        "modified_by_this_batch": False,
        "expected_if_merged": {
            "counts": {"PASS": 13, "BLOCKED": 3, "FAIL": 0,
                       "INCONCLUSIVE": 0, "NOT_INSTRUMENTED": 0},
            "arithmetic": ("per_layer_forward_calls NOT_INSTRUMENTED -> PASS moves one "
                           "gate from the NOT_INSTRUMENTED bucket to PASS; 12+1 = 13, "
                           "1-1 = 0. physical_page_return, product_service_http and "
                           "install_and_operate stay BLOCKED."),
            "requires": "separate explicit authorisation; this batch does not edit the ledger",
        },
    }


def main():
    inv, led = inventory(), ledger()
    if inv is None or led is None:
        return 3
    os.makedirs(os.path.join(B, "evidence"), exist_ok=True)
    with open(os.path.join(B, "evidence/instrumentation_inventory.json"), "w") as handle:
        json.dump(inv, handle, indent=1)
        handle.write("\n")
    with open(os.path.join(B, "evidence/ledger_untouched.json"), "w") as handle:
        json.dump(led, handle, indent=1)
        handle.write("\n")
    print(json.dumps({
        "instrumentation_files": len(inv["files"]),
        "instrumentation_lines": inv["total_lines"],
        "references_outside_dir": [r["path"] for r in inv["references_outside_instrumentation_dir"]],
        "ledger_sha256": led["sha256"],
        "ledger_counts": led["counts"],
    }, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
