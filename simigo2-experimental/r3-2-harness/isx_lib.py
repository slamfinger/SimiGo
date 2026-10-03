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
# H-X4 construction audit invariant — per-op effect assertions
# (path relation relative to canonical IS₀; verified on the composed IS).
# ---------------------------------------------------------------------------

EFFECT_ASSERTIONS = {
    "R32-I-Δ1": [("runtime/runtime-declaration.json", "differs")],
    "R32-I-Δ2": [("lineage/lineage-root.json", "absent")],
    "R32-I-Δ3": [("lineage/lineage-root-conflict.json", "present")],
    "R32-A-Δ1": [("objects/R-1.json", "absent")],
    "R32-A-Δ2": [("universe/R-1.json", "present"),
                 ("manifest.json", "differs")],
    "R32-A-Δ3": [("objects/R-1.json", "differs")],
    "R32-C-Δ1": [("objects/I-S0.json", "absent")],
    "R32-C-Δ2": [("invalidation_index.json", "differs")],
    "R32-C-Δ3": [("invalidation_index.json", "differs")],
    "R32-B-Δ1": [("manifest.json", "differs")],
    "R32N-Δ6": [("objects/I-S0.json", "absent"),
                ("objects/store-v2/I-S0.json", "present")],
    "R32N-Δ8": [("manifest.json", "differs")],
    "R32N-Δ9": [("extra/extra-note.json", "present"),
                ("manifest.json", "differs")],
    "R32N-Δ10": [("lineage/lineage-root.json", "absent"),
                 ("lineage/store-v2/lineage-root.json", "present")],
}


def _rel_state(is_dir: str, rel: str, is0_dir: str) -> str:
    p = os.path.join(is_dir, rel)
    p0 = os.path.join(is0_dir, rel)
    e, e0 = os.path.exists(p), os.path.exists(p0)
    if not e and not e0:
        return "both-absent"
    if not e:
        return "absent"
    if not e0:
        return "present"
    return "same" if L.sha256_file(p) == L.sha256_file(p0) else "differs"


def check_effect(op_id: str, is_dir: str, is0_dir: str):
    """Returns list of failed assertion strings (empty = effect present)."""
    failures = []
    for rel, want in EFFECT_ASSERTIONS.get(op_id, []):
        got = _rel_state(is_dir, rel, is0_dir)
        if got != want:
            failures.append(f"{op_id}:{rel} want={want} got={got}")
    return failures


def construction_integrity(pair_id: str, op_a: str, op_b: str,
                           is_dir: str, is0_dir: str, replay_dir: str):
    """H-X4 CI-1..CI-5 (design §2a). Returns (pass, failures dict)."""
    failures = {}
    # CI-1 op presentation/registration
    if op_a not in PAIRS[pair_id]["op_a"] and op_a != PAIRS[pair_id]["op_a"]:
        failures["CI-1"] = "op_a mismatch"
    if op_b != PAIRS[pair_id]["op_b"]:
        failures["CI-1"] = "op_b mismatch"
    # CI-2/CI-3 per-op effect probes on the composed IS
    f2 = check_effect(op_a, is_dir, is0_dir)
    if f2:
        failures["CI-2"] = "; ".join(f2)
    f3 = check_effect(op_b, is_dir, is0_dir)
    if f3:
        failures["CI-3"] = "; ".join(f3)
    # CI-4 no undeclared operation: composed tree == (op_a∘op_b) replay tree
    if L.sha256_dir(replay_dir) != L.sha256_dir(is_dir):
        failures["CI-4"] = "composed tree != preregistered replay tree"
    # CI-5 order — recorded via observation sequence; runner asserts flag
    return (not failures, failures)


def resolution_trace(is_dir: str, key: str) -> dict:
    """H-X1 observation: actual resolution state for a key (no judgment)."""
    status, cands = L.resolve_key(is_dir, key)
    return {"key": key, "status": status,
            "candidates": [rel for rel, _b in cands]}
