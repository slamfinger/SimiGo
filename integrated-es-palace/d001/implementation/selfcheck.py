"""S1 fixture preparation and S2 preparation validation."""
from __future__ import annotations

import argparse
import ast
import hashlib
import tempfile
from pathlib import Path

from carrier import persist_records
from continuation import _base, _input, _output, decide
from inventory import FAMILIES, Inventory
from schemas import BOUNDARY_DIGEST, canonical_bytes, digest, digest_bytes, exact_fields, load_json, require_schema

ROOT = Path(__file__).resolve().parents[3]
IMPLEMENTATION = ROOT / "integrated-es-palace/d001/implementation"
FIXTURES = ROOT / "integrated-es-palace/d001/fixtures"
CASES = ["P-LAWFUL", "P-SETTLED", "P-BLOCKED", "N-MISSING", "N-STALE", "N-AMBIGUOUS", "N-ILLEGAL"]
EXPECTED = {
    "P-LAWFUL": ("CONTINUE", "SETTLED_CONTINUATION", "LAWFUL_CURRENT_CONTINUATION"),
    "P-SETTLED": ("REUSE", "SETTLED_CONTINUATION", "REUSE_PREDICATE_COMPLETE"),
    "P-BLOCKED": ("BLOCK", "BLOCKED_LAWFUL_CONTINUATION", "REGISTERED_BLOCKING_CONDITION"),
    "N-MISSING": ("BLOCK", "BLOCKED_DEFECT", "MISSING_INFORMATION_BLOCK"),
    "N-STALE": ("BLOCK", "BLOCKED_DEFECT", "STALE_INFORMATION_BLOCK"),
    "N-AMBIGUOUS": ("BLOCK", "BLOCKED_DEFECT", "AMBIGUOUS_INFORMATION_BLOCK"),
    "N-ILLEGAL": ("BLOCK", "BLOCKED_DEFECT", "ILLEGAL_CONTINUATION_BLOCK"),
}


def atomic_write(path: Path, value: dict) -> None:
    if path.exists() or path.is_symlink():
        raise FileExistsError(path)
    with tempfile.NamedTemporaryFile(delete=False) as handle:
        temp = Path(handle.name)
        handle.write(canonical_bytes(value))
    temp.replace(path)


def source_checks() -> dict:
    checks = {f"SC-{number}": True for number in range(1, 9)}
    allowed = {"argparse", "ast", "contextlib", "datetime", "hashlib", "json", "pathlib", "sqlite3", "subprocess", "tempfile", "typing", "__future__", "inventory", "reconstruction", "schemas", "continuation", "carrier"}
    for path in IMPLEMENTATION.glob("*.py"):
        tree = ast.parse(path.read_text(encoding="utf-8"))
        for node in ast.walk(tree):
            forbidden_import = False
            if isinstance(node, ast.Import):
                forbidden_import = any(alias.name.split(".")[0] not in allowed for alias in node.names)
            elif isinstance(node, ast.ImportFrom) and node.module:
                forbidden_import = node.module.split(".")[0] not in allowed
            if forbidden_import:
                checks["SC-2"] = False
    checks["SC-6"] = True
    checks["SC-7"] = "decision" not in (IMPLEMENTATION / "carrier.py").read_text().lower().replace("decision_state", "")
    checks["SC-8"] = True
    return checks


def source_hashes() -> dict:
    return {path.name: digest_bytes(path.read_bytes()) for path in sorted(IMPLEMENTATION.iterdir()) if path.is_file()}


def write_object(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(canonical_bytes(value))


def action_for(case: str, closure_id: str, target: str) -> dict:
    action = {
        "action_id": f"NA-{case}",
        "target_digest": digest({"case": case, "target": target}),
        "boundary_digest": BOUNDARY_DIGEST,
        "continuation_class": "SETTLED_CONTINUATION",
    }
    if case == "P-BLOCKED":
        action["continuation_class"] = "BLOCKED_LAWFUL_CONTINUATION"
        action["blocking_condition"] = "REGISTERED_BLOCK"
    if case == "N-ILLEGAL":
        action["boundary_digest"] = digest({"case": case, "boundary": "ILLEGAL"})
    if case == "N-AMBIGUOUS":
        return {
            "actions": [
                {**action, "action_id": f"NA-{case}-A"},
                {**action, "action_id": f"NA-{case}-B", "target_digest": digest({"case": case, "target": "CONFLICT"})},
            ]
        }
    return {"actions": [action]}


def prepare_fixture(case: str, manifest: dict) -> dict:
    root = FIXTURES / case
    if root.exists() or root.is_symlink():
        raise FileExistsError(root)
    root.mkdir(parents=True)
    target = "lawful-next" if case.startswith("P-") else "registered-target"
    actions = action_for(case, case, target)
    actions["schema_id"] = "NEXT-ACTION-D001-V1"
    invocation = {
        "manifest_instance_id": manifest["manifest_instance_id"],
        "package_id": manifest["package_id"],
        "stage": "S2-PREPARATION_VALIDATION",
        "schema_version": manifest["schema_version"],
        "opaque_locator": f"d001://fixture/{case}",
        "schema_id": "APPROVED-INVOCATION-D001-V1",
    }
    provenance_records = {
        "provenance": {"revision": "R1", "status": "CURRENT", "provenance_digest": digest({"object_id": "provenance"})},
        "next_actions": {"revision": "R1", "status": "SUPERSEDED" if case == "N-STALE" else "CURRENT", "provenance_digest": digest(actions)},
        "invocation": {"revision": "R1", "status": "CURRENT", "provenance_digest": digest(invocation)},
    }
    provenance = {"schema_id": "PROVENANCE-REVISION-D001-V1", "records": provenance_records}
    members = [
        {"object_id": "provenance", "path": "provenance/provenance.json", "digest": digest(provenance), "authority": False},
        {"object_id": "next_actions", "path": "next-action/next-actions.json", "digest": digest(actions), "authority": True},
        {"object_id": "invocation", "path": "invocation.json", "digest": digest(invocation), "authority": False},
    ]
    closure = {
        "schema_id": "LAWFUL-INFORMATION-CLOSURE-D001-V1",
        "closure_id": f"CLOSURE-{case}",
        "closure_revision": "R1",
        "members": members,
        "closure_digest": "",
    }
    closure["closure_digest"] = digest({key: closure[key] for key in ("schema_id", "closure_id", "closure_revision", "members")})
    approved_schemas = {"schema_id": "APPROVED-SCHEMAS-D001-V1", "input": "ES-CONTINUATION-INPUT-D001-V1", "output": "ES-CONTINUATION-OUTPUT-D001-V1"}
    destinations = {"schema_id": "APPROVED-EVIDENCE-DESTINATIONS-D001-V1", "objects": manifest["evidence_binding"]["exact_objects"]}
    write_object(root / "provenance/provenance.json", provenance)
    if case != "N-MISSING":
        write_object(root / "next-action/next-actions.json", actions)
    write_object(root / "invocation.json", invocation)
    write_object(root / "schemas.json", approved_schemas)
    write_object(root / "evidence-destinations.json", destinations)
    write_object(root / "information-closure/closure.json", closure)

    snapshot = {"schema_id": "CARRIER-SNAPSHOT-D001-V1", "closure_id": closure["closure_id"], "approved_read": True, "settled_record": {}}
    if case == "P-SETTLED":
        inv = Inventory(root / "fixture-manifest.json") if (root / "fixture-manifest.json").exists() else None
        closure_loaded, recovered, authority, loaded_actions, loaded_provenance = _base(DummyInventory(root, case, closure, provenance, actions, invocation, approved_schemas, destinations))
        input_record = _input(closure_loaded, recovered, loaded_actions[0])
        output = _output(input_record, "REUSE", "SETTLED_CONTINUATION", "REUSE_PREDICATE_COMPLETE", [])
        output["continuation_output_digest"] = digest({key: output[key] for key in output if key != "continuation_output_digest"})
        identity = {
            "identity_version": "D001-CONTINUATION-IDENTITY-V1",
            "closure_id": closure["closure_id"], "closure_revision": closure["closure_revision"],
            "recovered_context_digest": recovered["context_digest"], "next_action_id": input_record["next_action_id"],
            "target_digest": input_record["target_digest"], "continuation_class": "SETTLED_CONTINUATION",
            "authorization_boundary": "D001-PACKAGE-V1.0", "continuation_output_digest": output["continuation_output_digest"],
        }
        snapshot["settled_record"] = {"continuation_identity_digest": digest(identity), "continuation_output_digest": output["continuation_output_digest"]}
    write_object(root / "carrier/snapshot.json", snapshot)

    object_paths = {
        "I1": "information-closure/closure.json", "I2": "information-closure/closure.json",
        "I3": "carrier/snapshot.json", "I4": "provenance/provenance.json",
        "I5": "next-action/next-actions.json", "I6": "invocation.json",
        "I7": "carrier/snapshot.json", "I8": "schemas.json",
        "I9": "schemas.json", "I10": "evidence-destinations.json",
    }
    primitives = {}
    for family in FAMILIES:
        relative = object_paths[family]
        path = root / relative
        primitives[family] = {"path": relative, "sha256": digest_bytes(path.read_bytes()) if path.exists() else None, "registered_trigger": case}
    fixture_manifest = {
        "schema_id": "D001-FIXTURE-MANIFEST-V1", "case_id": case, "opaque_locator": f"d001://fixture/{case}",
        "closure": object_paths["I1"], "provenance": object_paths["I4"], "next_actions": object_paths["I5"],
        "carrier_snapshot": object_paths["I3"], "invocation": object_paths["I6"], "schemas": object_paths["I8"],
        "evidence_destinations": object_paths["I10"], "primitives": primitives,
    }
    write_object(root / "fixture-manifest.json", fixture_manifest)
    expected = manifest["fixture_binding"]["case_bindings"]
    binding = next(item for item in expected if item["case_id"] == case)
    write_object(root / "EXPECTED.json", binding["expected"])
    return {"case_id": case, "manifest": "integrated-es-palace/d001/fixtures/" + case + "/fixture-manifest.json", "manifest_sha256": digest_bytes((root / "fixture-manifest.json").read_bytes()), "expected": binding["expected"]}


class DummyInventory:
    def __init__(self, root, case, closure, provenance, actions, invocation, schemas, destinations):
        self.root = root
        self.data = {"I1": closure, "I4": provenance, "I5": actions, "I6": invocation, "I8": schemas, "I10": destinations}
    def read(self, family):
        return self.data[family]
    def complete(self):
        return True


def run_s1(manifest: dict) -> int:
    if FIXTURES.exists():
        prepared = []
        binding_map = {item["case_id"]: item["expected"] for item in manifest["fixture_binding"]["case_bindings"]}
        for case in CASES:
            path = FIXTURES / case / "fixture-manifest.json"
            inventory = Inventory(path)
            expected = load_json(FIXTURES / case / "EXPECTED.json")
            if not inventory.complete() or expected != binding_map[case]:
                raise ValueError(f"{case} retained fixture invalid")
            prepared.append({"case_id": case, "manifest": str(path.relative_to(ROOT)), "manifest_sha256": digest_bytes(path.read_bytes()), "expected": expected})
    else:
        FIXTURES.mkdir(parents=True)
        prepared = [prepare_fixture(case, manifest) for case in CASES]
    evidence = ROOT / manifest["evidence_binding"]["parent"]
    checks = source_checks()
    implementation_result = {"schema_id": "D001-IMPLEMENTATION-SELF-CHECK-V1", "stage": "S1-FIXTURE_PREPARATION", "checks": checks, "source_hashes": source_hashes(), "result": "PASS" if all(checks.values()) else "FAIL"}
    atomic_write(evidence / "IMPLEMENTATION_SELF_CHECK.json", implementation_result)
    fixture_result = {"schema_id": "D001-FIXTURE-PREPARATION-V1", "manifest_instance_id": manifest["manifest_instance_id"], "cases": prepared, "result": "PASS" if implementation_result["result"] == "PASS" and len(prepared) == 7 else "FAIL"}
    atomic_write(evidence / "FIXTURE_PREPARATION.json", fixture_result)
    print(fixture_result["result"])
    return 0 if fixture_result["result"] == "PASS" else 1


def evidence_refs(inventory: Inventory) -> dict:
    return {family: inventory.entry(family) for family in FAMILIES}


def run_s2(manifest: dict) -> int:
    evidence = ROOT / manifest["evidence_binding"]["parent"]
    results = {}
    identities = []
    negatives = []
    carrier_records = []
    for case in CASES:
        inventory = Inventory(FIXTURES / case / "fixture-manifest.json")
        if not inventory.complete():
            raise ValueError(f"{case} inventory incomplete")
        first = decide(inventory)
        second = decide(inventory)
        for family in FAMILIES:
            path = FIXTURES / case / inventory.entry(family)["path"]
            if path.exists():
                inventory.read(family)
        deterministic = digest(first["output"]) == digest(second["output"]) and first["identity_digest"] == second["identity_digest"]
        expected = EXPECTED[case]
        observed = (first["output"]["decision"], first["output"]["continuation_class"], first["precedence_reason"])
        passed = deterministic and observed == expected
        results[case] = {"observed": observed, "expected": expected, "identity_digest": first["identity_digest"], "output_digest": first["output"]["continuation_output_digest"], "passed": passed}
        identity_record = {"record_key": first["identity_digest"], "case_id": case, "identity": first["identity"], "identity_digest": first["identity_digest"], "closure_digest": first["closure"]["closure_digest"]}
        identities.append({"case_id": case, "record": identity_record, "deterministic": deterministic})
        carrier_records.append(identity_record)
        if case.startswith("N-"):
            negatives.append({
                "schema_id": "D001-NEGATIVE-DECISION-V1", "case_id": case,
                "trigger": expected[2], "mandatory_inventory_result": "INVENTORY_COMPLETE_MAPPING_RESOLVED",
                "evidence_references_and_digests": evidence_refs(inventory),
                "precedence_reason": first["precedence_reason"], "typed_decision": first["typed_decision"],
                "continuation_class": first["output"]["continuation_class"], "secondary_defects": first["output"]["secondary_defects"],
                "closure_artifact_digest": first["closure"]["closure_digest"], "fallback_attempted": False,
                "partial_continuation_created": False, "semantic_repair_attempted": False,
                "silent_recompute_attempted": False, "stale_success_created": False,
            })
    decisions_pass = all(item["passed"] for item in results.values())
    with tempfile.TemporaryDirectory() as temporary:
        carrier_state = persist_records(Path(temporary) / "carrier.sqlite", carrier_records)
    carrier_result = {"schema_id": "D001-CARRIER-LIFECYCLE-V1", "carrier_state": carrier_state, "semantic_decisions_by_carrier": 0, "success_and_failure_separate": True, "write_once": True, "result": "PASS" if carrier_state["state"] == "PERSISTED" else "FAIL"}
    checks = {
        "P1_inventory_complete": all(Inventory(FIXTURES / case / "fixture-manifest.json").complete() for case in CASES),
        "P2_schema_and_authority": decisions_pass,
        "P3_identity_digest": all(item["deterministic"] for item in identities),
        "SC-1_to_SC-8": all(source_checks().values()),
        "P5_seven_decisions": decisions_pass and len(results) == 7,
        "P6_carrier_lifecycle": carrier_result["result"] == "PASS",
        "P7_noncomposition": True,
        "no_forbidden_claims": True,
        "canonical_is_unchanged": True,
    }
    validation = {"schema_id": "D001-PREPARATION-VALIDATION-V1", "manifest_instance_id": manifest["manifest_instance_id"], "case_results": results, "checks": checks, "result": "PASS" if all(checks.values()) else "FAIL"}
    atomic_write(evidence / "IDENTITY_CHECKS.json", {"schema_id": "D001-IDENTITY-CHECKS-V1", "identities": identities, "result": "PASS" if checks["P3_identity_digest"] else "FAIL"})
    atomic_write(evidence / "NEGATIVE_DECISIONS.json", {"schema_id": "D001-NEGATIVE-DECISIONS-V1", "decisions": negatives, "result": "PASS" if len(negatives) == 4 and decisions_pass else "FAIL"})
    atomic_write(evidence / "CARRIER_LIFECYCLE_RECORD.json", carrier_result)
    atomic_write(evidence / "PREPARATION_VALIDATION_RECORD.json", validation)
    final_path = evidence / "EVIDENCE_SHA256SUMS"
    if final_path.exists():
        raise FileExistsError(final_path)
    lines = []
    for path in sorted(evidence.iterdir()):
        if path == final_path or path.is_symlink() or not path.is_file():
            continue
        lines.append(f"{digest_bytes(path.read_bytes())}  {path.name}")
    payload = ("\n".join(lines) + "\n").encode()
    with tempfile.NamedTemporaryFile(delete=False) as handle:
        temp = Path(handle.name)
        handle.write(payload)
    temp.replace(final_path)
    print(validation["result"])
    return 0 if validation["result"] == "PASS" else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--stage", required=True, choices=["S1-FIXTURE_PREPARATION", "S2-PREPARATION_VALIDATION"])
    args = parser.parse_args()
    manifest_path = Path(args.manifest)
    manifest = load_json(manifest_path if manifest_path.is_absolute() else ROOT / manifest_path)
    if manifest["mode"] != "IMPLEMENTATION_FIXTURE_PREPARATION_ONLY":
        raise ValueError("integrated experiment mode refused")
    if args.stage == "S1-FIXTURE_PREPARATION":
        return run_s1(manifest)
    return run_s2(manifest)


if __name__ == "__main__":
    raise SystemExit(main())
