"""Derive R-I1..R-I10 fixtures from ordered snapshot metadata only."""
from __future__ import annotations

import json
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CASES = ["P-LAWFUL", "P-SETTLED", "P-BLOCKED", "N-MISSING", "N-STALE", "N-AMBIGUOUS", "N-ILLEGAL"]
EXCLUDED_CONTENT_KEY = "chroma:document"


def canonical(value) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def digest(value) -> str:
    import hashlib
    return hashlib.sha256(canonical(value)).hexdigest()


def digest_bytes(value: bytes) -> str:
    import hashlib
    return hashlib.sha256(value).hexdigest()


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(canonical(value))


def ordered_records(snapshot: Path) -> list[dict]:
    connection = sqlite3.connect(f"file:{snapshot}?mode=ro&immutable=1", uri=True)
    try:
        ids = [row[0] for row in connection.execute("select distinct id from embedding_metadata order by id limit 7")]
        records = []
        for internal_id in ids:
            rows = connection.execute("select key,string_value,int_value,float_value,bool_value from embedding_metadata where id=? order by key", (internal_id,)).fetchall()
            metadata = {}
            for key, string_value, int_value, float_value, bool_value in rows:
                if key == EXCLUDED_CONTENT_KEY:
                    metadata[key] = {"present": True, "sha256": digest({"string": string_value, "int": int_value, "float": float_value, "bool": bool_value})}
                else:
                    metadata[key] = {"string": string_value, "int": int_value, "float": float_value, "bool": bool_value}
            records.append({"internal_id": internal_id, "metadata": metadata, "record_digest": digest(metadata)})
        return records
    finally:
        connection.close()


def build_inventory(manifest: dict, binding: dict, snapshot: Path) -> tuple[dict, list[dict]]:
    records = ordered_records(snapshot)
    if len(records) != 7:
        raise ValueError(f"need seven ordered records, got {len(records)}")
    expected = {
        "P-LAWFUL": ("CONTINUE", "SETTLED_CONTINUATION", "LAWFUL_CURRENT_CONTINUATION"),
        "P-SETTLED": ("REUSE", "SETTLED_CONTINUATION", "REUSE_PREDICATE_COMPLETE"),
        "P-BLOCKED": ("BLOCK", "BLOCKED_LAWFUL_CONTINUATION", "REGISTERED_BLOCKING_CONDITION"),
        "N-MISSING": ("BLOCK", "BLOCKED_DEFECT", "MANDATORY_OBJECT_UNRESOLVABLE"),
        "N-STALE": ("BLOCK", "BLOCKED_DEFECT", "MANDATORY_EVIDENCE_SUPERSEDED"),
        "N-AMBIGUOUS": ("BLOCK", "BLOCKED_DEFECT", "CONFLICTING_VALID_POINTERS"),
        "N-ILLEGAL": ("BLOCK", "BLOCKED_DEFECT", "REGISTERED_BOUNDARY_VIOLATION_PROVEN"),
    }
    fixtures = []
    inventory_rows = []
    for case, record in zip(CASES, records):
        root = ROOT / "integrated-es-palace/d002/fixtures" / case
        if root.exists():
            raise FileExistsError(root)
        provenance_status = "SUPERSEDED" if case == "N-STALE" else "CURRENT"
        provenance = {"schema_id": "D002-RECORD-PROVENANCE-V1", "source_internal_id": record["internal_id"], "status": provenance_status, "record_digest": record["record_digest"], "metadata": record["metadata"]}
        write_json(root / "provenance/record.json", provenance)
        boundary = "ILLEGAL" if case == "N-ILLEGAL" else "D002-PACKAGE-V1.0"
        action = {"action_id": f"NA-{case}", "target_digest": record["record_digest"], "boundary": boundary, "continuation_class": "SETTLED_CONTINUATION" if case.startswith("P-") else "BLOCKED_DEFECT"}
        if case == "P-BLOCKED":
            action["continuation_class"] = "BLOCKED_LAWFUL_CONTINUATION"
            action["blocking_condition"] = "REGISTERED_BLOCK"
        if case == "N-ILLEGAL":
            action["boundary_digest"] = digest({"boundary": "ILLEGAL"})
        else:
            action["boundary_digest"] = digest({"boundary": "D002-PACKAGE-V1.0"})
        actions = {"schema_id": "D002-NEXT-ACTION-V1", "actions": [action]}
        if case == "N-AMBIGUOUS":
            actions["actions"].append({**action, "action_id": f"NA-{case}-B", "target_digest": digest({"conflict": case})})
        if case != "N-MISSING":
            write_json(root / "next-action/next-actions.json", actions)
        invocation = {"schema_id": "D002-APPROVED-INVOCATION-V1", "manifest_instance_id": manifest["manifest_instance_id"], "package_id": manifest["package_binding"]["package_id"], "stage": "D002_PREPARATION", "schema_version": manifest["schema_version"], "opaque_locator": f"d002://snapshot/embedding/{record['internal_id']}"}
        write_json(root / "invocation.json", invocation)
        snapshot_record = {"schema_id": "D002-CARRIER-SNAPSHOT-V1", "source_internal_id": record["internal_id"], "approved_read": True, "settled_record": {}}
        if case == "P-SETTLED":
            snapshot_record["settled_record"] = {"source_record_digest": record["record_digest"], "settled": True}
        write_json(root / "carrier/snapshot.json", snapshot_record)
        schemas = {"schema_id": "D002-APPROVED-SCHEMAS-V1", "input": "ES-CONTINUATION-INPUT-D001-V1", "output": "ES-CONTINUATION-OUTPUT-D001-V1"}
        write_json(root / "schemas.json", schemas)
        destinations = {"schema_id": "D002-APPROVED-DESTINATIONS-V1", "objects": manifest["evidence_binding"]["exact_objects"]}
        write_json(root / "evidence-destinations.json", destinations)
        members = [
            {"object_id": "provenance", "path": "provenance/record.json", "digest": digest(provenance), "authority": False},
            {"object_id": "next_actions", "path": "next-action/next-actions.json", "digest": digest(actions), "authority": True},
            {"object_id": "invocation", "path": "invocation.json", "digest": digest(invocation), "authority": False},
        ]
        closure = {"schema_id": "D002-LAWFUL-INFORMATION-CLOSURE-V1", "closure_id": f"REAL-{case}", "closure_revision": "R1", "members": members, "closure_digest": ""}
        closure["closure_digest"] = digest({key: closure[key] for key in ("schema_id", "closure_id", "closure_revision", "members")})
        write_json(root / "information-closure/closure.json", closure)
        object_paths = {"I1": "information-closure/closure.json", "I2": "information-closure/closure.json", "I3": "carrier/snapshot.json", "I4": "provenance/record.json", "I5": "next-action/next-actions.json", "I6": "invocation.json", "I7": "carrier/snapshot.json", "I8": "schemas.json", "I9": "schemas.json", "I10": "evidence-destinations.json"}
        primitives = {}
        for family in [f"I{n}" for n in range(1, 11)]:
            path = root / object_paths[family]
            primitives[family.replace("I", "R-I", 1)] = {"path": object_paths[family], "sha256": digest_bytes(path.read_bytes()) if path.exists() else None, "registered_trigger": case}
        fixture_manifest = {"schema_id": "D002-FIXTURE-MANIFEST-V1", "case_id": case, "source_internal_id": record["internal_id"], "source_record_digest": record["record_digest"], "opaque_locator": invocation["opaque_locator"], "closure": object_paths["I1"], "provenance": object_paths["I4"], "next_actions": object_paths["I5"], "carrier_snapshot": object_paths["I3"], "invocation": object_paths["I6"], "schemas": object_paths["I8"], "evidence_destinations": object_paths["I10"], "primitives": primitives}
        write_json(root / "fixture-manifest.json", fixture_manifest)
        top, cls, reason = expected[case]
        expected_record = {"decision": top, "continuation_class": cls, "precedence_reason": reason, "no_fallback_guess": True, "no_partial_continuation": True, "no_silent_recompute": True, "no_stale_success": True}
        write_json(root / "EXPECTED.json", expected_record)
        fixtures.append({"case_id": case, "source_internal_id": record["internal_id"], "manifest": f"integrated-es-palace/d002/fixtures/{case}/fixture-manifest.json", "manifest_sha256": digest_bytes((root / "fixture-manifest.json").read_bytes()), "expected": expected_record})
        inventory_rows.append({"case_id": case, "source_internal_id": record["internal_id"], "record_digest": record["record_digest"], "families": sorted(primitives)})
    inventory = {"schema_id": "D002-PRIMITIVE-INVENTORY-V1", "snapshot_sha256": binding["snapshot_sha256"], "records": inventory_rows, "synthetic_palace_records": False, "result": "PASS" if len(fixtures) == 7 else "FAIL"}
    return inventory, fixtures
