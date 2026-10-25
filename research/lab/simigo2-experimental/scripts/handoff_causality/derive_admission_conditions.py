#!/usr/bin/env python3
"""Re-derive the admission-condition block from immutable per-case evidence.

The first version of ``admission_conditions`` in the phase-2 runner required
``tokenize_text_calls == 0`` for EVERY condition, which is wrong for admitted
conditions: an admitted fresh-ES continuation must tokenize its seed and its
admitted next input exactly once. The check is fixed in the runner; this tool
re-derives the block from the untouched ``evidence/phase2.json`` files (their
sha256 is recorded) and revises ONLY the derived summary field. Per-case
evidence is never modified.

Usage:
  python3 derive_admission_conditions.py --run-root <run root>
"""
from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

import run_phase2_causality as runner

EVIDENCE_PATHS = {
    "B0-A": "phase2a/world-a/B0-A/evidence/phase2.json",
    "B0-B": "phase2b/world-b/B0-B/evidence/phase2.json",
    "B1-harness": "phase2a/world-a/B1-harness/evidence/phase2.json",
    "B3a": "phase2a/world-a/B3a/evidence/phase2.json",
    "B3b": "phase2a/world-a/B3b/evidence/phase2.json",
    "B3c": "phase2a/world-a/B3c/evidence/phase2.json",
}


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-root", required=True)
    arguments = parser.parse_args()
    run_root = Path(arguments.run_root).expanduser().resolve()
    summary_path = run_root / "summary.json"
    summary = json.loads(summary_path.read_text(encoding="utf-8"))

    results: dict[str, dict] = {}
    provenance: dict[str, dict] = {}
    for name, relative in EVIDENCE_PATHS.items():
        path = run_root / relative
        evidence = json.loads(path.read_text(encoding="utf-8"))
        results[name] = {
            "terminal_state": evidence.get("terminal_state"),
            "evidence": evidence,
        }
        provenance[name] = {
            "path": relative,
            "sha256": sha256_file(path),
        }

    derived = runner.admission_conditions(results)
    payload = {
        "schema_id": "SIMIGO-CAUSALITY-PHASE2-ADMISSION-V2",
        "created_at_utc": utc_now(),
        "run_id": summary.get("run_id"),
        "reason": (
            "The initial summarizer required tokenize_text_calls==0 for every "
            "condition; admitted conditions legitimately tokenize seed+input once. "
            "Re-derived from immutable per-case evidence; no condition was rerun "
            "and no evidence file was modified."
        ),
        "evidence_provenance": provenance,
        "admission_conditions": derived,
        "all_pass": all(item["pass"] for item in derived.values()),
    }
    (run_root / "admission_conditions_v2.json").write_text(
        json.dumps(payload, indent=1, sort_keys=True) + "\n", encoding="utf-8")

    summary.setdefault("summary_revisions", []).append({
        "at_utc": utc_now(),
        "field": "admission_conditions",
        "record": "admission_conditions_v2.json",
        "evidence_provenance": provenance,
    })
    summary["admission_conditions"] = derived
    summary_path.write_text(
        json.dumps(summary, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({
        "all_pass": payload["all_pass"],
        "conditions": {
            name: {
                "pass": item["pass"],
                "stage": item["refusal_stage"],
                "generation_calls": item["model_continuation_calls"],
                "tokenize_text_calls": item["tokenize_text_calls"],
                "tokenize_seed_calls": item["tokenize_seed_calls"],
            }
            for name, item in derived.items()
        },
    }, indent=1, sort_keys=True))
    return 0 if payload["all_pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
