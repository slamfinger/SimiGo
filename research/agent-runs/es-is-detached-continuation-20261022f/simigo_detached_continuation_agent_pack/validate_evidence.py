#!/usr/bin/env python3
"""Validate the minimum structure and claim-critical counters in summary.json.

Standard-library only. It checks evidence contracts, not whether a scientific claim is
true by itself; reviewers must still inspect raw inputs, stdout, token streams and hashes.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import sys

ALLOWED = {"OBSERVED", "INVALID_CONDITION", "BLOCKED_NOT_RUN", "OBSERVED_FORMAT_FAILURE"}
EXPECTED = {"W-A", "W-B", "N1-MISSING-SETTLEMENT", "N2-INVALID-SIGNATURE-OR-BYTE-TAMPER", "N3-DEPENDENCY-MISMATCH", "N4-PREFIX-AND-CROSS-WORLD-AUDIT"}


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("summary", type=Path)
    p.add_argument("--acceptance", type=Path, help="optional path to write a validation report")
    args = p.parse_args()
    data = json.loads(args.summary.read_text())
    errors = []
    for key in ("schema_version", "experiment_id", "terminal_state", "source_snapshot", "model_identity", "conditions", "conclusion_objects", "historical_artifact_guard"):
        if key not in data:
            errors.append(f"missing top-level key: {key}")
    if data.get("experiment_id") != "ES_IS_DETACHED_CONTINUATION_20261022F":
        errors.append("experiment_id mismatch")
    if data.get("terminal_state") not in ALLOWED:
        errors.append("invalid top-level terminal_state")
    conds = data.get("conditions", [])
    by_id = {}
    for c in conds:
        cid = c.get("condition_id")
        if cid in by_id:
            errors.append(f"duplicate condition_id: {cid}")
        by_id[cid] = c
        if c.get("terminal_state") not in ALLOWED:
            errors.append(f"{cid}: invalid terminal_state")
        for k in ("processes", "execution_state", "settlement", "counters", "inputs", "outputs", "side_effects", "claim_limit"):
            if k not in c:
                errors.append(f"{cid}: missing {k}")
    missing = EXPECTED - set(by_id)
    if missing:
        errors.append(f"missing required conditions: {sorted(missing)}")
    for cid in ("W-A", "W-B"):
        c = by_id.get(cid)
        if not c or c.get("terminal_state") != "OBSERVED":
            continue
        pr, es, st, ct, inp, out, se = (c.get(k, {}) for k in ("processes", "execution_state", "settlement", "counters", "inputs", "outputs", "side_effects"))
        if not pr.get("producer_exit_before_consumer_start"):
            errors.append(f"{cid}: producer must exit before consumer starts")
        if pr.get("producer_pid") == pr.get("consumer_pid"):
            errors.append(f"{cid}: producer and consumer PID must differ")
        if pr.get("producer_context_release_evidence") == "BLOCKED_NOT_OBSERVED":
            errors.append(f"{cid}: no evidence old context/process release")
        if not es.get("new_execution_state_id") or es.get("new_execution_state_id") == es.get("source_execution_state_id"):
            errors.append(f"{cid}: new ES ID missing or identical to source ES")
        if es.get("consumer_initial_position") != 0 or not es.get("consumer_state_empty_before_start"):
            errors.append(f"{cid}: consumer must start from empty state at position 0")
        if es.get("old_checkpoint_reads") != 0 or es.get("prefix_replay_tokens") != 0:
            errors.append(f"{cid}: old checkpoint/prefix replay detected")
        if st.get("signature_valid") is not True or not st.get("read_via_production_admission"):
            errors.append(f"{cid}: settlement not proven signed and read through production admission")
        if ct.get("u1_generate_calls_in_producer") != 1 or ct.get("u1_generate_calls_during_consumer") != 0 or ct.get("u2_generate_calls") != 1:
            errors.append(f"{cid}: generation counts do not show U1 once, not rerun in U2, and U2 once")
        if ct.get("harness_direct_settlement_reads") != 0 or ct.get("harness_direct_item_reads") != 0 or ct.get("production_admission_calls", 0) < 1:
            errors.append(f"{cid}: consumer must use production admission without harness direct reads")
        if not inp.get("base_template_nonce_free") or not inp.get("cold_seed_nonce_free") or not inp.get("argv_env_nonce_free") or not inp.get("cross_world_nonce_scan_clean"):
            errors.append(f"{cid}: nonce/prompt isolation audit incomplete or failed")
        if out.get("output_matches_world_settlement") is not True:
            errors.append(f"{cid}: U2 output does not match world settlement")
        if se.get("unexpected_effects"):
            errors.append(f"{cid}: unexpected side effects listed")
    for cid in ("N1-MISSING-SETTLEMENT", "N2-INVALID-SIGNATURE-OR-BYTE-TAMPER", "N3-DEPENDENCY-MISMATCH"):
        c = by_id.get(cid)
        if not c or c.get("terminal_state") != "OBSERVED":
            continue
        ct, se = c.get("counters", {}), c.get("side_effects", {})
        if any(ct.get(k) != 0 for k in ("tokenize_text_calls", "tokenize_seed_calls", "u2_generate_calls")):
            errors.append(f"{cid}: refusal was not before all tokenization/generation")
        if se.get("db_pre_sha256") != se.get("db_post_sha256") or se.get("state_pre_sha256") != se.get("state_post_sha256"):
            errors.append(f"{cid}: DB/state changed during refused admission")
        if se.get("unexpected_effects"):
            errors.append(f"{cid}: unexpected side effects listed")
    guard = data.get("historical_artifact_guard", {})
    if guard.get("result") != "PASS":
        errors.append("historical artifact guard is not PASS")
    report = {"result": "PASS" if not errors else "FAIL", "summary": str(args.summary.resolve()), "errors": errors, "condition_ids": sorted(by_id)}
    if args.acceptance:
        args.acceptance.parent.mkdir(parents=True, exist_ok=True)
        args.acceptance.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if not errors else 2

if __name__ == "__main__":
    raise SystemExit(main())
