"""I-1 G-2 conformance self-checks.

Proves, within ONE instantiate lifecycle at a time, that the frozen I-1c/I-1d
semantics hold together without drift:
  - IR lifecycle (established at step 0; completed on success)
  - VV applicability (NOT ENTERED on PRECONDITION-BLOCK; entered after)
  - verdict tiers (VERIFIED / COVENANTED / FAILED — never a fourth tier)
  - exactly one primary disposition per outcome, on every path
      PRECONDITION-BLOCK / POLICY-BLOCK / CREATE-BLOCK /
      PROCEED-WITH-ANNOTATION / DECLARED-ALTERNATIVE
  - binding three-state (BOUND / UNBOUND / MISMATCH) — mechanical, no inference
  - POST-CREATION-ANOMALY orthogonal lifecycle (not exercised to completion
    here; its format presence is checked)
  - per-check tier profile recorded in the IR

These are implementation self-checks (realization verification) — NOT the
E-run experiment (G-3), which stays gated.

Run:  python3 i1_g2_conformance.py   (exit 0 = all checks pass)
"""
from __future__ import annotations

import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from i1_records import sha256_hex
from i1_instantiate import (ConformanceSubstrate, OpaqueSubstrate,
                            instantiate)

RESULTS = []


def check(name: str, ok: bool, detail: str = "") -> None:
    RESULTS.append(f"[{'PASS' if ok else 'FAIL'}] {name}"
                   + (f" — {detail}" if detail else ""))


def build_world():
    """Build a store with a clean CR chain and a conformance substrate."""
    import i1_records
    tmp = Path(tempfile.mkdtemp(prefix="i1-g2-"))
    store = i1_records.ContentStore(tmp)
    cr0 = i1_records.write_cr(
        store, result_bytes=b"TASK BRIEF: release decision",
        used_items=[], surface_bytes=b"[briefing context]",
        parent_cr_ref=None,
        formation={"procedure_id": "T0", "input_digests": []},
        provenance={"segments": ["E0.seg[0..1]"],
                    "weights_id": "W-testbed-1"})
    cr1 = i1_records.write_cr(
        store, result_bytes=b"R1: gamma not compatible",
        used_items=[{"name": "F1", "bytes": b"F1 data"}],
        surface_bytes=b"[continuation surface: R1 available for T2]",
        parent_cr_ref=cr0["cr_ref"],
        formation={"procedure_id": "T1", "input_digests": [cr0["cr_ref"]]},
        provenance={"segments": ["E1.seg[0..3]"]})
    sub = ConformanceSubstrate("testbed-engine", "tokenizer-v1", "W-testbed-1")
    return store, cr0["cr_ref"], cr1["cr_ref"], sub


def base_tau(**over):
    tau = {"task_ref": "task/T2",
           "declaration_source": "external/human",
           "weights_id": "W-testbed-1",
           "envelope": {"policy": "default",
                        "lineage_strict_required": False}}
    tau.update(over)
    return tau


def disposition(ir):
    return ir["disposition"]["class"], ir["disposition"].get("subtype")


def entered(ir):
    """The VV surface was ENTERED = at least one check carries a real
    verdict tier (VERIFIED/COVENANTED/FAILED). A NOT-APPLICABLE record is
    the applicability fact of non-entry, not entry."""
    return any(v.get("verdict") in ("VERIFIED", "COVENANTED", "FAILED")
               for v in ir["verification"])


def tiers(ir):
    return {v["verdict"] for v in ir["verification"]}


def main() -> int:
    # 01 — happy path: BOUND -> COMPLETED / PROCEED-WITH-ANNOTATION ----------
    store, cr0, cr1, sub = build_world()
    ir = instantiate(cr1, store, base_tau(), sub, "att-01")
    check("01 happy path -> COMPLETED / PROCEED-WITH-ANNOTATION "
          "(annotations: document-form carrier-absent only)",
          ir["stage"] == "COMPLETED"
          and ir["disposition"]["class"] == "PROCEED-WITH-ANNOTATION"
          and len(ir["disposition"]["annotations"]) == 1
          and "carrier" in ir["disposition"]["annotations"][0])
    check("01b VV surface entered; tiers within the three-state vocabulary",
          entered(ir)
          and tiers(ir) <= {"VERIFIED", "COVENANTED", "FAILED"})
    check("01c BindingRecord = BOUND (predecessor weights-id carried in "
          "provenance and matched)", ir["binding_record"]["state"] == "BOUND")

    # 02 — precondition block: tampered chain -> PRECONDITION-BLOCK,
    #      VV NOT ENTERED (applicability fact, not a verdict tier) ----------
    store, cr0, cr1, sub = build_world()
    d = sha256_hex(b"F1 data")
    (store.root / "blobs" / d).write_bytes(b"F1 TAMPERED")
    ir = instantiate(cr1, store, base_tau(), sub, "att-02")
    cls, sub_t = disposition(ir)
    check("02 degraded chain -> BLOCK / PRECONDITION-BLOCK",
          cls == "BLOCK" and sub_t == "PRECONDITION-BLOCK")
    check("02b VV-1..7 NOT ENTERED (applicability fact recorded, no tier "
          "emitted)",
          not entered(ir)
          and any(v["check"] == "VV-1" and v["verdict"] == "NOT-APPLICABLE"
                  for v in ir["verification"]))
    check("02c IR closed (attempt record exists, lifecycle = CLOSED)",
          ir["stage"] == "CLOSED" and ir["task_record"]["task_ref"] != "")

    # 03 — UNBOUND -> PROCEED-WITH-ANNOTATION with UNDECIDABLE annotation ----
    store, cr0, cr1, sub = build_world()
    # strip the weights-id from the root CR provenance (legal MAY-carry gap)
    node = store.get_node(cr0)
    node["provenance"].pop("weights_id")
    store.overwrite_node(node, cr0)
    ir = instantiate(cr1, store, base_tau(), sub, "att-03")
    cls, _ = disposition(ir)
    check("03 UNBOUND -> PROCEED-WITH-ANNOTATION (no inference)",
          cls == "PROCEED-WITH-ANNOTATION"
          and ir["binding_record"]["state"] == "UNBOUND"
          and any("UNDECIDABLE" in a
                  for a in ir["disposition"]["annotations"]))

    # 04 — MISMATCH + allowed -> DECLARED-ALTERNATIVE recorded with a
    #      COMPLETED IR (full lifecycle continues — IF-G2-03) ---------------
    store, cr0, cr1, sub = build_world()
    ir = instantiate(cr1, store,
                     base_tau(weights_id="W-other-model"), sub, "att-04")
    cls, _ = disposition(ir)
    check("04 MISMATCH + allowed -> DECLARED-ALTERNATIVE on a COMPLETED IR "
          "(steps 2-5 executed; no early return)",
          cls == "DECLARED-ALTERNATIVE"
          and ir["binding_record"]["state"] == "MISMATCH"
          and ir["stage"] == "COMPLETED"
          and ir["substrate_manifest"] is not None
          and any("MISMATCH" in a
                  for a in ir["disposition"]["annotations"]))

    # 05 — MISMATCH + lineage-strict required -> BLOCK / POLICY-BLOCK ---------
    store, cr0, cr1, sub = build_world()
    ir = instantiate(cr1, store,
                     base_tau(weights_id="W-other-model",
                              envelope={"policy": "strict",
                                        "lineage_strict_required": True}),
                     sub, "att-05")
    cls, sub_t = disposition(ir)
    check("05 MISMATCH + lineage-strict required -> BLOCK / POLICY-BLOCK",
          cls == "BLOCK" and sub_t == "POLICY-BLOCK")

    # 06 — every EXERCISED outcome carries exactly one primary disposition
    #      (coverage note: anomaly + recovery transitions land at G-3) ------
    store, cr0, cr1, sub = build_world()
    outcomes = [
        instantiate(cr1, store, base_tau(), sub, "att-06-a"),      # BOUND
        instantiate(cr1, store, base_tau(weights_id="W-other"),
                    sub, "att-06-b"),                              # MISMATCH
    ]
    node = store.get_node(cr0)
    node["provenance"].pop("weights_id")
    store.overwrite_node(node, cr0)
    outcomes.append(instantiate(cr1, store, base_tau(), sub, "att-06-c"))
    count_ok = all(
        o["disposition"]["class"] in
        ("BLOCK", "PROCEED-WITH-ANNOTATION", "DECLARED-ALTERNATIVE")
        for o in outcomes)
    seen = {o["disposition"]["class"] for o in outcomes}
    check("06 exercised outcomes (BOUND/MISMATCH/UNBOUND) each carry exactly "
          "one primary disposition",
          count_ok and seen == {"PROCEED-WITH-ANNOTATION",
                                "DECLARED-ALTERNATIVE"})

    # 06b — opaque substrate: VV-2/VV-4 land COVENANTED, never ENVELOPE-DRIFT
    #      (IF-G2-06: the three-tier discipline proven on an unobservable
    #       substrate path) --------------------------------------------------
    store, cr0, cr1, _ = build_world()
    opaque = OpaqueSubstrate("opaque-engine", "tokenizer-v1", "W-testbed-1")
    ir = instantiate(cr1, store, base_tau(), opaque, "att-06b")
    vv2 = next(v for v in ir["verification"] if v["check"] == "VV-2")
    vv4 = next(v for v in ir["verification"] if v["check"] == "VV-4")
    check("06b opaque substrate -> VV-2/VV-4 COVENANTED (explicit covenant; "
          "ENVELOPE-DRIFT not claimable)",
          vv2["verdict"] == "COVENANTED" and vv4["verdict"] == "COVENANTED"
          and all("ENVELOPE-DRIFT" != v.get("signature")
                  for v in ir["verification"])
          and ir["stage"] == "COMPLETED")

    # 06c — POST-CREATION-ANOMALY: a FAILED check past the creation point is
    #      a lifecycle state + PROCEED-WITH-ANNOTATION, never CREATE-BLOCK;
    #      the verification record keeps its explicit VV ownership
    #      (IF-G2-07) ----------------------------------------------------------
    store, cr0, cr1, sub = build_world()
    # an unfaithful substrate: materialize succeeds (creation point crossed),
    # then readback observes surface infidelity
    class UnfaithfulSubstrate(ConformanceSubstrate):
        def readback_surface(self) -> bytes:
            return b"[UNFAITHFUL READBACK]"
    unfaithful = UnfaithfulSubstrate("bad-engine", "tokenizer-v1",
                                     "W-testbed-1")
    ir = instantiate(cr1, store, base_tau(), unfaithful, "att-06c")
    vv2_rec = next(v for v in ir["verification"] if v.get("signature")
                   == "SURFACE-INFIDELITY")
    check("06c post-creation FAILED check -> ANOMALY lifecycle + "
          "PROCEED-WITH-ANNOTATION; record owned by VV-2 (IF-G2-07)",
          ir["stage"] == "ANOMALY"
          and ir["lifecycle"]["anomaly"]["state"] == "POST-CREATION-ANOMALY"
          and ir["lifecycle"]["anomaly"]["check"] == "VV-2"
          and vv2_rec["check"] == "VV-2"
          and vv2_rec["verdict"] == "FAILED"
          and ir["disposition"]["class"] == "PROCEED-WITH-ANNOTATION"
          and any("POST-CREATION-ANOMALY" in a
                  for a in ir["disposition"]["annotations"]))

    # 06d — capability boundary, not class boundary (IF-G2-08): a substrate
    #      of the READBACK-CAPABLE class whose surface_readback_available()
    #      returns False gets COVENANTED — the decision follows the declared
    #      capability, never the type ------------------------------------------
    store, cr0, cr1, _ = build_world()

    class CapabilityRevokedSubstrate(ConformanceSubstrate):
        def surface_readback_available(self) -> bool:
            return False

        def readback_surface(self) -> bytes:
            return b"[WOULD BE READBACK]"  # must never be consulted

        def envelope_readback(self) -> Dict[str, Any]:
            raise NotImplementedError("capability revoked")
    revoked = CapabilityRevokedSubstrate("revoked-engine", "tokenizer-v1",
                                         "W-testbed-1")
    ir = instantiate(cr1, store, base_tau(), revoked, "att-06d")
    vv2 = next(v for v in ir["verification"] if v["check"] == "VV-2")
    vv4 = next(v for v in ir["verification"] if v["check"] == "VV-4")
    check("06d capability-revoked substrate (same class as readback) -> "
          "VV-2/VV-4 COVENANTED — decision follows the capability, not the "
          "class",
          ir["stage"] == "COMPLETED"
          and vv2["verdict"] == "COVENANTED"
          and vv4["verdict"] == "COVENANTED")

    # 07 — IR lifecycle on the happy path: ESTABLISHED -> COMPLETED ----------
    store, cr0, cr1, sub = build_world()
    ir = instantiate(cr1, store, base_tau(), sub, "att-07")
    check("07 happy-path IR lifecycle: established at step 0 (attempt id + "
          "TaskRecord) and completed at step 5",
          ir["stage"] == "COMPLETED"
          and ir["task_record"]["task_content_digest"] is not None
          and ir["r2_digest"] is not None
          and ir["substrate_manifest"] is not None
          and ir["position_record"]["method"] == "derived"
          and ir["attached_segment_provenance"] == ["E0.seg[0..1]",
                                                    "E1.seg[0..3]"])

    # 08 — verdict tier profile recorded (machine-readable claim strength) ----
    store, cr0, cr1, sub = build_world()
    ir = instantiate(cr1, store, base_tau(), sub, "att-08")
    profile = {v["check"]: v["verdict"] for v in ir["verification"]}
    check("08 tier profile: all entered checks VERIFIED on the conformance "
          "substrate",
          profile.get("VV-1") == "VERIFIED"
          and profile.get("VV-2") == "VERIFIED"
          and profile.get("VV-3") == "VERIFIED"
          and profile.get("VV-4") == "VERIFIED"
          and profile.get("VV-5") == "VERIFIED"
          and profile.get("VV-6") == "VERIFIED"
          and profile.get("VV-7") == "VERIFIED")

    # 09 — no-restore annotation present on document-form runs ---------------
    store, cr0, cr1, sub = build_world()
    ir = instantiate(cr1, store, base_tau(), sub, "att-09")
    check("09 document-form: carrier-absent annotation recorded (no "
          "carrier-form no-recompute evidence)",
          any("carrier" in a for a in ir["disposition"]["annotations"]))

    # 10 — no semantic-judgment surface: all VV details are mechanical -------
    store, cr0, cr1, sub = build_world()
    ir = instantiate(cr1, store, base_tau(), sub, "att-10")
    mechanical = all(
        v["verdict"] in ("VERIFIED", "COVENANTED", "FAILED",
                         "NOT-APPLICABLE")
        for v in ir["verification"])
    check("10 VV verdicts confined to the frozen vocabulary "
          "(no semantic tier)", mechanical)

    print("\n".join(RESULTS))
    failed = sum(1 for r in RESULTS if r.startswith("[FAIL]"))
    print(f"\n{len(RESULTS) - failed}/{len(RESULTS)} checks passed"
          + (f" — {failed} FAILED" if failed else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
