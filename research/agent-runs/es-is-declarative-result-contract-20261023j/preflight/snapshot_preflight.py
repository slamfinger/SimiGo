#!/usr/bin/env python3
"""J-round preflight snapshots: protected historical run roots + source SHAs.

Takes the file inventory BEFORE any source edit so the historical guard can
re-check it later. Writes:
  preflight/prechange-historical-snapshot.json
  preflight/prechange-source-sha256.json
"""
import hashlib, json, sys
from pathlib import Path

RUNS = Path.home() / "SimiGo-Agent-Runs"
PROTECTED = [
    "handoff-causality-20261022b", "handoff-causality-20261022c",
    "handoff-causality-20261022d", "settlement-provenance-20261022e",
    "es-is-detached-continuation-20261022f",
    "es-is-multihop-continuation-20261022g",
    "es-is-selective-invalidation-20261022h",
    "es-is-semantic-sufficiency-20261022i",
]
LAB = Path("/Users/mr.simi/Documents/SimiGo-Lab")
SOURCES = [
    "execution-information-loop/production_runtime_bridge.py",
    "execution-information-loop/carrier_loop.py",
    "execution-information-loop/settlement_provenance.py",
    "execution-information-loop/i_semantic_sufficiency_selftest.py",
    "execution-information-loop/h_selective_invalidation_selftest.py",
    "execution-information-loop/admission_selftest.py",
    "simigo2-experimental/scripts/ordinary_task/run_phase_i.py",
    "simigo2-experimental/Sources/SimiGoTaskRun/main.swift",
    "simigo2-experimental/Sources/SimiGoTaskRun/TaskResultContract.swift",
    "simigo2-experimental/Sources/SimiGo2Experimental/ProductionRuntimeInformationIntegration.swift",
]


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


out = Path(sys.argv[1])
roots, absent, total = [], [], 0
for name in PROTECTED:
    root = RUNS / name
    if not root.is_dir():
        absent.append(str(root))
        continue
    entries = []
    for path in sorted(p for p in root.rglob("*") if p.is_file()):
        entries.append({"path": str(path.relative_to(root)), "sha256": sha(path)})
    roots.append({"root": str(root), "exists": True, "entries": entries})
    total += len(entries)
(out / "prechange-historical-snapshot.json").write_text(json.dumps({
    "protected_roots": roots, "absent_roots": absent, "total_files": total,
}, indent=2, sort_keys=True), encoding="utf-8")

src = {}
for rel in SOURCES:
    p = LAB / rel
    src[rel] = sha(p) if p.is_file() else None
(out / "prechange-source-sha256.json").write_text(json.dumps(
    {"files": src}, indent=2, sort_keys=True), encoding="utf-8")
print(json.dumps({"protected_files": total, "absent_roots": absent,
                  "source_files": len(src)}))
