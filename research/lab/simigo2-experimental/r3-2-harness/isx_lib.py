#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
IS-X harness library — frozen ordered-pair catalog (design rev.2 §2/§2a).

Design source : SIMIGO_LAB_ISX_DESIGN_GATE_20261003.md (rev.2, RATIFIED)
Evaluation    : r32_lib procedures reused AS-IS (zero changes).
Op dispatch   : frozen single-variable ops from r32_lib.CATALOG and
                r3n_lib.N_CATALOG (no new single-variable ops — §4a).
P_comp        : mechanical composition of the frozen single-variable
                predictors at construction time (design §3) — never
                hand-written, never derived from outcomes.
"""

import json
import os

import r32_lib as L
import r3n_lib as N


def get_op_fn(op_id: str):
    if op_id in L.CATALOG:
        return L.CATALOG[op_id]["fn"]
    if op_id in N.N_CATALOG:
        return N.N_CATALOG[op_id]["fn"]
    raise KeyError(op_id)


def predict_single(op_id: str, es: dict):
    if op_id in L.CATALOG:
        return L.predict(op_id, es)
    if op_id in N.N_CATALOG:
        return N.predict(op_id, es)
    raise KeyError(op_id)


# ---------------------------------------------------------------------------
# Frozen ordered-pair catalog (design §2, 12 pairs; static compatibility
# verified in the design document §2 table).
# ---------------------------------------------------------------------------

PAIRS = {
    "X-01": {"op_a": "R32-I-Δ2", "op_b": "R32-A-Δ1",
             "relation": "cross I×A BROKEN×BROKEN"},
    "X-02": {"op_a": "R32-I-Δ1", "op_b": "R32-C-Δ2",
             "relation": "cross I×C BROKEN×BROKEN"},
    "X-03": {"op_a": "R32-A-Δ3", "op_b": "R32-C-Δ2",
             "relation": "cross A×C BROKEN×BROKEN"},
    "X-04": {"op_a": "R32-I-Δ2", "op_b": "R32-C-Δ1",
             "relation": "cross I×C BROKEN×BROKEN"},
    "X-05": {"op_a": "R32-I-Δ1", "op_b": "R32-I-Δ2",
             "relation": "same-I BROKEN×BROKEN"},
    "X-06": {"op_a": "R32-A-Δ3", "op_b": "R32-A-Δ2",
             "relation": "same-A BROKEN×BROKEN"},
    "X-07": {"op_a": "R32-C-Δ2", "op_b": "R32-C-Δ3",
             "relation": "same-C BROKEN×BROKEN"},
    "X-08": {"op_a": "R32-I-Δ2", "op_b": "R32-I-Δ3",
             "relation": "same-I order-1 — MASKING candidate (design §2a)",
             "resolution_key": "lineage-root"},
    "X-09": {"op_a": "R32-I-Δ3", "op_b": "R32-I-Δ2",
             "relation": "same-I order-2 (reverse of X-08)",
             "resolution_key": "lineage-root"},
    "X-10": {"op_a": "R32N-Δ6", "op_b": "R32N-Δ10",
             "relation": "HOLD×HOLD — two equivalent migrations"},
    "X-11": {"op_a": "R32N-Δ8", "op_b": "R32N-Δ9",
             "relation": "HOLD×HOLD — manifest additive RMW"},
    "X-12": {"op_a": "R32-B-Δ1", "op_b": "R32-A-Δ2",
             "relation": "cross-class — exclusion-set composition closure "
                         "(design §2a R)"},
}

CAMPAIGN_ORDER = (
    [f"X-{i:02d}" for i in range(1, 13)] +
    ["R32N-SANITY-A", "R32N-SANITY-I", "R32N-SANITY-C", "R32-K-0"])


def derive_class(cell_op: str) -> str:
    if cell_op in PAIRS:
        return "IS-X"
    if cell_op.startswith("R32N-SANITY"):
        return "SANITY"
    if cell_op == "R32-K-0":
        return "K-0"
    raise ValueError(cell_op)


# ---------------------------------------------------------------------------
# P_comp — mechanical composition of frozen single-variable predictions
# (design §3). sig-set = union of constituent signatures.
# ---------------------------------------------------------------------------

def compose_predictions(pred_a: dict, pred_b: dict) -> dict:
    out = {}
    for c in ("I", "A", "C"):
        sa, ga = pred_a[c]
        sb, gb = pred_b[c]
        if sa == "SATISFIED" and sb == "SATISFIED":
            out[c] = {"state": "SATISFIED", "sig_set": []}
        elif sa == "BROKEN" and sb == "SATISFIED":
            out[c] = {"state": "BROKEN", "sig_set": [ga]}
        elif sa == "SATISFIED" and sb == "BROKEN":
            out[c] = {"state": "BROKEN", "sig_set": [gb]}
        else:  # both BROKEN
            out[c] = {"state": "BROKEN",
                      "sig_set": sorted({ga, gb} - {None})}
    return out


def predict_pair(pair_id: str, es: dict) -> dict:
    p = PAIRS[pair_id]
    return compose_predictions(predict_single(p["op_a"], es),
                               predict_single(p["op_b"], es))


def predict_cell(cell_op: str, es: dict) -> dict:
    if cell_op in PAIRS:
        return predict_pair(cell_op, es)
    if cell_op.startswith("R32N-SANITY"):
        return N.predict(cell_op, es)
    if cell_op == "R32-K-0":
        return {c: ("SATISFIED", None) for c in ("I", "A", "C")}
    raise ValueError(cell_op)


# ---------------------------------------------------------------------------
# R1 revision (SIMIGO_LAB_ISX_IMPL_REVISION_20261003.md §1) — object/effect
# identity based effect assertions. Replaces the path-pinned probes
# (measurement model mismatch F-3): assertions follow the OBJECT via
# key-identity (pinned exact-key resolution) / content-identity (byte
# search) / manifest-field / record identity — no path dependency, no
# semantic judgment. Derivation source = op effect definitions (general);
# X-08/X-09 outcomes are NOT an input (independence guard G-1).
# ---------------------------------------------------------------------------

def _key_state(is_dir: str, is0_dir: str, key: str) -> dict:
    status, cands = L.resolve_key(is_dir, key)
    s0_status, s0_cands = L.resolve_key(is0_dir, key)
    is0_bytes = s0_cands[0][1] if s0_status == "found" else None
    resolved_bytes = cands[0][1] if status == "found" else None
    vs = None
    if resolved_bytes is not None and is0_bytes is not None:
        vs = "same" if resolved_bytes == is0_bytes else "differs"
    return {"status": status, "paths": [rel for rel, _ in cands],
            "bytes": resolved_bytes, "bytes_vs_is0": vs}


def _content_absent(is_dir: str, is0_dir: str, rel: str) -> dict:
    """Byte-identity search: is the IS₀ object at rel present anywhere in
    the composed IS? Empty hits = object absent everywhere."""
    p0 = os.path.join(is0_dir, rel)
    if not os.path.exists(p0):
        return {"searched": False, "hits": [],
                "note": "ill-formed: is0 file absent"}
    with open(p0, "rb") as f:
        target = f.read()
    hits = []
    for root, _d, files in os.walk(is_dir):
        for f in files:
            fp = os.path.join(root, f)
            try:
                with open(fp, "rb") as fh:
                    if fh.read() == target:
                        hits.append(os.path.relpath(fp, is_dir)
                                    .replace(os.sep, "/"))
            except OSError:
                pass
    return {"searched": True, "hits": hits}


# Per-op declared effects (design revision §1.3) — assertion tuples.
OP_EFFECT_SPEC = {
    "R32-I-Δ1": [("key-field", "runtime-declaration", "fixture_class",
                  "r3-2-minimal-v1-TAMPERED")],
    "R32-I-Δ2": [("content-absent", "lineage/lineage-root.json")],
    "R32-I-Δ3": [("file-present", "lineage/lineage-root-conflict.json")],
    "R32-A-Δ1": [("key-unresolved", "anchor:state-diff"),
                 ("content-absent", "objects/R-1.json")],
    "R32-A-Δ2": [("key-resolved-at", "anchor:state-diff",
                  "universe/R-1.json"),
                 ("manifest-contains", "out_of_scope", "universe/")],
    "R32-A-Δ3": [("key-substituted", "anchor:state-diff")],
    "R32-C-Δ1": [("key-unresolved", "I-S0"),
                 ("content-absent", "objects/I-S0.json")],
    "R32-C-Δ2": [("invalidation-has", "INV-R32-C-Δ2")],
    "R32-C-Δ3": [("invalidation-has", "SUP-R32-C-Δ3")],
    "R32-B-Δ1": [("manifest-contains", "out_of_scope", "archive/")],
    "R32N-Δ6": [("key-resolved-at", "I-S0", "objects/store-v2/I-S0.json"),
                ("key-same-bytes", "I-S0")],
    "R32N-Δ8": [("manifest-contains", "scope_tags", "r3-2-archive-scope")],
    "R32N-Δ9": [("file-present", "extra/extra-note.json"),
                ("manifest-contains", "in_scope", "extra/")],
    "R32N-Δ10": [("key-resolved-at", "lineage-root",
                  "lineage/store-v2/lineage-root.json"),
                 ("key-same-bytes", "lineage-root")],
}


def eval_effect_assertion(is_dir: str, is0_dir: str, a):
    kind = a[0]
    if kind == "key-field":
        _, key, field, value = a
        st = _key_state(is_dir, is0_dir, key)
        if st["status"] != "found":
            return False, f"key {key} {st['status']}"
        obj = json.loads(st["bytes"].decode("utf-8"))
        return obj.get(field) == value, f"{field}={obj.get(field)!r}"
    if kind == "content-absent":
        _, rel = a
        r = _content_absent(is_dir, is0_dir, rel)
        if not r["searched"]:
            return False, r["note"]
        return len(r["hits"]) == 0, f"byte-identity hits={r['hits']}"
    if kind == "file-present":
        ok = os.path.exists(os.path.join(is_dir, a[1]))
        return ok, f"{a[1]} present={ok}"
    if kind == "key-unresolved":
        st = _key_state(is_dir, is0_dir, a[1])
        return st["status"] == "not-found", f"{a[1]} {st['status']}"
    if kind == "key-resolved-at":
        _, key, path = a
        st = _key_state(is_dir, is0_dir, key)
        ok = st["status"] == "found" and st["paths"] == [path]
        return ok, f"{key} paths={st['paths']}"
    if kind == "key-substituted":
        st = _key_state(is_dir, is0_dir, a[1])
        ok = st["status"] == "found" and st["bytes_vs_is0"] == "differs"
        return ok, f"{a[1]} bytes_vs_is0={st['bytes_vs_is0']}"
    if kind == "key-same-bytes":
        st = _key_state(is_dir, is0_dir, a[1])
        ok = st["status"] == "found" and st["bytes_vs_is0"] == "same"
        return ok, f"{a[1]} bytes_vs_is0={st['bytes_vs_is0']}"
    if kind == "key-resolves":
        st = _key_state(is_dir, is0_dir, a[1])
        return st["status"] == "found", f"{a[1]} {st['status']}"
    if kind == "manifest-contains":
        _, field, value = a
        m = L.load_manifest(is_dir)
        ok = value in m.get(field, [])
        return ok, f"{field} contains {value!r}={ok}"
    if kind == "invalidation-has":
        _, rid = a
        inv = L.load_invalidation(is_dir)
        ok = any(r.get("record_id") == rid
                 for r in inv.get("records", []))
        return ok, f"record {rid} present={ok}"
    raise ValueError(f"unknown assertion {a}")


def check_effect_v2(op_id: str, is_dir: str, is0_dir: str):
    """Object/effect identity based probe (R1). Returns failed assertions."""
    failures = []
    for a in OP_EFFECT_SPEC.get(op_id, []):
        ok, detail = eval_effect_assertion(is_dir, is0_dir, a)
        if not ok:
            failures.append(f"{op_id}:{a} → {detail}")
    return failures


def check_effect(op_id: str, is_dir: str, is0_dir: str):
    """Deprecated path-pinned probe retained only for Attempt #1 history —
    superseded by check_effect_v2 (R1); must not be used for new runs."""
    return check_effect_v2(op_id, is_dir, is0_dir)


def construction_integrity(pair_id: str, op_a: str, op_b: str,
                           is_dir: str, is0_dir: str, replay_dir: str):
    """H-X4 CI-1..CI-4 via R1 object-identity probes (CI-5 order is
    verified from the observation sequence by the audit). Signature
    unchanged for caller compatibility."""
    failures = {}
    if op_a != PAIRS[pair_id]["op_a"]:
        failures["CI-1"] = "op_a mismatch"
    if op_b != PAIRS[pair_id]["op_b"]:
        failures["CI-1"] = "op_b mismatch"
    f2 = check_effect_v2(op_a, is_dir, is0_dir)
    if f2:
        failures["CI-2"] = "; ".join(f2)
    f3 = check_effect_v2(op_b, is_dir, is0_dir)
    if f3:
        failures["CI-3"] = "; ".join(f3)
    if L.sha256_dir(replay_dir) != L.sha256_dir(is_dir):
        failures["CI-4"] = "composed tree != preregistered replay tree"
    return (not failures, failures)


def resolution_trace(is_dir: str, key: str) -> dict:
    """H-X1 observation: actual resolution state for a key (no judgment)."""
    status, cands = L.resolve_key(is_dir, key)
    return {"key": key, "status": status,
            "candidates": [rel for rel, _b in cands]}
