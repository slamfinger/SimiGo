#!/usr/bin/env python3
"""Round-1 bounded observer (Design v0.2 §6).

Runs ONLY after all ES processes have exited. Independently re-derives the
evidence facts from raw artifacts (never from participant self-reports) and
emits observer_verdict.json. Produces no continuation state; has no write
channel into any ES process.

Registered delta: this instrument provides evidence separation only; the
full prebound tamper-resistant Observation Integrity Boundary (Authorization
Package v0.6 §6) remains an EXECUTION-stage obligation.
"""

import hashlib
import json
import os
import sys


def sha256_hex_file(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: observer.py RUN_DIR IS_DIR", file=sys.stderr)
        return 64
    run_dir, is_dir = sys.argv[1], sys.argv[2]
    checks = []

    # C1: re-hash every IS object against its content address.
    objects_dir = os.path.join(is_dir, "objects")
    c1 = True
    for name in sorted(os.listdir(objects_dir)):
        if sha256_hex_file(os.path.join(objects_dir, name)) != name:
            c1 = False
    checks.append({"check": "C1_object_write_once_integrity", "pass": c1})

    # C2: re-derive U ledger counts from raw event logs.
    counts = {}
    for name in sorted(os.listdir(run_dir)):
        if not name.endswith("events.jsonl"):
            continue
        n = 0
        with open(os.path.join(run_dir, name), "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                rec = json.loads(line)
                if rec.get("event") == "U_INVOCATION_LEDGER":
                    n += 1
        counts[name] = n
    es1_one = (counts.get("es1-events.jsonl") == 1)
    es2_zero = (counts.get("es2-events.jsonl") == 0)
    esn_zero = (counts.get("esn-events.jsonl") == 0)
    checks.append({"check": "C2_E6_ledger_rederivation",
                   "pass": es1_one and es2_zero and esn_zero,
                   "counts": counts,
                   "expected": {"es1-events.jsonl": 1, "es2-events.jsonl": 0,
                                "esn-events.jsonl": 0}})

    # C3: persisted-vs-resolved byte equality evidence present in es2 log.
    c3 = False
    path2 = os.path.join(run_dir, "es2-events.jsonl")
    if os.path.exists(path2):
        with open(path2, "r", encoding="utf-8") as fh:
            for line in fh:
                rec = json.loads(line.strip() or "{}")
                if rec.get("event") == "SRS_RESOLVED" and rec.get("byte_hash_match") is True:
                    c3 = True
    checks.append({"check": "C3_persisted_vs_resolved_byte_equality", "pass": c3})

    # C4: temporal separation — read from the DRIVER log (single campaign-level
    # file): es1 EXIT event ordinal < es2 SPAWN event ordinal; likewise
    # es2 EXIT < mutate-n1 SPAWN < esn SPAWN. Per-process logs are separate
    # files whose ordinals are not comparable across processes.
    c4 = False
    order_evidence = {}
    driver_log = os.path.join(run_dir, "driver-events.jsonl")
    if os.path.exists(driver_log):
        seq = []
        with open(driver_log, "r", encoding="utf-8") as fh:
            for line in fh:
                rec = json.loads(line.strip() or "{}")
                if rec.get("event") in ("SPAWN", "EXIT"):
                    seq.append((rec["ordinal"], rec["event"], rec.get("target")))
        def find(event, target):
            for ordinal, ev, tgt in seq:
                if ev == event and tgt == target:
                    return ordinal
            return None
        pairs = [("es1", "es2"), ("es2", "mutate-n1"), ("mutate-n1", "esn")]
        c4 = True
        for before, after in pairs:
            b = find("EXIT", before)
            a = find("SPAWN", after)
            order_evidence["%s_exit_before_%s_spawn" % (before, after)] = (
                b is not None and a is not None and b < a)
            if not (b is not None and a is not None and b < a):
                c4 = False
    checks.append({"check": "C4_temporal_separation", "pass": bool(c4),
                   "order_evidence": order_evidence})

    verdict = {"observer": "SRS-REAL-CLOSURE-01-ROUND1-BOUNDED-OBSERVER",
               "all_checks_pass": all(c["pass"] for c in checks), "checks": checks}
    out = os.path.join(run_dir, "observer_verdict.json")
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(verdict, fh, sort_keys=True, indent=2)
        fh.write("\n")
    print("observer verdict written:", out)
    return 0 if verdict["all_checks_pass"] else 1


if __name__ == "__main__":
    sys.exit(main())
