"""Mechanical I1-I10 inventory resolution confined to one fixture root."""
from __future__ import annotations

import hashlib
from pathlib import Path
from typing import Any

from schemas import digest_bytes, exact_fields, load_json

FAMILIES = [f"I{n}" for n in range(1, 11)]
MANIFEST_FIELDS = {
    "schema_id", "case_id", "opaque_locator", "closure", "provenance",
    "next_actions", "carrier_snapshot", "invocation", "schemas",
    "evidence_destinations", "primitives",
}


class Inventory:
    def __init__(self, manifest_path: Path):
        self.manifest_path = manifest_path.resolve()
        self.root = self.manifest_path.parent
        self.manifest = load_json(self.manifest_path)
        exact_fields(self.manifest, MANIFEST_FIELDS, "fixture-manifest")
        if self.manifest["schema_id"] != "D001-FIXTURE-MANIFEST-V1":
            raise ValueError("fixture manifest schema mismatch")

    def entry(self, family: str) -> dict:
        primitive = self.manifest["primitives"].get(family)
        if not isinstance(primitive, dict):
            raise ValueError(f"{family} is not registered")
        exact_fields(primitive, {"path", "sha256", "registered_trigger"}, f"{family}")
        return primitive

    def path_for(self, family: str) -> Path:
        path = (self.root / self.entry(family)["path"]).resolve()
        root = self.root.resolve()
        if root != path and root not in path.parents:
            raise ValueError(f"{family} escapes fixture root")
        if path.is_symlink() or not path.is_file():
            raise FileNotFoundError(f"{family} is absent or not a regular file")
        return path

    def read(self, family: str) -> Any:
        entry = self.entry(family)
        path = self.path_for(family)
        actual = digest_bytes(path.read_bytes())
        if entry["sha256"] != actual:
            raise ValueError(f"{family} digest mismatch")
        return load_json(path)

    def complete(self) -> bool:
        return set(self.manifest["primitives"]) == set(FAMILIES) and len(self.manifest["primitives"]) == 10
