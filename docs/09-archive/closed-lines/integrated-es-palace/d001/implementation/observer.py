"""Independent bounded observer for D-001 fixture decisions."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

BOUNDARY = hashlib.sha256(b"D001-PACKAGE-V1.0").hexdigest()
CASES = ["P-LAWFUL", "P-SETTLED", "P-BLOCKED", "N-MISSING", "N-STALE", "N-AMBIGUOUS", "N-ILLEGAL"]


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def classify(root: Path, case: str) -> dict:
    manifest = load(root / case / "fixture-manifest.json")
    required = [family for family in ("I1", "I2", "I4", "I5", "I6", "I8", "I10") if (root / case / manifest["primitives"][family]["path"]).exists()]
    missing = len(required) != 7 or not (root / case / manifest["primitives"]["I5"]["path"]).exists()
    invocation = load(root / case / "invocation.json")
    invocation_closed = set(invocation) == {"manifest_instance_id", "package_id", "stage", "schema_version", "opaque_locator", "schema_id"}
    if missing:
        decision = "MISSING_INFORMATION_BLOCK"
        reason = "mandatory I5 pointer is absent"
    else:
        closure = load(root / case / manifest["primitives"]["I1"]["path"])
        provenance = load(root / case / manifest["primitives"]["I4"]["path"])
        actions = load(root / case / manifest["primitives"]["I5"]["path"])["actions"]
        statuses = [provenance["records"][member["object_id"]]["status"] for member in closure["members"]]
        if any(status != "CURRENT" for status in statuses):
            decision = "STALE_INFORMATION_BLOCK"
            reason = "mandatory provenance is not current"
        elif len(actions) != 1:
            decision = "AMBIGUOUS_INFORMATION_BLOCK"
            reason = "mandatory pointers are not unique"
        elif actions[0]["boundary_digest"] != BOUNDARY:
            decision = "ILLEGAL_CONTINUATION_BLOCK"
            reason = "registered boundary is violated"
        elif actions[0]["continuation_class"] == "BLOCKED_LAWFUL_CONTINUATION":
            decision = "BLOCK"
            reason = "registered blocking condition applies"
        else:
            snapshot = load(root / case / manifest["primitives"]["I3"]["path"])
            decision = "REUSE" if snapshot["settled_record"] else "CONTINUE"
            reason = "settled identity is present" if snapshot["settled_record"] else "current lawful continuation"
    return {
        "case_id": case,
        "inventory_complete": len(manifest["primitives"]) == 10,
        "invocation_closed": invocation_closed,
        "observer_decision": decision,
        "reason": reason,
        "side_channels_denied": invocation_closed,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixtures", required=True)
    args = parser.parse_args()
    root = Path(args.fixtures).resolve()
    observations = [classify(root, case) for case in CASES]
    record = {
        "schema_id": "D001-OBSERVER-RECORD-V1",
        "observer_process": "independent",
        "expected_input_verdicts": "NOT_PROVIDED",
        "observations": observations,
        "result": "PASS" if all(item["inventory_complete"] and item["invocation_closed"] and item["side_channels_denied"] for item in observations) else "FAIL",
    }
    print(json.dumps(record, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
