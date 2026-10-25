#!/usr/bin/env python3
"""G2 restore-eligibility gate, v2: the restore decision is time-explicit.

`carrier_gate.py` is frozen and stays byte-identical. This module repeats its
checks and adds the one dimension the frozen gate could not express: whether the
source item's validity window actually covers the moment at which the restore is
being considered.

Two rules make v2 usable as evidence rather than as a convenience wrapper:

1. `evaluated_at_utc` is a required argument. The gate never reads the clock, so
   the same database and the same instant always produce the same decision.
2. The four window states are distinguished, not collapsed: absent, malformed,
   expired, current. Each has its own code so a report can name which one it hit.

Frozen refusal codes are preserved unchanged:
  SETTLEMENT_MISSING       settlement entry, dependency entry or object gone
  OBJECT_DIGEST_MISMATCH   stored bytes no longer hash to the content address
  SETTLEMENT_CONTRACT_UNKNOWN  a contract marker this gate does not know

One code is added for the dialect envelope itself:
  SETTLEMENT_CONTRACT_MALFORMED  the marker and the field shape disagree, or a
                                 payload carries both dialects' fields

Two settlement dialects are readable, and each is verified in its own terms:
  CONFORMING  `EINFO-SETTLEMENT-V1` + `EINFO-SETTLEMENT-CONTRACT-V1`; binds
              `result.value`, the source payload digest, the dependency
              *settlement* objects and the whole sealed policy
  HISTORICAL  a pre-contract G2 settlement; binds `result.r1_canonical`, the
              source item object id, the dependency item objects and the
              two-part policy identity
Making the gate dialect-aware is what keeps it honest: a conforming settlement
must not be refused for lacking a legacy field, and a legacy carrier must not be
silently re-read as if it had promised the newer binding. The marker alone
decides which reading applies; the field shape is then *checked against* that
reading rather than used to infer it, because a payload that infers its own
dialect would be verified under whichever contract flatters it.

Window codes added by v2:
  VALIDITY_MISSING         no valid_until_utc and --require-validity is set
  VALIDITY_MALFORMED       valid_until_utc is not YYYY-MM-DDTHH:MM:SSZ
  VALIDITY_EXPIRED         evaluated_at_utc is after valid_until_utc
  EVALUATED_AT_MALFORMED   evaluated_at_utc itself is not a UTC timestamp

Without `--require-validity` an absent window is recorded as
`validity_window_absent` and does not refuse, so historical G2 carriers can be
audited. G3 and every new run use the switch.

Usage:
  python3 carrier_gate_v2.py --db PATH --item ITEM --evaluated-at TS \
      --out RECORD.json [--require-validity] \
      [--phase1-record RECORD.json] [--expect restored|refused]
"""

import argparse
import json
import os
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

# Reuse the frozen gate's primitives instead of copying them: the read-only
# connection, schema check and object reading must stay identical to v1.
import carrier_gate as base  # noqa: E402
from carrier_loop import (  # noqa: E402
    SETTLEMENT_CONTRACT, digest, parse_utc, validity_policy_identity,
)

SCHEMA_ID = "SIMIGO-G2-RESTORE-GATE-V2"
SETTLEMENT_MISSING = base.SETTLEMENT_MISSING
OBJECT_DIGEST_MISMATCH = base.OBJECT_DIGEST_MISMATCH

VALIDITY_MISSING = "VALIDITY_MISSING"
VALIDITY_MALFORMED = "VALIDITY_MALFORMED"
VALIDITY_EXPIRED = "VALIDITY_EXPIRED"
EVALUATED_AT_MALFORMED = "EVALUATED_AT_MALFORMED"
SETTLEMENT_CONTRACT_MALFORMED = "SETTLEMENT_CONTRACT_MALFORMED"

# Fields that exist in exactly one dialect. They are used to check the shape
# against the declared marker, never to derive the marker.
CONFORMING_ONLY_FIELDS = ("value", "result_value_sha256")
LEGACY_ONLY_FIELDS = ("r1_canonical", "r1_sha256")

Refusal = base.Refusal


def evaluate(db_path, item_id, evaluated_at_utc, phase1_record=None,
             require_validity=False):
    """Run the v2 gate against one item at one explicit instant.

    Returns a record. The database is opened read-only and is never written.
    """
    checks = []

    def record(name, ok, detail=None, code=None):
        row = {"check": name, "ok": bool(ok)}
        if detail is not None:
            row["detail"] = detail
        if code is not None:
            row["code"] = code
        checks.append(row)
        if not ok:
            raise Refusal(code or "GATE_CHECK_FAILED", detail or name, checks)

    try:
        evaluated_at = parse_utc(evaluated_at_utc)
    except ValueError as error:
        record("evaluated_at_utc_parseable", False, str(error), EVALUATED_AT_MALFORMED)
    checks.append({"check": "evaluated_at_utc_parseable", "ok": True,
                   "detail": evaluated_at_utc})

    connection = base.connect_readonly(db_path)
    try:
        base.check_schema(connection)
        checks.append({"check": "schema", "ok": True})

        settlement_identity = "settlement:%s" % item_id
        index_entry = base.latest_index(connection, settlement_identity)
        record("settlement_index_present", index_entry is not None,
               "index entry %s" % settlement_identity, SETTLEMENT_MISSING)

        dependency = base.latest_dependency(connection, settlement_identity)
        record("settlement_dependency_present", dependency is not None,
               "dependency entry %s" % settlement_identity, SETTLEMENT_MISSING)

        object_id = index_entry["record_object"]
        record("settlement_pointer_agrees",
               dependency["content_address"] == object_id,
               "index=%s dependency=%s" % (object_id, dependency["content_address"]),
               OBJECT_DIGEST_MISMATCH)

        stored = base.read_object(connection, object_id)
        record("settlement_object_present", stored is not None,
               "object %s" % object_id, SETTLEMENT_MISSING)

        actual_digest = base.sha256_bytes(stored["content"])
        record("settlement_bytes_match_address", actual_digest == object_id,
               "computed=%s address=%s" % (actual_digest, object_id),
               OBJECT_DIGEST_MISMATCH)
        record("settlement_byte_size_matches",
               stored["byte_size"] == len(stored["content"]),
               "declared=%d actual=%d" % (stored["byte_size"], len(stored["content"])),
               OBJECT_DIGEST_MISMATCH)

        value = json.loads(stored["content"].decode("utf-8"))
        record("settlement_schema", value.get("schema_id") == "EINFO-SETTLEMENT-V1",
               str(value.get("schema_id")), "SETTLEMENT_NOT_SETTLED")
        record("settlement_state_settled", value.get("state") == "SETTLED",
               str(value.get("state")), "SETTLEMENT_NOT_SETTLED")

        result = value.get("result") or {}
        basis = value.get("basis") or {}

        # Two dialects are readable, and the gate must speak both: historical G2
        # carriers bind `result.r1_canonical`, contract carriers bind
        # `result.value`. Each dialect is verified in its own terms, so a
        # conforming settlement can never be refused for lacking a legacy field.
        contract = value.get("settlement_contract")
        conforming = contract == SETTLEMENT_CONTRACT
        # An absent marker is the V1 dialect: every carrier written before the
        # contract existed is in that state. A *present* marker that is not the
        # one this gate knows is refused instead of being read as V1.
        record("settlement_contract_known", contract is None or conforming,
               "marker=%s" % contract, "SETTLEMENT_CONTRACT_UNKNOWN")
        checks.append({
            "check": "settlement_contract_marker", "ok": True,
            "detail": "conforming" if conforming else "historical:no-marker",
        })

        present_conforming = [field for field in CONFORMING_ONLY_FIELDS
                              if field in result]
        present_legacy = [field for field in LEGACY_ONLY_FIELDS
                          if field in result]
        record("settlement_dialect_not_mixed",
               not (present_conforming and present_legacy),
               "conforming=%s legacy=%s" % (present_conforming, present_legacy),
               SETTLEMENT_CONTRACT_MALFORMED)
        record("settlement_contract_shape_agrees",
               bool(present_conforming) == conforming,
               "marker=%s conforming_fields=%s legacy_fields=%s"
               % (contract, present_conforming, present_legacy),
               SETTLEMENT_CONTRACT_MALFORMED)
        if conforming:
            record("settlement_contract_shape_complete",
                   len(present_conforming) == len(CONFORMING_ONLY_FIELDS),
                   "%s" % present_conforming, SETTLEMENT_CONTRACT_MALFORMED)
        else:
            record("settlement_contract_shape_complete",
                   len(present_legacy) == len(LEGACY_ONLY_FIELDS),
                   "%s" % present_legacy, SETTLEMENT_CONTRACT_MALFORMED)

        if conforming:
            recomputed = None
            if "value" in result:
                try:
                    recomputed = digest(result["value"])
                except (TypeError, ValueError):
                    recomputed = None
            record("contract_result_value_digest_matches",
                   recomputed is not None
                   and recomputed == result.get("result_value_sha256")
                   and recomputed == basis.get("result_value_sha256"),
                   "recomputed=%s result=%s basis=%s"
                   % (recomputed, result.get("result_value_sha256"),
                      basis.get("result_value_sha256")),
                   OBJECT_DIGEST_MISMATCH)
            r1_canonical = None
            r1_sha = None
        else:
            r1_canonical = result.get("r1_canonical")
            r1_sha = result.get("r1_sha256")
            recalculated = digest(json.loads(r1_canonical)) if r1_canonical else None
            record("r1_digest_matches_payload",
                   r1_canonical is not None and recalculated == r1_sha,
                   "recomputed=%s recorded=%s" % (recalculated, r1_sha),
                   OBJECT_DIGEST_MISMATCH)

            if phase1_record is not None:
                record("r1_matches_phase1_record",
                       r1_sha == phase1_record.get("r1_sha256"),
                       "gate=%s phase1=%s" % (r1_sha, phase1_record.get("r1_sha256")),
                       OBJECT_DIGEST_MISMATCH)
                record("r1_canonical_matches_phase1_record",
                       r1_canonical == phase1_record.get("r1_canonical"),
                       "canonical text byte-equal", OBJECT_DIGEST_MISMATCH)

        source_identity = "item:%s" % item_id
        source_entry = base.latest_index(connection, source_identity)
        record("source_present", source_entry is not None,
               source_identity, "SOURCE_IDENTITY_MISMATCH")
        source_object = base.read_object(connection, source_entry["record_object"])
        record("source_bytes_match_address",
               source_object is not None
               and base.sha256_bytes(source_object["content"])
               == source_object["object_id"],
               "source object %s" % source_entry["record_object"],
               "SOURCE_IDENTITY_MISMATCH")
        source_value = json.loads(source_object["content"].decode("utf-8"))
        if conforming:
            # The contract binds the source by payload digest, not by object id:
            # a re-written item object with identical bytes is the same input.
            recorded_payload_sha = basis.get("source_payload_sha256")
            current_payload_sha = digest(source_value.get("source_payload"))
            record("contract_source_payload_digest_agrees",
                   recorded_payload_sha is not None
                   and recorded_payload_sha == current_payload_sha,
                   "basis=%s current=%s"
                   % (recorded_payload_sha, current_payload_sha),
                   "SOURCE_IDENTITY_MISMATCH")
        else:
            record("source_object_identity_agrees",
                   basis.get("source_item_object_id") == source_object["object_id"],
                   "basis=%s current=%s" % (basis.get("source_item_object_id"),
                                            source_object["object_id"]),
                   "SOURCE_IDENTITY_MISMATCH")
        record("source_version_agrees",
               basis.get("source_version") == source_value.get("source_version"),
               "basis=%s current=%s" % (basis.get("source_version"),
                                        source_value.get("source_version")),
               "SOURCE_IDENTITY_MISMATCH")

        closure = list(source_value.get("dependencies") or [])
        declared_dependencies = (basis.get("dependency_object_ids") or {})
        record("dependency_closure_agrees",
               sorted(closure)
               == sorted(declared_dependencies if conforming
                         else (basis.get("dependency_ids") or [])),
               "current=%s basis=%s"
               % (closure, sorted(declared_dependencies) if conforming
                  else basis.get("dependency_ids")),
               "DEPENDENCY_CLOSURE_MISMATCH")
        resolved_closure = {}
        for dependency_id in closure:
            entry = base.latest_index(connection, "item:%s" % dependency_id)
            record("dependency_present:%s" % dependency_id, entry is not None,
                   "item:%s" % dependency_id, "DEPENDENCY_CLOSURE_MISMATCH")
            body = base.read_object(connection, entry["record_object"])
            record("dependency_bytes_match_address:%s" % dependency_id,
                   body is not None
                   and base.sha256_bytes(body["content"]) == body["object_id"],
                   entry["record_object"], "DEPENDENCY_CLOSURE_MISMATCH")
            if conforming:
                # A contract settlement binds the dependency's *settlement*
                # object, which is what `execute_demand` reuses; binding the
                # item object would let a rewritten item pass as the same work.
                dependency_settlement = base.latest_dependency(
                    connection, "settlement:%s" % dependency_id)
                expected = (dependency_settlement["content_address"]
                            if dependency_settlement is not None else None)
            else:
                expected = body["object_id"]
            record("dependency_object_agrees:%s" % dependency_id,
                   declared_dependencies.get(dependency_id) == expected,
                   "basis=%s current=%s"
                   % (declared_dependencies.get(dependency_id), expected),
                   "DEPENDENCY_CLOSURE_MISMATCH")
            resolved_closure[dependency_id] = expected

        policy = source_value.get("validity_policy")
        policy_identity = validity_policy_identity(policy)
        if conforming:
            # The contract carries the whole sealed policy, so equality is the
            # check; the legacy carrier could only carry its two-part identity.
            record("validity_policy_digest_agrees",
                   basis.get("validity_policy") == policy,
                   "current=%s basis=%s"
                   % (policy_identity["policy_sha256"],
                      (basis.get("validity_policy") or {}).get("policy_sha256")),
                   "VALIDITY_BASIS_MISMATCH")
        else:
            record("validity_policy_digest_agrees",
                   policy_identity["policy_sha256"]
                   == basis.get("validity_policy_sha256"),
                   "current=%s basis=%s" % (policy_identity["policy_sha256"],
                                            basis.get("validity_policy_sha256")),
                   "VALIDITY_BASIS_MISMATCH")
            record("validity_current",
                   policy_identity["policy_version"]
                   == basis.get("validity_policy_version"),
                   "version %s" % policy_identity["policy_version"],
                   "VALIDITY_BASIS_MISMATCH")

        # v2: the fourth window state is the only new decision. Absent,
        # malformed and expired windows each get their own code, and a window
        # that is present is always enforced regardless of the switch.
        declared_window = source_value.get("valid_until_utc")
        window_end = None
        window_error = None
        if declared_window is not None:
            try:
                window_end = parse_utc(declared_window)
            except ValueError as error:
                window_error = str(error)
        if declared_window is None:
            if require_validity:
                record("validity_window_present", False,
                       "source item declares no valid_until_utc", VALIDITY_MISSING)
            checks.append({
                "check": "validity_window_absent", "ok": True,
                "detail": "valid_until_utc undefined; recorded because "
                          "--require-validity is off",
            })
        else:
            record("validity_window_present", True, declared_window)
            record("validity_window_parseable", window_error is None,
                   window_error or declared_window, VALIDITY_MALFORMED)
            record("validity_window_current", evaluated_at <= window_end,
                   "evaluated_at=%s valid_until=%s"
                   % (evaluated_at_utc, declared_window), VALIDITY_EXPIRED)

        demand_identity = "demand:%s" % source_value.get("demand_id")
        demand_entry = base.latest_index(connection, demand_identity)
        record("demand_present", demand_entry is not None, demand_identity,
               "DEMAND_MISMATCH")
        demand_value = json.loads(
            base.read_object(connection, demand_entry["record_object"])["content"])
        record("demand_requires_item", item_id in demand_value["required_item_ids"],
               "required=%s" % demand_value["required_item_ids"], "DEMAND_MISMATCH")

        return {
            "schema_id": SCHEMA_ID,
            "decision": "RESTORED",
            "code": None,
            "checks": checks,
            "all_checks_pass": True,
            "item_id": item_id,
            "evaluated_at_utc": evaluated_at_utc,
            "require_validity": require_validity,
            "settlement": {
                "object_id": object_id,
                "dependency_revision": dependency["revision"],
                "sha256": actual_digest,
                "byte_size": stored["byte_size"],
                "dialect": "CONFORMING" if conforming else "HISTORICAL",
                "result_value_sha256": (result.get("result_value_sha256")
                                        if conforming else None),
                "r1_canonical": r1_canonical,
                "r1_sha256": r1_sha,
            },
            "source": {
                "object_id": source_object["object_id"],
                "source_kind": source_value.get("source_kind"),
                "source_version": source_value.get("source_version"),
                "demand_id": source_value.get("demand_id"),
            },
            "dependency_closure": {"ids": closure, "object_ids": resolved_closure},
            "validity_basis": {
                "policy_sha256": policy_identity["policy_sha256"],
                "policy_version": policy_identity["policy_version"],
                "policy_source": policy_identity["policy_source"],
                "valid_until_utc": declared_window,
                "window_enforced": declared_window is not None,
            },
            "model_loaded": False,
        }
    finally:
        connection.close()


def refused_record(code, detail, checks, evaluated_at_utc, require_validity):
    return {
        "schema_id": SCHEMA_ID,
        "decision": "REFUSED",
        "code": code,
        "detail": detail,
        "checks": checks,
        "all_checks_pass": False,
        "evaluated_at_utc": evaluated_at_utc,
        "require_validity": require_validity,
        "model_loaded": False,
    }


def run_gate(db_path, item_id, evaluated_at_utc, phase1_record=None,
             require_validity=False):
    """Evaluate and prove the database did not change."""
    before = base.tree_digest(db_path)
    try:
        body = evaluate(db_path, item_id, evaluated_at_utc,
                        phase1_record=phase1_record,
                        require_validity=require_validity)
    except Refusal as refusal:
        body = refused_record(refusal.code, refusal.detail, refusal.checks,
                              evaluated_at_utc, require_validity)
    except Exception as error:  # noqa: BLE001 - the gate must record any failure
        body = refused_record("GATE_ERROR",
                              "%s: %s" % (type(error).__name__, error), [],
                              evaluated_at_utc, require_validity)
    body["database"] = str(db_path)
    body["database_tree_digest_before"] = before
    body["database_tree_digest_after"] = base.tree_digest(db_path)
    body["database_unchanged"] = (
        body["database_tree_digest_before"] == body["database_tree_digest_after"])
    return body


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", required=True)
    parser.add_argument("--item", required=True)
    parser.add_argument("--evaluated-at", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--phase1-record")
    parser.add_argument("--require-validity", action="store_true")
    parser.add_argument("--expect", choices=["restored", "refused"], default=None)
    args = parser.parse_args()

    phase1 = None
    if args.phase1_record:
        phase1 = json.loads(
            pathlib.Path(args.phase1_record).read_text(encoding="utf-8"))
        phase1 = {"r1_canonical": phase1.get("r1_canonical"),
                  "r1_sha256": phase1.get("r1_sha256")}

    body = run_gate(args.db, args.item, args.evaluated_at, phase1,
                    require_validity=args.require_validity)
    body["expectation"] = args.expect
    body["expectation_met"] = (
        None if args.expect is None
        else (body["decision"] == "RESTORED") == (args.expect == "restored"))
    body["pid"] = os.getpid()
    base.write_once(args.out, body)
    print(json.dumps({"decision": body["decision"], "code": body["code"]}))
    if args.expect and not body["expectation_met"]:
        sys.exit(4)
    sys.exit(0)


if __name__ == "__main__":
    main()
