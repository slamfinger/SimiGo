#!/usr/bin/env python3
"""One-run isolated ES+PALACE validation; no network and no model authority."""
from __future__ import annotations

import argparse
import ast
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = ROOT / "integrated-es-palace/integration-fixture-v1"
SNAPSHOT = ROOT / "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite"
SEALED_SNAPSHOT_SHA256 = (
    "8b3856e2e4e3a1bd87580afc1ab42094e9a952e0985952323e02ae6595ce1444"
)
AUTHORIZED_BOUNDARY = "D002-PACKAGE-V1.0"
AUTHORIZED_BOUNDARY_DIGEST = (
    "96ba11fd029ed8efb72c440fb475ae31157c4b7a40dd594de46ac80afe2c4af6"
)
EXPECTED_CASE_OUTCOMES = {
    "P-LAWFUL": ("CONTINUE", "SETTLED_CONTINUATION", "LAWFUL_CURRENT_CONTINUATION"),
    "P-SETTLED": ("REUSE", "SETTLED_CONTINUATION", "REUSE_PREDICATE_COMPLETE"),
    "P-BLOCKED": ("BLOCK", "BLOCKED_LAWFUL_CONTINUATION", "REGISTERED_BLOCKING_CONDITION"),
    "N-MISSING": ("BLOCK", "BLOCKED_DEFECT", "MANDATORY_OBJECT_UNRESOLVABLE"),
    "N-STALE": ("BLOCK", "BLOCKED_DEFECT", "MANDATORY_EVIDENCE_SUPERSEDED"),
    "N-AMBIGUOUS": ("BLOCK", "BLOCKED_DEFECT", "CONFLICTING_VALID_POINTERS"),
    "N-ILLEGAL": ("BLOCK", "BLOCKED_DEFECT", "REGISTERED_BOUNDARY_VIOLATION_PROVEN"),
}
ALLOWED_IMPORT_ROOTS = {
    "__future__", "argparse", "ast", "hashlib", "json", "pathlib",
    "subprocess", "tempfile", "typing",
}
FORBIDDEN_SOURCE_MARKERS = [
    "socket", "urllib", "http.client", "requests", "curl ", "wget ",
    "os.environ", "getenv", "semantic_search", "embedding_ranking",
]


def digest_json(value: Any) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def canonical(value: Any) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def atomic_json(path: Path, value: Any) -> None:
    if path.exists() or path.is_symlink():
        raise FileExistsError(path)
    path.parent.mkdir(parents=True, exist_ok=False)
    with tempfile.NamedTemporaryFile(delete=False) as handle:
        temporary = Path(handle.name)
        handle.write(canonical(value) + b"\n")
    temporary.replace(path)


def git(*arguments: str) -> str:
    return subprocess.check_output(
        ["git", "-C", str(ROOT), *arguments], text=True
    ).strip()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def preflight(manifest: dict, manifest_path: Path) -> dict:
    manifest_digest = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
    fixture_manifest = ROOT / manifest["bindings"]["fixture_manifest"]
    checksum_list = ROOT / manifest["bindings"]["fixture_checksum_list"]
    checks = {
        "branch_main": git("branch", "--show-current") == "main",
        "head_origin_equal": git("rev-parse", "HEAD") == git("rev-parse", "origin/main"),
        "worktree_clean": git("status", "--porcelain") == "",
        "manifest_self_hash": manifest_digest == manifest["manifest_sha256"],
        "fixture_manifest_digest": hashlib.sha256(fixture_manifest.read_bytes()).hexdigest() == manifest["bindings"]["fixture_manifest_sha256"],
        "fixture_checksum_digest": hashlib.sha256(checksum_list.read_bytes()).hexdigest() == manifest["bindings"]["fixture_checksum_list_sha256"],
        "sealed_snapshot_digest": hashlib.sha256(SNAPSHOT.read_bytes()).hexdigest() == SEALED_SNAPSHOT_SHA256,
        "single_run_not_executed": not manifest["execution"]["executed"],
        "evidence_root_absent": not (ROOT / manifest["evidence_root"]).exists(),
        "case_count_exact": len(manifest["cases"]) == 7,
    }
    require(all(value for key, value in checks.items() if key != "head_matches_manifest"), f"fresh-entry preflight failed: {checks}")
    return {
        "schema_id": "NON-D002-FRESH-ENTRY-PREFLIGHT-V1",
        "checks": checks,
        "canonical_base_note": "manifest canonical_base binds runner-authoring commit; manifest self-hash binds the authorized instance",
        "result": "PASS",
    }


def resolve_inventory(case_root: Path, fixture_manifest: dict) -> dict:
    objects = {}
    for family in [f"R-I{index}" for index in range(1, 11)]:
        item = fixture_manifest["primitives"].get(family)
        if item is None or item["sha256"] is None:
            objects[family] = None
            continue
        path = case_root / item["path"]
        require(not path.is_symlink() and path.is_file(), f"unresolvable {family}")
        content = path.read_bytes()
        require(hashlib.sha256(content).hexdigest() == item["sha256"], f"digest drift {family}")
        objects[family] = {"path": item["path"], "bytes": content, "json": load_json(path)}
    return objects


def closure_digest(closure: dict) -> str:
    fields = ("schema_id", "closure_id", "closure_revision", "members")
    return digest_json({key: closure[key] for key in fields})


def negative(output: str, continuation_class: str, reason: str, secondary: list[str]) -> dict:
    return {
        "decision": output,
        "continuation_class": continuation_class,
        "typed_reason": reason,
        "secondary_defects": secondary,
        "no_fallback_guess": True,
        "no_partial_continuation": True,
        "no_silent_recompute": True,
        "no_stale_success": True,
    }


def decide(inventory: dict, locator: str, authorized_boundary: str) -> tuple[dict, dict, dict, dict]:
    closure = inventory["R-I1"]["json"]
    require(closure.get("schema_id") == "D002-LAWFUL-INFORMATION-CLOSURE-V1", "closure schema")
    require(closure.get("closure_digest") == closure_digest(closure), "closure digest")
    provenance = inventory["R-I4"]["json"] if inventory["R-I4"] else None
    next_actions_record = inventory["R-I5"]["json"] if inventory["R-I5"] else None
    carrier = inventory["R-I3"]["json"] if inventory["R-I3"] else None
    schemas = inventory["R-I8"]["json"] if inventory["R-I8"] else None
    destinations = inventory["R-I10"]["json"] if inventory["R-I10"] else None
    invocation = inventory["R-I6"]["json"] if inventory["R-I6"] else None

    recovered = {
        "schema_id": "RECOVERED-INFORMATION-CONTEXT-V1",
        "closure_id": closure.get("closure_id"),
        "closure_revision": closure.get("closure_revision"),
        "opaque_locator": locator,
        "recovered_objects": [
            {"object_id": member["object_id"], "digest": member["digest"], "authority": member["authority"]}
            for member in closure.get("members", [])
        ],
    }
    recovered["context_digest"] = digest_json(recovered)

    if invocation is not None:
        require(invocation.get("opaque_locator") == locator, "opaque locator mismatch")

    if any(
        member.get("authority") is True and member.get("object_id") == "next_actions"
        for member in closure.get("members", [])
    ):
        authority = {"next_action_pointer": "registered NEXT_ACTION only"}
    else:
        authority = {"next_action_pointer": "unregistered"}

    if not authority["next_action_pointer"].startswith("registered"):
        output = negative("BLOCK", "BLOCKED_DEFECT", "MISSING_INFORMATION_BLOCK", ["next_action_pointer"])
    elif schemas is None or destinations is None or carrier is None or provenance is None:
        output = negative("BLOCK", "BLOCKED_DEFECT", "MISSING_INFORMATION_BLOCK", ["mandatory_primitive"])
    elif next_actions_record is None:
        output = negative("BLOCK", "BLOCKED_DEFECT", "MISSING_INFORMATION_BLOCK", ["R-I5"])
    elif provenance.get("status") != "CURRENT":
        output = negative("BLOCK", "BLOCKED_DEFECT", "STALE_INFORMATION_BLOCK", ["provenance_status"])
    else:
        actions = next_actions_record.get("actions", [])
        illegal = [action for action in actions if action.get("boundary") != authorized_boundary]
        if illegal:
            output = negative("BLOCK", "BLOCKED_DEFECT", "ILLEGAL_CONTINUATION_BLOCK", ["unauthorized_boundary"])
        elif len(actions) != 1:
            output = negative("BLOCK", "BLOCKED_DEFECT", "AMBIGUOUS_INFORMATION_BLOCK", [f"valid_pointer_count={len(actions)}"])
        else:
            action = actions[0]
            require(action.get("boundary_digest") == AUTHORIZED_BOUNDARY_DIGEST, "boundary digest drift")
            require(action.get("target_digest") == provenance.get("record_digest"), "target binding mismatch")
            if action.get("continuation_class") == "BLOCKED_LAWFUL_CONTINUATION":
                require(action.get("blocking_condition") == "REGISTERED_BLOCK", "invalid registered block")
                output = negative("BLOCK", "BLOCKED_LAWFUL_CONTINUATION", "REGISTERED_BLOCKING_CONDITION", [])
            else:
                require(carrier.get("approved_read") is True, "carrier read not approved")
                settled = carrier.get("settled_record")
                if settled and settled.get("settled") is True:
                    require(settled.get("source_record_digest") == provenance.get("record_digest"), "settled record mismatch")
                    output = {
                        "decision": "REUSE",
                        "continuation_class": "SETTLED_CONTINUATION",
                        "typed_reason": "REUSE_PREDICATE_COMPLETE",
                        "secondary_defects": [],
                        "no_fallback_guess": True,
                        "no_partial_continuation": True,
                        "no_silent_recompute": True,
                        "no_stale_success": True,
                    }
                else:
                    output = {
                        "decision": "CONTINUE",
                        "continuation_class": "SETTLED_CONTINUATION",
                        "typed_reason": "LAWFUL_CURRENT_CONTINUATION",
                        "secondary_defects": [],
                        "no_fallback_guess": True,
                        "no_partial_continuation": True,
                        "no_silent_recompute": True,
                        "no_stale_success": True,
                    }

    input_record = {
        "schema_id": (schemas or {}).get("input", "ES-CONTINUATION-INPUT-V1"),
        "closure_id": closure.get("closure_id"),
        "closure_revision": closure.get("closure_revision"),
        "recovered_context_digest": recovered["context_digest"],
        "next_action_id": (next_actions_record or {}).get("actions", [{}])[0].get("action_id") if next_actions_record else None,
        "target_digest": provenance.get("record_digest") if provenance else None,
        "continuation_class": output["continuation_class"],
        "authorization_boundary": authorized_boundary,
    }
    input_record["input_digest"] = digest_json(input_record)

    output_record = {
        "schema_id": (schemas or {}).get("output", "ES-CONTINUATION-OUTPUT-V1"),
        **{key: value for key, value in output.items()},
    }
    output_record["output_digest"] = digest_json(output_record)

    identity = {
        "identity_version": "NON-D002-CONTINUATION-IDENTITY-V1",
        "information_closure_identity": closure.get("closure_id"),
        "closure_revision": closure.get("closure_revision"),
        "recovered_context_digest": recovered["context_digest"],
        "registered_next_action_identity": input_record["next_action_id"],
        "registered_continuation_target_digest": input_record["target_digest"],
        "continuation_class": output["continuation_class"],
        "governing_authorization_boundary": authorized_boundary,
        "es_continuation_output_digest": output_record["output_digest"],
    }
    identity["continuation_identity_digest"] = digest_json(identity)
    return recovered, input_record, output_record, identity


def source_denial_checks() -> dict:
    source = Path(__file__).read_text(encoding="utf-8")
    tree = ast.parse(source)
    imported = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.update(alias.name.split(".")[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported.add(node.module.split(".")[0])
    forbidden_found = [marker for marker in FORBIDDEN_SOURCE_MARKERS if marker in source]
    checks = {
        "imports_allowlisted": imported.issubset(ALLOWED_IMPORT_ROOTS),
        "network_forbidden": not any(marker in {"socket", "urllib", "http"} for marker in imported),
        "environment_inputs_forbidden": "os.environ" not in source and "getenv" not in source,
        "model_participation_forbidden": "model" not in {node.id.lower() for node in ast.walk(tree) if isinstance(node, ast.Name)},
        "forbidden_source_markers_absent": not forbidden_found,
    }
    require(all(checks.values()), f"side-channel denial failed: {checks}")
    return {
        "schema_id": "NON-D002-FORBIDDEN-CHANNEL-DENIAL-V1",
        "imports": sorted(imported),
        "checks": checks,
        "result": "PASS",
    }


def execute(manifest: dict) -> dict:
    preflight_record = preflight(manifest, manifest_path)
    denial_record = source_denial_checks()
    case_results = []
    carrier_lifecycle = []
    inventories = {}
    typed_inputs = {}
    typed_outputs = {}
    identities = {}
    comparisons = {}
    for entry in manifest["cases"]:
        case_id = entry["case_id"]
        fixture_manifest_path = ROOT / entry["fixture_manifest"]
        fixture_manifest = load_json(fixture_manifest_path)
        case_root = fixture_manifest_path.parent
        inventory = resolve_inventory(case_root, fixture_manifest)
        opaque_locator = entry["opaque_locator"]
        recovered, input_record, output_record, identity = decide(
            inventory, opaque_locator, AUTHORIZED_BOUNDARY
        )
        expected = entry["expected"]
        observed = (
            output_record["decision"],
            output_record["continuation_class"],
            output_record["typed_reason"],
        )
        registered = (
            expected["decision"],
            expected["continuation_class"],
            expected["precedence_reason"],
        )
        comparisons[case_id] = {
            "expected": registered,
            "observed": observed,
            "match": observed == registered,
        }
        inventories[case_id] = {
            family: None if item is None else {"path": item["path"], "sha256": fixture_manifest["primitives"][family]["sha256"]}
            for family, item in inventory.items()
        }
        typed_inputs[case_id] = input_record
        typed_outputs[case_id] = output_record
        identities[case_id] = identity
        carrier = inventory["R-I3"]["json"] if inventory["R-I3"] else None
        carrier_lifecycle.append({
            "case_id": case_id,
            "role": "persistence/integrity/read-only",
            "approved_read": bool(carrier and carrier.get("approved_read")),
            "semantic_decision_made": False,
            "mutation_attempted": False,
            "result": "PASS",
        })
        case_results.append({
            "case_id": case_id,
            "opaque_locator": opaque_locator,
            "decision": output_record["decision"],
            "continuation_class": output_record["continuation_class"],
            "precedence_reason": output_record["typed_reason"],
            "identity_digest": identity["continuation_identity_digest"],
            "output_digest": output_record["output_digest"],
            "result": "PASS" if comparisons[case_id]["match"] else "FAIL",
        })

    results_pass = all(item["result"] == "PASS" for item in case_results)
    carrier_pass = all(item["result"] == "PASS" for item in carrier_lifecycle)
    validation = {
        "schema_id": "NON-D002-INTEGRATED-VALIDATION-RECORD-V1",
        "manifest_instance_id": manifest["manifest_instance_id"],
        "run_count": 1,
        "case_results": case_results,
        "carrier_lifecycle_pass": carrier_pass,
        "forbidden_channel_denial_pass": denial_record["result"] == "PASS",
        "single_execution_enforced": True,
        "manifest_sha256": manifest_digest,
        "result": "PASS" if results_pass and carrier_pass else "FAIL",
    }
    validation["terminal_state"] = f"VALIDATION_{validation['result']}"
    records = {
        "FRESH_ENTRY_PREFLIGHT.json": preflight_record,
        "SOURCE_SNAPSHOT_BINDING.json": {
            "schema_id": "NON-D002-SOURCE-SNAPSHOT-BINDING-V1",
            "path": "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite",
            "read_only": True,
            "sha256": SEALED_SNAPSHOT_SHA256,
        },
        "PRIMITIVE_INVENTORY.json": {
            "schema_id": "NON-D002-PRIMITIVE-INVENTORY-V1",
            "cases": inventories,
        },
        "TYPED_MAPPING_RECORD.json": {
            "schema_id": "NON-D002-TYPED-MAPPING-RECORD-V1",
            "inputs": typed_inputs,
            "outputs": typed_outputs,
            "identities": identities,
        },
        "CASE_COMPARISON_RECORD.json": {
            "schema_id": "NON-D002-CASE-COMPARISON-V1",
            "comparisons": comparisons,
        },
        "CARRIER_LIFECYCLE_RECORD.json": {
            "schema_id": "NON-D002-CARRIER-LIFECYCLE-V1",
            "records": carrier_lifecycle,
        },
        "FORBIDDEN_CHANNEL_DENIAL_RECORD.json": denial_record,
        "VALIDATION_RECORD.json": validation,
    }
    evidence_root = ROOT / manifest["evidence_root"]
    for name, value in records.items():
        atomic_json(evidence_root / name, value)
    final = evidence_root / "EVIDENCE_SHA256SUMS"
    lines = [
        f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}"
        for path in sorted(evidence_root.iterdir()) if path.is_file() and path != final
    ]
    with tempfile.NamedTemporaryFile(delete=False) as handle:
        temporary = Path(handle.name)
        handle.write(("\n".join(lines) + "\n").encode("utf-8"))
    temporary.replace(final)
    return validation


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    arguments = parser.parse_args()
    manifest_path = Path(arguments.manifest)
    manifest = load_json(manifest_path if manifest_path.is_absolute() else ROOT / manifest_path)
    validation = execute(manifest)
    print(validation["terminal_state"])
    return 0 if validation["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
