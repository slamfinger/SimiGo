#!/usr/bin/env python3
"""SRS schema validator (Design v0.2 §2) with synthetic self-check examples.

Canonical serialization (D-SRS-ID-1): json.dumps(record, sort_keys=True,
separators=(',',':'), ensure_ascii=False) over ALL fields including
provenance; srs_identity = sha256(canonical_bytes).

The anti-masquerade rejection rule: a record missing any of dependency
bindings, provenance, freshness conditions, or DECLARED_SETTLED status is
NOT an SRS and must be rejected at persist time and at resolve time.
"""

import hashlib
import json
import sys

REQUIRED_TOP = ["schema_version", "settlement_status", "result", "source_relation",
                "dependencies", "provenance", "freshness", "request_class", "identity_rule"]


def canonical_json(record) -> str:
    return json.dumps(record, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def identity_of(record) -> str:
    return hashlib.sha256(canonical_json(record).encode("utf-8")).hexdigest()


def validate(record):
    """Return (ok, reason). reason is None when ok."""
    if not isinstance(record, dict):
        return False, "record is not an object"
    for field in REQUIRED_TOP:
        if field not in record:
            return False, "missing required field: " + field
    if record["settlement_status"] != "DECLARED_SETTLED":
        return False, "settlement_status is not DECLARED_SETTLED (anti-masquerade)"
    result = record["result"]
    if not isinstance(result, dict) or not result.get("identity"):
        return False, "result identity missing"
    if not isinstance(result.get("derivation_procedure"), dict) or \
            not result["derivation_procedure"].get("identity") or \
            not result["derivation_procedure"].get("version"):
        return False, "derivation procedure not exactly bound"
    sr = record["source_relation"]
    if not isinstance(sr, dict) or not sr.get("relation_id") or not sr.get("semantics_binding"):
        return False, "source relation binding missing"
    deps = record["dependencies"]
    if not isinstance(deps, list) or len(deps) == 0:
        return False, "dependency bindings missing (anti-masquerade)"
    for d in deps:
        if not isinstance(d, dict) or not d.get("dependency_id") \
                or not d.get("content_address") or "revision" not in d:
            return False, "incomplete dependency binding"
    prov = record["provenance"]
    if not isinstance(prov, dict) or not prov.get("formation_es_id") \
            or not prov.get("formation_run_id") or not prov.get("u_invocation_record_ref"):
        return False, "provenance missing (anti-masquerade)"
    fresh = record["freshness"]
    if not isinstance(fresh, list) or len(fresh) == 0:
        return False, "freshness conditions missing (anti-masquerade)"
    for f in fresh:
        if not isinstance(f, dict) or not f.get("requirement_id") \
                or not f.get("condition") or not f.get("initial_evidence_ref"):
            return False, "incomplete freshness condition"
    if not record.get("request_class"):
        return False, "request_class missing"
    ir = record["identity_rule"]
    if not isinstance(ir, dict) or not ir.get("identity") or not ir.get("version"):
        return False, "identity rule not pinned"
    if "srs_identity" not in record:
        return False, "srs_identity field missing"
    stated = record["srs_identity"]
    body = {k: v for k, v in record.items() if k != "srs_identity"}
    recomputed = identity_of(body)
    if stated != recomputed:
        return False, "srs_identity mismatch (stated %s != recomputed %s)" % (stated, recomputed)
    return True, None


def self_check():
    """Synthetic examples: one valid, four masquerades/rejections. Returns
    (passed, total). These are fixture-internal examples only; they exercise
    the validator, not the experiment."""
    body = {
        "schema_version": "SRS-1",
        "settlement_status": "DECLARED_SETTLED",
        "result": {"identity": "res-abc", "derivation_procedure": {"identity": "P-1", "version": "1.0.0"}},
        "source_relation": {"relation_id": "rel-1", "semantics_binding": "sem-1"},
        "dependencies": [{"dependency_id": "D-1", "content_address": "aa11", "revision": 1}],
        "provenance": {"formation_es_id": "ES1-r1", "formation_run_id": "r1",
                       "u_invocation_record_ref": "U:r1:1"},
        "freshness": [{"requirement_id": "dep-current", "condition": "dependency-content-current",
                       "initial_evidence_ref": "aa11"}],
        "request_class": "R1-continuation",
        "identity_rule": {"identity": "SRS-CANONICAL-ID-V1", "version": "1.0.0"},
    }
    valid = dict(body, srs_identity=identity_of(body))
    bare_digest = {"result_identity": "res-abc"}
    no_deps = dict(valid)
    no_deps.pop("dependencies")
    no_prov = dict(valid)
    no_prov.pop("provenance")
    tampered = dict(valid)
    tampered["result"] = dict(body["result"], identity="res-TAMPERED")
    cases = [
        (valid, True, "valid record"),
        (bare_digest, False, "bare output digest masquerade"),
        (no_deps, False, "missing dependency bindings"),
        (no_prov, False, "missing provenance"),
        (tampered, False, "identity hash mismatch after field tamper"),
    ]
    passed = 0
    for record, expect, name in cases:
        ok, _ = validate(record)
        if ok == expect:
            passed += 1
        else:
            print("SELF-CHECK FAIL: %s" % name, file=sys.stderr)
    return passed, len(cases)


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--self-check":
        p, t = self_check()
        print("SCHEMA SELF-CHECK: %d/%d" % (p, t))
        sys.exit(0 if p == t else 1)
    if len(sys.argv) < 2:
        print("usage: validate_srs.py RECORD.json | --self-check", file=sys.stderr)
        sys.exit(64)
    with open(sys.argv[1], "r", encoding="utf-8") as fh:
        record = json.load(fh)
    ok, reason = validate(record)
    print(json.dumps({"schema_valid": ok, "reason": reason}, sort_keys=True))
    sys.exit(0 if ok else 1)
