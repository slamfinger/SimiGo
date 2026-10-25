"""I-1 G-1 conformance self-checks.

Verifies that the G-1 implementation (i1_records + i1_resolve) realizes the
FROZEN I-1 contract's Verification Suite V-1..V-5 with the exact frozen
failure signatures, plus the IR lifecycle format (frozen I-1d field list).

These are implementation self-checks (realization verification) — NOT the
E-run experiment (G-3), which stays gated.

Run:  python3 i1_g1_conformance.py   (exit 0 = all checks pass)
"""
from __future__ import annotations

import json
import shutil
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from i1_records import (ContentStore, compute_cr_identity, formation_baseline,
                        ir_new, ir_set_stage, ir_validate_completed,
                        sha256_hex)
from i1_resolve import resolve

RESULTS: List[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    RESULTS.append(f"[{'PASS' if ok else 'FAIL'}] {name}" +
                   (f" — {detail}" if detail else ""))


def signatures(res) -> List[str]:
    return [v["signature"] for v in res["violations"]]


def fresh_store(root: Path) -> ContentStore:
    return ContentStore(root)


def build_chain(root: Path):
    """A minimal two-CR lineage: CR0 (root, task briefing) -> CR1 (the
    resolution target). Returns (store, cr0_ref, cr1_ref, blobs)."""
    import i1_records
    store = fresh_store(root)
    f1 = b"F1: alpha is baseline-compatible"
    f2 = b"F2: beta conflicts with gamma"
    cr0 = i1_records.write_cr(
        store,
        result_bytes=b"TASK BRIEF: prepare release decision",
        used_items=[],
        surface_bytes=b"[briefing context for the release task]",
        parent_cr_ref=None,
        formation={"procedure_id": "T0-briefing", "input_digests": []},
        provenance={"segments": ["E0.seg[0..1]"], "backend": "testbed"},
    )
    cr1 = i1_records.write_cr(
        store,
        result_bytes=b"R1: gamma is NOT baseline-compatible; alpha+beta ok",
        used_items=[{"name": "F1", "bytes": f1},
                    {"name": "F2", "bytes": f2}],
        surface_bytes=(b"[continuation context: F1+F2 analysis performed; "
                       b"R1 produced; T2 may resolve R1]"),
        parent_cr_ref=cr0["cr_ref"],
        formation={"procedure_id": "T1-release-analysis",
                   "input_digests": [cr0["cr_ref"]]},
        provenance={"segments": ["E1.seg[0..3]"], "backend": "testbed"},
    )
    return store, cr0["cr_ref"], cr1["cr_ref"], {"f1": f1, "f2": f2}


def main() -> int:
    tmp = Path(tempfile.mkdtemp(prefix="i1-g1-conformance-"))

    # 01 — clean chain resolves ------------------------------------------------
    root = tmp / "01"
    store, cr0, cr1, _ = build_chain(root)
    res = resolve(cr1, store)
    check("01 clean chain -> RESOLVED with R2",
          res["state"] == "RESOLVED" and res["r2"] is not None
          and not res["violations"])
    check("01b lineage segments inherited into R2",
          res["r2"]["lineage"]["segments"] == ["E0.seg[0..1]", "E1.seg[0..3]"])

    # 02 — used item tampered -> I-MISMATCH -----------------------------------
    root = tmp / "02"
    store, cr0, cr1, _ = build_chain(root)
    f1_digest = sha256_hex(b"F1: alpha is baseline-compatible")
    (store.root / "blobs" / f1_digest).write_bytes(b"F1: TAMPERED")
    res = resolve(cr1, store)
    check("02 used item tampered -> I-MISMATCH (RESOLVED-WITH-VIOLATIONS)",
          res["state"] == "RESOLVED-WITH-VIOLATIONS"
          and "I-MISMATCH" in signatures(res))

    # 03 — used item missing -> I-NF ------------------------------------------
    root = tmp / "03"
    store, cr0, cr1, _ = build_chain(root)
    f2_digest = sha256_hex(b"F2: beta conflicts with gamma")
    (store.root / "blobs" / f2_digest).unlink()
    res = resolve(cr1, store)
    check("03 used item missing -> I-NF (RESOLVED-WITH-VIOLATIONS)",
          res["state"] == "RESOLVED-WITH-VIOLATIONS"
          and "I-NF" in signatures(res))

    # 04 — CR node tampered -> CR-ID-MISMATCH ---------------------------------
    root = tmp / "04"
    store, cr0, cr1, _ = build_chain(root)
    node = store.get_node(cr1)
    node["used"][0]["content_digest"] = sha256_hex(b"something else")
    store.overwrite_node(node, cr1)  # simulate substitution at the same address
    res = resolve(cr1, store)
    check("04 CR node tampered -> CR-ID-MISMATCH (UNRESOLVABLE)",
          res["state"] == "UNRESOLVABLE"
          and "CR-ID-MISMATCH" in signatures(res))

    # 05 — ancestor substituted -> A-SUB --------------------------------------
    root = tmp / "05"
    store, cr0, cr1, _ = build_chain(root)
    anc = store.get_node(cr0)
    anc["result"]["content_digest"] = sha256_hex(b"SUBSTITUTED BRIEF")
    store.overwrite_node(anc, cr0)
    res = resolve(cr1, store)
    check("05 ancestor substituted -> A-SUB (RESOLVED-WITH-VIOLATIONS)",
          res["state"] == "RESOLVED-WITH-VIOLATIONS"
          and "A-SUB" in signatures(res))

    # 06 — ancestor missing -> A-NF -------------------------------------------
    root = tmp / "06"
    store, cr0, cr1, _ = build_chain(root)
    (store.root / "nodes" / f"{cr0}.json").unlink()
    res = resolve(cr1, store)
    check("06 ancestor missing -> A-NF (RESOLVED-WITH-VIOLATIONS)",
          res["state"] == "RESOLVED-WITH-VIOLATIONS"
          and "A-NF" in signatures(res))

    # 07 — lineage cycle -> A-CYCLE -------------------------------------------
    root = tmp / "07"
    store = fresh_store(root)
    import i1_records
    a = i1_records.write_cr(store, result_bytes=b"A", used_items=[],
                            surface_bytes=b"surface A", parent_cr_ref=None,
                            formation={"procedure_id": "p-a",
                                       "input_digests": []},
                            provenance={})
    b = i1_records.write_cr(store, result_bytes=b"B", used_items=[],
                            surface_bytes=b"surface B", parent_cr_ref=a["cr_ref"],
                            formation={"procedure_id": "p-b",
                                       "input_digests": []},
                            provenance={})
    # force a cycle: node A now continues -> B (edited at the same address);
    # A-CYCLE is exercised with the conformance instrument
    # (verify_lineage_identity=False), because with parent refs hashed into
    # CR identities a store-built cycle always trips A-SUB first.
    na = store.get_node(a["cr_ref"])
    na["continues"]["parent_cr_ref"] = b["cr_ref"]
    store.overwrite_node(na, a["cr_ref"])
    res = resolve(b["cr_ref"], store, verify_lineage_identity=False)
    check("07 lineage cycle -> A-CYCLE (UNRESOLVABLE)",
          res["state"] == "UNRESOLVABLE" and "A-CYCLE" in signatures(res))

    # 08 — surface tampered -> P-VIOLATION ------------------------------------
    root = tmp / "08"
    store, cr0, cr1, _ = build_chain(root)
    s_digest = store.get_node(cr1)["surface"]["content_digest"]
    (store.root / "blobs" / s_digest).write_bytes(b"[TAMPERED SURFACE]")
    res = resolve(cr1, store)
    check("08 surface tampered -> P-VIOLATION (RESOLVED-WITH-VIOLATIONS)",
          res["state"] == "RESOLVED-WITH-VIOLATIONS"
          and "P-VIOLATION" in signatures(res))

    # 09 — formation drift -> FORM-DRIFT --------------------------------------
    root = tmp / "09"
    store, cr0, cr1, _ = build_chain(root)
    node = store.get_node(cr1)
    node["formation"]["procedure_id"] = "T1-release-analysis-v2"
    store.overwrite_node(node, cr1)
    res = resolve(cr1, store)
    check("09 formation drift -> FORM-DRIFT (RESOLVED-WITH-VIOLATIONS)",
          res["state"] == "RESOLVED-WITH-VIOLATIONS"
          and "FORM-DRIFT" in signatures(res))

    # 10 — provenance is outside the identity hash (drop-test property) -------
    root = tmp / "10"
    store = fresh_store(root)
    c1 = i1_records.write_cr(store, result_bytes=b"same result",
                             used_items=[{"name": "F", "bytes": b"F"}],
                             surface_bytes=b"surface",
                             parent_cr_ref=None,
                             formation={"procedure_id": "p",
                                        "input_digests": []},
                             provenance={"actor": "one"})
    c2 = i1_records.write_cr(store, result_bytes=b"same result",
                             used_items=[{"name": "F", "bytes": b"F"}],
                             surface_bytes=b"surface",
                             parent_cr_ref=None,
                             formation={"procedure_id": "p",
                                        "input_digests": []},
                             provenance={"actor": "two", "extra": True})
    check("10 provenance outside identity hash (identical identity fields "
          "-> identical cr_ref)", c1["cr_ref"] == c2["cr_ref"])

    # 11 — canonical order (used-set insertion order irrelevant) --------------
    root = tmp / "11"
    store = fresh_store(root)
    x = i1_records.write_cr(store, result_bytes=b"R",
                            used_items=[{"name": "a", "bytes": b"A"},
                                        {"name": "b", "bytes": b"B"}],
                            surface_bytes=b"surface",
                            parent_cr_ref=None,
                            formation={"procedure_id": "p",
                                       "input_digests": []},
                            provenance={})
    y = i1_records.write_cr(store, result_bytes=b"R",
                            used_items=[{"name": "b", "bytes": b"B"},
                                        {"name": "a", "bytes": b"A"}],
                            surface_bytes=b"surface",
                            parent_cr_ref=None,
                            formation={"procedure_id": "p",
                                       "input_digests": []},
                            provenance={})
    check("11 canonical order: insertion order does not change CR identity",
          x["cr_ref"] == y["cr_ref"])

    # 12 — root reference dangling -> C-REF-NOT-FOUND --------------------------
    root = tmp / "12"
    store = fresh_store(root)
    res = resolve("deadbeef" * 8, store)
    check("12 dangling root reference -> C-REF-NOT-FOUND (UNRESOLVABLE)",
          res["state"] == "UNRESOLVABLE"
          and "C-REF-NOT-FOUND" in signatures(res))

    # 13 — IR lifecycle: establish -> complete (clean audit) ------------------
    ir = ir_new("attempt-1", cr_ref="cr-ref-x",
                task_record={"task_ref": "task/T2",
                             "task_content_digest": sha256_hex(b"T2 spec"),
                             "declaration_source": "external/human",
                             "version": "1"},
                timestamp="2026-10-05T00:00:00Z", actor="test/g1")
    ir_set_stage(ir, "COMPLETED")
    ir["r2_digest"] = "r2-digest"
    ir["binding_record"] = {"state": "BOUND"}
    ir["execution_envelope"] = {"policy": "default"}
    ir["substrate_manifest"] = {"engine-id": "testbed"}
    ir["position_record"] = {"method": "derived"}
    ir["attached_segment_provenance"] = ["E1.seg[0..3]"]
    ir["used_item_identities"] = []
    ir["verification"] = [{"check": "VV-1", "verdict": "VERIFIED"}]
    findings = ir_validate_completed(ir)
    check("13 IR lifecycle: ESTABLISHED -> COMPLETED, clean audit "
          "(timestamp/actor included)",
          findings == [] and ir["timestamp"] == "2026-10-05T00:00:00Z"
          and ir["actor"] == "test/g1")

    # 14 — IR: incomplete completed record -> audit findings ------------------
    ir2 = ir_new("attempt-2", cr_ref="cr-ref-y",
                 task_record={"task_ref": "task/T2b",
                              "task_content_digest": sha256_hex(b"x"),
                              "declaration_source": "external/human"},
                 timestamp="2026-10-05T00:00:01Z", actor="test/g1")
    ir_set_stage(ir2, "COMPLETED")  # fields left pending
    findings = ir_validate_completed(ir2)
    check("14 IR completed with pending fields -> audit findings",
          len(findings) > 0
          and any(f.startswith("FIELD-INCOMPLETE") for f in findings))

    # 15 — IR: invalid verdict tier -> audit finding ---------------------------
    ir["verification"].append({"check": "VV-2", "verdict": "KIND-OF-OK"})
    findings = ir_validate_completed(ir)
    check("15 IR invalid verdict tier -> VERDICT-TIER-INVALID finding",
          any("VERDICT-TIER-INVALID" in f for f in findings))

    # 16 — IR: precondition-fail closure carries the disposition --------------
    ir3 = ir_new("attempt-3", cr_ref="cr-ref-z",
                 task_record={"task_ref": "task/T3",
                              "task_content_digest": sha256_hex(b"y"),
                              "declaration_source": "external/human"},
                 timestamp="2026-10-05T00:00:02Z", actor="test/g1")
    ir_set_stage(ir3, "CLOSED")
    ir3["disposition"] = {"class": "BLOCK",
                          "subtype": "PRECONDITION-BLOCK",
                          "signatures": ["PRECONDITION-FAIL"]}
    check("16 IR precondition-fail closure carries BLOCK/PRECONDITION-BLOCK",
          ir3["disposition"]["class"] == "BLOCK"
          and ir3["stage"] == "CLOSED")

    # 17 — result blob missing -> V-1 / C-REF-NOT-FOUND (IF-G1-01) ------------
    root = tmp / "17"
    store, cr0, cr1, _ = build_chain(root)
    r_digest = store.get_node(cr1)["result"]["content_digest"]
    (store.root / "blobs" / r_digest).unlink()
    res = resolve(cr1, store)
    check("17 result blob missing -> V-1 / C-REF-NOT-FOUND (UNRESOLVABLE)",
          res["state"] == "UNRESOLVABLE"
          and any(v["signature"] == "C-REF-NOT-FOUND" and v["check"] == "V-1"
                  for v in res["violations"]))

    # 18 — result content substituted -> V-2 / I-MISMATCH (IF-G1-01) ----------
    root = tmp / "18"
    store, cr0, cr1, _ = build_chain(root)
    r_digest = store.get_node(cr1)["result"]["content_digest"]
    (store.root / "blobs" / r_digest).write_bytes(b"SUBSTITUTED RESULT")
    res = resolve(cr1, store)
    check("18 result content substituted -> V-2 / I-MISMATCH "
          "(RESOLVED-WITH-VIOLATIONS)",
          res["state"] == "RESOLVED-WITH-VIOLATIONS"
          and any(v["signature"] == "I-MISMATCH" and v["check"] == "V-2"
                  for v in res["violations"]))

    shutil.rmtree(tmp, ignore_errors=True)

    print("\n".join(RESULTS))
    failed = sum(1 for r in RESULTS if r.startswith("[FAIL]"))
    print(f"\n{len(RESULTS) - failed}/{len(RESULTS)} checks passed"
          + (f" — {failed} FAILED" if failed else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
