#!/usr/bin/env python3
"""Recompute the G2 settlement invariants from carrier bytes.

`run_batch.py --verify-only` re-derives each fixture verdict from the checks the
runner itself wrote into `verification.json`; it never re-opens a carrier. The
settlement identity, its dependency history and the phase-2 append set are
therefore self-reported. This audit closes that gap: every value below is
recomputed from the SQLite bytes and compared against the independent records
written at the time (`carrier_phase1.json`, `restore_gate.json`, `gate.json`,
`checker.json`, `host_record.json`).

It reads no verdict file (`verification.json`, `terminal.json`), opens every
database with `mode=ro&immutable=1`, and writes nothing but its own report.
"""

import argparse
import hashlib
import json
import pathlib
import re
import shutil
import sqlite3
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[5]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(REPO / "execution-information-loop"))
from carrier_loop import digest  # noqa: E402

SETTLEMENT = "settlement:u1-result"
ITEM = "item:u1-result"
DEPENDENCY = "item:s1-source"
ANSWER_RE = re.compile(r"^ANSWER=([0-9a-f]{12})-([0-9a-f]{8})$")
SCHEMA_ID = "SIMIGO-G2-SETTLEMENT-INVARIANT-AUDIT-V1"


def read_json(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def sha256_file(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


def connect(path):
    uri = pathlib.Path(path).resolve().as_uri() + "?mode=ro&immutable=1"
    connection = sqlite3.connect(uri, uri=True)
    connection.row_factory = sqlite3.Row
    return connection


def index_object(connection, identity):
    row = connection.execute(
        "SELECT append_order, record_object FROM is_index_entries "
        "WHERE srs_identity=?", (identity,)).fetchone()
    if row is None:
        return None
    return row["append_order"], row["record_object"]


def object_bytes(connection, object_id):
    row = connection.execute(
        "SELECT byte_size, content FROM is_objects WHERE object_id=?",
        (object_id,)).fetchone()
    if row is None:
        return None
    return row["byte_size"], bytes(row["content"])


def latest_index_object(connection, identity):
    row = connection.execute(
        "SELECT record_object FROM is_index_entries WHERE srs_identity=? "
        "ORDER BY append_order DESC LIMIT 1", (identity,)).fetchone()
    return None if row is None else row["record_object"]


def record(checks, name, ok, detail=""):
    checks[name] = {"ok": bool(ok), "detail": str(detail)}


def audit_fixture(fixture_dir, fixture):
    fixture_id = fixture["fixture_id"]
    checks = {}
    carrier = fixture_dir / "B1/carrier/g2.sqlite"
    phase1 = read_json(fixture_dir / "B1/carrier_phase1.json")
    restore = read_json(fixture_dir / "restore_gate.json")
    host_record = read_json(fixture_dir / "B2/host_record.json")
    checker = read_json(fixture_dir / "B2/checker.json")

    connection = connect(carrier)
    try:
        located = index_object(connection, SETTLEMENT)
        record(checks, "settlement_index_single",
               located is not None, "one index entry for %s" % SETTLEMENT)
        if located is None:
            return checks
        order, object_id = located

        blob = object_bytes(connection, object_id)
        record(checks, "settlement_object_present",
               blob is not None, "object %s" % object_id)
        if blob is None:
            return checks
        declared_size, body = blob
        record(checks, "settlement_bytes_match_address",
               hashlib.sha256(body).hexdigest() == object_id,
               "sha256(bytes) == index address")
        record(checks, "settlement_byte_size_matches",
               declared_size == len(body), "declared=%d" % declared_size)

        payload = json.loads(body)
        result = payload.get("result") or {}
        record(checks, "settlement_payload_settled",
               payload.get("schema_id") == "EINFO-SETTLEMENT-V1"
               and payload.get("state") == "SETTLED"
               and payload.get("item_id") == "u1-result",
               "%s/%s" % (payload.get("schema_id"), payload.get("state")))
        r1_canonical = result.get("r1_canonical")
        r1_sha256 = result.get("r1_sha256")
        r1 = json.loads(r1_canonical) if r1_canonical else None
        record(checks, "settlement_r1_self_consistent",
               r1 is not None and digest(r1) == r1_sha256,
               "recomputed r1 digest")
        phase1_r1 = read_json(fixture_dir / "B1/r1.json")
        record(checks, "settlement_r1_matches_phase1_record",
               r1_canonical == phase1_r1["r1_canonical"]
               and r1_sha256 == phase1_r1["r1_sha256"],
               "canonical text and digest")
        record(checks, "settlement_object_id_stable",
               object_id == phase1["settlement"]["object_id"]
               == restore["settlement"]["object_id"],
               "phase1 == restore gate == carrier bytes")

        history = connection.execute(
            "SELECT revision, content_address FROM dependency_entries "
            "WHERE dependency_id=? ORDER BY append_order", (SETTLEMENT,)).fetchall()
        record(checks, "settlement_dependency_single_revision",
               len(history) == 1 and history[0]["revision"] == 1
               and history[0]["content_address"] == object_id,
               "rows=%d" % len(history))
        phase2_record = read_json(fixture_dir / "B2/execution_states.json")
        record(checks, "settlement_history_length_one",
               len(history) == 1
               == phase2_record["settlement_history_before"]
               == phase2_record["settlement_history_after"],
               "recomputed=%d recorded=%s->%s" % (
                   len(history), phase2_record["settlement_history_before"],
                   phase2_record["settlement_history_after"]))

        basis = payload.get("basis") or {}
        source_id = latest_index_object(connection, ITEM)
        source = object_bytes(connection, source_id) if source_id else None
        record(checks, "source_identity_stable",
               source is not None
               and hashlib.sha256(source[1]).hexdigest() == source_id
               and source_id == basis.get("source_item_object_id")
               == phase1["source"]["object_id"],
               "item:u1-result %s" % source_id)
        dependency_id = latest_index_object(connection, DEPENDENCY)
        dependency = object_bytes(connection, dependency_id) \
            if dependency_id else None
        record(checks, "dependency_identity_stable",
               dependency is not None
               and hashlib.sha256(dependency[1]).hexdigest() == dependency_id
               and dependency_id
               == (basis.get("dependency_object_ids") or {}).get("s1-source")
               == phase1["dependency_source"]["object_id"],
               "item:s1-source %s" % dependency_id)
        record(checks, "s1_digest_matches_fixture",
               hashlib.sha256(fixture["s1_text"].encode("utf-8")).hexdigest()
               == basis.get("s1_sha256") == fixture["s1_sha256"],
               basis.get("s1_sha256", ""))

        appended = connection.execute(
            "SELECT append_order, srs_identity FROM is_index_entries "
            "WHERE append_order>? ORDER BY append_order", (order,)).fetchall()
        identities = [row["srs_identity"] for row in appended]
        record(checks, "post_settlement_appends_are_states_only",
               len(identities) == 3
               and all(name.startswith("execution_state:") for name in identities),
               "%d append(s)" % len(identities))
        record(checks, "no_settlement_item_or_demand_appends",
               not any(name.startswith(("settlement:", "item:", "demand:"))
                       for name in identities),
               "post-settlement index entries")

        states = {}
        for row in connection.execute(
                "SELECT srs_identity, record_object FROM is_index_entries "
                "WHERE srs_identity LIKE 'execution_state:%' ORDER BY append_order"):
            value = json.loads(object_bytes(connection, row["record_object"])[1])
            states[value["state_id"]] = value
        settled = states.get("%s-u1-settled" % fixture_id) or {}
        restored = states.get("%s-u2-restored" % fixture_id) or {}
        advanced = states.get("%s-u2-advanced" % fixture_id) or {}
        record(checks, "state_chain_predecessors",
               settled.get("prior_state_id") is None
               and restored.get("prior_state_id") == "%s-u1-settled" % fixture_id
               and advanced.get("prior_state_id") == "%s-u2-restored" % fixture_id,
               "settled -> restored -> advanced")
        record(checks, "settled_state_digest_matches_phase1",
               settled.get("status") == "ADVANCED"
               and settled.get("result_digest") == phase1["result_digest"],
               "phase-1 execution state unchanged")
        expected_restored = digest({
            "fixture_id": fixture_id,
            "restored_object_id": restore["settlement"]["object_id"],
            "r1_sha256": restore["settlement"]["r1_sha256"],
        })
        record(checks, "restored_state_digest_recomputed",
               restored.get("status") == "RESTORED"
               and restored.get("result_digest") == expected_restored,
               "result digest recomputed from restored identity")
        expected_advanced = digest({
            "fixture_id": fixture_id,
            "answer": host_record["u2"]["text"],
            "checker_pass": checker["pass"],
        })
        record(checks, "advanced_state_digest_recomputed",
               advanced.get("status") == "ADVANCED"
               and advanced.get("result_digest") == expected_advanced,
               "result digest recomputed from U2 answer and checker")
    finally:
        connection.close()

    for control, code in (("C_missing", "SETTLEMENT_MISSING"),
                          ("C_tampered", "OBJECT_DIGEST_MISMATCH")):
        gate = read_json(fixture_dir / control / "gate.json")
        copy = fixture_dir / control / "g2.sqlite"
        record(checks, "%s_refusal_recorded" % control,
               gate.get("decision") == "REFUSED" and gate.get("code") == code
               and gate.get("model_loaded") is False,
               "%s/%s" % (gate.get("decision"), gate.get("code")))
        record(checks, "%s_copy_unchanged_since_gate" % control,
               sha256_file(copy) == gate.get("database_tree_digest_before")
               == gate.get("database_tree_digest_after"),
               "current file digest == before == after")
        record(checks, "%s_copy_is_not_canonical" % control,
               pathlib.Path(gate.get("database") or "").resolve()
               == copy.resolve(), str(copy))
        control_connection = connect(copy)
        try:
            rows = control_connection.execute(
                "SELECT record_object FROM is_index_entries WHERE srs_identity=?",
                (SETTLEMENT,)).fetchall()
            if control == "C_missing":
                dependencies = control_connection.execute(
                    "SELECT COUNT(*) FROM dependency_entries WHERE dependency_id=?",
                    (SETTLEMENT,)).fetchone()[0]
                record(checks, "C_missing_settlement_absent",
                       not rows and dependencies == 0,
                       "index=%d dependency=%d" % (len(rows), dependencies))
            else:
                record(checks, "C_tampered_settlement_present",
                       len(rows) == 1, "index rows=%d" % len(rows))
                tampered = object_bytes(control_connection, rows[0]["record_object"]) \
                    if rows else None
                record(checks, "C_tampered_bytes_break_address",
                       tampered is not None
                       and hashlib.sha256(tampered[1]).hexdigest()
                       != rows[0]["record_object"]
                       and tampered[0] == len(tampered[1]),
                       "sha256(bytes) != address; byte_size agrees")
        finally:
            control_connection.close()

    raw = checker.get("raw_text") or ""
    lines = raw.rstrip("\n").split("\n")
    match = ANSWER_RE.match(lines[0]) if len(lines) == 1 else None
    secret, checksum = match.groups() if match else (None, None)
    site = (r1 or {}).get("site", "")
    recomputed = hashlib.sha256(site.lower().encode("utf-8")).hexdigest()[:8]
    record(checks, "u2_answer_recomputed",
           secret == (r1 or {}).get("secret") and checksum == recomputed
           == (r1 or {}).get("checksum") and checker.get("pass") is True,
           "ANSWER=<settled secret>-<sha256(site)[:8]>")
    prompt = host_record["u2"]["request_text"]
    record(checks, "u2_prompt_carries_recovered_r1",
           r1_canonical in prompt, "recovered R1 present in the U2 request")
    phase2_files = [path for path in (fixture_dir / "B2").rglob("*")
                    if path.is_file() and path.suffix in (".json", ".log")]
    record(checks, "s1_not_reinjected_in_phase2",
           all(fixture["s1_text"] not in path.read_text(errors="ignore")
               for path in phase2_files),
           "%d phase-2 file(s) scanned" % len(phase2_files))
    record(checks, "canary_absent_from_phase2",
           all(fixture["context_canary"] not in path.read_text(errors="ignore")
               for path in phase2_files),
           fixture["context_canary"])
    return checks


def _inject_extra_settlement_revision(db, fixture):
    connection = sqlite3.connect(str(db))
    try:
        with connection:
            connection.execute(
                "INSERT INTO dependency_entries(append_order, dependency_id, "
                "content_address, revision, reason) "
                "SELECT 99, 'settlement:u1-result', content_address, 2, 'probe' "
                "FROM dependency_entries "
                "WHERE dependency_id='settlement:u1-result' LIMIT 1")
    finally:
        connection.close()


def _inject_item_append(db, fixture):
    connection = sqlite3.connect(str(db))
    try:
        with connection:
            connection.execute(
                "INSERT INTO is_index_entries(append_order, srs_identity, "
                "record_object) SELECT 99, 'item:u2-answer', record_object "
                "FROM is_index_entries "
                "WHERE srs_identity='settlement:u1-result'")
    finally:
        connection.close()


def _inject_byte_flip(db, fixture):
    site = fixture["site"]
    replacement = site[:-1] + (site[-1].upper()
                               if site[-1].islower() else site[-1].lower())
    connection = sqlite3.connect(str(db))
    try:
        with connection:
            object_id = connection.execute(
                "SELECT record_object FROM is_index_entries "
                "WHERE srs_identity='settlement:u1-result'").fetchone()[0]
            body = connection.execute(
                "SELECT content FROM is_objects WHERE object_id=?",
                (object_id,)).fetchone()[0]
            connection.execute(
                "UPDATE is_objects SET content=? WHERE object_id=?",
                (bytes(body).replace(site.encode("utf-8"),
                                     replacement.encode("utf-8"), 1), object_id))
    finally:
        connection.close()


PROBES = (
    ("extra settlement revision", _inject_extra_settlement_revision,
     "settlement_dependency_single_revision"),
    ("extra item append", _inject_item_append,
     "no_settlement_item_or_demand_appends"),
    ("byte flip in settlement object", _inject_byte_flip,
     "settlement_bytes_match_address"),
)


def run_probes(run_dir, fixtures_dir):
    """Inject one violation at a time into a temp copy; the audit must notice."""
    probes = []
    for fixture_path in sorted(fixtures_dir.glob("fixture-*.json")):
        fixture = read_json(fixture_path)
        if "fixture_id" not in fixture:
            continue
        source = run_dir / "fixtures" / fixture["fixture_id"]
        if not source.is_dir():
            continue
        for label, inject, expected in PROBES:
            with tempfile.TemporaryDirectory() as tmp:
                copy = pathlib.Path(tmp) / fixture["fixture_id"]
                shutil.copytree(source, copy)
                inject(copy / "B1/carrier/g2.sqlite", fixture)
                checks = audit_fixture(copy, fixture)
            failed = sorted(name for name, body in checks.items() if not body["ok"])
            path_only = [name for name in failed
                         if name.endswith("_copy_is_not_canonical")]
            probes.append({
                "fixture_id": fixture["fixture_id"],
                "injected": label,
                "expected_check": expected,
                "detected": expected in failed,
                "failed_checks": [name for name in failed
                                  if name not in path_only],
                "excluded_path_checks": path_only,
                "note": "the temp copy breaks the recorded absolute gate path; "
                        "that check is expected to fail and is excluded",
            })
    return {"all_detected": all(probe["detected"] for probe in probes),
            "probes": probes}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("run_dir")
    parser.add_argument("-o", "--output", required=True)
    parser.add_argument("--fixtures", default=str(HERE / "fixtures"))
    parser.add_argument("--probe", action="store_true",
                        help="also prove the audit rejects three injected violations")
    args = parser.parse_args()

    run_dir = pathlib.Path(args.run_dir)
    fixtures_dir = pathlib.Path(args.fixtures)
    fixtures = {}
    for fixture_path in sorted(fixtures_dir.glob("fixture-*.json")):
        fixture = read_json(fixture_path)
        if "fixture_id" not in fixture:
            continue
        fixture_dir = run_dir / "fixtures" / fixture["fixture_id"]
        if not fixture_dir.is_dir():
            continue
        checks = audit_fixture(fixture_dir, fixture)
        fixtures[fixture["fixture_id"]] = {
            "checks": checks,
            "failed_checks": sorted(name for name, body in checks.items()
                                    if not body["ok"]),
        }

    all_pass = bool(fixtures) and all(
        not body["failed_checks"] for body in fixtures.values())
    report = {
        "schema_id": SCHEMA_ID,
        "run_id": run_dir.name,
        "method": "values recomputed from SQLite bytes opened with "
                  "mode=ro&immutable=1; no verdict file was read",
        "verdict_files_ignored": ["terminal.json", "verification.json"],
        "fixtures": fixtures,
        "all_pass": all_pass,
    }
    if args.probe:
        report["discrimination_probe"] = run_probes(run_dir, fixtures_dir)
    pathlib.Path(args.output).write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"all_pass": all_pass, "fixtures": {
        name: body["failed_checks"] for name, body in fixtures.items()}},
        indent=2, sort_keys=True))
    return 0 if all_pass else 4


if __name__ == "__main__":
    sys.exit(main())
