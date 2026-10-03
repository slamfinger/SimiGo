#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
R3-2 harness library — fixture, frozen ΔIS catalog, and R3-1 Spec rev.2
evaluation procedures.

Design source : SIMIGO_LAB_R3_2_DESIGN_20261003.md (rev.2, RATIFIED)
Judgment rule : SIMIGO_LAB_R3_1_JUDGMENT_SPECIFICATION_20261003.md
                (rev.2, RATIFIED) — referenced, not modified.
Zero dependencies (stdlib only); zero model inference (R3-2 design §1).

Discipline implemented here (design §4/§4a):
  - ΔIS catalog is FROZEN; classes are mechanically derived from op
    metadata by CLASS_RULE (never hand-assigned).
  - Predictions are mechanically derived by predict() from op metadata
    x ES evidence map (construction-time knowledge only).
"""

import hashlib
import json
import os
import shutil

# ---------------------------------------------------------------------------
# canonical hashing
# ---------------------------------------------------------------------------

def sha256_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def canonical_json_bytes(obj) -> bytes:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=False).encode("utf-8")


def sha256_canonical(obj) -> str:
    return sha256_bytes(canonical_json_bytes(obj))


def sha256_dir(path: str) -> str:
    """Deterministic directory hash: sorted relpaths + file content hashes."""
    entries = []
    for root, _dirs, files in os.walk(path):
        for name in files:
            full = os.path.join(root, name)
            rel = os.path.relpath(full, path).replace(os.sep, "/")
            entries.append((rel, sha256_file(full)))
    entries.sort()
    blob = "\n".join(f"{rel}:{h}" for rel, h in entries).encode("utf-8")
    return sha256_bytes(blob)


def read_json(path: str):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path: str, obj) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")


# ---------------------------------------------------------------------------
# Information Space (IS) — fixture structure (design §2, §2a)
#
# IS holds ONLY referable objects and mutation records.
# Judgment baselines live exclusively in the ES artifact (§2a H-B).
# ---------------------------------------------------------------------------

IS_MANIFEST = "manifest.json"
IS_INDEX = "index.json"
IS_INVALIDATION = "invalidation_index.json"


def load_manifest(is_dir):
    return read_json(os.path.join(is_dir, IS_MANIFEST))


def load_index(is_dir):
    return read_json(os.path.join(is_dir, IS_INDEX))


def load_invalidation(is_dir):
    return read_json(os.path.join(is_dir, IS_INVALIDATION))


def save_manifest(is_dir, m):
    write_json(os.path.join(is_dir, IS_MANIFEST), m)


def save_index(is_dir, idx):
    write_json(os.path.join(is_dir, IS_INDEX), idx)


def save_invalidation(is_dir, inv):
    write_json(os.path.join(is_dir, IS_INVALIDATION), inv)


def in_boundary(manifest, relpath: str):
    """True iff relpath is inside current IS boundary and accessible.

    Deterministic per design §5a H-D: prefix membership against the
    manifest's in_scope / out_of_scope / access_denied lists.
    """
    rel = relpath.replace(os.sep, "/")
    for p in manifest.get("out_of_scope", []):
        if rel.startswith(p):
            return False, "out-of-boundary"
    for p in manifest.get("access_denied", []):
        if rel.startswith(p):
            return False, "inaccessible"
    ok = any(rel.startswith(p) for p in manifest.get("in_scope", []))
    return (ok, None if ok else "outside-in-scope-declaration")


def resolve_key(is_dir, key: str):
    """Exact-key resolution (design §5a H-D: exact match, no fuzz).

    Returns (status, candidates):
      status ∈ {"found", "not-found", "ambiguous", "structural-missing"}
      candidates: list of (relpath, bytes) for found/ambiguous.
    Multi-candidate with byte-identical content collapses to one
    (deterministic rule pinned in the harness README).
    """
    idx_path = os.path.join(is_dir, IS_INDEX)
    if not os.path.exists(idx_path):
        return "structural-missing", []
    idx = read_json(idx_path)
    rels = idx.get(key, [])
    found = []
    for rel in rels:
        full = os.path.join(is_dir, rel)
        if os.path.exists(full):
            with open(full, "rb") as f:
                found.append((rel, f.read()))
    if not found:
        return "not-found", []
    if len(found) > 1:
        contents = {c for _r, c in found}
        if len(contents) > 1:
            return "ambiguous", found
        found = found[:1]
    return "found", found


# ---------------------------------------------------------------------------
# Evaluation procedures — R3-1 Spec rev.2 §1 / §2 / §3 instantiated.
# Each returns (state, signature, detail) with
# state ∈ {"SATISFIED", "BROKEN", "NOT-EVALUABLE"}.
# ---------------------------------------------------------------------------

def _structural(is_dir, mode: str):
    """H-C disambiguation (design §5 rev.2):
    in-cell t1 structural missing  -> I BROKEN (I-STRUCT-REMOVED)
    setup-stage structural missing -> NOT-EVALUABLE (S-1 path)
    """
    for name in (IS_INDEX, IS_MANIFEST):
        if not os.path.exists(os.path.join(is_dir, name)):
            if mode == "t1":
                return ("BROKEN", "I-STRUCT-REMOVED",
                        f"{name} missing at t1 (existed at t0;唯一变量=ΔIS)")
            return ("NOT-EVALUABLE", "I-UNSTRUCT",
                    f"{name} missing at setup")
    return None


def eval_I(es: dict, is_dir: str, mode: str = "t1"):
    st = _structural(is_dir, mode)
    if st:
        return st
    manifest = load_manifest(is_dir)

    # I-EV-1: model/fixture binding — self declaration vs IS-side declaration
    ev1 = es["I_ev"]["I-EV-1"]
    status, cands = resolve_key(is_dir, ev1["is_reference"]["key"])
    if status == "structural-missing":
        return ("BROKEN", "I-STRUCT-REMOVED", "index missing (t1)") \
            if mode == "t1" else ("NOT-EVALUABLE", "I-UNSTRUCT", "index missing")
    if status == "not-found":
        return ("BROKEN", "I-NF", "runtime-declaration not found")
    if status == "ambiguous":
        return ("BROKEN", "I-AMBIG", "runtime-declaration ambiguous")
    decl = json.loads(cands[0][1].decode("utf-8"))
    field = ev1["is_reference"]["field"]
    if decl.get(field) != ev1["self_declaration"][field]:
        return ("BROKEN", "I-MISMATCH",
                f"IS-side {field}={decl.get(field)!r} != ES declaration "
                f"{ev1['self_declaration'][field]!r}")

    # I-EV-2: lineage binding — lineage reference resolvable & unambiguous
    ev2 = es["I_ev"]["I-EV-2"]
    status, cands = resolve_key(is_dir, ev2["is_reference"]["key"])
    if status == "not-found":
        return ("BROKEN", "I-NF", "lineage-root not found")
    if status == "ambiguous":
        return ("BROKEN", "I-AMBIG",
                "lineage-root resolves to conflicting candidates "
                "(provenance conflation)")

    # I-EV-3: payload integrity — record↔carrier cross-check (self-contained)
    ev3 = es["I_ev"]["I-EV-3"]
    actual = sha256_canonical(es["payload"])
    if actual != ev3["payload_sha256"]:
        return ("BROKEN", "I-MISMATCH", "payload digest mismatch")

    _ = manifest  # manifest integrity is part of structural check
    return ("SATISFIED", None, "all identity evidence evaluable & unambiguous")


def eval_A(es: dict, is_dir: str, mode: str = "t1"):
    st = _structural(is_dir, mode)
    if st:
        if mode != "t1":
            return ("NOT-EVALUABLE", "A-UNSTRUCT", st[2])
        # anchor reference is ES-resident; missing resolution infrastructure
        # at t1 = content not referable = A-NF (design §5 H-C).
        return ("BROKEN", "A-NF", "resolution infrastructure missing")
    a = es["A_ev"]
    status, cands = resolve_key(is_dir, a["anchor_name"])
    if status == "structural-missing":
        return ("BROKEN", "A-NF", "index missing")
    if status == "not-found":
        return ("BROKEN", "A-NF", "anchor target not found / not referable")
    if status == "ambiguous":
        return ("BROKEN", "A-NF", "anchor resolves ambiguously")
    rel, content = cands[0]
    manifest = load_manifest(is_dir)
    ok, reason = in_boundary(manifest, rel)
    if not ok:
        return ("BROKEN", "A-NF",
                f"anchor resolved but outside current IS boundary ({reason})")
    if sha256_bytes(content) != a["formation_target_content_sha256"]:
        return ("BROKEN", "A-SUB",
                "resolved content digest != formation digest "
                "(same address, different content)")
    return ("SATISFIED", None, "anchor resolvable, in-boundary, digest match")


def _referenced_keys(es: dict):
    keys = set(es["C_ev"]["prerequisite_keys"])
    keys.add(es["A_ev"]["anchor_name"])
    for ev in ("I-EV-1", "I-EV-2"):
        ref = es["I_ev"][ev].get("is_reference")
        if ref:
            keys.add(ref["key"])
    return keys


def eval_C(es: dict, is_dir: str, setup_pinned_ts: str, mode: str = "t1"):
    st = _structural(is_dir, mode)
    if st:
        if mode != "t1":
            return ("NOT-EVALUABLE", "C-DECL-NON-MECHANICAL", st[2])
        # prerequisite referability depends on resolution infrastructure
        return ("BROKEN", "C-REF-NOT-FOUND",
                "resolution infrastructure missing")
    inv_path = os.path.join(is_dir, IS_INVALIDATION)
    if not os.path.exists(inv_path):
        # catalog cannot produce this; occurrence = instrument suspect
        return ("NOT-EVALUABLE", "C-INVALIDATION-INDEX-MISSING",
                "invalidation index missing at t1 (not producible by "
                "frozen catalog)")

    # C-REF: prerequisite resolution
    for key in es["C_ev"]["prerequisite_keys"]:
        status, _c = resolve_key(is_dir, key)
        if status == "not-found":
            return ("BROKEN", "C-REF-NOT-FOUND",
                    f"prerequisite {key} not found")
        if status == "ambiguous":
            return ("BROKEN", "C-REF-NOT-FOUND",
                    f"prerequisite {key} ambiguous")
        if status == "structural-missing":
            return ("NOT-EVALUABLE", "C-INVALIDATION-INDEX-MISSING",
                    "index missing")
        rel = _c[0][0]
        manifest = load_manifest(is_dir)
        ok, reason = in_boundary(manifest, rel)
        if not ok:
            return ("BROKEN", "C-REF-NOT-FOUND",
                    f"prerequisite {key} outside boundary ({reason})")

    # C-INV: invalidation / supersession records targeting ES-referenced keys
    inv = load_invalidation(is_dir)
    ref_keys = _referenced_keys(es)
    for rec in inv.get("records", []):
        if rec.get("target") in ref_keys:
            return ("BROKEN", "C-INV",
                    f"{rec.get('type')} record targets {rec.get('target')}")

    # C-DECL: declared applicability conditions — mechanical allowlist only
    # (design §5a H-D: scope-tag / validity-vs-setup-pinned-ts / dependency)
    for cond in es["C_ev"]["declared_conditions"]:
        ctype = cond["type"]
        if ctype == "scope-tag":
            if cond["value"] not in load_manifest(is_dir).get("scope_tags", []):
                return ("BROKEN", "C-DECL-FAIL",
                        f"scope tag {cond['value']!r} absent")
        elif ctype == "validity":
            if setup_pinned_ts > cond["not_after"]:
                return ("BROKEN", "C-DECL-FAIL",
                        "past declared validity (vs setup-pinned timestamp)")
        elif ctype == "dependency-reference":
            for k in cond["keys"]:
                s, _c = resolve_key(is_dir, k)
                if s != "found":
                    return ("BROKEN", "C-DECL-FAIL",
                            f"dependency {k} unresolvable")
        else:
            # outside the frozen mechanical allowlist
            return ("NOT-EVALUABLE", "C-DECL-NON-MECHANICAL",
                    f"declared condition type {ctype!r} not in allowlist")

    return ("SATISFIED", None, "prerequisites resolvable; no invalidation; "
                               "declared conditions hold")


def eval_cons(es: dict, is_dir: str, setup_pinned_ts: str, mode: str = "t1"):
    """Spec §7: I ∧ A ∧ C with NOT-EVALUABLE propagation."""
    i_st, i_sig, i_det = eval_I(es, is_dir, mode)
    a_st, a_sig, a_det = eval_A(es, is_dir, mode)
    c_st, c_sig, c_det = eval_C(es, is_dir, setup_pinned_ts, mode)
    states = [i_st, a_st, c_st]
    if "NOT-EVALUABLE" in states:
        cons = "NOT-EVALUABLE"
    elif "BROKEN" in states:
        cons = "BROKEN"
    else:
        cons = "SATISFIED"
    return {
        "I": {"state": i_st, "signature": i_sig, "detail": i_det},
        "A": {"state": a_st, "signature": a_sig, "detail": a_det},
        "C": {"state": c_st, "signature": c_sig, "detail": c_det},
        "cons": cons,
    }


# ---------------------------------------------------------------------------
# Frozen ΔIS catalog (design §3). Operations mutate an IS *copy*.
# Metadata: mechanism + target_group feed CLASS_RULE and predict().
# ---------------------------------------------------------------------------

def _read(is_dir, rel):
    with open(os.path.join(is_dir, rel), "r", encoding="utf-8") as f:
        return json.load(f)


def _write(is_dir, rel, obj):
    write_json(os.path.join(is_dir, rel), obj)


def _drop_key(is_dir, key):
    idx = load_index(is_dir)
    idx.pop(key, None)
    save_index(is_dir, idx)


def _op_i_delta1(is_dir):  # IS-side model/fixture declaration change
    p = "runtime/runtime-declaration.json"
    d = _read(is_dir, p)
    d["fixture_class"] = "r3-2-minimal-v1-TAMPERED"
    _write(is_dir, p, d)


def _op_i_delta2(is_dir):  # lineage target deleted
    os.remove(os.path.join(is_dir, "lineage/lineage-root.json"))
    _drop_key(is_dir, "lineage-root")


def _op_i_delta3(is_dir):  # lineage target duplicated with conflict
    conflict = {"derived_from": "R-C1-A4 C-A arm (conflicting claim)",
                "evidence_manifest_sha256": "0" * 64,
                "note": "conflicting duplicate injected by R32-I-Δ3"}
    _write(is_dir, "lineage/lineage-root-conflict.json", conflict)
    idx = load_index(is_dir)
    idx["lineage-root"] = ["lineage/lineage-root.json",
                           "lineage/lineage-root-conflict.json"]
    save_index(is_dir, idx)


def _op_a_delta1(is_dir):  # anchor target deleted
    os.remove(os.path.join(is_dir, "objects/R-1.json"))
    _drop_key(is_dir, "anchor:state-diff")


def _op_a_delta2(is_dir):  # anchor target moved out of current IS boundary
    os.makedirs(os.path.join(is_dir, "universe"), exist_ok=True)
    shutil.move(os.path.join(is_dir, "objects/R-1.json"),
                os.path.join(is_dir, "universe/R-1.json"))
    idx = load_index(is_dir)
    idx["anchor:state-diff"] = ["universe/R-1.json"]
    save_index(is_dir, idx)
    m = load_manifest(is_dir)
    m["out_of_scope"] = sorted(set(m.get("out_of_scope", [])) | {"universe/"})
    save_manifest(is_dir, m)


def _op_a_delta3(is_dir):  # silent substitution: same key, different content
    p = "objects/R-1.json"
    obj = _read(is_dir, p)
    obj["content"] = {"settled_diff": {"alpha": {"from": 42, "to": 17},
                                       "mode": {"from": "active",
                                                "to": "quiet"}},
                      "next_action": "REQUEST_SHUTDOWN",
                      "basis": "substituted content injected by R32-A-Δ3"}
    _write(is_dir, p, obj)  # no mutation record — that is the point (silent)


def _op_c_delta1(is_dir):  # prerequisite deleted
    os.remove(os.path.join(is_dir, "objects/I-S0.json"))
    _drop_key(is_dir, "I-S0")


def _op_c_delta2(is_dir):  # invalidation record targeting the settled result
    inv = load_invalidation(is_dir)
    inv["records"].append({"record_id": "INV-R32-C-Δ2",
                           "type": "invalidation",
                           "target": "anchor:state-diff",
                           "reason": "result retired (R32-C-Δ2)"})
    save_invalidation(is_dir, inv)


def _op_c_delta3(is_dir):  # supersession record targeting the settled result
    inv = load_invalidation(is_dir)
    inv["records"].append({"record_id": "SUP-R32-C-Δ3",
                           "type": "supersession",
                           "target": "anchor:state-diff",
                           "superseded_by": "R-2 (declared, not present)",
                           "reason": "result superseded (R32-C-Δ3)"})
    save_invalidation(is_dir, inv)


def _op_b_delta1(is_dir):  # whole-boundary shrink over archive region
    m = load_manifest(is_dir)
    m["in_scope"] = [p for p in m["in_scope"] if p != "archive/"]
    m["out_of_scope"] = sorted(set(m.get("out_of_scope", [])) | {"archive/"})
    save_manifest(is_dir, m)


def _op_b_delta2(is_dir):  # whole-region access-mode change
    m = load_manifest(is_dir)
    m["access_denied"] = sorted(set(m.get("access_denied", [])) | {"archive/"})
    save_manifest(is_dir, m)


def _op_k1a(is_dir):  # pure addition, unreferenced
    _write(is_dir, "objects/new-fact.json",
           {"id": "NEW-1", "content": "new unrelated fact (R32-K-1a)"})
    idx = load_index(is_dir)
    idx["new-fact"] = ["objects/new-fact.json"]
    save_index(is_dir, idx)


def _op_k1b(is_dir):  # equivalent migration: referenced object relocated,
    # index re-pointed, content identical → resolution+digest hold
    os.makedirs(os.path.join(is_dir, "objects/store-v2"), exist_ok=True)
    shutil.move(os.path.join(is_dir, "objects/R-1.json"),
                os.path.join(is_dir, "objects/store-v2/R-1.json"))
    idx = load_index(is_dir)
    idx["anchor:state-diff"] = ["objects/store-v2/R-1.json"]
    save_index(is_dir, idx)


def _op_k0(_is_dir):  # null control: no-op
    pass


# Frozen catalog: op_id -> {mechanism, target_group, fn}
# mechanism/target feed CLASS_RULE (§4a) and predict() — never hand-classified.
CATALOG = {
    "R32-I-Δ1": {"mechanism": "identity-declaration-change",
                 "target_group": "I", "fn": _op_i_delta1},
    "R32-I-Δ2": {"mechanism": "identity-target-delete",
                 "target_group": "I", "fn": _op_i_delta2},
    "R32-I-Δ3": {"mechanism": "identity-target-duplicate",
                 "target_group": "I", "fn": _op_i_delta3},
    "R32-A-Δ1": {"mechanism": "anchor-delete",
                 "target_group": "A", "fn": _op_a_delta1},
    "R32-A-Δ2": {"mechanism": "anchor-out-of-boundary",
                 "target_group": "A", "fn": _op_a_delta2},
    "R32-A-Δ3": {"mechanism": "anchor-substitute",
                 "target_group": "A", "fn": _op_a_delta3},
    "R32-C-Δ1": {"mechanism": "prerequisite-delete",
                 "target_group": "C", "fn": _op_c_delta1},
    "R32-C-Δ2": {"mechanism": "invalidation-add",
                 "target_group": "C", "fn": _op_c_delta2},
    "R32-C-Δ3": {"mechanism": "supersession-add",
                 "target_group": "C", "fn": _op_c_delta3},
    "R32-B-Δ1": {"mechanism": "boundary-shrink",
                 "target_group": "none", "fn": _op_b_delta1,
                 "region": "archive/"},
    "R32-B-Δ2": {"mechanism": "access-deny",
                 "target_group": "none", "fn": _op_b_delta2,
                 "region": "archive/"},
    "R32-K-1a": {"mechanism": "unrelated-add",
                 "target_group": "none", "fn": _op_k1a},
    "R32-K-1b": {"mechanism": "equivalent-migration",
                 "target_group": "none", "fn": _op_k1b},
    "R32-K-0":  {"mechanism": "no-op",
                 "target_group": "none", "fn": _op_k0},
}

# Single-variable campaign order (design §3; IS-X deferred — §4a closure)
CAMPAIGN_ORDER = list(CATALOG.keys())


# ---------------------------------------------------------------------------
# CLASS_RULE (design §4a): mechanically derive ΔIS_class from op metadata.
# ---------------------------------------------------------------------------

def derive_class(op_id: str) -> str:
    meta = CATALOG[op_id]
    mech, tgt = meta["mechanism"], meta["target_group"]
    if mech == "no-op":
        return "K-0"
    if mech in ("unrelated-add", "equivalent-migration"):
        return "K-1"
    if mech in ("boundary-shrink", "access-deny"):
        return "IS-B"
    if tgt in ("I", "A", "C"):
        return f"IS-{tgt}"
    raise ValueError(f"unclassifiable op {op_id}")


# ---------------------------------------------------------------------------
# predict(): mechanically derive per-condition predicted states from op
# metadata x ES evidence map (construction-time knowledge only, design §9).
# ---------------------------------------------------------------------------

def _es_uses_key(es: dict, key: str) -> bool:
    return key in _referenced_keys(es)


def predict(op_id: str, es: dict) -> dict:
    meta = CATALOG[op_id]
    mech, tgt = meta["mechanism"], meta["target_group"]
    sat = ("SATISFIED", None)

    def broken(sig):
        return ("BROKEN", sig)

    if mech == "no-op":
        out = {"I": sat, "A": sat, "C": sat}
    elif mech == "unrelated-add":
        out = {"I": sat, "A": sat, "C": sat}
    elif mech == "equivalent-migration":
        # index re-point keeps resolution + digest → anchor holds
        out = {"I": sat, "A": sat, "C": sat}
    elif mech in ("boundary-shrink", "access-deny"):
        region = meta["region"]
        idx = None  # affected-set derivation happens against construction IS0
        out = None  # filled by caller with region∩referenced computation
    elif tgt == "I":
        sig = {"identity-declaration-change": "I-MISMATCH",
               "identity-target-delete": "I-NF",
               "identity-target-duplicate": "I-AMBIG"}[mech]
        out = {"I": broken(sig), "A": sat, "C": sat}
    elif tgt == "A":
        sig = {"anchor-delete": "A-NF",
               "anchor-out-of-boundary": "A-NF",
               "anchor-substitute": "A-SUB"}[mech]
        out = {"I": sat, "A": broken(sig), "C": sat}
    elif tgt == "C":
        sig = {"prerequisite-delete": "C-REF-NOT-FOUND",
               "invalidation-add": "C-INV",
               "supersession-add": "C-INV"}[mech]
        out = {"I": sat, "A": sat, "C": broken(sig)}
    else:
        raise ValueError(f"unpredictable op {op_id}")

    if out is None:
        # IS-B: mechanically derive from region ∩ ES-referenced storage paths
        region = meta["region"]
        hits = [k for k in _referenced_keys(es) if k in _region_keys(es, region)]
        if hits:
            out = {"I": sat, "A": broken("A-NF"), "C": broken("C-REF-NOT-FOUND")}
        else:
            out = {"I": sat, "A": sat, "C": sat}
    return out


def _region_keys(es: dict, region: str) -> set:
    """Keys whose construction-time storage paths fall inside region."""
    # construction-time index snapshot is provided by the caller via
    # predict_with_index; this simple variant keys off the setup index.
    return set(_REGION_KEY_CACHE.get(region, set()))


# populated at construction time by run_cells (construction-time knowledge)
_REGION_KEY_CACHE = {}


def build_region_cache(is_dir):
    """Construction-time computation of region ∩ referenced storage paths."""
    idx = load_index(is_dir)
    cache = {}
    for key, rels in idx.items():
        for rel in rels:
            for region in ("archive/", "universe/"):
                if rel.startswith(region):
                    cache.setdefault(region, set()).add(key)
    _REGION_KEY_CACHE.clear()
    _REGION_KEY_CACHE.update(cache)
