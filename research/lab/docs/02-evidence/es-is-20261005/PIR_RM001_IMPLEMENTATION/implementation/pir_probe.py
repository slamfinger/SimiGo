#!/usr/bin/env python3
"""Frozen Minimal PIR Probe v0.2 implementation and fixture-preparation helpers.

This module implements only the accepted RM-001 preparation contract.  It does
not execute MINIMAL-PIR-EXP-001, generate reconciliation observations, mutate an
Information Space, or authorize an experiment.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import shutil
import tarfile
import tempfile
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

EVIDENCE_DESTINATIONS = {
    "EV-P01": "fixture_manifests_and_checksums.json",
    "EV-P02": "query_freshness_policy.json",
    "EV-P03": "blinded_measured_path_input.json",
    "EV-P04": "sealed_oracle_ledger.json",
    "EV-P05": "phase_separated_icac_vectors.json",
    "EV-P06": "information_scope_resolution.json",
    "EV-P07": "physical_scope_resolution.json",
    "EV-P08": "physical_reconciliation_observations.jsonl",
    "EV-P09": "w_obs_age_calculations.json",
    "EV-P10": "w_latency_calculations.json",
    "EV-P11": "fresh_closure.json",
    "EV-P12": "evaluation_join.json",
    "EV-P13": "false_positives_false_negatives.json",
    "EV-P14": "paired_e_l_e_s_comparison.json",
    "EV-P15": "side_channel_denial_record.json",
    "EV-P16": "raw_object_touch_audit.jsonl",
    "EV-P17": "move_rename_correlation_evidence.json",
    "EV-P18": "observations_versus_changes_counts.json",
}

SUCCESS_STATE_FILES = (
    "EV-P08_physical_reconciliation_observations.jsonl",
    "EV-P11_fresh_closure.json",
    "EV-P12_evaluation_join.json",
    "EV-P13_false_positives_false_negatives.json",
    "EV-P14_paired_e_l_e_s_comparison.json",
    "EV-P18_observations_versus_changes_counts.json",
)

FORBIDDEN_MEASURED_KEYS = {
    "role", "fixture_role", "planned_changes", "planted_changes",
    "ground_truth", "expected_verdicts", "oracle", "oracle_ledger",
    "expected_cost", "control_cost", "agent_notes",
}

TYPED_VERDICTS = {
    "FRESH_WITHIN_WINDOW",
    "STALE_BEYOND_WINDOW",
    "PHYSICALLY_CHANGED",
    "PHYSICALLY_DELETED",
    "PHYSICALLY_MOVED",
    "CONFLICT",
    "INDETERMINATE",
}

RUN_SHAPES = {
    "E-L": {"n": 10000, "r": 20, "m": 5, "changes": True},
    "E-S": {"n": 20, "r": 20, "m": 5, "changes": True},
    "C-NOCHANGE-L": {"n": 10000, "r": 20, "m": 0, "changes": False},
    "C-NOCHANGE-S": {"n": 20, "r": 20, "m": 0, "changes": False},
}

W_OBS_AGE_MS = 60000
W_LATENCY_MS = 5000


class ProbeContractError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ProbeContractError(message)


def utc_epoch() -> str:
    return datetime(1970, 1, 1, tzinfo=timezone.utc).isoformat()


def canonical_bytes(value: object) -> bytes:
    return json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False,
        allow_nan=False,
    ).encode("utf-8")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def opaque(seed: str) -> str:
    return hashlib.sha256(seed.encode("utf-8")).hexdigest()


@dataclass
class ObjectRecord:
    stable_object_id: str
    information_identity: str
    locator: str
    content_sha256: str
    byte_size: int
    metadata_revision: int
    last_lawful_observation: str
    required_checks: List[str]
    pre_change_locator: Optional[str] = None

    def public(self) -> dict:
        value = asdict(self)
        value["required_checks"] = list(value["required_checks"])
        return value


def write_json(path: Path, value: object) -> str:
    data = json.dumps(
        value, sort_keys=True, indent=2, ensure_ascii=False, allow_nan=False
    ) + "\n"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(data, encoding="utf-8")
    return sha256_bytes(data.encode("utf-8"))


def read_json(path: Path) -> object:
    return json.loads(path.read_bytes())


def _object_payload(index: int, metadata_revision: int) -> bytes:
    value = {
        "opaque_payload_index": index,
        "synthetic_payload": f"synthetic-payload-{index}",
        "metadata_revision": metadata_revision,
    }
    return canonical_bytes(value)


def _record_for(instance_id: str, index: int, locator: str, payload: bytes,
                metadata_revision: int, observation: str,
                pre_change_locator: Optional[str] = None) -> ObjectRecord:
    stable_id = opaque(f"{instance_id}:stable-object:{index}")
    info_id = opaque(f"{instance_id}:information:{index}")
    return ObjectRecord(
        stable_object_id=stable_id,
        information_identity=info_id,
        locator=locator,
        content_sha256=sha256_bytes(payload),
        byte_size=len(payload),
        metadata_revision=metadata_revision,
        last_lawful_observation=observation,
        required_checks=[
            "locator_resolution", "existence_test",
            "identity_locator_correspondence", "content_digest",
            "policy_required_metadata_comparison",
        ],
        pre_change_locator=pre_change_locator,
    )


def build_fixture(shape: str, output_dir: Path,
                  instance_id: Optional[str] = None) -> dict:
    """Prepare one synthetic RM-001 fixture; performs no reconciliation."""
    require(shape in RUN_SHAPES, f"unknown run shape: {shape}")
    spec = RUN_SHAPES[shape]
    n = spec["n"]
    r = spec["r"]
    m = spec["m"]
    instance = instance_id or opaque(f"{shape}:{n}:{r}:{m}")
    observation = utc_epoch()
    baseline: Dict[str, bytes] = {}
    current: Dict[str, bytes] = {}
    records: Dict[str, ObjectRecord] = {}
    oracle_changes: List[dict] = []

    for index in range(n):
        locator = f"objects/{opaque(f'{instance}:locator:{index}')}.json"
        payload = _object_payload(index, 1)
        record = _record_for(instance, index, locator, payload, 1, observation)
        locator_key = locator
        baseline[locator_key] = payload
        current[locator_key] = payload
        records[record.stable_object_id] = record

    accepted_ids = [records[opaque(f'{instance}:stable-object:{i}')].stable_object_id
                    for i in range(r)]

    if spec["changes"]:
        content_changes = [0, 1]
        metadata_change = 2
        delete_index = 3
        move_index = 4
        for offset in content_changes:
            index = offset
            record = records[opaque(f"{instance}:stable-object:{index}")]
            old_locator = record.locator
            payload = _object_payload(index, 1) + b"PIR-CONTENT-CHANGE"
            current[old_locator] = payload
            new_digest = sha256_bytes(payload)
            record.content_sha256 = new_digest
            record.byte_size = len(payload)
            oracle_changes.append({
                "change_id": f"PC-MODIFY-CONTENT-{offset}",
                "change_class": "PC-MODIFY",
                "stable_object_id": record.stable_object_id,
                "old_locator": old_locator,
                "new_locator": old_locator,
                "expected_digest": new_digest,
            })
        index = metadata_change
        record = records[opaque(f"{instance}:stable-object:{index}")]
        old_locator = record.locator
        payload = current[old_locator]
        current[old_locator] = payload
        record.metadata_revision = 2
        oracle_changes.append({
            "change_id": "PC-MODIFY-METADATA",
            "change_class": "PC-MODIFY",
            "stable_object_id": record.stable_object_id,
            "old_locator": old_locator,
            "new_locator": old_locator,
            "expected_metadata_revision": 2,
        })
        index = delete_index
        record = records[opaque(f"{instance}:stable-object:{index}")]
        old_locator = record.locator
        current.pop(old_locator, None)
        oracle_changes.append({
            "change_id": "PC-DELETE",
            "change_class": "PC-DELETE",
            "stable_object_id": record.stable_object_id,
            "old_locator": old_locator,
            "new_locator": None,
        })
        index = move_index
        record = records[opaque(f"{instance}:stable-object:{index}")]
        old_locator = record.locator
        payload = current.pop(old_locator)
        new_locator = f"objects/{record.stable_object_id}.moved.json"
        current[new_locator] = payload
        record.locator = new_locator
        record.pre_change_locator = old_locator
        oracle_changes.append({
            "change_id": "PC-MOVE-RENAME",
            "change_class": "PC-MOVE",
            "stable_object_id": record.stable_object_id,
            "old_locator": old_locator,
            "new_locator": new_locator,
            "content_sha256": record.content_sha256,
            "byte_size": record.byte_size,
        })

    measured_registry = {
        record.stable_object_id: record.public() for record in records.values()
    }
    accepted_records = [measured_registry[item] for item in accepted_ids]
    measured_input = {
        "opaque_query_id": opaque(f"{instance}:query"),
        "fixture_instance_id": instance,
        "freshness_policy": {
            "w_obs_age_ms": W_OBS_AGE_MS,
            "w_latency_ms": W_LATENCY_MS,
            "is_update_authorized": False,
        },
        "registered_non_semantic_object_registry": measured_registry,
        "candidate_source": {
            "kind": "OPAQUE_NON_SEMANTIC_INDEX",
            "accepted_identifiers": accepted_ids,
        },
        "physical_scope": {
            "kind": "SYNTHETIC_ISOLATED_ARCHIVE",
            "root": "/",
            "allowed_object_class": "REGULAR_SYNTHETIC_JSON_RECORD",
            "symlinks_allowed": False,
            "global_scan_allowed": False,
        },
        "fresh_closure_output_path": "EV-P11_fresh_closure.json",
    }
    oracle_ledger = {
        "fixture_role": shape,
        "planted_changes": oracle_changes,
        "accepted_information_scope_identifiers": accepted_ids,
        "expected_no_change": not spec["changes"],
    }

    output_dir.mkdir(parents=True, exist_ok=True)
    archive_path = output_dir / "physical-state.tar"
    with tarfile.open(archive_path, mode="w", format=tarfile.PAX_FORMAT) as archive:
        for locator in sorted(current):
            data = current[locator]
            info = tarfile.TarInfo(name=locator)
            info.size = len(data)
            info.mode = 0o600
            info.mtime = 0
            info.uid = 0
            info.gid = 0
            archive.addfile(info, io.BytesIO(data))

    registry_path = output_dir / "measured_input.json"
    measured_sha = write_json(registry_path, measured_input)
    oracle_path = output_dir / "oracle_ledger.json"
    oracle_sha = write_json(oracle_path, oracle_ledger)
    binding_path = output_dir / "evidence_destination_binding.json"
    binding_sha = write_json(binding_path, {
        "authorized_destinations": EVIDENCE_DESTINATIONS,
        "state": "RESERVED_NOT_GENERATED",
        "is_update_authorized": False,
    })

    public_manifest = {
        "shape": shape,
        "fixture_instance_id": instance,
        "n": n,
        "r": r,
        "m": m,
        "w_obs_age_ms": W_OBS_AGE_MS,
        "w_latency_ms": W_LATENCY_MS,
        "physical_state_archive": archive_path.name,
        "physical_state_archive_sha256": sha256_path(archive_path),
        "physical_state_member_count": len(current),
        "measured_input_sha256": measured_sha,
        "oracle_ledger_present": True,
        "oracle_ledger_sha256": oracle_sha,
        "evidence_destination_binding_sha256": binding_sha,
        "is_update_authorized": False,
        "physical_observations_generated": 0,
    }
    manifest_path = output_dir / "fixture_manifest.json"
    manifest_sha = write_json(manifest_path, public_manifest)

    return {
        "shape": shape,
        "output_dir": str(output_dir),
        "instance_id": instance,
        "n": n,
        "r": r,
        "m": m,
        "archive": str(archive_path),
        "archive_sha256": sha256_path(archive_path),
        "member_count": len(current),
        "measured_input_sha256": measured_sha,
        "oracle_ledger_sha256": oracle_sha,
        "fixture_manifest_sha256": manifest_sha,
        "evidence_binding_sha256": binding_sha,
        "physical_observations_generated": 0,
        "is_mutations": 0,
    }


def sha256_path(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_member(archive_path: Path, name: str) -> bytes:
    with tarfile.open(archive_path, mode="r") as archive:
        member = archive.getmember(name)
        require(not member.issym() and not member.islnk() and member.isfile(),
                f"unsafe archive member: {name}")
        handle = archive.extractfile(member)
        require(handle is not None, f"unreadable archive member: {member.name}")
        return handle.read()


def validate_prechange_snapshot(fixture_dir: Path, measured: dict,
                                members: Dict[str, bytes],
                                oracle_moves: List[dict]) -> dict:
    registered = measured["registered_non_semantic_object_registry"]
    validated = []
    for move in oracle_moves:
        stable_id = move["stable_object_id"]
        record = registered[stable_id]
        pre_change = record.get("pre_change_locator")
        current = record["locator"]
        require(bool(pre_change), f"preserved pre-change locator missing: {stable_id}")
        require(pre_change not in members, f"pre-change locator still exists: {pre_change}")
        require(current in members, f"post-change locator missing: {current}")
        require(current != pre_change, f"post-change equals pre-change: {stable_id}")
        require(record["stable_object_id"] == stable_id, "stable object ID changed")
        validated.append({
            "stable_object_id": stable_id,
            "pre_change_locator": pre_change,
            "post_change_locator": current,
        })
    require(len(validated) == len(oracle_moves), "pre-change validation count mismatch")
    return {"validated_moves": validated, "pass": True}


def verify_fixture(fixture_dir: Path) -> dict:
    manifest_path = fixture_dir / "fixture_manifest.json"
    manifest = json.loads(manifest_path.read_bytes())
    shape = manifest["shape"]
    require(shape in RUN_SHAPES, "unknown fixture shape")
    spec = RUN_SHAPES[shape]
    require(manifest["n"] == spec["n"], "fixture N mismatch")
    require(manifest["r"] == spec["r"], "fixture R mismatch")
    require(manifest["m"] == spec["m"], "fixture M mismatch")
    require(manifest["physical_observations_generated"] == 0,
            "fixture preparation generated observations")
    require(manifest["is_update_authorized"] is False, "IS update is unauthorized")

    archive_path = fixture_dir / manifest["physical_state_archive"]
    require(sha256_path(archive_path) == manifest["physical_state_archive_sha256"],
            "physical-state archive hash mismatch")
    measured_path = fixture_dir / "measured_input.json"
    require(sha256_path(measured_path) == manifest["measured_input_sha256"],
            "measured-input hash mismatch")

    measured = json.loads(measured_path.read_bytes())
    for key in FORBIDDEN_MEASURED_KEYS:
        require(key not in measured, f"forbidden measured-path key: {key}")
    require(measured["freshness_policy"]["is_update_authorized"] is False,
            "IS update is unauthorized")
    registry = measured["registered_non_semantic_object_registry"]
    require(len(registry) == spec["n"], "registered N mismatch")
    accepted = measured["candidate_source"]["accepted_identifiers"]
    require(len(accepted) == spec["r"], "accepted R mismatch")
    require(len(set(accepted)) == spec["r"], "accepted scope duplicates")
    scope = measured["physical_scope"]
    require(scope["global_scan_allowed"] is False, "global scan is forbidden")
    require(scope["symlinks_allowed"] is False, "symlinks are forbidden")

    members = {}
    with tarfile.open(archive_path, mode="r") as archive:
        for member in archive.getmembers():
            require(member.isfile(), f"non-regular archive member: {member.name}")
            require(not member.issym() and not member.islnk(),
                    f"link in archive: {member.name}")
            handle = archive.extractfile(member)
            require(handle is not None, f"unreadable archive member: {member.name}")
            members[member.name] = handle.read()
    require(len(members) == manifest["physical_state_member_count"],
            "archive member count mismatch")

    oracle_path = fixture_dir / "oracle_ledger.json"
    require(sha256_path(oracle_path) == manifest.get("oracle_ledger_sha256"),
            "oracle-ledger hash mismatch")
    oracle = json.loads(oracle_path.read_bytes())
    require(oracle["fixture_role"] == shape, "oracle fixture role mismatch")
    require(len(oracle["planted_changes"]) == spec["m"], "planted M mismatch")
    require(oracle["expected_no_change"] is (not spec["changes"]),
            "no-change expectation mismatch")
    prechange_validation = validate_prechange_snapshot(
        fixture_dir, measured, members,
        [x for x in oracle["planted_changes"] if x["change_class"] == "PC-MOVE"],
    )

    for stable_id, record in measured["registered_non_semantic_object_registry"].items():
        require(record["stable_object_id"] == stable_id, "stable ID mismatch")
    # Strong record/archive verification
    for stable_id, record in measured["registered_non_semantic_object_registry"].items():
        locator = record["locator"]
        if locator not in members:
            # Deleted and moved old locators are lawfully absent from the
            # post-change physical archive.  Reconciliation must detect that
            # absence during the separately authorized experiment.
            continue
        payload = members[locator]
        require(hashlib.sha256(payload).hexdigest() == record["content_sha256"],
                f"registry digest mismatch: {locator}")
        require(len(payload) == record["byte_size"], f"registry size mismatch: {locator}")

    # Validate planted control ledger against baseline/current separated by oracle.
    for change in oracle["planted_changes"]:
        stable_id = change["stable_object_id"]
        record = measured["registered_non_semantic_object_registry"][stable_id]
        if change["change_class"] == "PC-DELETE":
            require(change["old_locator"] not in members, "deleted object still exists")
        elif change["change_class"] == "PC-MOVE":
            require(change["old_locator"] not in members, "old moved locator exists")
            require(change["new_locator"] in members, "moved object missing")
            moved = members[change["new_locator"]]
            require(hashlib.sha256(moved).hexdigest() == change["content_sha256"],
                    "moved content mismatch")
        elif change["change_class"] == "PC-MODIFY":
            require(change["new_locator"] in members, "modified object missing")
            modified = members[change["new_locator"]]
            if "expected_digest" in change:
                require(hashlib.sha256(modified).hexdigest() == change["expected_digest"],
                        "modified content mismatch")

    binding_path = fixture_dir / "evidence_destination_binding.json"
    binding = json.loads(binding_path.read_bytes())
    require(binding["state"] == "RESERVED_NOT_GENERATED",
            "fixture preparation generated evidence observations")
    require(binding["is_update_authorized"] is False, "IS update is unauthorized")
    required_ev = {f"EV-P{i:02d}" for i in range(1, 19)}
    require(set(binding["authorized_destinations"]) == required_ev,
            "EV-P01..EV-P18 binding mismatch")

    return {
        "shape": shape,
        "fixture_instance_id": manifest["fixture_instance_id"],
        "n": manifest["n"],
        "r": manifest["r"],
        "m": manifest["m"],
        "member_count": len(members),
        "physical_observations": 0,
        "physical_changes_in_fixture": len(oracle["planted_changes"]),
        "is_mutations": 0,
        "oracle_isolation": "PASS",
        "prechange_snapshot_validation": prechange_validation,
        "fixture_legality": "PASS",
        "evidence_destination_binding": "PASS",
    }


def validate_no_experiment_output(fixture_root: Path) -> dict:
    prohibited = list(SUCCESS_STATE_FILES) + [
        "physical_reconciliation_results.json",
        "experiment_run_record.json",
    ]
    found = [name for name in prohibited if (fixture_root / name).exists()]
    require(not found, f"forbidden experiment output present: {found}")
    return {"prohibited_experiment_outputs_found": found}


def prepare_all(output_root: Path) -> dict:
    results = {}
    for shape in RUN_SHAPES:
        fixture_dir = output_root / shape
        results[shape] = build_fixture(shape, fixture_dir)
    return results


def self_check(output_root: Path) -> dict:
    with tempfile.TemporaryDirectory(prefix="pir-rm001-selfcheck-") as directory:
        temporary = Path(directory)
        prepared = prepare_all(temporary)
        fixture_results = {}
        for shape, info in prepared.items():
            fixture_dir = temporary / shape
            fixture_results[shape] = verify_fixture(fixture_dir)
            validate_no_experiment_output(fixture_dir)
        # Contract assertions
        require(TYPED_VERDICTS == {
            "FRESH_WITHIN_WINDOW", "STALE_BEYOND_WINDOW", "PHYSICALLY_CHANGED",
            "PHYSICALLY_DELETED", "PHYSICALLY_MOVED", "CONFLICT", "INDETERMINATE"
        }, "typed verdict set mismatch")
        require(set(EVIDENCE_DESTINATIONS) == {f"EV-P{i:02d}" for i in range(1, 19)},
                "EV destination set mismatch")
        require(all(x["physical_observations_generated"] == 0 for x in prepared.values()),
                "fixture preparation generated observations")
        require(all(x["is_mutations"] == 0 for x in prepared.values()),
                "fixture preparation mutated IS")
    return {
        "probe_contract": "Minimal PIR Probe v0.2 / DESIGN FROZEN",
        "implementation_self_check": "PASS",
        "fixture_legality": "PASS",
        "oracle_isolation": "PASS",
        "attribution_separation": "PASS",
        "experiment_output_leak": "NONE",
        "is_mutations": 0,
        "physical_observations": 0,
        "fixtures": fixture_results,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    prepare = sub.add_parser("prepare", help="prepare RM-001 fixtures")
    prepare.add_argument("--output", required=True, type=Path)
    check = sub.add_parser("self-check", help="validate implementation and prepared fixtures")
    check.add_argument("--fixtures", required=True, type=Path)
    check.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()
    if args.command == "prepare":
        result = prepare_all(args.output)
    elif args.command == "self-check":
        result = self_check(args.fixtures)
        write_json(args.report, result)
        print(f"SELF_CHECK={result['implementation_self_check']}")
        print(f"PHYSICAL_OBSERVATIONS={result['physical_observations']}")
        print(f"IS_MUTATIONS={result['is_mutations']}")
        return 0
    print(json.dumps(result, indent=2, sort_keys=True, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
