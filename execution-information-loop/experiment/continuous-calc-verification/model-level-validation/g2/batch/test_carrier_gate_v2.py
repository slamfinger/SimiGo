#!/usr/bin/env python3
"""Five-scenario test for the validity-aware gate, plus the switch-off case.

Every scenario is built on its own copy of a synthetic G2-dialect carrier: one
demand, one source item and one settlement written in the pre-contract shape the
G2 batch used. The carrier is created here, never read from `g2/evidence/`, so
the frozen evidence bytes are untouched.

Scenario table (expected decision / code):

  1 valid window                      RESTORED   -
  2 expired window                    REFUSED    VALIDITY_EXPIRED
  3 malformed timestamp               REFUSED    VALIDITY_MALFORMED
  4 missing window + --require-validity REFUSED  VALIDITY_MISSING
  5 tampered settlement object        REFUSED    OBJECT_DIGEST_MISMATCH

Plus: a missing window without the switch is recorded as
`validity_window_absent` and does not refuse, which is what keeps historical G2
carriers auditable.

Each scenario also asserts `database_unchanged == true`, so a refusal can never
be explained by the gate having mutated its evidence.

Usage: python3 test_carrier_gate_v2.py [--out RECORD.json]
"""

import argparse
import json
import pathlib
import shutil
import sqlite3
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parents[4]))

from carrier_gate_v2 import run_gate  # noqa: E402
from carrier_loop import (  # noqa: E402
    SETTLEMENT_CONTRACT, CarrierInformationLoop, canonical, digest,
)

SCHEMA_ID = "SIMIGO-G2-GATE-V2-SELFTEST-V1"
ITEM = "u1-result"
DEMAND = "demand-fx-1"
FIXTURE = {"fixture_id": "fx-1", "s1_sha256": digest({"s1": 1}), "s1_words": 4}
EVALUATED_AT = "2026-10-20T08:21:24Z"
DEFAULT_WINDOW = "2030-12-31T23:59:59Z"


def validity_policy() -> dict:
    body = {
        "policy_version": "g2-selftest-v2",
        "policy_source": "simulation://carrier-gate-v2/fixture",
    }
    return {**body, "policy_sha256": digest(body)}


POLICY = validity_policy()


def write_legacy_settlement(loop, source_object_id: str, policy: dict) -> str:
    """Write one settlement in the pre-contract (G2) dialect, bypassing settle().

    `settle()` rejects this shape on purpose. A historical carrier could only
    have been written before the contract existed, so the only faithful way to
    reproduce one is to append the bytes directly.
    """
    r1 = {"secret": "selftest-secret", "site": "selftest-site",
          "checksum": "selftest-checksum"}
    r1_canonical = json.dumps(r1, sort_keys=True, separators=(",", ":"))
    value = {
        "schema_id": "EINFO-SETTLEMENT-V1",
        "state": "SETTLED",
        "advancement_id": "%s-u1-settled" % FIXTURE["fixture_id"],
        "item_id": ITEM,
        "result": {
            "fixture_id": FIXTURE["fixture_id"],
            "r1": r1,
            "r1_canonical": r1_canonical,
            "r1_sha256": digest(r1),
        },
        "basis": {
            "fixture_id": FIXTURE["fixture_id"],
            "source_item_object_id": source_object_id,
            "source_kind": "model-extraction-u1",
            "source_version": "v1",
            "dependency_ids": [],
            "dependency_object_ids": {},
            "validity_policy_sha256": policy["policy_sha256"],
            "validity_policy_version": policy["policy_version"],
            "s1_sha256": FIXTURE["s1_sha256"],
        },
    }
    dependency_id = "settlement:%s" % ITEM
    revision = len(loop.carrier.get_dependency_history(dependency_id)) + 1
    with loop.carrier.atomic_write_group():
        object_id, _ = loop.carrier.atomic_dependency_materialization(
            canonical(value),
            {
                "dependency_id": dependency_id,
                "content_address": "",
                "revision": revision,
                "reason": "historical settlement",
            },
        )
        loop.carrier.append_index_entry({
            "srs_identity": dependency_id,
            "record_object": object_id,
        })
    return object_id


def rewrite_item_window(loop, item_id: str, window: str) -> str:
    """Replace the item's window the way an unvalidated writer could have.

    `put_source()` refuses a malformed timestamp, so a carrier that contains one
    can only have been produced by a writer that skipped that check. Rewriting
    the item object directly reproduces exactly that historical shape.
    """
    current = loop.current_item(item_id)
    current["valid_until_utc"] = window
    dependency_id = "dependency:%s" % item_id
    revision = len(loop.carrier.get_dependency_history(dependency_id)) + 1
    with loop.carrier.atomic_write_group():
        object_id, _ = loop.carrier.atomic_dependency_materialization(
            canonical(current),
            {
                "dependency_id": dependency_id,
                "content_address": "",
                "revision": revision,
                "reason": "unvalidated window rewrite",
            },
        )
        loop.carrier.append_index_entry({
            "srs_identity": "item:%s" % item_id,
            "record_object": object_id,
        })
    return object_id


def build_carrier(path: pathlib.Path, valid_until_utc, force_window=None):
    loop = CarrierInformationLoop.create(str(path))
    loop.define_demand(
        DEMAND,
        continuation_point="gate-v2-selftest",
        pending_obligations=["answer u2"],
        continuation_conditions=["u1 settlement restores"],
        required_item_ids=[ITEM],
    )
    source = loop.put_source(
        DEMAND, ITEM, "model-extraction-u1", "v1",
        {"fixture_id": FIXTURE["fixture_id"],
         "s1_sha256": FIXTURE["s1_sha256"],
         "s1_word_count": FIXTURE["s1_words"]},
        dependencies=[],
        valid_until_utc=valid_until_utc,
        validity_policy=POLICY,
    )
    source_object_id = source["object_id"]
    if force_window is not None:
        source_object_id = rewrite_item_window(loop, ITEM, force_window)
    write_legacy_settlement(loop, source_object_id, POLICY)
    loop.commit()
    loop.close()


def tamper_object(path: pathlib.Path):
    """Overwrite the settlement bytes without changing the content address."""
    connection = sqlite3.connect(str(path))
    object_id = connection.execute(
        "SELECT record_object FROM is_index_entries WHERE srs_identity=? "
        "ORDER BY append_order DESC LIMIT 1",
        ("settlement:%s" % ITEM,),
    ).fetchone()[0]
    original = bytes(connection.execute(
        "SELECT content FROM is_objects WHERE object_id=?", (object_id,)
    ).fetchone()[0])
    connection.execute(
        "UPDATE is_objects SET content=? WHERE object_id=?",
        (original.replace(b"selftest-secret", b"tampered-secret"), object_id),
    )
    connection.commit()
    connection.close()
    return object_id


def scenario(name, expected_decision, expected_code, build_window,
             require_validity=False, tamper=False, force_window=None, extra=None):
    work = pathlib.Path(tempfile.mkdtemp(prefix="gate-v2-%s-" % name))
    try:
        database = work / "g2.sqlite"
        build_carrier(database, build_window, force_window=force_window)
        if tamper:
            tamper_object(database)
        result = run_gate(database, ITEM, EVALUATED_AT,
                          require_validity=require_validity)
        checks = {
            "decision_matches": result["decision"] == expected_decision,
            "code_matches": result.get("code") == expected_code,
            "database_unchanged": result["database_unchanged"] is True,
            "model_not_loaded": result["model_loaded"] is False,
        }
        if extra is not None:
            checks.update(extra(result))
        return name, checks, result
    finally:
        shutil.rmtree(work, ignore_errors=True)


def window_absent_recorded(result):
    names = [row["check"] for row in result["checks"]]
    return {"absent_window_recorded": "validity_window_absent" in names}


def window_current_checked(result):
    names = {row["check"]: row for row in result["checks"]}
    return {"window_current_check_present": "validity_window_current" in names
            and names["validity_window_current"]["ok"] is True}


def window_agreement():
    """Prove the gate and the loop reach the same conclusion on all four cases.

    The gate is the pre-model refusal; the loop is the in-process demand. If they
    disagreed, a gate PASS could still be refused (or worse, accepted) by the
    loop, so the correspondence is asserted rather than assumed.
    """
    cases = [
        # label, window written through put_source, forced window,
        # gate code, loop state
        ("valid", DEFAULT_WINDOW, None, None, "ADVANCED"),
        ("expired", "2026-01-01T00:00:00Z", None,
         "VALIDITY_EXPIRED", "BLOCKED_STALE_VALIDITY"),
        ("malformed", DEFAULT_WINDOW, "2026-13-45",
         "VALIDITY_MALFORMED", "BLOCKED_INVALID_VALIDITY"),
        ("missing", None, None, "VALIDITY_MISSING", "BLOCKED_MISSING_VALIDITY"),
    ]
    checks = {}
    details = {}
    for label, window, forced, gate_code, loop_state in cases:
        work = pathlib.Path(tempfile.mkdtemp(prefix="gate-v2-agree-%s-" % label))
        try:
            database = work / "g2.sqlite"
            build_carrier(database, window, force_window=forced)
            gate = run_gate(database, ITEM, EVALUATED_AT,
                            require_validity=gate_code == "VALIDITY_MISSING")
            loop = CarrierInformationLoop.open(str(database))
            try:
                outcome = loop.execute_demand(
                    DEMAND, "adv-loop-%s" % label,
                    lambda item_id, source_payload, dependencies: {"label": label},
                    evaluated_at_utc=EVALUATED_AT,
                )
            finally:
                loop.close()
            checks["%s.gate_decision" % label] = (
                (gate["decision"] == "RESTORED") if gate_code is None
                else gate.get("code") == gate_code)
            checks["%s.loop_state" % label] = outcome["state"] == loop_state
            checks["%s.gate_database_unchanged" % label] = (
                gate["database_unchanged"] is True)
            details[label] = {
                "gate": gate.get("code") or gate["decision"],
                "loop": outcome["state"],
                "loop_failure_reason": outcome.get("failure_reason"),
            }
        finally:
            shutil.rmtree(work, ignore_errors=True)
    return checks, details


def write_contract_settlement(loop, item_id: str, payload: dict, policy: dict,
                             valid_until_utc: str) -> str:
    """Write one settlement through `settle()`, i.e. in the current contract.

    The gate must certify this dialect too; a gate that only understands the
    historical shape would refuse every carrier the loop itself accepts.
    """
    result, basis = contract_scopes(item_id, payload, policy, valid_until_utc)
    return loop.settle("contract-%s" % item_id, item_id, result, basis)["object_id"]


def contract_scopes(item_id: str, payload: dict, policy: dict,
                    valid_until_utc: str):
    """The (result, basis) pair a contract settlement binds."""
    value = {"answer": item_id}
    shared = {
        "source_payload_sha256": digest(payload),
        "result_value_sha256": digest(value),
        "source_version": "v1",
        "dependency_object_ids": {},
        "evaluated_at_utc": EVALUATED_AT,
        "valid_until_utc": valid_until_utc,
        "validity_policy": policy,
    }
    return {"value": value, **shared}, dict(shared)


def contract_envelope(item_id: str, payload: dict, policy: dict,
                      valid_until_utc: str) -> dict:
    """The full settlement object `settle()` would write, as mutable bytes."""
    result, basis = contract_scopes(item_id, payload, policy, valid_until_utc)
    return {
        "schema_id": "EINFO-SETTLEMENT-V1",
        "state": "SETTLED",
        "settlement_contract": SETTLEMENT_CONTRACT,
        "advancement_id": "contract-%s" % item_id,
        "item_id": item_id,
        "result": result,
        "basis": basis,
    }


def append_raw_settlement(loop, item_id: str, value: dict) -> str:
    """Append a settlement object verbatim, bypassing settle()'s validation.

    The negative dialect scenarios are envelopes no conforming writer would
    emit, so the only faithful way to present one to the gate is to append the
    bytes directly, exactly as `write_legacy_settlement` does.
    """
    dependency_id = "settlement:%s" % item_id
    revision = len(loop.carrier.get_dependency_history(dependency_id)) + 1
    with loop.carrier.atomic_write_group():
        object_id, _ = loop.carrier.atomic_dependency_materialization(
            canonical(value),
            {"dependency_id": dependency_id, "content_address": "",
             "revision": revision, "reason": "dialect scenario"},
        )
        loop.carrier.append_index_entry({
            "srs_identity": dependency_id,
            "record_object": object_id,
        })
    return object_id


def build_contract_carrier(path: pathlib.Path, valid_until_utc):
    loop = CarrierInformationLoop.create(str(path))
    loop.define_demand(
        DEMAND,
        continuation_point="gate-v2-contract",
        pending_obligations=["answer u2"],
        continuation_conditions=["u1 settlement restores"],
        required_item_ids=[ITEM],
    )
    payload = {"fixture_id": FIXTURE["fixture_id"],
               "s1_sha256": FIXTURE["s1_sha256"],
               "s1_word_count": FIXTURE["s1_words"]}
    loop.put_source(
        DEMAND, ITEM, "model-extraction-u1", "v1", payload,
        dependencies=[],
        valid_until_utc=valid_until_utc,
        validity_policy=POLICY,
    )
    write_contract_settlement(loop, ITEM, payload, POLICY, valid_until_utc)
    loop.commit()
    loop.close()


def contract_scenario(name, expected_decision, expected_code, valid_until_utc,
                      evaluate_at=None):
    """Certify the contract dialect at a chosen instant.

    The contract refuses to *write* a settlement against an already-expired
    window, so expiry is produced the way it really happens: settle inside the
    window, then evaluate the gate later.
    """
    evaluate_at = evaluate_at or EVALUATED_AT
    work = pathlib.Path(tempfile.mkdtemp(prefix="gate-v2-contract-%s-" % name))
    try:
        database = work / "g2.sqlite"
        build_contract_carrier(database, valid_until_utc)
        result = run_gate(database, ITEM, evaluate_at, require_validity=True)
        checks = {
            "decision_matches": result["decision"] == expected_decision,
            "code_matches": result.get("code") == expected_code,
            "database_unchanged": result["database_unchanged"] is True,
            "model_not_loaded": result["model_loaded"] is False,
            "dialect_is_conforming": result.get("settlement", {}).get(
                "dialect") == "CONFORMING" if result["decision"] == "RESTORED"
                else True,
        }
        return name, checks, result
    finally:
        shutil.rmtree(work, ignore_errors=True)


def build_dialect_carrier(path: pathlib.Path, mutate):
    loop = CarrierInformationLoop.create(str(path))
    loop.define_demand(
        DEMAND,
        continuation_point="gate-v2-dialect",
        pending_obligations=["answer u2"],
        continuation_conditions=["u1 settlement restores"],
        required_item_ids=[ITEM],
    )
    payload = {"fixture_id": FIXTURE["fixture_id"],
               "s1_sha256": FIXTURE["s1_sha256"],
               "s1_word_count": FIXTURE["s1_words"]}
    loop.put_source(
        DEMAND, ITEM, "model-extraction-u1", "v1", payload,
        dependencies=[], valid_until_utc=DEFAULT_WINDOW,
        validity_policy=POLICY,
    )
    envelope = contract_envelope(ITEM, payload, POLICY, DEFAULT_WINDOW)
    mutate(envelope)
    append_raw_settlement(loop, ITEM, envelope)
    loop.commit()
    loop.close()


def dialect_scenario(name, mutate, expected_code):
    """A payload whose marker and shape disagree must be refused, not read.

    W1's rule is that an unknown contract identity makes a settlement opaque
    instead of "probably compatible", so the gate may not pick a dialect from
    whichever fields happen to be present.
    """
    work = pathlib.Path(tempfile.mkdtemp(prefix="gate-v2-dialect-%s-" % name))
    try:
        database = work / "g2.sqlite"
        build_dialect_carrier(database, mutate)
        result = run_gate(database, ITEM, EVALUATED_AT, require_validity=True)
        checks = {
            "decision_matches": result["decision"] == "REFUSED",
            "code_matches": result.get("code") == expected_code,
            "database_unchanged": result["database_unchanged"] is True,
            "model_not_loaded": result["model_loaded"] is False,
        }
        return name, checks, result
    finally:
        shutil.rmtree(work, ignore_errors=True)


def add_unknown_marker(envelope):
    envelope["settlement_contract"] = "EINFO-SETTLEMENT-CONTRACT-V9"


def add_marker_with_legacy_shape(envelope):
    """Marker says conforming; the fields are the historical ones."""
    envelope["result"] = {
        "r1_canonical": json.dumps({"answer": ITEM}, sort_keys=True,
                                   separators=(",", ":")),
        "r1_sha256": digest({"answer": ITEM}),
    }


def add_mixed_dialect(envelope):
    """Both dialects' exclusive fields in one payload."""
    legacy = json.dumps({"answer": ITEM}, sort_keys=True, separators=(",", ":"))
    envelope["result"]["r1_canonical"] = legacy
    envelope["result"]["r1_sha256"] = digest({"answer": ITEM})


def drop_contract_marker(envelope):
    """Conforming fields with no marker: must not be inferred as V1."""
    del envelope["settlement_contract"]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out")
    args = parser.parse_args()

    scenarios = [
        scenario("valid_window", "RESTORED", None, DEFAULT_WINDOW,
                 extra=window_current_checked),
        scenario("expired_window", "REFUSED", "VALIDITY_EXPIRED", "2026-01-01T00:00:00Z"),
        scenario("malformed_timestamp", "REFUSED", "VALIDITY_MALFORMED",
                 DEFAULT_WINDOW, force_window="2026-13-45"),
        scenario("missing_window_require", "REFUSED", "VALIDITY_MISSING", None,
                 require_validity=True),
        scenario("tampered_object", "REFUSED", "OBJECT_DIGEST_MISMATCH",
                 DEFAULT_WINDOW, tamper=True),
        scenario("missing_window_optional", "RESTORED", None, None,
                 extra=window_absent_recorded),
        # The dialect the loop itself writes. Both outcomes must be reachable:
        # a conforming carrier is certifiable, and its window still expires.
        contract_scenario("contract_valid", "RESTORED", None, DEFAULT_WINDOW),
        contract_scenario("contract_expired", "REFUSED", "VALIDITY_EXPIRED",
                          DEFAULT_WINDOW, evaluate_at="2040-01-01T00:00:00Z"),
        # The envelope itself is checked, not inferred. An unknown marker, a
        # marker that contradicts the shape, a payload carrying both dialects,
        # and a conforming-shaped payload with no marker all refuse.
        dialect_scenario("unknown_marker", add_unknown_marker,
                         "SETTLEMENT_CONTRACT_UNKNOWN"),
        dialect_scenario("marker_shape_conflict", add_marker_with_legacy_shape,
                         "SETTLEMENT_CONTRACT_MALFORMED"),
        dialect_scenario("mixed_dialect", add_mixed_dialect,
                         "SETTLEMENT_CONTRACT_MALFORMED"),
        dialect_scenario("marker_absent_conforming_shape", drop_contract_marker,
                         "SETTLEMENT_CONTRACT_MALFORMED"),
    ]

    checks = {}
    details = {}
    for name, scenario_checks, result in scenarios:
        for key, value in scenario_checks.items():
            checks["%s.%s" % (name, key)] = value
        details[name] = {"decision": result["decision"], "code": result.get("code"),
                         "checks": scenario_checks}
    agreement_checks, agreement_details = window_agreement()
    checks.update(agreement_checks)
    checks["all_scenarios_expected"] = all(checks.values())

    report = {
        "schema_id": SCHEMA_ID,
        "scenarios": len(scenarios),
        "evaluated_at_utc": EVALUATED_AT,
        "details": details,
        "gate_loop_agreement": agreement_details,
        "checks": checks,
        "model_loaded": False,
        "database_mutations_by_gate": False,
        "result": "PASS" if checks["all_scenarios_expected"] else "FAIL",
    }
    text = json.dumps(report, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":")) + "\n"
    print(text, end="")
    if args.out:
        pathlib.Path(args.out).write_text(text, encoding="utf-8")
    return 0 if report["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
