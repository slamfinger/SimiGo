#!/usr/bin/env python3
"""Offline self-test for the G2 batch plumbing. Never loads the model.

Exercises the exact code paths the run will use:
  carrier settlement -> restore gate -> two negative-control mutations ->
  second gate pass after phase-2 execution states.

It writes nothing into the repository and creates no evidence root. A failure
here means the batch must not be frozen.

Usage: python3 selftest_offline.py
"""

import json
import pathlib
import shutil
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from carrier_gate import run_gate  # noqa: E402
from carrier_loop import digest  # noqa: E402
import run_batch  # noqa: E402

FIXTURE = json.loads((HERE / "fixtures" / "fixture-1.json").read_text(encoding="utf-8"))


def fake_u1_record():
    r1 = {"secret": FIXTURE["transfer_secret"], "site": FIXTURE["site"],
          "checksum": FIXTURE["record_checksum"]}
    canonical = json.dumps(r1, sort_keys=True, separators=(",", ":"))
    return {"r1_canonical": canonical, "r1_sha256": digest(json.loads(canonical))}


def main():
    failures = []
    work = pathlib.Path(tempfile.mkdtemp(prefix="g2-selftest-"))
    try:
        carrier = work / "carrier"
        carrier.mkdir()
        db = carrier / "g2.sqlite"
        u1 = fake_u1_record()
        settlement = run_batch.create_phase1_carrier(db, FIXTURE, u1)

        restored = run_gate(db, "u1-result", phase1_record=u1)
        if restored["decision"] != "RESTORED":
            failures.append("canonical carrier refused: %s" % restored.get("code"))
        if restored["settlement"]["object_id"] != settlement["settlement"]["object_id"]:
            failures.append("restored object_id differs from the settlement")
        if not restored["database_unchanged"]:
            failures.append("gate changed the canonical carrier")

        for variant, mutate, expected in (
                ("missing", run_batch.remove_settlement, "SETTLEMENT_MISSING"),
                ("tampered", run_batch.tamper_payload, "OBJECT_DIGEST_MISMATCH")):
            target = work / variant
            copy = run_batch.copy_carrier(db, target)
            mutate(copy, "u1-result")
            before = run_batch.sqlite_digest(copy)
            gate = run_gate(copy, "u1-result", phase1_record=u1)
            after = run_batch.sqlite_digest(copy)
            if gate["decision"] != "REFUSED":
                failures.append("%s was not refused" % variant)
            if gate["code"] != expected:
                failures.append("%s refused with %s, expected %s"
                                % (variant, gate["code"], expected))
            if before != after:
                failures.append("%s copy changed after refusal" % variant)

        states = run_batch.record_phase2_states(
            db, FIXTURE, {"restored_object_id": settlement["settlement"]["object_id"]},
            {"answer": "ANSWER=%s-%s" % (FIXTURE["transfer_secret"],
                                         FIXTURE["record_checksum"]),
             "checker_pass": True})
        identities = run_batch.carrier_index_identities(db)
        appended = identities[-2:]
        if not all(entry.startswith("execution_state:") for entry in appended):
            failures.append("phase-2 appended a non execution-state entry: %s" % appended)
        second = run_gate(db, "u1-result")
        if second["settlement"]["object_id"] != restored["settlement"]["object_id"]:
            failures.append("settlement object changed after phase 2")

        checker = run_batch.check_u2(
            "ANSWER=%s-%s" % (FIXTURE["transfer_secret"], FIXTURE["record_checksum"]),
            json.loads(u1["r1_canonical"]), FIXTURE)
        if not checker["pass"]:
            failures.append("checker rejected a correct answer")

        print(json.dumps({
            "schema_id": "SIMIGO-G2-BATCH-OFFLINE-SELFTEST-V1",
            "fixture": FIXTURE["fixture_id"],
            "model_loaded": False,
            "restore": restored["decision"],
            "negative_controls": ["SETTLEMENT_MISSING", "OBJECT_DIGEST_MISMATCH"],
            "phase2_states": states,
            "failures": failures,
            "passed": not failures,
        }, indent=2, sort_keys=True))
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return 0 if not failures else 6


if __name__ == "__main__":
    sys.exit(main())
