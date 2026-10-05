"""I-1 G-1 — CR/IR record formats (frozen field lists) + content-addressed store.

Frozen sources (this implementation produces evidence; it never modifies the
frozen contracts — Implementation Finding protocol applies):
  - IPAC_PERSISTENCE_RESOLVE_CONCEPTUAL_DESIGN_V0.3.md   (FROZEN, main 2b2e2ef)
  - IPAC_INSTANTIATE_RUNTIME_REALIZATION_VERIFICATION_CONCEPTUAL_DESIGN_V0.3.md
    (FROZEN, branch 1832676)

No semantic judgment anywhere (IC-6 / no-oracle discipline): every operation in
this module is byte/hash/structure mechanics.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any, Dict, List, Optional

def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def canonical(parts: List[bytes]) -> bytes:
    """Unambiguous framing: 8-byte big-endian length prefix per part."""
    out = b""
    for p in parts:
        out += len(p).to_bytes(8, "big") + p
    return out

def digest_canonical(parts: List[bytes]) -> str:
    return sha256_hex(canonical(parts))


class ContentStore:
    """Minimal content-addressed store (MC-4): blobs by content digest,
    nodes by identity. Realizes IS persistence; the store is not the IS."""

    def __init__(self, root: Path) -> None:
        self.root = Path(root)

    def put_blob(self, data: bytes) -> str:
        d = sha256_hex(data)
        p = self.root / "blobs" / d
        if not p.exists():
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(data)
        return d

    def get_blob(self, digest: str) -> Optional[bytes]:
        p = self.root / "blobs" / digest
        return p.read_bytes() if p.exists() else None

    def put_node(self, node: Dict[str, Any], node_id: str) -> str:
        """Write-once: an existing node at the same identity is never
        overwritten (content-addressed immutability)."""
        p = self.root / "nodes" / f"{node_id}.json"
        if not p.exists():
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(json.dumps(node, sort_keys=True, ensure_ascii=False),
                         encoding="utf-8")
        return node_id

    def overwrite_node(self, node: Dict[str, Any], node_id: str) -> str:
        """UNCONDITIONAL write — exists for conformance tampering simulations
        only (simulating storage corruption/substitution); a conforming
        runtime never calls this on an identity-addressed node."""
        p = self.root / "nodes" / f"{node_id}.json"
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(node, sort_keys=True, ensure_ascii=False),
                     encoding="utf-8")
        return node_id

    def get_node(self, node_id: str) -> Optional[Dict[str, Any]]:
        p = self.root / "nodes" / f"{node_id}.json"
        if not p.exists():
            return None
        return json.loads(p.read_text(encoding="utf-8"))


# ---------------------------------------------------------------- CR format

def compute_cr_identity(result_digest: str, used_entries: List[Dict[str, str]],
                        surface_digest: str, parent_ref: Optional[str]) -> str:
    """Frozen I-1 §2.1: CR identity = hash over identity-bearing fields
    (result-ref, used-set with pinned versions in canonical order, surface
    bytes, parent CR-ref). Canonical order = deterministic serialization from
    the pinned content-identity byte strings (lexicographic over identity
    digest bytes). Provenance is OUTSIDE the identity hash (drop-test
    property: dropping/changing provenance changes nothing)."""
    parts: List[bytes] = [b"I1-CR-v1",
                          result_digest.encode("utf-8"),
                          surface_digest.encode("utf-8"),
                          (parent_ref or "ROOT").encode("utf-8")]
    for u in sorted(used_entries,
                    key=lambda e: (e["content_digest"], e["ref"])):
        parts.append(u["ref"].encode("utf-8"))
        parts.append(u["content_digest"].encode("utf-8"))
    return digest_canonical(parts)


def formation_baseline(procedure_id: str, input_digests: List[str]) -> str:
    """V-5 enumerated formation fields: baseline = hash over (procedure_id,
    sorted input digests). Nothing else is part of the baseline (V-5 is
    hash/field equality only — no semantic review)."""
    return digest_canonical([b"I1-FORM-v1", procedure_id.encode("utf-8")] +
                            [d.encode("utf-8")
                             for d in sorted(input_digests)])


def write_cr(store: ContentStore, *, result_bytes: bytes,
             used_items: List[Dict[str, Any]], surface_bytes: bytes,
             parent_cr_ref: Optional[str], formation: Dict[str, Any],
             provenance: Dict[str, Any]) -> Dict[str, Any]:
    """Build and store a CR node. used_items are pinned AT USE TIME:
    each entry's content digest is computed here, from the bytes actually
    used (R3 institutionalized). provenance is recorded but excluded from
    the identity hash. Returns the stored node (including cr_ref)."""
    result_digest = store.put_blob(result_bytes)
    surface_digest = store.put_blob(surface_bytes)
    used: List[Dict[str, str]] = []
    for u in used_items:
        d = store.put_blob(u["bytes"])
        used.append({"name": u.get("name", ""),
                     "ref": d, "content_digest": d})
    inputs = sorted(formation.get("input_digests", []))
    baseline = formation_baseline(formation["procedure_id"], inputs)
    cr_ref = compute_cr_identity(result_digest, used, surface_digest,
                                 parent_cr_ref)
    node = {
        "type": "CR",
        "cr_ref": cr_ref,
        "result": {"content_digest": result_digest},
        "used": used,
        "surface": {"content_digest": surface_digest,
                    "size": len(surface_bytes)},
        "continues": {"parent_cr_ref": parent_cr_ref},
        "formation": {"procedure_id": formation["procedure_id"],
                      "input_digests": inputs,
                      "baseline_digest": baseline},
        "provenance": provenance,  # outside the identity hash
    }
    store.put_node(node, cr_ref)
    return node


def recompute_cr_identity(node: Dict[str, Any]) -> str:
    """Recompute the canonical identity hash from a CR node's stored
    identity-bearing fields (V-1(i) self-identity check)."""
    return compute_cr_identity(node["result"]["content_digest"],
                               node["used"],
                               node["surface"]["content_digest"],
                               node["continues"]["parent_cr_ref"])


# ---------------------------------------------------------------- IR format

IR_STAGES = ("ESTABLISHED", "CREATED", "COMPLETED", "CLOSED", "ANOMALY")

def ir_new(attempt_id: str, cr_ref: str, task_record: Dict[str, Any],
           meta: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """Step-0 attempt record (frozen I-1d §1.1 field list). The TaskRecord
    carries the τ2 identity: task-ref / task-content-digest / declaration
    source / version. All later fields are present-but-pending until their
    lifecycle stage fills them."""
    return {
        "type": "IR",
        "attempt_id": attempt_id,
        "stage": "ESTABLISHED",
        "cr_ref": cr_ref,
        "task_record": {
            "task_ref": task_record["task_ref"],
            "task_content_digest": task_record["task_content_digest"],
            "declaration_source": task_record["declaration_source"],
            "version": task_record.get("version"),
        },
        "r2_digest": None,
        "binding_record": None,        # step 1 (G-2)
        "execution_envelope": None,    # step 1 (G-2)
        "substrate_manifest": None,    # step 7/VV-7 (G-2)
        "position_record": None,       # step 5/VV-5 (G-2)
        "attached_segment_provenance": [],  # step 4 (G-2)
        "verification": [],            # VV-1..VV-7 results (G-2)
        "disposition": None,
        "lifecycle": {"anomaly": None, "recovery_of": None},
        "meta": meta or {},
    }

def ir_set_stage(ir: Dict[str, Any], stage: str) -> None:
    if stage not in IR_STAGES:
        raise ValueError(f"unknown IR stage: {stage}")
    ir["stage"] = stage

def ir_validate_completed(ir: Dict[str, Any]) -> List[str]:
    """Frozen compliance (a)/(b): a COMPLETED IR must carry every §1.1 field
    at its verdict tier, and every verification verdict must be one of the
    three tiers. Returns a list of audit findings (empty = clean)."""
    findings: List[str] = []
    if ir.get("stage") != "COMPLETED":
        findings.append("STAGE-NOT-COMPLETED")
    for field in ("r2_digest", "binding_record", "execution_envelope",
                  "substrate_manifest", "position_record",
                  "attached_segment_provenance", "verification"):
        if ir.get(field) is None:
            findings.append(f"FIELD-INCOMPLETE:{field}")
    if ir.get("task_record", {}).get("task_content_digest") is None:
        findings.append("FIELD-INCOMPLETE:task_record")
    for v in ir.get("verification", []):
        if v.get("verdict") not in ("VERIFIED", "COVENANTED", "FAILED"):
            findings.append(f"VERDICT-TIER-INVALID:{v.get('check')}")
    return findings
