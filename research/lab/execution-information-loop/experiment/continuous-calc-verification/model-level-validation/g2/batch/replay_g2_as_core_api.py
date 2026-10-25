#!/usr/bin/env python3
"""Rebind the recorded G2 host event onto the core ES/IS API.

What this script is:

  A semantic replay. It reads the frozen G2-A/B evidence of one fixture,
  verifies that the evidence still identifies the same model and the same
  answer, and then drives the *core* API (`define_demand` -> `put_source` ->
  `execute_demand` -> `confirm_runtime_application`) over those recorded bytes.

What this script is not:

  New execution evidence. It starts no model, launches no host, and claims no
  new Swift application. The `APPLIED_SWIFT` records inside the replay carrier
  mean "the recorded host event was rebound to the core ES chain", which is
  exactly what `runtime_application_semantics: REBINDS_RECORDED_EVENT` in the
  first record of the carrier says.

The reuse proof is deliberately not self-fulfilling: the second `execute_demand`
passes a calculator that raises `AssertionError("U1 was re-executed")`. If the
reuse predicate misses, the script fails hard instead of labelling a compute as
a reuse.

Evidence verification happens *before* any carrier is created. If the evidence
does not identify itself, the report is INCONCLUSIVE and zero ES records are
written.

`confirm_runtime_application` does not itself verify evidence: it accepts a
state id that is pending Swift application and is the latest state. The proof
that the application *happened* is therefore carried entirely by the evidence
chain this script verifies first, and that chain has five links, each checked
against the frozen bytes rather than asserted:

  event identity      pid / parent_pid / process_group / started_at / finished_at
  terminal state      exit_code 0, both host checks true, evidence-level claim PASS
  executable hash     the frozen G2Host build product recorded in the manifest
  entry identity      model directory, revision prefix, engine content triple
  result binding      host u1 record binds the same r1_canonical and r1_sha256

Usage:
  python3 replay_g2_as_core_api.py [--out REPORT.json] [--fixtures fixture-1]
"""

import argparse
import hashlib
import json
import pathlib
import shutil
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[5]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(REPO_ROOT / "execution-information-loop"))

from carrier_loop import (  # noqa: E402
    CarrierInformationLoop, audit_settlement_contracts, canonical, digest, parse_utc,
)
from checker import check_u2  # noqa: E402

SCHEMA_ID = "SIMIGO-G2-CORE-API-REPLAY-V1"
BINDING_SCHEMA_ID = "SIMIGO-G2-REPLAY-BINDING-V1"
SOURCE_RUN = "20261020T082124Z"
EVIDENCE_ROOT = HERE.parent / "evidence" / SOURCE_RUN
REPLAY_VALID_UNTIL = "2030-12-31T23:59:59Z"
REPLAY_EVALUATED_AT = "2026-10-20T08:21:24Z"
REPLAY_REUSE_AT = "2026-10-20T08:21:30Z"
CONTINUATION_POINT = "g2-replay-downstream"
# The three identity digests are the binding. The manifest carries an extra
# `source` label beside them, which is provenance text, not identity.
IDENTITY_KEYS = ("weights_digest", "tokenizer_digest", "combined_digest")


def identity_tuple(mapping: dict) -> dict:
    mapping = mapping or {}
    return {key: mapping.get(key) for key in IDENTITY_KEYS}


def sha256_path(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path: pathlib.Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def is_sha256(value) -> bool:
    return (isinstance(value, str) and len(value) == 64
            and all(character in "0123456789abcdef" for character in value))


def replay_validity_policy() -> dict:
    body = {
        "policy_version": "g2-replay-declared-v1",
        "policy_source": "SIMIGO_G2_REPLAY_DECLARED_WINDOW",
    }
    return {**body, "policy_sha256": digest(body)}


def verify_evidence(fixture_id: str, expected_identity: dict,
                    manifest: dict = None) -> dict:
    """Verify that the frozen evidence still identifies the recorded event.

    Returns {"ok": bool, "checks": {...}, "evidence": [...], "r1": {...},
    "r1_sha256": ..., "r1_canonical": ..., "u2_text": ...}. Any failed check
    means the replay must stop before writing anything.
    """
    root = EVIDENCE_ROOT / "fixtures" / fixture_id
    paths = {
        "a_identity": root / "A" / "identity_check.json",
        "b1_identity": root / "B1" / "identity_check.json",
        "b1_r1": root / "B1" / "r1.json",
        "b1_host_record": root / "B1" / "host_record.json",
        "b1_carrier_phase1": root / "B1" / "carrier_phase1.json",
        "b2_host_record": root / "B2" / "host_record.json",
        "b2_checker": root / "B2" / "checker.json",
        "b2_identity": root / "B2" / "identity_check.json",
    }
    checks = {}
    present = {name: path.is_file() for name, path in paths.items()}
    checks["all_evidence_files_present"] = all(present.values())
    if not checks["all_evidence_files_present"]:
        return {"ok": False, "checks": checks, "evidence": [],
                "missing": sorted(k for k, v in present.items() if not v)}

    evidence = [
        {"path": str(paths[name].relative_to(REPO_ROOT).as_posix()),
         "sha256": sha256_path(paths[name])}
        for name in sorted(paths)
    ]

    for label in ("a_identity", "b1_identity", "b2_identity"):
        body = read_json(paths[label])
        checks["%s_all_match" % label] = body.get("all_match") is True
        checks["%s_observed_equals_expected" % label] = (
            body.get("observed") == body.get("expected"))
        checks["%s_expected_equals_manifest" % label] = (
            identity_tuple(body.get("expected"))
            == identity_tuple(expected_identity))

    r1_record = read_json(paths["b1_r1"])
    r1_canonical = r1_record.get("r1_canonical")
    r1_sha256 = r1_record.get("r1_sha256")
    try:
        r1 = json.loads(r1_canonical)
    except (TypeError, ValueError):
        r1 = None
    checks["r1_canonical_parses"] = isinstance(r1, dict)
    checks["r1_digest_matches_canonical"] = (
        isinstance(r1, dict) and digest(r1) == r1_sha256)

    b1_host = read_json(paths["b1_host_record"])
    checks["b1_host_record_agrees_with_r1"] = (
        (b1_host.get("u1") or {}).get("r1_canonical") == r1_canonical)
    checks["b1_host_record_identity_agrees"] = (
        identity_tuple(b1_host.get("engine_content_identity"))
        == identity_tuple(expected_identity))

    # The five links of the application evidence. A recorded answer without a
    # terminated host run, a named binary and a bound model entry would not
    # distinguish "a host applied this" from "a script wrote this".
    host_checks = b1_host.get("checks") or {}
    checks["b1_host_record_terminal_state"] = (
        b1_host.get("exit_code") == 0
        and bool(b1_host.get("finished_at_utc"))
        and host_checks.get("u1_generated") is True
        and host_checks.get("u1_parsed") is True)
    try:
        started = parse_utc(b1_host.get("started_at_utc"))
        finished = parse_utc(b1_host.get("finished_at_utc"))
        checks["b1_host_record_event_span_ordered"] = started <= finished
    except (TypeError, ValueError):
        checks["b1_host_record_event_span_ordered"] = False
    checks["b1_host_record_event_identity_complete"] = (
        all(isinstance(b1_host.get(field), int)
            for field in ("pid", "parent_pid", "process_group"))
        and b1_host.get("mode") == "phase1")
    checks["b1_host_record_binds_r1"] = (
        (b1_host.get("u1") or {}).get("r1_sha256") == r1_sha256
        and (b1_host.get("u1") or {}).get("r1_canonical") == r1_canonical)

    manifest = manifest or read_json(HERE.parent / "manifest" / "G2_MANIFEST.json")
    binding = manifest.get("model_binding") or {}
    recorded_model_dir = pathlib.Path(b1_host.get("model_directory") or "").name
    checks["b1_host_record_entry_identity_agrees"] = (
        recorded_model_dir == pathlib.Path(binding.get("model_dir") or "").name
        and str(binding.get("revision") or "")[:8] in recorded_model_dir)
    checks["frozen_executable_hash_present"] = is_sha256(
        (manifest.get("backend") or {}).get("build_product", {}).get("sha256"))

    terminal = read_json(EVIDENCE_ROOT / "terminal.json")
    terminal_claims = (terminal.get("fixtures") or {}).get(fixture_id, {}).get(
        "claims") or {}
    checks["terminal_claims_pass"] = (
        terminal_claims.get("G2-B") == "PASS"
        and terminal.get("halted") is False)
    checks["terminal_binds_frozen_manifest"] = (
        terminal.get("manifest_sha256")
        == sha256_path(HERE.parent / "manifest" / "G2_MANIFEST.json"))

    phase1 = read_json(paths["b1_carrier_phase1"])
    checks["carrier_phase1_result_digest_agrees"] = (
        phase1.get("result_digest")
        == digest({
            "fixture_id": fixture_id,
            "r1": r1,
            "r1_canonical": r1_canonical,
            "r1_sha256": r1_sha256,
        }))

    b2_host = read_json(paths["b2_host_record"])
    u2_text = "".join((b2_host.get("u2") or {}).get("chunk_sequence") or [])
    checks["u2_text_present"] = bool(u2_text)
    checks["b2_host_record_identity_agrees"] = (
        identity_tuple(b2_host.get("engine_content_identity"))
        == identity_tuple(expected_identity))

    fixture = read_json(HERE / "fixtures" / ("%s.json" % fixture_id))
    recomputed = check_u2(u2_text, r1, fixture)
    recorded = read_json(paths["b2_checker"])
    checks["u2_recheck_passes"] = recomputed["pass"] is True
    checks["u2_format_ok"] = recomputed["format_ok"] is True
    checks["u2_secret_equals_settled_r1"] = (
        recomputed["secret_matches_settled_r1"] is True)
    checks["u2_checksum_recomputed_agrees"] = (
        recomputed["checksum_matches_recomputed"] is True)
    checks["u2_recorded_checker_matches_recheck"] = all(
        recorded.get(field) == recomputed[field]
        for field in ("pass", "format_ok", "secret_matches_settled_r1",
                      "checksum_matches_recomputed",
                      "settled_r1_checksum_self_consistent")
    )
    checks["u2_recorded_checker_passed"] = recorded.get("pass") is True

    return {
        "ok": all(checks.values()),
        "checks": checks,
        "evidence": evidence,
        "r1": r1,
        "r1_canonical": r1_canonical,
        "r1_sha256": r1_sha256,
        "u2_text": u2_text,
        "provenance": {
            "event": {
                "source_run": SOURCE_RUN,
                "pid": b1_host.get("pid"),
                "parent_pid": b1_host.get("parent_pid"),
                "process_group": b1_host.get("process_group"),
                "started_at_utc": b1_host.get("started_at_utc"),
                "finished_at_utc": b1_host.get("finished_at_utc"),
                "mode": b1_host.get("mode"),
            },
            "terminal_state": {
                "exit_code": b1_host.get("exit_code"),
                "host_checks": host_checks,
                "arm_claim": terminal_claims.get("G2-B"),
            },
            "executable": {
                "host_build_product_sha256": (manifest.get("backend") or {})
                    .get("build_product", {}).get("sha256"),
                "frozen_tools": sorted((manifest.get("executables") or {})),
            },
            "entry": {
                "model_dir": recorded_model_dir,
                "model_revision": binding.get("revision"),
                "engine_content_identity": identity_tuple(
                    b1_host.get("engine_content_identity")),
            },
            "result_binding": {
                "r1_sha256": r1_sha256,
                "request_sha256": (b1_host.get("u1") or {}).get("request_sha256"),
                "prompt_token_ids_sha256":
                    (b1_host.get("u1") or {}).get("prompt_token_ids_sha256"),
            },
        },
    }


def write_binding_record(loop, binding: dict) -> str:
    """Append the replay binding as the first record of the replay carrier."""
    with loop.carrier.atomic_write_group():
        object_id = loop.carrier.write_object(canonical(binding))
        loop.carrier.append_index_entry({
            "srs_identity": "replay_binding:%s" % binding["source_run"],
            "record_object": object_id,
        })
    return object_id


def state_chain(loop, continuation_point: str, latest_state_id: str) -> list:
    """Walk `prior_state_id` from the latest state back to the root."""
    chain = []
    state_id = latest_state_id
    while state_id is not None:
        row = loop._current_index_object(
            "execution_state:%s:%s" % (continuation_point, state_id))
        if row is None:
            break
        chain.append(row)
        state_id = row.get("prior_state_id")
    return list(reversed(chain))


def replay(fixture_id: str, verified: dict, binding: dict) -> dict:
    """Drive the core API over the verified bytes and prove reuse."""
    checks = {}
    demand_id = "g2-replay-%s-demand" % fixture_id
    policy = replay_validity_policy()
    r1 = verified["r1"]

    with tempfile.TemporaryDirectory(prefix="g2-core-replay-") as temporary:
        database = str(pathlib.Path(temporary) / "replay_carrier.sqlite")
        loop = CarrierInformationLoop.create(database)
        binding_object_id = write_binding_record(loop, binding)
        checks["binding_is_first_record"] = (
            loop.carrier.connection.execute(
                "SELECT srs_identity FROM is_index_entries "
                "ORDER BY append_order ASC LIMIT 1").fetchone()[0]
            == "replay_binding:%s" % SOURCE_RUN)

        loop.define_demand(
            demand_id,
            continuation_point=CONTINUATION_POINT,
            pending_obligations=["continue after recorded u1 settlement"],
            continuation_conditions=["u1 settlement restores and is reusable"],
            required_item_ids=["u1-result"],
        )
        loop.put_source(
            demand_id, "u1-result", "model-extraction-u1", "v1",
            {"fixture_id": fixture_id,
             "r1_sha256": verified["r1_sha256"],
             "u1_recorded_by": "G2_HOST_RUN_%s" % SOURCE_RUN},
            dependencies=[],
            valid_until_utc=REPLAY_VALID_UNTIL,
            validity_policy=policy,
        )

        first = loop.execute_demand(
            demand_id, "u1-settled",
            lambda item_id, source_payload, dependencies: r1,
            evaluated_at_utc=REPLAY_EVALUATED_AT,
        )
        checks["u1_executed_once"] = first["state"] == "ADVANCED"
        checks["u1_calculator_result_is_recorded_r1"] = (
            first["actions"][0]["result_digest"] == verified["r1_sha256"])
        u1_settlement_object_id = first["actions"][0]["settlement_object_id"]
        u1_state_result_digest = (first["execution_state"] or {}).get("result_digest")
        checks["u1_state_result_digest_matches_evidence"] = (
            u1_state_result_digest == digest({
                "demand_id": demand_id,
                "continuation_point": CONTINUATION_POINT,
                "resolved_items": {"u1-result": r1},
            }))

        loop.confirm_runtime_application("u1-settled")
        checks["u1_runtime_confirmed"] = (
            loop.latest_execution_state(CONTINUATION_POINT)["state_id"]
            == "u1-settled:runtime-applied")

        # The G2 phase-2 "restored" step, rebound: the recorded u2 answer is the
        # continuation artifact, not a new execution.
        u2_result_digest = digest({
            "u2_raw_text": verified["u2_text"],
            "r1_sha256": verified["r1_sha256"],
        })
        loop.record_execution_state(
            "u2-restored",
            continuation_point=CONTINUATION_POINT,
            prior_state_id="u1-settled:runtime-applied",
            demand_id=demand_id,
            status="RESTORED",
            pending_obligations=["apply recorded u2 answer"],
            next_continuation_point="u2-advanced",
            result_digest=u2_result_digest,
            runtime_application_status="APPLIED_SWIFT",
        )
        restored = loop.restore_continuation(CONTINUATION_POINT)
        checks["core_api_restore"] = (
            restored["state"]["state_id"] == "u2-restored"
            and restored["demand"]["demand_id"] == demand_id
            and restored["required_item_ids"] == ["u1-result"])

        def refuse_reexecution(item_id, source_payload, dependencies):
            raise AssertionError("U1 was re-executed")

        second = loop.execute_demand(
            demand_id, "u2-advanced", refuse_reexecution,
            evaluated_at_utc=REPLAY_REUSE_AT,
        )
        action = second["actions"][0]
        checks["core_api_reuse"] = (
            second["state"] == "ADVANCED"
            and action["action"] == "REUSE"
            and action["settlement_object_id"] == u1_settlement_object_id
            and second["computed_item_ids"] == [])
        checks["reuse_reason_absent"] = action.get("reason") is None
        loop.confirm_runtime_application("u2-advanced")

        latest = loop.latest_execution_state(CONTINUATION_POINT)
        chain = state_chain(loop, CONTINUATION_POINT, latest["state_id"])
        chain_ids = [state["state_id"] for state in chain]
        checks["state_chain_is_replay_chain"] = chain_ids == [
            "u1-settled",
            "u1-settled:runtime-applied",
            "u2-restored",
            "u2-advanced",
            "u2-advanced:runtime-applied",
        ]
        checks["u2_state_result_digest_matches_evidence"] = (
            [state["result_digest"] for state in chain
             if state["state_id"] == "u2-restored"] == [u2_result_digest])

        final_restore = loop.restore_continuation(CONTINUATION_POINT)
        checks["core_api_restore_after_advance"] = (
            final_restore["state"]["state_id"] == "u2-advanced:runtime-applied")
        checks["replay_carrier_has_no_invalidations"] = (
            loop.carrier.connection.execute(
                "SELECT COUNT(*) FROM is_index_entries WHERE srs_identity LIKE "
                "'settlement:%'").fetchone()[0] == 1)
        loop.carrier.validate_schema()
        loop.close()

    return {
        "checks": checks,
        "binding_object_id": binding_object_id,
        "u1_settlement_object_id": u1_settlement_object_id,
        "state_chain": chain_ids,
        "u1_action": action["action"],
        "calculator_calls": 1,
    }


def legacy_classification() -> dict:
    """Classify the frozen G2 settlements without writing to them."""
    counts = {}
    per_fixture = {}
    for fixture_id in ("fixture-1", "fixture-2", "fixture-3"):
        database = EVIDENCE_ROOT / "fixtures" / fixture_id / "B1" / "carrier" / "g2.sqlite"
        audit = audit_settlement_contracts(str(database))
        per_fixture[fixture_id] = audit["counts"]
        for key, value in audit["counts"].items():
            counts[key] = counts.get(key, 0) + value
    return {
        "contract": "EINFO-SETTLEMENT-CONTRACT-V1",
        "per_fixture": per_fixture,
        "counts": counts,
        "all_opaque": set(counts) == {"OPAQUE"},
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out")
    parser.add_argument("--fixtures", nargs="*", default=["fixture-1"])
    args = parser.parse_args()

    manifest = read_json(HERE.parent / "manifest" / "G2_MANIFEST.json")
    expected_identity = manifest["model_binding"]["expected_engine_identity"]
    legacy = legacy_classification()

    report = {
        "schema_id": SCHEMA_ID,
        "scope": "SYNTHETIC_REPLAY",
        "source_run": SOURCE_RUN,
        "evidence_root": str(EVIDENCE_ROOT.relative_to(REPO_ROOT).as_posix()),
        "model_starts": 0,
        "new_model_starts": 0,
        "is_new_execution_evidence": False,
        "runtime_application_semantics": "REBINDS_RECORDED_EVENT",
        "legacy_settlements_classification": legacy,
        "fixtures": {},
    }

    verdicts = []
    for fixture_id in args.fixtures:
        verified = verify_evidence(fixture_id, expected_identity, manifest)
        entry = {"evidence_checks": verified["checks"],
                 "evidence_provenance": verified.get("provenance")}
        if not verified["ok"]:
            entry["decision"] = "INCONCLUSIVE"
            entry["es_records_written"] = 0
            report["fixtures"][fixture_id] = entry
            verdicts.append("INCONCLUSIVE")
            continue

        binding = {
            "schema_id": BINDING_SCHEMA_ID,
            "scope": "SYNTHETIC_REPLAY",
            "source_run": SOURCE_RUN,
            "fixture_id": fixture_id,
            "evidence": verified["evidence"],
            "model_starts": 0,
            "runtime_application_semantics": "REBINDS_RECORDED_EVENT",
            "is_new_execution_evidence": False,
            "note": "APPLIED_SWIFT in this carrier rebinds a recorded host event "
                    "to the core ES chain; no model ran for this record",
        }
        replayed = replay(fixture_id, verified, binding)
        entry.update({
            "decision": "PASS" if all(replayed["checks"].values()) else "FAIL",
            "replay_checks": replayed["checks"],
            "binding": binding,
            "evidence": verified["evidence"],
            "u1_settlement_object_id": replayed["u1_settlement_object_id"],
            "u1_action": replayed["u1_action"],
            "state_chain": replayed["state_chain"],
            "es_records_written": 0,
        })
        verdicts.append(entry["decision"])
        report["fixtures"][fixture_id] = entry

    report["core_api_restore"] = "PASS" if all(
        entry.get("replay_checks", {}).get("core_api_restore")
        for entry in report["fixtures"].values()) and verdicts else "NOT_RUN"
    report["core_api_reuse"] = "PASS" if all(
        entry.get("replay_checks", {}).get("core_api_reuse")
        for entry in report["fixtures"].values()) and verdicts else "NOT_RUN"
    report["reuse_scope_note"] = (
        "The reuse proved here is the reuse of a settlement this script wrote "
        "under the current contract. The historical G2 settlement objects in "
        "frozen evidence stay OPAQUE and are not reused: `legacy_settlements_"
        "classification` reports that separately. Rebuilding a conforming "
        "settlement from recorded bytes is not the same as making the old "
        "settlement object reusable."
    )
    report["non_claims"] = [
        "no G2-A/B/C evidence is produced by this script",
        "the 98 frozen evidence files are not replaced",
        "no new Swift application is claimed",
        "the historical G2 settlement objects are not made reusable",
    ]
    if verdicts and all(verdict == "PASS" for verdict in verdicts):
        report["result"] = "PASS"
    elif any(verdict == "FAIL" for verdict in verdicts):
        report["result"] = "FAIL"
    else:
        report["result"] = "INCONCLUSIVE"

    text = json.dumps(report, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":")) + "\n"
    print(text, end="")
    if args.out:
        pathlib.Path(args.out).write_text(text, encoding="utf-8")
    return 0 if report["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
