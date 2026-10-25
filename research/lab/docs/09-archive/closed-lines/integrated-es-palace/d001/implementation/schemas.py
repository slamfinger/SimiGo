"""Canonical JSON, digests, and exact-schema checks."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

CANONICAL_BOUNDARY = "D001-PACKAGE-V1.0"
BOUNDARY_DIGEST = hashlib.sha256(CANONICAL_BOUNDARY.encode()).hexdigest()
SCHEMAS = {
    "closure": "LAWFUL-INFORMATION-CLOSURE-D001-V1",
    "recovered": "RECOVERED-INFORMATION-CONTEXT-D001-V1",
    "authority": "CONTINUATION-AUTHORITY-VIEW-D001-V1",
    "input": "ES-CONTINUATION-INPUT-D001-V1",
    "output": "ES-CONTINUATION-OUTPUT-D001-V1",
    "negative": "D001-NEGATIVE-DECISION-V1",
}


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def digest(value: Any) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


def digest_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def exact_fields(value: Any, fields: set[str], label: str) -> None:
    if not isinstance(value, dict):
        raise ValueError(f"{label} must be an object")
    missing = fields - set(value)
    extra = set(value) - fields
    if missing or extra:
        raise ValueError(f"{label} field mismatch: missing={sorted(missing)} extra={sorted(extra)}")


def require_schema(value: dict, schema_id: str, fields: set[str], label: str) -> None:
    exact_fields(value, fields | {"schema_id"}, label)
    if value["schema_id"] != schema_id:
        raise ValueError(f"{label} schema mismatch: {value['schema_id']!r}")


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_canonical(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(canonical_bytes(value))
