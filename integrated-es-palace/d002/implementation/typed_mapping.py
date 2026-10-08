"""Map real snapshot metadata into D-001 typed input schemas; no decisions."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "integrated-es-palace/d001/implementation"))
from schemas import digest, digest_bytes  # noqa: E402


def map_fixtures(fixtures: list[dict], manifest: dict) -> dict:
    mappings = []
    for fixture in fixtures:
        path = ROOT / fixture["manifest"]
        record = __import__("json").loads(path.read_text())
        es_input = {
            "schema_id": "ES-CONTINUATION-INPUT-D001-V1",
            "closure_id": record["case_id"],
            "closure_revision": "R1",
            "recovered_context_digest": record["source_record_digest"],
            "next_action_id": f"NA-{record['case_id']}",
            "target_digest": record["source_record_digest"],
            "continuation_class": fixture["expected"]["continuation_class"],
            "authorization_boundary": "D002-PACKAGE-V1.0",
        }
        mappings.append({
            "case_id": record["case_id"], "source_internal_id": record["source_internal_id"],
            "es_input": es_input, "input_digest": digest(es_input),
            "input_schema": record["schemas"]["I8"]["path"], "frozen_expected": fixture["expected"],
        })
    d001_core = {name: digest_bytes((ROOT / "integrated-es-palace/d001/implementation" / name).read_bytes()) for name in ["schemas.py", "inventory.py", "reconstruction.py", "continuation.py"]}
    return {
        "schema_id": "D002-TYPED-MAPPING-RECORD-V1", "manifest_instance_id": manifest["manifest_instance_id"],
        "mappings": mappings, "d001_decision_core_sha256": d001_core,
        "decision_execution_performed": False, "result": "PASS" if len(mappings) == 7 else "FAIL",
    }
