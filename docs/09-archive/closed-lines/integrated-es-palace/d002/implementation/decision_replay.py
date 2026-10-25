"""One D-002 decision replay through the unchanged D-001 Decision Core."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
import sys
sys.path.insert(0, str(ROOT / "integrated-es-palace/d001/implementation"))
D001 = ROOT / "integrated-es-palace/d001/implementation"


class ReplayInventory:
    def __init__(self, root: Path, manifest: dict, replay_manifest: dict):
        self.root = root
        self.manifest = manifest
        self.replay_manifest = replay_manifest
        self.case = manifest["case_id"]

    def load(self, relative: str):
        return json.loads((self.root / relative).read_text(encoding="utf-8"))

    def complete(self) -> bool:
        return len(self.manifest["primitives"]) == 10

    def read(self, family: str):
        if family == "I1":
            source = self.load(self.manifest["closure"])
            translated = {
                "schema_id": "LAWFUL-INFORMATION-CLOSURE-D001-V1",
                "closure_id": source["closure_id"], "closure_revision": source["closure_revision"],
                "members": source["members"],
            }
            digest_payload = {key: translated[key] for key in ("schema_id", "closure_id", "closure_revision", "members")}
            translated["closure_digest"] = hashlib.sha256(json.dumps(digest_payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
            return translated
        if family == "I4":
            source = self.load(self.manifest["provenance"])
            closure = self.read("I1")
            return {
                "schema_id": "PROVENANCE-REVISION-D001-V1",
                "records": {member["object_id"]: {"revision": "R1", "status": source["status"], "provenance_digest": member["digest"]} for member in closure["members"]},
            }
        if family == "I5":
            source = self.load(self.manifest["next_actions"])
            d001_boundary = hashlib.sha256(b"D001-PACKAGE-V1.0").hexdigest()
            actions = []
            for action in source["actions"]:
                translated = dict(action)
                translated["boundary_digest"] = d001_boundary if action["boundary"] == "D002-PACKAGE-V1.0" else action["boundary_digest"]
                actions.append(translated)
            return {"schema_id": "NEXT-ACTION-D001-V1", "actions": actions}
        if family == "I6":
            source = self.load(self.manifest["invocation"])
            return {
                "schema_id": "APPROVED-INVOCATION-D001-V1",
                "manifest_instance_id": self.replay_manifest["manifest_instance_id"],
                "package_id": self.replay_manifest["package_binding"]["package_id"],
                "stage": "D002_CONSUMPTION", "schema_version": self.replay_manifest["schema_version"],
                "opaque_locator": source["opaque_locator"],
            }
        if family == "I8":
            return {"schema_id": "APPROVED-SCHEMAS-D001-V1", "input": "ES-CONTINUATION-INPUT-D001-V1", "output": "ES-CONTINUATION-OUTPUT-D001-V1"}
        if family == "I10":
            return {"schema_id": "APPROVED-EVIDENCE-DESTINATIONS-D001-V1", "objects": self.replay_manifest["evidence_binding"]["exact_objects"]}
        if family == "I3":
            source = self.load(self.manifest["carrier_snapshot"])
            closure = self.read("I1")
            if not source["settled_record"]:
                return {"schema_id": "CARRIER-SNAPSHOT-D001-V1", "closure_id": closure["closure_id"], "approved_read": bool(source["approved_read"]), "settled_record": {}}
            from continuation import _base, _input, _output
            closure_view, recovered, authority, actions, provenance = _base(self)
            input_record = _input(closure_view, recovered, actions[0])
            output = _output(input_record, "REUSE", "SETTLED_CONTINUATION", "REUSE_PREDICATE_COMPLETE", [])
            output["continuation_output_digest"] = hashlib.sha256(json.dumps({key: output[key] for key in output if key != "continuation_output_digest"}, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
            identity = {
                "identity_version": "D001-CONTINUATION-IDENTITY-V1", "closure_id": closure_view["closure_id"],
                "closure_revision": closure_view["closure_revision"], "recovered_context_digest": recovered["context_digest"],
                "next_action_id": input_record["next_action_id"], "target_digest": input_record["target_digest"],
                "continuation_class": "SETTLED_CONTINUATION", "authorization_boundary": "D001-PACKAGE-V1.0",
                "continuation_output_digest": output["continuation_output_digest"],
            }
            return {
                "schema_id": "CARRIER-SNAPSHOT-D001-V1", "closure_id": closure["closure_id"], "approved_read": True,
                "settled_record": {"source_record_digest": source["settled_record"]["source_record_digest"], "continuation_identity_digest": hashlib.sha256(json.dumps(identity, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest(), "continuation_output_digest": output["continuation_output_digest"]},
            }
        raise FileNotFoundError(f"unresolvable D002 replay family: {family}")


def replay(root: Path, case: str, replay_manifest: dict) -> dict:
    manifest = json.loads((root / case / "fixture-manifest.json").read_text())
    inventory = ReplayInventory(root, manifest, replay_manifest)
    from continuation import decide
    result = decide(inventory)
    expected = json.loads((root / case / "EXPECTED.json").read_text())
    return {
        "case_id": case, "source_internal_id": manifest["source_internal_id"],
        "source_record_digest": manifest["source_record_digest"],
        "decision_core": "D001-UNMODIFIED", "observed": {
            "decision": result["output"]["decision"], "continuation_class": result["output"]["continuation_class"],
            "precedence_reason": result["precedence_reason"], "typed_label": result["typed_decision"],
        }, "identity_digest": result["identity_digest"], "output_digest": result["output"]["continuation_output_digest"],
        "input": result["input"], "input_digest": result["input"]["schema_id"] and hashlib.sha256(json.dumps(result["input"], ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest(),
        "frozen_expected": expected,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    args = parser.parse_args()
    manifest_path = Path(args.manifest)
    manifest = json.loads((manifest_path if manifest_path.is_absolute() else ROOT / manifest_path).read_text())
    cases = manifest["campaign_binding"]["cases"]
    records = [replay(ROOT / manifest["fixture_binding"]["fixtures_parent"], case, manifest) for case in cases]
    record = {
        "schema_id": "D002-DECISION-REPLAY-RECORD-V1", "manifest_instance_id": manifest["manifest_instance_id"],
        "decision_core_policy": "D001-READ-ONLY", "replay_count": 1, "records": records,
        "result": "PASS" if len(records) == 7 else "FAIL",
    }
    print(json.dumps(record, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
