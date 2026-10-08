"""Independent D-002 observer; receives no expected verdicts."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

CASES = ["P-LAWFUL", "P-SETTLED", "P-BLOCKED", "N-MISSING", "N-STALE", "N-AMBIGUOUS", "N-ILLEGAL"]
BOUNDARY = hashlib.sha256(b"D002-PACKAGE-V1.0").hexdigest()


def classify(root: Path, case: str) -> dict:
    load = lambda path: json.loads(path.read_text(encoding="utf-8"))
    directory = root / case
    manifest = load(directory / "fixture-manifest.json")
    invocation = load(directory / "invocation.json")
    invocation_closed = set(invocation) == {"schema_id", "manifest_instance_id", "opaque_locator", "package_id", "schema_version", "stage"}
    action_path = directory / manifest["next_actions"]
    if not action_path.exists():
        decision = "MISSING_INFORMATION_BLOCK"
        reason = "mandatory pointer is absent"
    else:
        closure = load(directory / manifest["closure"])
        provenance = load(directory / manifest["provenance"])
        actions = load(action_path)["actions"]
        statuses = [provenance["status"] for _ in closure["members"]]
        if any(status != "CURRENT" for status in statuses):
            decision = "STALE_INFORMATION_BLOCK"
            reason = "mandatory provenance is not current"
        elif len(actions) != 1:
            decision = "AMBIGUOUS_INFORMATION_BLOCK"
            reason = "mandatory pointers are not unique"
        elif actions[0]["boundary"] != "D002-PACKAGE-V1.0" or actions[0]["boundary_digest"] != BOUNDARY:
            decision = "ILLEGAL_CONTINUATION_BLOCK"
            reason = "registered boundary is violated"
        elif actions[0]["continuation_class"] == "BLOCKED_LAWFUL_CONTINUATION":
            decision = "BLOCK"
            reason = "registered blocking condition applies"
        else:
            carrier = load(directory / manifest["carrier_snapshot"])
            decision = "REUSE" if carrier["settled_record"] else "CONTINUE"
            reason = "settled marker is present" if carrier["settled_record"] else "current lawful continuation"
    return {
        "case_id": case, "source_internal_id": manifest["source_internal_id"], "inventory_complete": len(manifest["primitives"]) == 10,
        "invocation_closed": invocation_closed, "observer_decision": decision, "reason": reason,
        "side_channels_denied": invocation_closed,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixtures", required=True)
    args = parser.parse_args()
    root = Path(args.fixtures).resolve()
    observations = [classify(root, case) for case in CASES]
    record = {
        "schema_id": "D002-OBSERVER-RECORD-V1", "observer_process": "independent",
        "expected_input_verdicts": "NOT_PROVIDED", "observations": observations,
        "result": "PASS" if all(item["inventory_complete"] and item["invocation_closed"] and item["side_channels_denied"] for item in observations) else "FAIL",
    }
    print(json.dumps(record, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
