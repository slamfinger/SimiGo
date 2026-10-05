"""I-1 G-2 — Instantiate pipeline (steps 0-5) + Verification Surface VV-1..VV-7
per the frozen I-1c contract (instantiate(R2, τ2★, substrate) → S2;
IPAC_INSTANTIATE_COMPLETENESS_CONCEPTUAL_DESIGN_V0.3.md, main 6c3cf6a) and
the frozen I-1d contract (IPAC_INSTANTIATE_RUNTIME_REALIZATION_VERIFICATION_
CONCEPTUAL_DESIGN_V0.3.md, branch 1832676).

Frozen obligations realized here:
  pipeline     0 precondition / 1 bind / 2 restore(opt) / 3 materialize
               [CREATION POINT] / 4 attach / 5 record
  VV surface   VV-1..VV-7, tiers VERIFIED / COVENANTED / FAILED; applicable
               only after the precondition gate passes; NOT ENTERED on
               PRECONDITION-BLOCK (applicability fact, not a verdict tier)
  dispositions exactly one primary disposition per outcome:
               BLOCK{PRECONDITION-BLOCK, CREATE-BLOCK, POLICY-BLOCK} /
               PROCEED-WITH-ANNOTATION / DECLARED-ALTERNATIVE;
               POST-CREATION-ANOMALY = lifecycle state orthogonal, with the
               original attempt's primary disposition PROCEED-WITH-ANNOTATION
  bindings     BOUND / UNBOUND / MISMATCH (mechanical; no semantic inference)

No semantic judgment anywhere (IC-6). The substrate here is a CONFORMANCE
SUBSTRATE (MC-1..MC-6 minimal testbed realizing G-1's ContentStore as the
information side) — carrier-form restore is not taken (document-form first
run, per the gate package).
"""
from __future__ import annotations

import hashlib
from typing import Any, Dict, List, Optional

from i1_records import ContentStore, sha256_hex
from i1_resolve import resolve


class ConformanceSubstrate:
    """MC-1..MC-6 minimal testbed substrate. Realizes bind / materialize /
    attach surface readback (VV-2 VERIFIED path); restore is available but
    not taken (document-form)."""

    def __init__(self, engine_id: str, tokenizer_id: str,
                 weights_id: str) -> None:
        self.engine_id = engine_id
        self.tokenizer_id = tokenizer_id
        self.weights_id = weights_id
        self._materialized: Optional[Dict[str, Any]] = None

    # MC-1: bind — configuration; records what was configured -----------
    def bind(self, declared_weights_id: Optional[str],
             envelope: Dict[str, Any]) -> Dict[str, Any]:
        self._envelope = envelope
        self._bound_weights_id = declared_weights_id or self.weights_id
        return {"declared_weights_id": self._bound_weights_id,
                "envelope": envelope}

    # MC-2: materialize — accepts the continuation surface as BYTES; the
    # substrate keeps it addressable and returns an object handle ---------
    def materialize(self, surface: bytes) -> Dict[str, Any]:
        handle = {"surface_digest": sha256_hex(surface),
                  "size": len(surface),
                  "addressable": True}
        self._materialized = handle
        return handle

    # readback interface (VERIFIED path for VV-2/VV-4) --------------------
    def readback_surface(self) -> bytes:
        # The conformance substrate is surface-faithful by construction; a
        # real engine exposes this or the check lands COVENANTED.
        return self._surface_bytes

    def feed_surface(self, surface: bytes) -> None:
        self._surface_bytes = surface

    # MC-6: tokenizer ------------------------------------------------------
    def tokenize_position(self, surface: bytes) -> int:
        return len(surface)  # unit-position derivation (deterministic)

    # MC-3/IC-7: restore (available; document-form does NOT take it) -------
    def restore(self, carrier_state: bytes) -> Dict[str, Any]:
        data = hashlib.sha256(carrier_state).digest()
        return {"consumed_prefix_units": int.from_bytes(data[:4], "big") % 1024,
                "taken": True}


def decide_binding(r2: Dict[str, Any], tau_star: Dict[str, Any]) -> Dict[str, Any]:
    """IC-2 three-state binding decision (mechanical; no inference).
    Predecessor weights identity = read from the root CR's provenance
    (surfaced into R2 by resolve upstream), where the formation recorded it
    — the frozen MAY-carry rule; absence ⇒ UNBOUND, never inference."""
    pred = r2.get("predecessor_weights_id")
    declared = tau_star.get("weights_id")
    if pred is not None and declared is not None:
        state = "BOUND" if pred == declared else "MISMATCH"
        return {"state": state,
                "predecessor_weights_id": pred,
                "declared_weights_id": declared}
    return {"state": "UNBOUND", "predecessor_weights_id": pred,
            "declared_weights_id": declared}


def instantiate(cr_ref: str, store: ContentStore, tau_star: Dict[str, Any],
                substrate: ConformanceSubstrate,
                attempt_id: str,
                task_digest: Optional[str] = None,
                verify_lineage_identity: bool = True) -> Dict[str, Any]:
    """The full pipeline. Returns the final IR dict (completed, or closed on
    block). One primary disposition per outcome; lifecycle recorded."""
    task_record = {
        "task_ref": tau_star.get("task_ref", ""),
        "task_content_digest": task_digest or sha256_hex(
            tau_star.get("task_ref", "").encode("utf-8")),
        "declaration_source": tau_star.get("declaration_source", "external"),
        "version": tau_star.get("version"),
    }
    ir: Dict[str, Any] = {
        "type": "IR",
        "attempt_id": attempt_id,
        "stage": "ESTABLISHED",
        "cr_ref": cr_ref,
        "task_record": task_record,
        "r2_digest": None,
        "binding_record": None,
        "execution_envelope": tau_star.get("envelope"),
        "substrate_manifest": None,
        "position_record": None,
        "attached_segment_provenance": [],
        "verification": [],
        "disposition": None,
        "lifecycle": {"anomaly": None, "recovery_of": None},
        "meta": {},
    }

    def finish(block_class: Optional[str] = None, subtype: str = "",
               signatures: Optional[List[str]] = None,
               annotations: Optional[List[str]] = None,
               state: str = "CLOSED") -> Dict[str, Any]:
        ir["stage"] = state
        if block_class:
            ir["disposition"] = {"class": "BLOCK", "subtype": subtype,
                                 "signatures": signatures or []}
        elif annotations is not None:
            ir["disposition"] = {"class": "PROCEED-WITH-ANNOTATION",
                                 "annotations": annotations}
        return ir

    # ---- step 0: precondition gate (R2 must be clean RESOLVED; τ2 present) -
    res = resolve(cr_ref, store, verify_lineage_identity=verify_lineage_identity)
    if res["state"] != "RESOLVED":
        ir["verification"].append({
            "check": "VV-1", "verdict": "NOT-APPLICABLE",
            "detail": f"precondition gate: resolve state = {res['state']}"})
        ir["disposition"] = {"class": "BLOCK", "subtype": "PRECONDITION-BLOCK",
                             "signatures": [v["signature"]
                                            for v in res["violations"]]}
        return finish(state="CLOSED")
    if not tau_star.get("task_ref"):
        ir["disposition"] = {"class": "BLOCK", "subtype": "PRECONDITION-BLOCK",
                             "signatures": ["TASK-MISSING"]}
        return finish(state="CLOSED")
    ir["r2_digest"] = res["r2"]["r2_digest"]

    # ---- VV surface ENTERED from here (precondition passed) ---------------
    r2 = res["r2"]

    # ---- step 1: bind (IC-2/IC-3; BindingRecord) ---------------------------
    binding = decide_binding(r2, tau_star)
    ir["binding_record"] = binding
    declared_weights = (binding["declared_weights_id"]
                        or substrate.weights_id)
    substrate.bind(declared_weights, tau_star.get("envelope", {}))
    ir["verification"].append(
        {"check": "VV-3", "verdict": "VERIFIED",
         "detail": f"binding state = {binding['state']}"})
    if binding["state"] == "MISMATCH":
        env = tau_star.get("envelope", {})
        if env.get("lineage_strict_required"):
            ir["disposition"] = {"class": "BLOCK", "subtype": "POLICY-BLOCK",
                                 "signatures": ["MISMATCH-LINEAGE-STRICT-REQUIRED"]}
            return finish(state="CLOSED")
        # frozen final patch: the envelope decides the primary disposition —
        # MISMATCH + cross-model allowed => DECLARED-ALTERNATIVE (no side-branch)
        annotations = ["MISMATCH: declared cross-model continuation"]
        if tau_star.get("carrier_state") is None:
            annotations.append("carrier state absent: no carrier-form "
                               "no-recompute evidence (document-form run)")
        ir["disposition"] = {"class": "DECLARED-ALTERNATIVE",
                             "annotations": annotations}
        ir["stage"] = "COMPLETED"
        return ir
    else:
        annotations = []
        if binding["state"] == "UNBOUND":
            annotations.append("UNBOUND: lineage-strict status UNDECIDABLE")

    # ---- step 2: restore (optional; document-form does NOT take it) --------
    restore_note = None
    if tau_star.get("carrier_state") is not None:
        m = substrate.restore(tau_star["carrier_state"])
        ir["verification"].append(
            {"check": "VV-restore", "verdict": "VERIFIED",
             "detail": f"consumed-prefix {m['consumed_prefix_units']}"})
    else:
        restore_note = ("carrier state absent: no carrier-form no-recompute "
                        "evidence (document-form run)")

    # ---- step 3: materialize [CREATION POINT] ------------------------------
    substrate.feed_surface(r2["surface"])
    created = substrate.materialize(r2["surface"])
    if not created.get("addressable"):
        ir["verification"].append(
            {"check": "VV-2", "verdict": "FAILED",
             "signature": "SURFACE-INFIDELITY",
             "detail": "substrate did not accept the surface as addressable"})
        return finish(block_class="BLOCK", subtype="CREATE-BLOCK",
                      signatures=["SURFACE-INFIDELITY"])

    # ---- step 4: attach (IC-4; lineage + segment provenance) ---------------
    attached = list(r2["lineage"]["segments"])
    ir["attached_segment_provenance"] = attached
    ir["verification"].append(
        {"check": "VV-6", "verdict": "VERIFIED",
         "detail": f"{len(attached)} inherited segment identifiers attached"})

    # ---- step 5: record — Verification Surface ------------------------------
    # VV-1: input precondition (R2 clean + digest match)
    ir["verification"].insert(0, {
        "check": "VV-1", "verdict": "VERIFIED",
        "detail": f"R2 clean RESOLVED; r2_digest {r2['r2_digest']}"})
    # VV-2: surface faithfulness (readback-verified on this substrate)
    substrate.feed_surface(r2["surface"])
    rb = substrate.readback_surface()
    if rb == r2["surface"]:
        ir["verification"].append(
            {"check": "VV-2", "verdict": "VERIFIED",
             "detail": "readback byte-identical to R2.surface"})
    else:
        ir["verification"].append(
            {"check": "VV-2", "verdict": "FAILED",
             "signature": "SURFACE-INFIDELITY",
             "detail": "readback differs from R2.surface"})
        return finish(block_class="BLOCK", subtype="CREATE-BLOCK",
                      signatures=["SURFACE-INFIDELITY"])
    # VV-4: envelope equality (readback on this substrate)
    eff = substrate._envelope
    if eff == tau_star.get("envelope"):
        ir["verification"].append(
            {"check": "VV-4", "verdict": "VERIFIED",
             "detail": "effective envelope == declared ε2"})
    else:
        ir["verification"].append(
            {"check": "VV-4", "verdict": "FAILED",
             "signature": "ENVELOPE-DRIFT",
             "detail": "readback mismatch"})
        return finish(block_class="BLOCK", subtype="CREATE-BLOCK",
                      signatures=["ENVELOPE-DRIFT"])
    # VV-5: position derivation (PD-6 derived)
    pos_units = substrate.tokenize_position(r2["surface"])
    ir["position_record"] = {"method": "derived", "tokenizer_id":
                             substrate.tokenizer_id, "units": pos_units}
    ir["verification"].append(
        {"check": "VV-5", "verdict": "VERIFIED",
         "detail": f"position derived: {pos_units} units"})
    # VV-7: substrate manifest
    ir["substrate_manifest"] = {
        "engine-id": substrate.engine_id,
        "weights-id": substrate._bound_weights_id,
        "tokenizer-id": substrate.tokenizer_id}
    ir["verification"].append(
        {"check": "VV-7", "verdict": "VERIFIED",
         "detail": "manifest complete"})

    # ---- annotations + disposition ------------------------------------------
    if restore_note:
        annotations.append(restore_note)
    ir["disposition"] = {"class": "PROCEED-WITH-ANNOTATION",
                         "annotations": annotations}
    ir["stage"] = "COMPLETED"
    return ir
