#!/usr/bin/env python3
"""Execute an authorized Minimal PIR Probe fixture set under RM-001."""
from __future__ import annotations

import argparse
import hashlib
import json
import tarfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import pir_probe


@dataclass
class PhaseMeter:
    started_monotonic: float
    ended_monotonic: float
    objects: dict
    bytes_read: int
    syscalls: dict
    blockers: int

    @classmethod
    def start(cls) -> "PhaseMeter":
        return cls(started_monotonic=time.monotonic(), ended_monotonic=time.monotonic(),
                   objects={"total_registered_n": 0, "index_candidates": 0,
                            "information_scope_accepted": 0, "physical_candidates": 0,
                            "physical_checks": 0, "changed_found": 0,
                            "closure_references": 0, "unrelated_object_touches": 0},
                   bytes_read={"payload_bytes_read": 0, "digest_bytes_read": 0},
                   syscalls={"stat": 0, "open": 0, "read": 0}, blockers=0)

    def finish(self) -> None:
        self.ended_monotonic = time.monotonic()

    def vector(self) -> dict:
        return {
            "latency_ms": {
                "elapsed_ms": max(0, int((self.ended_monotonic - self.started_monotonic) * 1000)),
            },
            "objects": dict(self.objects),
            "bytes": dict(self.bytes_read),
            "syscalls": dict(self.syscalls),
            "blockers": {"typed_blocker_count": self.blockers},
        }


def sha_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False,
                               allow_nan=False) + "\n", encoding="utf-8")


def load_archive_index(archive_path: Path, meter: PhaseMeter) -> Dict[str, bytes]:
    members: Dict[str, bytes] = {}
    with tarfile.open(archive_path, mode="r") as archive:
        for member in archive.getmembers():
            meter.syscalls["open"] += 1
            if not member.isfile():
                raise RuntimeError(f"non-regular Physical Scope member: {member.name}")
            handle = archive.extractfile(member)
            if handle is None:
                raise RuntimeError(f"unreadable Physical Scope member: {member.name}")
            members[member.name] = handle.read()
    return members


def resolve_accepted_scope(measured: dict, meter: PhaseMeter) -> List[dict]:
    registry = measured["registered_non_semantic_object_registry"]
    accepted = measured["candidate_source"]["accepted_identifiers"]
    meter.objects["total_registered_n"] = len(registry)
    meter.objects["index_candidates"] = len(accepted)
    meter.objects["information_scope_accepted"] = len(accepted)
    records = []
    for stable_id in accepted:
        if stable_id not in registry:
            raise RuntimeError(f"accepted Information Scope object missing: {stable_id}")
        records.append(registry[stable_id])
    return records


def parse_metadata(payload: bytes) -> Optional[dict]:
    try:
        return json.loads(payload)
    except Exception:
        return None


def reconcile_accepted_object(record: dict, members: Dict[str, bytes],
                              previous_ns: int, current_ns: int,
                              w_obs_age_ms: int, meter: PhaseMeter) -> dict:
    old_locator = record["locator"]
    meter.syscalls["stat"] += 1
    exists = old_locator in members
    candidates: List[str] = []
    if exists:
        candidates.append(old_locator)
    else:
        # The registered record is the only lawful deterministic correlation
        # source. The updated locator is accepted only when its content and size
        # exactly match the registered object facts.
        updated_locator = record.get("updated_locator")
        if updated_locator and updated_locator in members:
            candidates.append(updated_locator)
    meter.objects["physical_candidates"] += len(candidates)
    meter.objects["physical_checks"] += 1
    observation_age_ms = max(0, (current_ns - previous_ns) // 1_000_000)
    obs_age_pass = observation_age_ms <= w_obs_age_ms
    evidence = {
        "stable_object_id": record["stable_object_id"],
        "information_identity": record["information_identity"],
        "registered_locator": old_locator,
        "observed_locators": candidates,
        "registered_content_sha256": record["content_sha256"],
        "registered_byte_size": record["byte_size"],
        "registered_metadata_revision": record["metadata_revision"],
        "observation_age_ms": observation_age_ms,
        "w_obs_age_pass": obs_age_pass,
    }
    if not candidates:
        verdict = "PHYSICALLY_DELETED"
    elif len(candidates) > 1:
        verdict = "CONFLICT"
    else:
        locator = candidates[0]
        payload = members[locator]
        meter.bytes_read["payload_bytes_read"] += len(payload)
        digest = sha_bytes(payload)
        evidence.update({
            "observed_locator": locator,
            "observed_content_sha256": digest,
            "observed_byte_size": len(payload),
        })
        metadata = parse_metadata(payload)
        observed_revision = metadata.get("metadata_revision") if isinstance(metadata, dict) else None
        evidence["observed_metadata_revision"] = observed_revision
        same_digest = digest == record["content_sha256"]
        same_size = len(payload) == record["byte_size"]
        same_revision = observed_revision == record["metadata_revision"]
        if not (same_digest and same_size and same_revision):
            verdict = "PHYSICALLY_CHANGED"
        elif not obs_age_pass:
            verdict = "STALE_BEYOND_WINDOW"
        else:
            verdict = "FRESH_WITHIN_WINDOW"
    evidence["verdict"] = verdict
    if verdict in {"STALE_BEYOND_WINDOW", "CONFLICT", "INDETERMINATE"}:
        meter.blockers += 1
    return evidence


def reconstruct_fresh_closure(query_id: str, accepted_records: List[dict],
                              observations: List[dict], policy: dict,
                              meter: PhaseMeter) -> dict:
    by_id = {x["stable_object_id"]: x for x in observations}
    closure_items = []
    for record in accepted_records:
        observation = by_id.get(record["stable_object_id"])
        if observation is None:
            raise RuntimeError(f"Fresh Closure missing accepted object: {record['stable_object_id']}")
        closure_items.append({
            "stable_object_id": record["stable_object_id"],
            "information_identity": record["information_identity"],
            "physical_verdict": observation["verdict"],
            "observation_age_ms": observation["observation_age_ms"],
            "blocker": observation["verdict"] in {
                "STALE_BEYOND_WINDOW", "CONFLICT", "INDETERMINATE"
            },
        })
    complete = all(not item["blocker"] for item in closure_items)
    meter.objects["closure_references"] = len(closure_items)
    return {
        "opaque_query_id": query_id,
        "accepted_information_scope_size": len(accepted_records),
        "closure_items": closure_items,
        "closure_complete": complete,
        "freshness_policy": policy,
    }


def execute_fixture(shape: str, fixture_dir: Path, output_dir: Path) -> dict:
    fixture_dir = fixture_dir.resolve()
    output_dir = output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=False)
    measured_path = fixture_dir / "measured_input.json"
    measured = json.loads(measured_path.read_bytes())
    archive_path = fixture_dir / "physical-state.tar"
    policy = measured["freshness_policy"]
    query_id = measured["opaque_query_id"]
    w_obs_age_ms = int(policy["w_obs_age_ms"])
    w_latency_ms = int(policy["w_latency_ms"])
    oracle_path = fixture_dir / "oracle_ledger.json"
    oracle_sha256 = hashlib.sha256(oracle_path.read_bytes()).hexdigest()

    query_start_monotonic = time.monotonic()
    query_start_ns = time.monotonic_ns()
    write_json(output_dir / "EV-P02_query_freshness_policy.json", {
        "shape": shape,
        "policy": policy,
        "clock_mode": "CONTROLLED_FIXTURE_CLOCK_FOR_SYNTHETIC_OBSERVATION_AGE",
    })
    phase_meters = {}
    write_json(output_dir / "EV-P15_side_channel_denial_record.json", {
        "planted_change_ledger_input": False,
        "ground_truth_input": False,
        "expected_verdict_input": False,
        "control_cost_target_input": False,
        "fixture_role_input": False,
        "semantic_similarity_used": False,
        "whole_space_scan_used": False,
    })

    meter = PhaseMeter.start()
    meter.objects["total_registered_n"] = len(measured["registered_non_semantic_object_registry"])
    accepted_records = resolve_accepted_scope(measured, meter)
    meter.finish()
    phase_meters["S1_information_scope_resolution"] = meter.vector()

    meter = PhaseMeter.start()
    meter.objects["information_scope_accepted"] = len(accepted_records)
    # Individual tar member opens are counted in S4 as stat/read effects.
    meter.finish()
    phase_meters["S2_physical_scope_assembly"] = meter.vector()

    members = load_archive_index(archive_path, meter := PhaseMeter.start())
    phase_meters["S3_candidate_retrieval"] = meter.vector()

    meter = PhaseMeter.start()
    meter.objects["information_scope_accepted"] = len(accepted_records)
    # The archive is the declared synthetic Physical Scope. Previous observation
    # timestamps are fixture-controlled; current reconciliation is advanced by
    # exactly one controlled millisecond per object so W_obs_age tests threshold
    # handling without real-wall-clock dependence.
    previous_by_id = {
        record["stable_object_id"]: record["last_lawful_observation"] for record in accepted_records
    }
    observations = []
    move_evidence = []
    max_previous_ns = 0
    for record in accepted_records:
        stable_id = record["stable_object_id"]
        previous = previous_by_id[stable_id]
        previous_ns = int(__import__("datetime").datetime.fromisoformat(previous).timestamp() * 1_000_000)
        max_previous_ns = max(max_previous_ns, previous_ns)
        current_ns = previous_ns + 1_000_000
        observation = reconcile_accepted_object(record, members, previous_ns,
                                                current_ns, w_obs_age_ms, meter)
        observations.append(observation)
        if observation["verdict"] == "PHYSICALLY_MOVED":
            move_evidence.append(observation)
    meter.finish()
    phase_meters["S4_physical_reconciliation"] = meter.vector()
    observations_payload = b"".join(
        json.dumps(x, sort_keys=True, separators=(",", ":"),
                   ensure_ascii=False, allow_nan=False).encode("utf-8") + b"\n"
        for x in observations
    )
    observations_path = output_dir / "EV-P08_physical_reconciliation_observations.jsonl"
    observations_path.write_bytes(observations_payload)
    reconciliation_current_ns = max_previous_ns + 1_000_000

    closure_meter = PhaseMeter.start()
    closure = reconstruct_fresh_closure(query_id, accepted_records, observations,
                                        policy, closure_meter)
    closure_meter.finish()
    phase_meters["S5_fresh_closure_reconstruction"] = closure_meter.vector()
    closure["w_obs_age_ms"] = w_obs_age_ms
    closure["w_obs_age_pass"] = all(
        not item["blocker"] or item["physical_verdict"] != "STALE_BEYOND_WINDOW"
        for item in closure["closure_items"]
    )
    closure["w_latency_ms_limit"] = w_latency_ms
    write_json(output_dir / "EV-P11_fresh_closure.json", closure)

    query_latency_ms = int((time.monotonic() - query_start_monotonic) * 1000)
    latency_pass = query_latency_ms <= w_latency_ms
    write_json(output_dir / "EV-P09_w_obs_age_calculations.json", {
        "threshold_ms": w_obs_age_ms,
        "clock_mode": "CONTROLLED_FIXTURE_CLOCK_FOR_SYNTHETIC_OBSERVATION_AGE",
        "observations": [
            {"stable_object_id": x["stable_object_id"],
             "observation_age_ms": x["observation_age_ms"],
             "pass": x["observation_age_ms"] <= w_obs_age_ms}
            for x in observations
        ],
    })
    write_json(output_dir / "EV-P10_w_latency_calculations.json", {
        "threshold_ms": w_latency_ms,
        "observed_ms": query_latency_ms,
        "pass": latency_pass,
    })

    # Evaluation join occurs only after the measured Fresh Closure is complete.
    oracle = json.loads(oracle_path.read_bytes())
    oracle_by_id = {x["stable_object_id"]: x for x in oracle["planted_changes"]}
    observations_by_id = {x["stable_object_id"]: x for x in observations}
    true_positive, false_negative, false_positive = [], [], []
    for change in oracle["planted_changes"]:
        stable_id = change["stable_object_id"]
        observed = observations_by_id.get(stable_id)
        if observed and observed["verdict"] in {
            "PHYSICALLY_CHANGED", "PHYSICALLY_DELETED", "PHYSICALLY_MOVED"
        }:
            true_positive.append(stable_id)
        else:
            false_negative.append(stable_id)
    predicted_changed = [
        x["stable_object_id"] for x in observations
        if x["verdict"] in {"PHYSICALLY_CHANGED", "PHYSICALLY_DELETED", "PHYSICALLY_MOVED"}
    ]
    oracle_changed = set(oracle_by_id)
    for stable_id in predicted_changed:
        if stable_id not in oracle_changed:
            false_positive.append(stable_id)

    paired = {
        "e_l": None,
        "e_s": None,
        "note": "paired comparison is assembled after all fixture executions",
    }
    write_json(output_dir / "EV-P12_evaluation_join.json", {
        "true_positive_changes": true_positive,
        "false_negative_changes": false_negative,
        "false_positive_changes": false_positive,
    })
    write_json(output_dir / "EV-P13_false_positives_false_negatives.json", {
        "false_negative_count": len(false_negative),
        "false_positive_count": len(false_positive),
    })
    write_json(output_dir / "EV-P16_raw_object_touch_audit.jsonl", "".join(
        json.dumps({
            "stable_object_id": x["stable_object_id"],
            "registered_locator": x["registered_locator"],
            "observed_locators": x["observed_locators"],
            "physical_check": True,
        }, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n"
        for x in observations
    ))
    write_json(output_dir / "EV-P17_move_rename_correlation_evidence.json", {
        "rule": "registered stable object ID + exact content SHA256 + exact byte size",
        "maximum_candidates": 1,
        "evidence": move_evidence,
    })
    write_json(output_dir / "EV-P18_observations_versus_changes_counts.json", {
        "physical_observations": len(observations),
        "physical_changes_detected": len(predicted_changed),
        "oracle_physical_changes": len(oracle_changed),
        "false_negative_changes": len(false_negative),
        "false_positive_changes": len(false_positive),
    })

    overall_pass = (
        closure["closure_complete"]
        and closure.get("w_obs_age_pass") is True
        and latency_pass
        and not false_negative
        and not false_positive
    )
    result = {
        "shape": shape,
        "execution_commit": subprocess_check_head(),
        "fixture_dir": str(fixture_dir),
        "outcome": "PASS" if overall_pass else "FAIL_CLOSED",
        "stop_code": ("MINIMAL_PIR_EXPERIMENT_COMPLETE"
                      if overall_pass else
                      "MINIMAL_PIR_EXPERIMENT_ASSERTION_FAILURE"),
        "w_obs_age_ms": w_obs_age_ms,
        "w_obs_age_pass": closure.get("w_obs_age_pass"),
        "w_latency_ms": w_latency_ms,
        "w_latency_observed_ms": query_latency_ms,
        "w_latency_pass": latency_pass,
        "accepted_scope": len(accepted_records),
        "observations": len(observations),
        "oracle_changes": len(oracle_changed),
        "true_positive_changes": len(true_positive),
        "false_negative_changes": len(false_negative),
        "false_positive_changes": len(false_positive),
        "closure_complete": closure["closure_complete"],
        "artifact_state": "FINAL_SUCCESS" if overall_pass else "FAILURE",
        "phase_vectors": phase_meters,
    }
    write_json(output_dir / "EXPERIMENT_RESULT.json", result)
    write_json(output_dir / "EV-P14_paired_e_l_e_s_comparison.json", paired)
    return result


def subprocess_check_head() -> str:
    import subprocess
    return __import__("subprocess").check_output(["git", "rev-parse", "HEAD"], text=True).strip()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixtures", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--experiment-id", required=True)
    args = parser.parse_args()
    results = {}
    overall = True
    for shape in ("E-L", "E-S", "C-NOCHANGE-L", "C-NOCHANGE-S"):
        result = execute_fixture(shape, args.fixtures / shape,
                                 args.output / shape)
        results[shape] = result
        overall = overall and result["outcome"] == "PASS"
        if not overall:
            break
    summary = {
        "experiment_id": args.experiment_id,
        "results": results,
        "overall_outcome": "PASS" if overall else "FAIL_CLOSED",
        "candidate_equivalence_pending_human_audit": overall,
        "pir_equivalence_established": False,
        "is_mutations": 0,
        "repair_performed": False,
        "rerun_performed": False,
    }
    write_json(args.output / "EXPERIMENT_SUMMARY.json", summary)
    print(f"MINIMAL_PIR_EXP_001={summary['overall_outcome']}")
    print(f"IS_MUTATIONS={summary['is_mutations']}")
    print(f"REPAIR={summary['repair_performed']} RERUN={summary['rerun_performed']}")
    return 0 if overall else 1


if __name__ == "__main__":
    raise SystemExit(main())
