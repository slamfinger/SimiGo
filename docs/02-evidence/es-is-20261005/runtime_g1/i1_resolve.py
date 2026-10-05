"""I-1 G-1 — resolve(CR_ref) per the frozen I-1 contract
(IPAC_PERSISTENCE_RESOLVE_CONCEPTUAL_DESIGN_V0.3.md, FROZEN main 2b2e2ef).

Implements the Verification Suite V-1..V-5 with the frozen failure
signatures, the three-state output, and R2 assembly:

  V-1  referability        (i) CR self-identity: canonical identity hash over
                             the record's identity-bearing fields must equal
                             CR_ref — else CR-ID-MISMATCH;
                          (ii) every referenced target (result, used items)
                             must EXIST at its pinned address
                             — else C-REF-NOT-FOUND / I-NF
  V-2  content match       re-materialized items AND the result hash-match
                             their pinned versions — else I-MISMATCH
                             (IF-G1-01 applied: result content-match is V-2)
  V-3  lineage integrity   A-chain unbroken, link-wise hash-consistent, acyclic
                             (visited-set) — else A-SUB / A-NF / A-CYCLE
  V-4  surface integrity   stored surface digest equals the recorded digest
                             — else P-VIOLATION
  V-5  formation baseline  hash equality over the enumerated formation fields
                             — else FORM-DRIFT

Classification of traversal outcomes (implementation of the frozen text
"UNRESOLVABLE = the record cannot be traversed"; the alternative — treating
I-NF as UNRESOLVABLE — is registered in G1_DELIVERY.md as a documented
implementation decision, not a contract change):
  UNRESOLVABLE                the record itself cannot be traversed/verified
                              at its root: CR-ID-MISMATCH, C-REF-NOT-FOUND,
                              A-CYCLE
  RESOLVED-WITH-VIOLATIONS    traversal completed; violations mechanically
                              signed: I-NF, I-MISMATCH, A-SUB, A-NF,
                              P-VIOLATION, FORM-DRIFT
  RESOLVED                    no violations; R2 produced
"""
from __future__ import annotations

import hashlib
from typing import Any, Dict, List, Optional

from i1_records import ContentStore, \
    formation_baseline, recompute_cr_identity, sha256_hex


def _violation(check: str, signature: str, detail: str) -> Dict[str, str]:
    return {"check": check, "signature": signature, "detail": detail}


def resolve(cr_ref: str, store: ContentStore, max_chain: int = 64,
            verify_lineage_identity: bool = True) -> Dict[str, Any]:
    """resolve(CR_ref) per the frozen I-1 contract. Returns:

    {"state": "RESOLVED" | "RESOLVED-WITH-VIOLATIONS" | "UNRESOLVABLE",
     "violations": [ {check, signature, detail}, ... ],
     "r2": { surface, used_items, lineage, formation, r2_digest } | None}

    verify_lineage_identity=False is a CONFORMANCE INSTRUMENT ONLY (drives the
    A-CYCLE visited-set guard in isolation): because parent refs are hashed
    into CR identities, a store-constructed cycle always trips A-SUB first —
    the A-CYCLE guard is defense-in-depth for stores that cannot verify
    identity. No semantic judgment anywhere: every check is byte/hash/
    structure mechanics (IC-6 / no-oracle discipline)."""
    violations: List[Dict[str, str]] = []

    # ---- V-1(i): root CR self-identity (addressability self-check) --------
    node = store.get_node(cr_ref)
    if node is None:
        return {"state": "UNRESOLVABLE",
                "violations": [_violation("V-1", "C-REF-NOT-FOUND",
                                          f"no node at {cr_ref}")],
                "r2": None}
    if node.get("type") != "CR":
        return {"state": "UNRESOLVABLE",
                "violations": [_violation("V-1", "C-REF-NOT-FOUND",
                                          f"node at {cr_ref} is not a CR")],
                "r2": None}
    if recompute_cr_identity(node) != cr_ref:
        return {"state": "UNRESOLVABLE",
                "violations": [_violation("V-1", "CR-ID-MISMATCH",
                                          "recomputed canonical identity hash "
                                          "does not equal CR_ref")],
                "r2": None}

    # ---- V-1(ii): the result edge must be REFERABLE (resolution target) ----
    # IF-G1-01 applied: V-1 owns existence only; result content-match is V-2.
    result_digest = node["result"]["content_digest"]
    result_bytes = store.get_blob(result_digest)
    if result_bytes is None:
        return {"state": "UNRESOLVABLE",
                "violations": [_violation("V-1", "C-REF-NOT-FOUND",
                                          f"result blob {result_digest} "
                                          f"not found")],
                "r2": None}

    # ---- V-1(ii)/V-2: used items — referability and content match ---------
    used_out: List[Dict[str, Any]] = []
    for u in node["used"]:
        blob = store.get_blob(u["content_digest"])
        if blob is None:
            violations.append(_violation(
                "V-1/V-2", "I-NF",
                f"used item {u.get('name', '')} not found at pinned identity "
                f"{u['content_digest']}"))
            used_out.append({"name": u.get("name", ""),
                             "pinned_digest": u["content_digest"],
                             "present": False})
            continue
        actual = sha256_hex(blob)
        if actual != u["content_digest"]:
            violations.append(_violation(
                "V-2", "I-MISMATCH",
                f"used item {u.get('name', '')} content hash {actual} does "
                f"not match pinned {u['content_digest']}"))
            used_out.append({"name": u.get("name", ""),
                             "pinned_digest": u["content_digest"],
                             "present": True, "actual_digest": actual,
                             "bytes": blob})
            continue
        used_out.append({"name": u.get("name", ""),
                         "pinned_digest": u["content_digest"],
                         "present": True, "actual_digest": actual,
                         "bytes": blob})

    # ---- V-2: result content match (moved from V-1 per IF-G1-01) ----------
    result_actual = sha256_hex(result_bytes)
    if result_actual != result_digest:
        violations.append(_violation(
            "V-2", "I-MISMATCH",
            f"result content hash {result_actual} does not match pinned "
            f"{result_digest}"))
        result_out = {"content_digest": result_digest, "present": True,
                      "actual_digest": result_actual, "bytes": result_bytes}
    else:
        result_out = {"content_digest": result_digest, "present": True,
                      "actual_digest": result_digest, "bytes": result_bytes}

    # ---- V-4: surface integrity -------------------------------------------
    surface_digest = node["surface"]["content_digest"]
    surface_bytes = store.get_blob(surface_digest)
    if surface_bytes is None:
        violations.append(_violation("V-4", "P-VIOLATION",
                                     f"surface blob {surface_digest} missing"))
        surface_out = None
    else:
        actual_surface = sha256_hex(surface_bytes)
        if actual_surface != surface_digest:
            violations.append(_violation(
                "V-4", "P-VIOLATION",
                f"surface content hash {actual_surface} does not match "
                f"recorded {surface_digest}"))
        surface_out = surface_bytes

    # ---- V-5: formation baseline (enumerated fields, hash equality only) --
    formation = node["formation"]
    recomputed = formation_baseline(formation["procedure_id"],
                                    formation["input_digests"])
    if recomputed != formation["baseline_digest"]:
        violations.append(_violation(
            "V-5", "FORM-DRIFT",
            f"formation baseline mismatch: recorded "
            f"{formation['baseline_digest']}, recomputed {recomputed}"))
    for d in formation["input_digests"]:
        if store.get_blob(d) is None and store.get_node(d) is None:
            violations.append(_violation(
                "V-5", "FORM-DRIFT",
                f"formation input digest {d} not resolvable in store"))

    # ---- V-3: lineage chain (unbroken, hash-consistent, acyclic) ----------
    lineage_ancestors: List[Dict[str, Any]] = []
    visited = {cr_ref}
    cur = node["continues"]["parent_cr_ref"]
    depth = 0
    while cur is not None:
        depth += 1
        if depth > max_chain:
            violations.append(_violation(
                "V-3", "A-CYCLE",
                f"lineage chain exceeded max depth {max_chain}"))
            return {"state": "UNRESOLVABLE",
                    "violations": violations, "r2": None}
        if cur in visited:
            violations.append(_violation(
                "V-3", "A-CYCLE", f"lineage cycle at {cur}"))
            return {"state": "UNRESOLVABLE",
                    "violations": violations, "r2": None}
        visited.add(cur)
        anc = store.get_node(cur)
        if anc is None:
            violations.append(_violation(
                "V-3", "A-NF", f"ancestor CR {cur} not found"))
            lineage_ancestors.append({"cr_ref": cur, "present": False})
            break
        if verify_lineage_identity and (
                anc.get("type") != "CR"
                or recompute_cr_identity(anc) != cur):
            violations.append(_violation(
                "V-3", "A-SUB",
                f"ancestor CR {cur} failed self-identity — substituted "
                f"lineage node"))
            lineage_ancestors.append({"cr_ref": cur, "present": False,
                                      "substituted": True})
            break
        lineage_ancestors.append({"cr_ref": cur,
                                  "weights_id":
                                  anc.get("provenance", {}).get("weights_id"),
                                  "segments": anc.get("provenance", {})
                                  .get("segments", [])})
        nxt = anc["continues"]["parent_cr_ref"]
        cur = nxt

    # ---- assemble R2 -------------------------------------------------------
    segments: List[str] = []
    for a in lineage_ancestors:
        segments.extend(a.get("segments", []))
    segments.extend(node.get("provenance", {}).get("segments", []))
    # predecessor weights identity: surfaced from the LINEAGE provenance
    # (ancestors, nearest first) where the formation recorded it
    # (MAY-carry rule — absent everywhere ⇒ UNBOUND)
    predecessor_weights_id = None
    for a in lineage_ancestors:
        wid = a.get("weights_id")
        if wid is not None:
            predecessor_weights_id = wid
            break
    if predecessor_weights_id is None:
        predecessor_weights_id = node.get("provenance", {}).get("weights_id")
    r2 = {
        "surface": surface_out,
        "surface_digest": surface_digest,
        "result": result_out,
        "used_items": used_out,
        "lineage": {"ancestors": lineage_ancestors,
                    "segments": segments,
                    "root_cr_ref": cr_ref},
        "formation": formation,
        "predecessor_weights_id": predecessor_weights_id,
    }
    r2_digest = sha256_hex(
        repr(sorted(r2.items(), key=lambda kv: kv[0])).encode("utf-8"))
    r2["r2_digest"] = r2_digest

    state = "RESOLVED" if not violations else "RESOLVED-WITH-VIOLATIONS"
    return {"state": state, "violations": violations, "r2": r2}
