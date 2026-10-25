"""Inventory-only reconstruction into the typed recovered context."""
from __future__ import annotations

from typing import Any

from inventory import Inventory
from schemas import SCHEMAS, digest, require_schema


def reconstruct(inventory: Inventory) -> tuple[dict, dict, dict, list, dict]:
    closure = inventory.read("I1")
    require_schema(closure, SCHEMAS["closure"], {"closure_id", "closure_revision", "members", "closure_digest"}, "closure")
    if closure["closure_digest"] != digest({key: closure[key] for key in ("schema_id", "closure_id", "closure_revision", "members")}):
        raise ValueError("closure digest mismatch")

    provenance = inventory.read("I4")
    require_schema(provenance, "PROVENANCE-REVISION-D001-V1", {"records"}, "provenance")
    actions = inventory.read("I5")
    require_schema(actions, "NEXT-ACTION-D001-V1", {"actions"}, "next-actions")
    invocation = inventory.read("I6")
    require_schema(invocation, "APPROVED-INVOCATION-D001-V1", {"manifest_instance_id", "package_id", "stage", "schema_version", "opaque_locator"}, "invocation")
    approved_schemas = inventory.read("I8")
    require_schema(approved_schemas, "APPROVED-SCHEMAS-D001-V1", {"input", "output"}, "approved-schemas")
    destinations = inventory.read("I10")
    require_schema(destinations, "APPROVED-EVIDENCE-DESTINATIONS-D001-V1", {"objects"}, "evidence-destinations")

    records = []
    for member in closure["members"]:
        object_id = member["object_id"]
        prov = provenance["records"][object_id]
        records.append({
            "object_id": object_id,
            "digest": member["digest"],
            "authority": member["authority"],
            "revision": prov["revision"],
            "status": prov["status"],
            "provenance_digest": prov["provenance_digest"],
        })

    recovered = {
        "schema_id": SCHEMAS["recovered"],
        "closure_id": closure["closure_id"],
        "closure_revision": closure["closure_revision"],
        "recovered_objects": records,
        "context_digest": "",
    }
    recovered["context_digest"] = digest({key: recovered[key] for key in ("schema_id", "closure_id", "closure_revision", "recovered_objects")})
    return closure, recovered, provenance, actions["actions"], invocation
