#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
R3-N harness library — frozen counterexample catalog (design rev.2 §1).

Design source : SIMIGO_LAB_R3_3_DESIGN_R3N_20261003.md (rev.2, RATIFIED)
Evaluation    : r32_lib procedures reused AS-IS (zero changes — design §7
                "评估程序零改动"); this module only adds the R3-N frozen
                catalog, its CLASS derivation, and its rule-clause predictor.

Independence anchors (design §4):
  inv-2  N-catalog derived from frozen rule clauses (each op carries the
         clause it attacks); R3-2 outcomes are NOT an input.
  Catalog frozen at design-gate seal; execution must not add/remove/modify.
"""

import json
import os
import shutil

import r32_lib as L

# ---------------------------------------------------------------------------
# Frozen R3-N catalog (design §1 rev.2: 10 counterexample probes +
# 3 per-condition positive controls + K-0).
# Each N-op metadata carries the rule clause whose untested HOLD side it
# attacks (provenance for the derivation-purity audit).
# ---------------------------------------------------------------------------

def _op_n1(is_dir):   # unreferenced object deleted
    os.remove(os.path.join(is_dir, "objects/unreferenced-1.json"))
    idx = L.load_index(is_dir)
    idx.pop("unreferenced-1", None)
    L.save_index(is_dir, idx)


def _op_n2(is_dir):   # unreferenced object content rewritten (same key)
    p = "objects/unreferenced-1.json"
    obj = L.read_json(is_dir, p) if False else json.load(
        open(os.path.join(is_dir, p), encoding="utf-8"))
    obj["content"] = "rewritten unreferenced content (R32N-Δ2)"
    L.write_json(os.path.join(is_dir, p), obj)


def _op_n3(is_dir):   # dead index entry (key → nonexistent path)
    idx = L.load_index(is_dir)
    idx["ghost"] = ["objects/ghost.json"]
    L.save_index(is_dir, idx)


def _op_n4(is_dir):   # identical duplicate candidate for a referenced key
    shutil.copy(os.path.join(is_dir, "lineage/lineage-root.json"),
                os.path.join(is_dir, "lineage/lineage-root-dup.json"))
    idx = L.load_index(is_dir)
    idx["lineage-root"] = ["lineage/lineage-root.json",
                           "lineage/lineage-root-dup.json"]
    L.save_index(is_dir, idx)


def _op_n5(is_dir):   # field-preserving extension of a referenced object
    p = "runtime/runtime-declaration.json"
    obj = json.load(open(os.path.join(is_dir, p), encoding="utf-8"))
    obj["audit_note"] = "extra field added by R32N-Δ5 (fixture_class intact)"
    L.write_json(os.path.join(is_dir, p), obj)


def _op_n6(is_dir):   # prerequisite equivalent migration (I-S0)
    os.makedirs(os.path.join(is_dir, "objects/store-v2"), exist_ok=True)
    shutil.move(os.path.join(is_dir, "objects/I-S0.json"),
                os.path.join(is_dir, "objects/store-v2/I-S0.json"))
    idx = L.load_index(is_dir)
    idx["I-S0"] = ["objects/store-v2/I-S0.json"]
    L.save_index(is_dir, idx)


def _op_n7(is_dir):   # invalidation record targeting an UNREFERENCED key
    inv = L.load_invalidation(is_dir)
    inv["records"].append({"record_id": "INV-R32N-Δ7",
                           "type": "invalidation",
                           "target": "unreferenced-1",
                           "reason": "targets non-referenced key (R32N-Δ7)"})
    L.save_invalidation(is_dir, inv)


def _op_n8(is_dir):   # scope-tag addition (required tag untouched)
    m = L.load_manifest(is_dir)
    m["scope_tags"] = sorted(set(m["scope_tags"]) | {"r3-2-archive-scope"})
    L.save_manifest(is_dir, m)


def _op_n9(is_dir):   # in_scope region addition (new region, unreferenced)
    os.makedirs(os.path.join(is_dir, "extra"), exist_ok=True)
    L.write_json(os.path.join(is_dir, "extra/extra-note.json"),
                 {"id": "EXTRA-1", "content": "new region note (R32N-Δ9)"})
    m = L.load_manifest(is_dir)
    m["in_scope"] = sorted(set(m["in_scope"]) | {"extra/"})
    L.save_manifest(is_dir, m)
    idx = L.load_index(is_dir)
    idx["extra-note"] = ["extra/extra-note.json"]
    L.save_index(is_dir, idx)


def _op_n10(is_dir):  # lineage equivalent migration (lineage-root)
    os.makedirs(os.path.join(is_dir, "lineage/store-v2"), exist_ok=True)
    shutil.move(os.path.join(is_dir, "lineage/lineage-root.json"),
                os.path.join(is_dir, "lineage/store-v2/lineage-root.json"))
    idx = L.load_index(is_dir)
    idx["lineage-root"] = ["lineage/store-v2/lineage-root.json"]
    L.save_index(is_dir, idx)


# SANITY positive controls re-instantiate FROZEN R3-2 catalog ops as-is.
N_CATALOG = {
    "R32N-Δ1": {"mechanism": "unreferenced-delete",
                "rule_clause": "判定只依赖 ES 引用键"
                               "（Spec resolve/C-REF/_referenced_keys）",
                "fn": _op_n1},
    "R32N-Δ2": {"mechanism": "unreferenced-mutate",
                "rule_clause": "同上（内容改写不触及引用键）",
                "fn": _op_n2},
    "R32N-Δ3": {"mechanism": "dead-index-entry",
                "rule_clause": "精确键解析+存在性过滤（设计 §5a H-D）",
                "fn": _op_n3},
    "R32N-Δ4": {"mechanism": "identical-duplicate",
                "rule_clause": "多候选坍缩规则：逐字节相同→收敛为 1",
                "fn": _op_n4},
    "R32N-Δ5": {"mechanism": "field-preserving-extension",
                "rule_clause": "字段域比较（I-EV-1 只比对声明字段）",
                "fn": _op_n5},
    "R32N-Δ6": {"mechanism": "prerequisite-equivalent-migration",
                "rule_clause": "可引用性=解析+边界，非存储地址（C-REF）",
                "fn": _op_n6},
    "R32N-Δ7": {"mechanism": "untargeted-invalidation",
                "rule_clause": "C-INV 扫描仅核对 ES 引用键目标",
                "fn": _op_n7},
    "R32N-Δ8": {"mechanism": "scope-tag-addition",
                "rule_clause": "C-DECL scope-tag 存在性检查方向性",
                "fn": _op_n8},
    "R32N-Δ9": {"mechanism": "in-scope-addition",
                "rule_clause": "边界隶属是要求侧（对象须在界内）",
                "fn": _op_n9},
    "R32N-Δ10": {"mechanism": "lineage-equivalent-migration",
                 "rule_clause": "referability=解析+边界（I-EV-2 引用组）",
                 "fn": _op_n10},
    "R32N-SANITY-A": {"mechanism": "positive-control",
                      "underlying": "R32-A-Δ3", "fn": L._op_a_delta3},
    "R32N-SANITY-I": {"mechanism": "positive-control",
                      "underlying": "R32-I-Δ1", "fn": L._op_i_delta1},
    "R32N-SANITY-C": {"mechanism": "positive-control",
                      "underlying": "R32-C-Δ2", "fn": L._op_c_delta2},
    "R32-K-0": {"mechanism": "no-op", "underlying": "R32-K-0",
                "fn": L._op_k0},
}

# Campaign order pinned at design gate (N probes → per-condition SANITY →
# K-0). Frozen; execution must not reorder.
CAMPAIGN_ORDER = [
    "R32N-Δ1", "R32N-Δ2", "R32N-Δ3", "R32N-Δ4", "R32N-Δ5",
    "R32N-Δ6", "R32N-Δ7", "R32N-Δ8", "R32N-Δ9", "R32N-Δ10",
    "R32N-SANITY-A", "R32N-SANITY-I", "R32N-SANITY-C",
    "R32-K-0",
]


def derive_class(op_id: str) -> str:
    meta = N_CATALOG[op_id]
    if meta["mechanism"] == "positive-control":
        return "SANITY"
    if meta["mechanism"] == "no-op":
        return "K-0"
    return "R3-N"


def predict(op_id: str, es: dict) -> dict:
    """Mechanically derive per-condition predictions from the rule clauses.

    N-ops: each mechanism branch mirrors the cited rule clause (design §1
    table) — all derive HOLD. SANITY ops delegate to the frozen R3-2
    predictor for their underlying op (no hand-written predictions).
    """
    meta = N_CATALOG[op_id]
    sat = ("SATISFIED", None)
    if meta["mechanism"] == "positive-control":
        return L.predict(meta["underlying"], es)
    if meta["mechanism"] == "no-op":
        return {"I": sat, "A": sat, "C": sat}

    # N-ops: rule-clause derivation. Each branch asserts the cited clause
    # leaves all three conditions satisfied for this ES evidence map.
    mech = meta["mechanism"]
    if mech in ("unreferenced-delete", "unreferenced-mutate",
                "dead-index-entry", "untargeted-invalidation",
                "scope-tag-addition", "in-scope-addition"):
        # cited clauses operate only on non-referenced keys / additive
        # manifest fields — no referenced key touched
        out = {"I": sat, "A": sat, "C": sat}
    elif mech == "identical-duplicate":
        # collapse rule: identical candidates resolve to one → I-EV-2 OK
        out = {"I": sat, "A": sat, "C": sat}
    elif mech == "field-preserving-extension":
        # field-scoped comparison: declared field unchanged → I-EV-1 OK
        out = {"I": sat, "A": sat, "C": sat}
    elif mech in ("prerequisite-equivalent-migration",
                  "lineage-equivalent-migration"):
        # referability = resolution + boundary; migration + index re-point
        # preserves both → C-REF / I-EV-2 OK
        out = {"I": sat, "A": sat, "C": sat}
    else:
        raise ValueError(f"unpredictable op {op_id}")
    return out
