"""I-1 G-3 — the E-run: the first end-to-end auditable I-1 runtime evidence.

Per the Implementation Gate Package (§4, "defined, not executed" — now
authorized): ONE end-to-end pass,

    E1 executes T1 -> R1 produced -> CR(E1) written
    resolve(CR_ref) -> R2 (V-1..V-5, three-state output)
    instantiate(R2, tau2-star, substrate) -> IR(S2) + S2 (VV-1..VV-7, tiers)
    E2 executes T2 from S2 -> CR(E2) written

with C-CAP measured exactly as frozen:
  (a) clean RESOLVED           (V-1..V-5 pass)
  (b) instantiate + continue   (T2 continued from S2)
  (c) no-recompute evidence    (document-form: E2's consumed input contains the
                               resolve output — R2/pinned items — and E2's
                               trace references E1.seg with no equivalent
                               new segment)

Judgment: success = (a)+(b)+(c) together. "It stored something" is not success.
No-oracle discipline throughout; document-form (no carrier-state restore).

Run:  python3 i1_g3_erun.py   (exit 0 = E-run SUPPORTED)
"""
from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, List

sys.path.insert(0, str(Path(__file__).parent))

from i1_records import ContentStore, sha256_hex, write_cr
from i1_instantiate import ConformanceSubstrate, instantiate
from i1_resolve import resolve

EVIDENCE: List[str] = []
CCAP: Dict[str, Any] = {}


def ev(name: str, ok: bool, detail: str = "") -> None:
    EVIDENCE.append(f"[{'PASS' if ok else 'FAIL'}] {name}"
                    + (f" — {detail}" if detail else ""))
    # machine-readable evidence: every judgment lands in the persisted record
    CCAP[name] = {"pass": ok, "detail": detail}


# ===========================================================================
# E1 — Task T1 executes and produces R1
# ===========================================================================
def run_e1(store: ContentStore) -> Dict[str, Any]:
    """E1: T1 = the compatibility analysis. Consumes F1..F3 (pinned at use
    time), produces R1, runs on segments E1.seg[0..3] on weights W-testbed-1.
    Its execution trace is recorded for C-CAP(c) predecessor provenance."""
    f_items = [
        {"name": "F1", "bytes": b"F1: alpha is baseline-compatible"},
        {"name": "F2", "bytes": b"F2: beta is baseline-compatible"},
        {"name": "F3", "bytes": b"F3: gamma is NOT baseline-compatible"},
    ]
    r1 = b"R1: deploy alpha+beta; block gamma (per F3)"
    surface = (b"[continuation surface: F1+F2+F3 analyzed under T1 rules; "
               b"R1 produced; the deployment decision may resolve R1]")
    cr = write_cr(
        store,
        result_bytes=r1,
        used_items=f_items,
        surface_bytes=surface,
        parent_cr_ref=None,
        formation={"procedure_id": "T1-compat-analysis",
                   "input_digests": []},
        provenance={"segments": ["E1.seg[0]", "E1.seg[1]", "E1.seg[2]",
                                 "E1.seg[3]"],
                    "weights_id": "W-testbed-1",
                    "backend": "testbed"},
    )
    trace = {  # E1's execution-trace record (document-form, minimal)
        "execution": "E1",
        "segments": ["E1.seg[0]", "E1.seg[1]", "E1.seg[2]", "E1.seg[3]"],
        "consumed": [u["content_digest"] for u in cr["used"]],
        "produced": cr["result"]["content_digest"],
    }
    return {"cr": cr, "trace": trace}


# ===========================================================================
# E2 — Task T2 resolves R1 and continues WITHOUT recomputing T1
# ===========================================================================
def run_e2(store: ContentStore, cr_ref: str, substrate,
           tau_star: Dict[str, Any], e1_trace: Dict[str, Any],
           r2: Dict[str, Any]) -> Dict[str, Any]:
    """E2: THE SINGLE instantiate of the E-run happens here; its S2 is the
    object T2 consumes (IF-G3-04: one lifecycle, one IR, one S2, throughout).
    IF-G3-03: T2's result is DERIVED FROM the S2-carried contents — the
    result digest is computed over the S2 surface bytes + position + bound
    weights, so the data flow is S2 → result, un-bypassable."""
    ir = instantiate(cr_ref, store, tau_star, substrate, attempt_id="E2-att-1")
    if ir["stage"] != "COMPLETED":
        raise RuntimeError(f"instantiate did not complete: {ir['disposition']}")

    # ---- T2 executes ON S2 (the continuation object instantiate produced) --
    s2 = substrate.continuation_object()
    if s2 is None:
        raise RuntimeError("no continuation object: instantiate did not "
                           "materialize an addressable S2")
    # Mechanical binding checks: the object E2 consumes IS the R2-derived one
    if s2["surface_bytes"] != r2["surface"]:
        raise RuntimeError("S2 surface is not the resolved surface")
    if s2["handle"]["surface_digest"] != r2["surface_digest"]:
        raise RuntimeError("S2 handle digest does not match R2")
    if s2["bound_weights_id"] != tau_star["weights_id"]:
        raise RuntimeError("S2 bound to an unexpected weights identity")

    # IF-G3-03: T2's result digest is computed OVER THE S2 CONTENTS
    # (surface bytes + position + bound weights read from the S2 object) —
    # a direct, un-bypassable data dependency: change any S2 field and the
    # result changes. R2 supplies only the R1 item referenced in CR(E2).
    s2_material = (s2["surface_bytes"]
                   + str(s2["position_units"]).encode("utf-8")
                   + s2["bound_weights_id"].encode("utf-8"))
    result_digest = sha256_hex(s2_material)
    result = (b"R2-result [digest " + result_digest.encode()[:24]
              + b"] derived from S2 surface " +
              s2["handle"]["surface_digest"].encode()[:16] + b" at position "
              + str(s2["position_units"]).encode() + b" on "
              + s2["bound_weights_id"].encode())
    e2_segments = ["E2.seg[0]", "E2.seg[1]"]
    consumed = [r2["surface_digest"]] + \
               [u["actual_digest"] for u in r2["used_items"]]
    trace = {
        "execution": "E2",
        "segments": e2_segments,
        "predecessor_references": list(r2["lineage"]["segments"]),
        "consumed": consumed,
        "executed_on_s2": {"surface_digest": s2["handle"]["surface_digest"],
                           "position_units": s2["position_units"],
                           "bound_weights_id": s2["bound_weights_id"],
                           "result_digest": result_digest},
        "produced": None,
    }
    cr2 = write_cr(
        store,
        result_bytes=result,
        used_items=[{"name": "R1", "bytes": store.get_blob(
            r2["result"]["content_digest"])},
            {"name": "F3", "bytes": b"F3: gamma is NOT baseline-compatible"}],
        surface_bytes=b"[continuation surface: R1 resolved; release plan issued]",
        parent_cr_ref=cr_ref,
        formation={"procedure_id": "T2-release-plan",
                   "input_digests": [cr_ref]},
        provenance={"segments": e2_segments,
                    "weights_id": "W-testbed-1",
                    "backend": "testbed"},
    )
    trace["produced"] = cr2["result"]["content_digest"]
    return {"ir": ir, "trace": trace, "cr2": cr2, "s2": s2,
            "result_digest": result_digest}


# ===========================================================================
# C-CAP judgment (frozen: (a) + (b) + (c), never "it stored something")
# ===========================================================================
def judge(res: Dict[str, Any], ir: Dict[str, Any],
          e2_trace: Dict[str, Any], e1_trace: Dict[str, Any],
          s2: Dict[str, Any], tau_star: Dict[str, Any]) -> bool:
    # (a) clean RESOLVED
    ccap_a = res["state"] == "RESOLVED" and not res["violations"]
    ev("C-CAP(a) clean RESOLVED (V-1..V-5 pass, zero violations)",
       ccap_a, f"resolve state = {res['state']}")
    # (b) instantiate + continue: COMPLETED IR, continuable disposition,
    #     and T2 ACTUALLY EXECUTED ON the S2 object instantiate produced
    #     (IF-G3-01): the consumed object's surface digest matches R2, the
    #     bound weights match the declaration, and the executed position is
    #     the S2-derived one
    s2_ok = (s2["handle"]["surface_digest"] == res["r2"]["surface_digest"]
             and s2["surface_bytes"] == res["r2"]["surface"]
             and s2["bound_weights_id"] == tau_star["weights_id"])
    ccap_b = (ir["stage"] == "COMPLETED"
              and ir["disposition"]["class"] == "PROCEED-WITH-ANNOTATION"
              and s2_ok
              and e2_trace.get("executed_on_s2") is not None
              and e2_trace["produced"] is not None)
    ev("C-CAP(b) instantiate + continue from S2 (T2 executed ON the "
       "continuation object)", ccap_b,
       f"IR stage = {ir['stage']}, disposition = "
       f"{ir['disposition']['class']}, S2 consumed: "
       f"{s2['handle']['surface_digest'][:12]}…")
    # (c) no-recompute, document-form — LIMITED MECHANICAL EVIDENCE
    #     (IF-G3-02 wording tightened): what is proven is that E2's trace
    #     references the inherited predecessor segments, does not reuse
    #     their identifiers for new work, and consumed the resolve output.
    #     It is finite document-form mechanical support — NOT a proof that
    #     no recomputation happened (a semantically-equivalent re-derivation
    #     under a new identifier is the registered detection boundary).
    refs = set(e2_trace["predecessor_references"])
    e1_segs = set(e1_trace["segments"])
    references_ok = e1_segs.issubset(refs)
    ev("C-CAP(c)-i E2 trace references all inherited predecessor segments",
       references_ok, f"{sorted(e1_segs & refs)}")
    new_segs = set(e2_trace["segments"])
    no_identifier_reuse = not (new_segs & e1_segs)
    ev("C-CAP(c)-ii E2 reused no predecessor segment identifier for new work "
       "(limited mechanical support; semantic re-derivation under a new id "
       "is the registered detection boundary)",
       no_identifier_reuse,
       f"E2 new segments {sorted(new_segs)} are identifier-disjoint from "
       f"E1's")
    consumed_necessary = (res["r2"]["surface_digest"] in e2_trace["consumed"])
    ev("C-CAP(necessary) E2 consumed the resolve output", consumed_necessary)
    ev("C-CAP(b)-s2 the executed object IS the R2-derived S2", s2_ok,
       "surface/handle/weights all match the resolved R2")
    return (ccap_a and ccap_b and references_ok and no_identifier_reuse
            and consumed_necessary and s2_ok)


def main() -> int:
    tmp = Path(tempfile.mkdtemp(prefix="i1-g3-erun-"))
    store = ContentStore(tmp)
    substrate = ConformanceSubstrate("testbed-engine", "tokenizer-v1",
                                     "W-testbed-1")
    tau_star = {
        "task_ref": "task/T2-release-plan",
        "declaration_source": "external/human",
        "version": "1",
        "weights_id": "W-testbed-1",
        "envelope": {"policy": "default", "lineage_strict_required": False},
    }

    # ---- the E-run ----------------------------------------------------------
    e1 = run_e1(store)
    ev("E1 executed T1; CR(E1) written with use-time-pinned F1..F3",
       e1["cr"]["cr_ref"] is not None and len(e1["cr"]["used"]) == 3,
       f"CR ref {e1['cr']['cr_ref'][:16]}…")
    res = resolve(e1["cr"]["cr_ref"], store)
    # IF-G3-04: ONE instantiate for the whole E-run — run_e2 performs it,
    # and the SAME IR and SAME S2 flow through T2 into CR(E2).
    e2 = run_e2(store, e1["cr"]["cr_ref"], substrate, tau_star,
                e1["trace"], res["r2"])
    ir = e2["ir"]
    ev("E2 executed T2 from the reconstructed S2; CR(E2) written",
       e2["cr2"]["cr_ref"] is not None,
       f"CR ref {e2['cr2']['cr_ref'][:16]}…")

    # ---- the auditable object chain -----------------------------------------
    chain_ok = (e2["cr2"]["continues"]["parent_cr_ref"]
                == e1["cr"]["cr_ref"])
    ev("auditable object chain CR(E1) -> IR(S2) -> CR(E2) is linked",
       chain_ok,
       "E2's lineage parent is E1's CR (resolve/instantiate provenance "
       "carried)")

    # ---- C-CAP ---------------------------------------------------------------
    ok = judge(res, ir, e2["trace"], e1["trace"], e2["s2"], tau_star)
    ev("E-RUN VERDICT: C-CAP SUPPORTED (document-form)" if ok
       else "E-RUN VERDICT: C-CAP NOT SUPPORTED", ok)

    # ---- evidence record (persisted alongside the run) -----------------------
    record = {
        "run": "G-3 E-run v3",
        "r2_state": res["state"],
        "ir_stage": ir["stage"],
        "ir_disposition": ir["disposition"],
        "ir_verification": ir["verification"],
        "ir_task_record": ir["task_record"],
        "ir_timestamp": ir["timestamp"],
        "ir_actor": ir["actor"],
        "ir_used_item_identities": ir["used_item_identities"],
        "binding": ir["binding_record"],
        "ccap": {k: v for k, v in CCAP.items()},
        "cr_chain": {"cr1": e1["cr"]["cr_ref"],
                     "cr2": e2["cr2"]["cr_ref"]},
        "verdict": "SUPPORTED" if ok else "NOT SUPPORTED",
    }
    out = Path(__file__).parent / "G3_ERUN_RECORD.json"
    out.write_text(json.dumps(record, indent=1, ensure_ascii=False),
                   encoding="utf-8")

    print("\n".join(EVIDENCE))
    failed = sum(1 for r in EVIDENCE if r.startswith("[FAIL]"))
    print(f"\n{len(EVIDENCE) - failed}/{len(EVIDENCE)} evidence items PASS"
          + (f" — {failed} FAILED" if failed else ""))
    print(f"evidence record: {out}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
