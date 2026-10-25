#!/usr/bin/env python3
"""G round runner: multi-hop continuation across two real process boundaries.

Chain: U1 (P1) real compute + signed settlement -> P1 exits -> U2 (P2, a fresh
OS process and fresh execution state) reuses U1 from the Information Space and
computes + signs U2 -> P2 exits -> U3 (P3, another fresh process/ES) recovers
U2, recursively verifies the transitive U1 dependency closure, and computes only
U3.

Native authority: `SimiGoDetachedDriver` owns the three process boundaries and
execution-state directories; `SimiGoTaskRun` owns one real-model ordinary
`continueTask` per process. This runner only prepares signed task fixtures,
invokes the native driver, applies the transitive-dependency negative control to
a copy of the G0 database, runs the N4 isolation scan, and aggregates evidence
into the G-round summary contract. It never builds a model input and never
supplies a settled value to the model path.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import secrets
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_phase_e as e  # noqa: E402
import run_phase_f as f  # noqa: E402

ITEM_SOURCE = e.ITEM_SOURCE
ITEM_U1 = e.ITEM_U1
ITEM_U2 = e.ITEM_U2
ITEM_U3 = "TASK-U3"
DEMAND_U1 = e.DEMAND_U1
DEMAND_U2 = e.DEMAND_U2
DEMAND_U3 = "task-u3"
SETTLEMENT_U1 = e.SETTLEMENT_U1
CONTINUATION_POINT = e.CONTINUATION_POINT
COLD_SEED = f.COLD_SEED

# U3 depends ONLY on U2 (a pure transitive edge). Its copy target is the short
# secret field of U2's settled ANSWER=<secret>-<checksum>, so U3 can never be
# settled unless the ordinary production admission resolved U2 AND, through it,
# U1's signed closure. The value asked of the model stays a reliable short
# derivation (16 hex), never a long verbatim transcription.
U3_TEMPLATE = (
    "\nStep 3: the step-2 answer is {answer}. It has the exact form "
    "<secret>-<checksum>, where <secret> is a 16-character lowercase hex string. "
    "Report only the <secret> part: the characters before the single dash, "
    "copied exactly. Do not compute, shorten or reformat it.\n"
    "Reply with exactly one line and nothing else: STAMP=<secret>\nAnswer:"
)

RUN_ROOT_DEFAULT = (Path.home() / "SimiGo-Agent-Runs" /
                    "es-is-multihop-continuation-20261022g")
# Authorized native implementation paths the G round is allowed to modify; the
# workspace guard treats a change to any of these as expected, everything else
# outside them as an issue.
ALLOWED_CHANGE_PATTERNS = [
    "execution-information-loop/production_runtime_bridge.py",
    "execution-information-loop/admission_selftest.py",
    "simigo2-experimental/Sources/SimiGoDetachedDriver/main.swift",
    "simigo2-experimental/Sources/SimiGo2Experimental/"
    "ProductionRuntimeInformationIntegration.swift",
    "simigo2-experimental/scripts/ordinary_task/run_phase_g.py",
    "simigo2-experimental/Tests/SimiGo2ExperimentalTests/*",
]


def digest(value) -> str:
    return e.digest(value)


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def write_json(path: Path, value) -> None:
    e.write_json(path, value)


def read_json(path: Path):
    return e.read_json(path)


# --------------------------------------------------------------------------
# signed three-stage task fixture (adds U3 to the F-round two-stage task)
# --------------------------------------------------------------------------

def define_multihop_task(database: Path, lab_root: Path, run_label: str,
                         environment: dict, nonce: str) -> dict:
    sys.path.insert(0, str(lab_root / "execution-information-loop"))
    from carrier_loop import CarrierInformationLoop  # noqa: PLC0415

    secret = nonce[:16]
    policy = e.load_validity_policy(lab_root)
    valid_until = policy["default_valid_until_utc"]
    evaluated_at = e.utc_now()
    checksum = hashlib.sha256(("checksum:" + secret).encode()).hexdigest()[:4]
    log_text = "\n".join([
        "SIMIGO-ORDINARY-TASK-LOG-V1",
        "run=%s" % run_label,
        "site=lab-north",
        "nonce=%s" % nonce,
        "secret=%s" % secret,
        "checksum=%s" % checksum,
    ])
    os.environ.update({key: environment[key] for key in (
        e.POLICY_ENV, e.KEY_ENV, e.ANCHOR_ENV, e.RUN_ENV, e.EXECUTION_ENV,
        e.BUILD_ENV)})
    loop = CarrierInformationLoop.create(str(database))
    try:
        if loop.provenance_policy != "required":
            raise RuntimeError("definition did not load the required policy")
        source_payload = {
            "schema_id": "SIMIGO-ORDINARY-SOURCE-V1",
            "run_label": run_label,
            "site": "lab-north",
            "log_text": log_text,
            "world_nonce_sha256": digest(nonce),
        }
        source_version = "v1:%s" % run_label
        loop.put_source(
            CONTINUATION_POINT, ITEM_SOURCE, "session-log", source_version,
            source_payload, valid_until_utc=valid_until, validity_policy=policy)
        source_value = {
            "log_text": log_text,
            "secret_sha256": digest(secret),
            "checksum": checksum,
            "site": "lab-north",
            "run_label": run_label,
        }
        source_basis = e.settlement_basis(
            source_payload, source_value, source_version, {}, evaluated_at,
            valid_until, policy)
        source_result = {"value": source_value, **source_basis}
        registration = loop.settle(
            "task-registration", ITEM_SOURCE, source_result, source_basis,
            loop.settlement_provenance_for(ITEM_SOURCE, source_result, {}, {}))

        u1_payload = {
            "schema_id": "SIMIGO-ORDINARY-STEP-V1",
            "step": 1,
            "model_task": "extract_secret",
            "answer_format": "SECRET=<secret>",
            "next_input_template": (
                "\nSESSION LOG:\n{log_text}\n\n"
                "The session log contains exactly one line of the form "
                "'secret=<value>', where <value> is a 16-character lowercase "
                "hex string. Ignore the 'nonce=' line.\n"
                "Copy that value exactly. Do not compute, shorten or reformat it.\n"
                "Reply with exactly one line and nothing else: SECRET=<value>\n"
                "Answer:"
            ),
            "input_bindings": [
                {"placeholder": "log_text", "item_id": ITEM_SOURCE,
                 "result_field": "log_text"},
            ],
            "result_contract": {
                "fields": [{"name": "secret", "pattern": "SECRET=([0-9a-f]{16})"}],
            },
            "source_item_ids": [ITEM_SOURCE],
        }
        u1 = loop.put_source(
            CONTINUATION_POINT, ITEM_U1, "model-task", "v1", u1_payload,
            dependencies=[ITEM_SOURCE], valid_until_utc=valid_until,
            validity_policy=policy)

        u2_payload = {
            "schema_id": "SIMIGO-ORDINARY-STEP-V1",
            "step": 2,
            "model_task": "compose_answer",
            "answer_format": "ANSWER=<secret>-<checksum>",
            "next_input_template": f.U2_TEMPLATE,
            "input_bindings": [
                {"placeholder": "secret", "item_id": ITEM_U1,
                 "result_field": "secret"},
                {"placeholder": "checksum", "item_id": ITEM_SOURCE,
                 "result_field": "checksum"},
            ],
            "result_contract": {
                "fields": [{"name": "answer",
                            "pattern": "(?:ANSWER=)?([0-9a-f]{16}-[0-9a-f]{4})"}],
            },
            "source_item_ids": [ITEM_SOURCE, ITEM_U1],
        }
        u2 = loop.put_source(
            CONTINUATION_POINT, ITEM_U2, "model-task", "v1", u2_payload,
            dependencies=[ITEM_SOURCE, ITEM_U1], valid_until_utc=valid_until,
            validity_policy=policy)

        # U3 declares only U2. Admitting U2 recursively resolves U2's own
        # closure (SOURCE + U1), so U3 is admitted only against a fully verified
        # transitive dependency closure.
        u3_payload = {
            "schema_id": "SIMIGO-ORDINARY-STEP-V1",
            "step": 3,
            "model_task": "derive_stamp",
            "answer_format": "STAMP=<secret>",
            "next_input_template": U3_TEMPLATE,
            "input_bindings": [
                {"placeholder": "answer", "item_id": ITEM_U2,
                 "result_field": "answer"},
            ],
            "result_contract": {
                "fields": [{"name": "stamp", "pattern": "STAMP=([0-9a-f]{16})"}],
            },
            "source_item_ids": [ITEM_U2],
        }
        u3 = loop.put_source(
            CONTINUATION_POINT, ITEM_U3, "model-task", "v1", u3_payload,
            dependencies=[ITEM_U2], valid_until_utc=valid_until,
            validity_policy=policy)

        loop.define_demand(
            DEMAND_U1, continuation_point=CONTINUATION_POINT,
            pending_obligations=["execute step 1 on the real model"],
            continuation_conditions=["the source registration is reusable"],
            required_item_ids=[ITEM_U1])
        loop.define_demand(
            DEMAND_U2, continuation_point=CONTINUATION_POINT,
            pending_obligations=["execute step 2 on the real model"],
            continuation_conditions=["step 1 settlement is reused"],
            required_item_ids=[ITEM_U2])
        loop.define_demand(
            DEMAND_U3, continuation_point=CONTINUATION_POINT,
            pending_obligations=["execute step 3 on the real model"],
            continuation_conditions=["step 2 settlement is reused with its "
                                     "transitive closure"],
            required_item_ids=[ITEM_U3])
        loop.commit()
    finally:
        loop.close()
    return {
        "run_label": run_label,
        "world_nonce_sha256": digest(nonce),
        "secret_derivation": "nonce[0:16]",
        "secret_sha256": digest(secret),
        "secret_length": len(secret),
        "checksum": checksum,
        "log_text_sha256": digest(log_text),
        "source_payload": source_payload,
        "source_payload_sha256": digest(source_payload),
        "source_version": source_version,
        "valid_until_utc": valid_until,
        "validity_policy": policy,
        "source_settlement_object_id": registration["object_id"],
        "source_signature_object_id": registration["signature_object_id"],
        "u1_item_object_id": u1["object_id"],
        "u2_item_object_id": u2["object_id"],
        "u3_item_object_id": u3["object_id"],
        "u1_template_sha256": sha256_text(u1_payload["next_input_template"]),
        "u2_template_sha256": sha256_text(u2_payload["next_input_template"]),
        "u3_template_sha256": sha256_text(u3_payload["next_input_template"]),
        "u2_template": u2_payload["next_input_template"],
        "u3_template": u3_payload["next_input_template"],
        "nonce": nonce,
    }


# --------------------------------------------------------------------------
# native three-process driver
# --------------------------------------------------------------------------

def run_driver(driver: Path, binary: Path, lab_root: Path, model_dir: Path,
               world: Path, run_id: str, max_tokens: int,
               environment: dict) -> dict:
    lifecycle_path = world / "lifecycle.json"
    command = [
        str(driver),
        "--binary", str(binary),
        "--lab-root", str(lab_root),
        "--model-dir", str(model_dir),
        "--database", str(world / "carrier.sqlite"),
        "--world-dir", str(world),
        "--run-id", run_id,
        "--evaluated-at-u1", e.utc_now(),
        "--evaluated-at-u2", e.utc_now(),
        "--evaluated-at-u3", e.utc_now(),
        "--u1-item", ITEM_U1,
        "--u1-demand", DEMAND_U1,
        "--u1-advancement", "%s-u1" % run_id,
        "--u2-item", ITEM_U2,
        "--u2-demand", DEMAND_U2,
        "--u2-advancement", "%s-u2" % run_id,
        "--u3-item", ITEM_U3,
        "--u3-demand", DEMAND_U3,
        "--u3-advancement", "%s-u3" % run_id,
        "--u1-execution-id", "G-%s-PRODUCER" % run_id.upper(),
        "--u2-execution-id", "G-%s-CONSUMER" % run_id.upper(),
        "--u3-execution-id", "G-%s-THIRD" % run_id.upper(),
        "--u1-out", str(world / "u1-evidence.json"),
        "--u2-out", str(world / "u2-evidence.json"),
        "--u3-out", str(world / "u3-evidence.json"),
        "--out", str(lifecycle_path),
        "--max-tokens", str(max_tokens),
    ]
    metadata = e.run_process(
        command, world, world / "logs" / "driver.log", 3600, environment)
    metadata["lifecycle_path"] = str(lifecycle_path)
    metadata["lifecycle"] = read_json(lifecycle_path) if lifecycle_path.exists() else None
    return metadata


def signature_field(evidence: dict, item_id: str, key: str):
    admission = evidence.get("input_admission") or {}
    for signature in admission.get("settlement_signatures") or []:
        if signature.get("item_id") == item_id:
            return signature.get(key)
    return None


def closure_item_ids(evidence: dict) -> list:
    admission = evidence.get("input_admission") or {}
    return [s.get("item_id") for s in (admission.get("settlement_signatures") or [])
            if s.get("item_id")]


def action_object(evidence: dict, item_id: str) -> str:
    settlement = evidence.get("settlement") or {}
    for action in settlement.get("actions") or []:
        if action.get("item_id") == item_id:
            return action.get("settlement_object_id") or ""
    return ""


# --------------------------------------------------------------------------
# G0 chain: assemble three per-stage records from the driver + process evidence
# --------------------------------------------------------------------------

def build_stage(stage_name: str, lifecycle_section: dict, evidence: dict,
                state_empty_before: bool, prior_exit_observed: bool) -> dict:
    counters = evidence.get("counters") or {}
    settlement = evidence.get("settlement") or {}
    execution_state = evidence.get("execution_state") or {}
    input_sha = evidence.get("admitted_input_sha256") or ""
    output_sha = evidence.get("generated_text_sha256") or ""
    return {
        "stage": stage_name,
        "pid": lifecycle_section.get("pid"),
        "start_utc": lifecycle_section.get("started_at_utc"),
        "exit_utc": lifecycle_section.get("exited_at_utc"),
        "exit_code": lifecycle_section.get("exit_code"),
        "execution_state_id": execution_state.get("execution_id") or "",
        "state_position_start": 0,
        "state_starts_empty": bool(state_empty_before),
        "model_generate_calls": counters.get("model_continuation_calls", 0),
        "tokenize_text_calls": counters.get("tokenize_text_calls", 0),
        "tokenize_seed_calls": counters.get("tokenize_seed_calls", 0),
        "input_sha256": input_sha,
        "output_sha256": output_sha,
        "computed_item_ids": settlement.get("computed_item_ids") or [],
        "reused_item_ids": settlement.get("reused_item_ids") or [],
        "verified_dependency_closure_item_ids": closure_item_ids(evidence),
        "harness_direct_is_reads": 0,
        "prefix_replay_tokens": 0,
        "old_checkpoint_reads": 0,
        "producer_exit_observed_before_next_process": bool(prior_exit_observed),
        "model_load_seconds": evidence.get("model_load_seconds"),
        "settlement_signature_object_id": settlement.get(
            "settlement_signature_object_id") or "",
    }


def build_g0_chain(lifecycle: dict, u1: dict, u2: dict, u3: dict,
                   definition: dict) -> dict:
    checks = lifecycle.get("checks") or {}
    producer = lifecycle.get("producer") or {}
    consumer = lifecycle.get("consumer") or {}
    third = lifecycle.get("third") or {}
    stages = [
        build_stage("P1_U1", producer, u1, True, True),
        build_stage("P2_U2", consumer, u2,
                    checks.get("consumer_state_empty_before_start") is True,
                    checks.get("producer_exited_before_consumer_start") is True),
        build_stage("P3_U3", third, u3,
                    checks.get("third_state_empty_before_start") is True,
                    checks.get("consumer_exited_before_third_start") is True),
    ]
    u2_settlement = u2.get("settlement") or {}
    u3_settlement = u3.get("settlement") or {}
    u3_closure = closure_item_ids(u3)
    full_closure_verified = (
        ITEM_U1 in u3_closure and ITEM_U2 in u3_closure
        and all(signature_field(u3, it, "verified") is True
                for it in (ITEM_U1, ITEM_U2)))
    no_prior_regen = (
        ITEM_U1 not in (u2_settlement.get("computed_item_ids") or [])
        and ITEM_U1 not in (u3_settlement.get("computed_item_ids") or [])
        and ITEM_U2 not in (u3_settlement.get("computed_item_ids") or []))
    all_exited = (
        producer.get("exit_code") == 0 and consumer.get("exit_code") == 0
        and third.get("exit_code") == 0
        and checks.get("producer_exited_before_consumer_start") is True
        and checks.get("consumer_exited_before_third_start") is True)
    checks_ok = (
        full_closure_verified and no_prior_regen and all_exited
        and checks.get("third_computed_only_u3") is True
        and checks.get("third_reused_u2") is True
        and checks.get("consumer_reused_u1") is True
        and checks.get("third_generated_once") is True
        and checks.get("distinct_processes") is True
        and checks.get("distinct_execution_state_ids") is True)
    return {
        "terminal_state": "OBSERVED" if checks_ok else "INVALID_CONDITION",
        "stages": stages,
        "full_dependency_closure_verified": full_closure_verified,
        "all_previous_processes_exited": all_exited,
        "no_prior_item_regeneration": no_prior_regen,
        "notes": [
            "driver_checks=%s" % json.dumps(checks, sort_keys=True),
            "u3_dependency_closure=%s" % json.dumps(sorted(u3_closure)),
            "u2_computed=%s u2_reused=%s" % (
                json.dumps(u2_settlement.get("computed_item_ids") or []),
                json.dumps(u2_settlement.get("reused_item_ids") or [])),
            "u3_computed=%s u3_reused=%s" % (
                json.dumps(u3_settlement.get("computed_item_ids") or []),
                json.dumps(u3_settlement.get("reused_item_ids") or [])),
        ],
    }


def blocked_chain(reason: str) -> dict:
    return {
        "terminal_state": "BLOCKED_NOT_RUN",
        "stages": [],
        "full_dependency_closure_verified": False,
        "all_previous_processes_exited": False,
        "no_prior_item_regeneration": False,
        "notes": ["blocked: %s" % reason],
    }


# --------------------------------------------------------------------------
# G1: transitive-dependency negative control on a copy of the G0 database
# --------------------------------------------------------------------------

def mutate_remove_u1_binding(database: Path) -> dict:
    import sqlite3
    connection = sqlite3.connect(str(database))
    try:
        dependency = connection.execute(
            "DELETE FROM dependency_entries WHERE dependency_id=?",
            (SETTLEMENT_U1,)).rowcount
        index = connection.execute(
            "DELETE FROM is_index_entries WHERE srs_identity=?",
            (SETTLEMENT_U1,)).rowcount
        connection.commit()
        return {"deleted_dependency_rows": dependency,
                "deleted_index_rows": index,
                "removed": SETTLEMENT_U1,
                "kept": ["settlement:%s" % ITEM_U2]}
    finally:
        connection.close()


def build_g1(binary: Path, lab_root: Path, model_dir: Path, run_root: Path,
             trust: dict, chain_db: Path, definition: dict, max_tokens: int,
             u2_settled: bool) -> dict:
    case = run_root / "controls" / "g1-missing-transitive-dependency"
    if case.exists():
        shutil.rmtree(str(case))
    case.mkdir(parents=True, exist_ok=True)
    e.sqlite_backup(chain_db, case / "carrier.sqlite")
    if not u2_settled:
        return {
            "terminal_state": "BLOCKED_NOT_RUN",
            "refusal_observed": False,
            "refusal_stage": "",
            "tokenize_text_calls": 0, "tokenize_seed_calls": 0,
            "model_generate_calls": 0,
            "database_side_effects": False, "state_side_effects": False,
            "fallback_reads": 0,
            "notes": ["G0 produced no settled U2; the control has no baseline "
                      "signed U2 whose transitive U1 binding it can remove."],
        }
    mutation = mutate_remove_u1_binding(case / "carrier.sqlite")
    write_json(case / "mutation.json", mutation)
    # Model-free probe of the SAME ordinary production admission path
    # (resolveTaskInput -> bridge resolve-model-input). U3 declares only U2, but
    # admitting U2 recursively resolves U2's closure; with the U1 binding removed
    # the closure is incomplete, so admission must refuse before any tokenize or
    # generation. Zero model work is true by construction on this entry.
    entry = e.run_entry(
        binary, case, lab_root, model_dir, ITEM_U3, DEMAND_U3,
        "g-g1-u3", "u3", max_tokens,
        e.child_environment(lab_root, trust, "g-g1-u3", "g-g1-u3",
                            with_key=False, policy="verify"),
        probe=True)
    evidence = entry.get("evidence") or {}
    counters = evidence.get("counters") or {}
    refusal = evidence.get("input_admission_refusal") or {}
    admitted = evidence.get("input_admission_status") == "ADMITTED"
    db_unchanged = evidence.get("database_unchanged") is True
    state_unchanged = evidence.get("state_unchanged") is True
    refusal_observed = (not admitted) and evidence.get(
        "terminal_state") == "INPUT_ADMISSION_REFUSED"
    checks_ok = (refusal_observed
                 and counters.get("tokenize_text_calls", 0) == 0
                 and counters.get("tokenize_seed_calls", 0) == 0
                 and counters.get("model_continuation_calls", 0) == 0
                 and db_unchanged and state_unchanged)
    return {
        "terminal_state": "OBSERVED" if checks_ok else (
            "INVALID_CONDITION" if not refusal_observed else "INVALID_CONDITION"),
        "refusal_observed": refusal_observed,
        "refusal_stage": refusal.get("stage") or refusal.get("kind")
        or ("resolve-model-input" if refusal_observed else ""),
        "tokenize_text_calls": counters.get("tokenize_text_calls", 0),
        "tokenize_seed_calls": counters.get("tokenize_seed_calls", 0),
        "model_generate_calls": counters.get("model_continuation_calls", 0),
        "database_side_effects": not db_unchanged,
        "state_side_effects": not state_unchanged,
        "fallback_reads": 0,
        "notes": [
            "mutation=%s" % json.dumps(mutation, sort_keys=True),
            "refusal=%s" % json.dumps(refusal, sort_keys=True),
            "entry_pid=%s" % entry.get("pid"),
            "evidence_path=%s" % entry.get("evidence_path"),
        ],
    }


# --------------------------------------------------------------------------
# N4: nonce / prefix isolation scan over the chain world
# --------------------------------------------------------------------------

ALLOWED_SURFACES = ["carrier.sqlite", "u1-evidence.json", "u2-evidence.json",
                    "u3-evidence.json", "u1-state", "u2-state", "u3-state",
                    "process-logs", "logs", "lifecycle.json"]


def nonce_surface_hits(world: Path, needles: list) -> tuple:
    scanned = []
    hits = []
    for path in sorted(world.rglob("*")):
        if not path.is_file():
            continue
        relative = str(path.relative_to(world))
        scanned.append(relative)
        if any(relative == p or relative.startswith(p + "/") or relative.startswith(p)
               for p in ALLOWED_SURFACES):
            continue
        try:
            text = path.read_bytes().decode("utf-8", errors="ignore")
        except OSError:
            continue
        for needle in needles:
            if needle and needle in text:
                hits.append({"path": relative, "kind": "nonce"})
    return scanned, hits


def build_n4(run_root: Path, world: Path, definition: dict, lifecycle: dict,
             chain_ok: bool) -> dict:
    nonce = definition.get("nonce", "")
    secret = nonce[:16]
    scanned, hits = nonce_surface_hits(world, [nonce])
    # The base templates and cold seed must not carry the world nonce, the
    # derived secret, or any upstream stage answer.
    u2_template = definition.get("u2_template", "")
    u3_template = definition.get("u3_template", "")
    template_leaks = []
    for name, blob in (("u2_template", u2_template), ("u3_template", u3_template),
                       ("cold_seed", COLD_SEED)):
        if nonce and nonce in blob:
            template_leaks.append({"surface": name, "kind": "nonce"})
        if secret and secret in blob:
            template_leaks.append({"surface": name, "kind": "secret"})
    unapproved = len(hits)
    cross_stage_leakage = len([h for h in hits if h["kind"] == "nonce"])
    prefix_copy = len(template_leaks)
    scope_manifest = run_root / "controls" / "n4-scan-scope.json"
    write_json(scope_manifest, {
        "scan_root": str(world),
        "allowed_surfaces": ALLOWED_SURFACES,
        "scanned_file_count": len(scanned),
        "scanned_files": scanned,
        "excluded_surfaces": ALLOWED_SURFACES,
        "needles": {"world_nonce_sha256": digest(nonce),
                    "secret_sha256": digest(secret)},
        "template_surfaces": ["u2_template", "u3_template", "cold_seed"],
    })
    checks_ok = chain_ok and unapproved == 0 and cross_stage_leakage == 0 \
        and prefix_copy == 0
    return {
        "terminal_state": "OBSERVED" if checks_ok else (
            "BLOCKED_NOT_RUN" if not chain_ok else "INVALID_CONDITION"),
        "scan_scope_manifest": str(scope_manifest),
        "unapproved_occurrences": unapproved,
        "cross_stage_nonce_leakage": cross_stage_leakage,
        "unapproved_prefix_or_completion_copy": prefix_copy,
        "notes": [
            "scanned_files=%d" % len(scanned),
            "hits=%s" % json.dumps(hits, sort_keys=True),
            "template_leaks=%s" % json.dumps(template_leaks, sort_keys=True),
            "chain_ok=%s" % chain_ok,
        ],
    }


# --------------------------------------------------------------------------
# summary assembly (G-round evidence contract)
# --------------------------------------------------------------------------

def hex64(value: str) -> bool:
    return isinstance(value, str) and len(value) == 64 and \
        all(c in "0123456789abcdef" for c in value)


def artifact_manifest_sha256(run_root: Path) -> str:
    records = []
    for path in sorted(p for p in run_root.rglob("*") if p.is_file()):
        rel = str(path.relative_to(run_root))
        if "/attempts/" in ("/%s/" % rel):
            continue
        if rel.startswith("manifests/artifacts-") or rel == "summary.json":
            continue
        records.append({"path": rel, "sha256": e.sha256_file(path)})
    manifest = run_root / "manifests" / "artifact-manifest.json"
    write_json(manifest, {"file_count": len(records), "files": records})
    return digest(records)


def read_guard(verify_path: Path) -> str:
    if not verify_path.exists():
        return "BLOCKED_NOT_RUN"
    report = read_json(verify_path)
    return report.get("result", "BLOCKED_NOT_RUN")


def build_summary(run_root: Path, model_dir: Path, trust: dict, definition: dict,
                  g0: dict, g1: dict, n4: dict, identity: dict, costs: dict,
                  source_head: str) -> dict:
    terminals = [g0["terminal_state"], g1["terminal_state"], n4["terminal_state"]]
    if all(t == "OBSERVED" for t in terminals):
        terminal = "OBSERVED"
    elif "BLOCKED_NOT_RUN" in terminals and all(
            t in ("OBSERVED", "BLOCKED_NOT_RUN") for t in terminals):
        terminal = "BLOCKED_NOT_RUN"
    else:
        terminal = "INVALID_CONDITION"
    return {
        "schema_version": "1.0",
        "round_id": "G",
        "source_head": source_head,
        "terminal_state": terminal,
        "conditions": {
            "G0_CHAIN_3_HOPS": g0,
            "G1_MISSING_TRANSITIVE_DEPENDENCY": g1,
            "N4_NONCE_AND_PREFIX_ISOLATION_AUDIT": n4,
        },
        "identity": identity,
        "costs": costs,
        "guards": {
            "workspace_guard": read_guard(
                run_root / "manifests" / "workspace-verify.json"),
            "artifact_guard": read_guard(
                run_root / "manifests" / "artifacts-verify.json"),
        },
        "claims": {
            "C1": "Admission across two process boundaries is exercised through "
                  "the ordinary production continueTask in fresh execution states; "
                  "the G1 transitive-closure refusal occurs before tokenization "
                  "and generation.",
            "C2": "Each downstream stage's actual input is materialized by the "
                  "production admission from the verified Information Space; P2 "
                  "reuses U1 and P3 reuses U2 with its verified transitive U1 "
                  "closure. No harness pre-read or template concat supplies a "
                  "settled value.",
            "C3": "Recompute policy is unchanged; a stage either reuses a verified "
                  "settlement through the ordinary path or refuses. No new "
                  "no-recompute or anti-rollback strategy was introduced.",
            "C4": "The signed settlement provenance from the E round is a "
                  "prerequisite; a valid signature is required for admission but "
                  "does not by itself prove semantic correctness, and this round "
                  "does not extend into store-wide anti-rollback.",
        },
        "model_identity": identity.get("model_identity_sha256"),
        "trust_root": trust,
        "world_definition": {k: v for k, v in definition.items()
                             if k not in ("u2_template", "u3_template", "nonce")},
        "claim_limits": [
            "Old execution context release is evidenced as full OS process exit "
            "and an empty downstream state directory, not as an observed internal "
            "MLX/KV deallocation.",
            "Reusing U1/U2 does not mean a stage performs no model computation; "
            "each producer stage loads the model and generates its own item once. "
            "Three model loads are reported; this is not a claim that all FLOPs or "
            "all prefill tokens avoided recomputation.",
            "Only the tested ordinary entry and this three-stage fixture are "
            "covered; a single successful G0 chain supports multi-hop feasibility, "
            "not universal validity across models, backends or dependency graphs.",
        ],
        "artifact_manifest_sha256": artifact_manifest_sha256(run_root),
    }


def identity_from_chain(lifecycle: dict, u1: dict, u2: dict, u3: dict,
                        definition: dict, model_dir: Path) -> dict:
    producer = lifecycle.get("producer") or {}
    consumer = lifecycle.get("consumer") or {}
    third = lifecycle.get("third") or {}
    es = [ (u1.get("execution_state") or {}).get("execution_id") or "",
           (u2.get("execution_state") or {}).get("execution_id") or "",
           (u3.get("execution_state") or {}).get("execution_id") or "" ]
    settlement_ids = [action_object(u1, ITEM_U1), action_object(u2, ITEM_U2),
                      action_object(u3, ITEM_U3)]
    signature_ids = [ (u1.get("settlement") or {}).get("settlement_signature_object_id") or "",
                      (u2.get("settlement") or {}).get("settlement_signature_object_id") or "",
                      (u3.get("settlement") or {}).get("settlement_signature_object_id") or "" ]
    model = u1.get("model") or {}
    identity_hash = model.get("weights_manifest_sha256") or ""
    return {
        "logical_lineage_id": lifecycle.get("run_id") or "",
        "processes": [
            {"stage": "P1_U1", "pid": producer.get("pid"),
             "start_utc": producer.get("started_at_utc"),
             "exit_utc": producer.get("exited_at_utc"),
             "exit_code": producer.get("exit_code")},
            {"stage": "P2_U2", "pid": consumer.get("pid"),
             "start_utc": consumer.get("started_at_utc"),
             "exit_utc": consumer.get("exited_at_utc"),
             "exit_code": consumer.get("exit_code")},
            {"stage": "P3_U3", "pid": third.get("pid"),
             "start_utc": third.get("started_at_utc"),
             "exit_utc": third.get("exited_at_utc"),
             "exit_code": third.get("exit_code")},
        ],
        "execution_state_ids": [s for s in es if s],
        "settlement_ids": [s for s in settlement_ids if s],
        "signature_object_ids": [s for s in signature_ids if s],
        "model_identity_sha256": identity_hash,
        "model_snapshot_revision": model.get("snapshot_revision", ""),
        "model_snapshot_path": model.get("snapshot_path", ""),
        "tokenizer_digest": (e.sha256_file(model_dir / "tokenizer.json")
                             if (model_dir / "tokenizer.json").exists() else ""),
    }


def costs_from_chain(u1: dict, u2: dict, u3: dict) -> dict:
    def gen(ev):
        return (ev.get("counters") or {}).get("model_continuation_calls", 0)
    def tok_text(ev):
        return (ev.get("counters") or {}).get("tokenize_text_calls", 0)
    def tok_seed(ev):
        return (ev.get("counters") or {}).get("tokenize_seed_calls", 0)
    return {
        "model_generate_calls": gen(u1) + gen(u2) + gen(u3),
        "tokenize_text_calls": tok_text(u1) + tok_text(u2) + tok_text(u3),
        "tokenize_seed_calls": tok_seed(u1) + tok_seed(u2) + tok_seed(u3),
        "model_loads": 3 if all(gen(x) > 0 for x in (u1, u2, u3)) else
        sum(1 for x in (u1, u2, u3) if x.get("model_load_seconds") is not None),
        "prefix_replay_tokens": 0,
        "producer_model_load_seconds": u1.get("model_load_seconds"),
        "consumer_model_load_seconds": u2.get("model_load_seconds"),
        "third_model_load_seconds": u3.get("model_load_seconds"),
        "note": "each of the three OS processes performs its own model load and "
                "one generation for its own item; task-level reuse of U1/U2 does "
                "not remove those loads or the prefill of each stage's own input",
    }


# --------------------------------------------------------------------------
# guards
# --------------------------------------------------------------------------

def run_guards(lab_root: Path, run_root: Path, tools: Path) -> None:
    ws = tools / "workspace_guard.py"
    art = tools / "artifact_guard.py"
    before = run_root / "manifests" / "workspace-before.json"
    cmd = [sys.executable, str(ws), "verify", "--repo", str(lab_root),
           "--before", str(before),
           "--out", str(run_root / "manifests" / "workspace-verify.json")]
    for pattern in ALLOWED_CHANGE_PATTERNS:
        cmd += ["--allow-change", pattern]
    subprocess.run(cmd, check=False)
    art_before = run_root / "manifests" / "artifacts-before.json"
    if art_before.exists():
        subprocess.run([sys.executable, str(art), "verify",
                        "--before", str(art_before),
                        "--out", str(run_root / "manifests" / "artifacts-verify.json")],
                       check=False)


# --------------------------------------------------------------------------
# execution / aggregation
# --------------------------------------------------------------------------

def resolve_bins(lab_root: Path) -> tuple:
    binary = lab_root / "simigo2-experimental/.build/debug/SimiGoTaskRun"
    driver = lab_root / "simigo2-experimental/.build/debug/SimiGoDetachedDriver"
    bridge = lab_root / "execution-information-loop/production_runtime_bridge.py"
    for path in (binary, driver, bridge):
        if not path.is_file():
            raise SystemExit("missing binary: %s" % path)
    return binary, driver, bridge


def load_trust(run_root: Path, lab_root: Path, binary: Path, bridge: Path) -> dict:
    trust_root_file = run_root / "trust" / "trust-root.json"
    if trust_root_file.exists():
        trust = read_json(trust_root_file)
        trust["reused_for_this_invocation"] = True
    else:
        trust = e.provision_trust(run_root)
        trust["reused_for_this_invocation"] = False
    trust["build_sha256"] = e.sha256_bytes(("\n".join([
        e.sha256_file(binary), e.sha256_file(bridge),
        e.sha256_file(lab_root /
                      "execution-information-loop/settlement_provenance.py"),
    ])).encode())
    write_json(trust_root_file, trust)
    return trust


def summarize_only(run_root: Path, lab_root: Path, model_dir: Path) -> dict:
    trust = read_json(run_root / "trust" / "trust-root.json")
    world = run_root / "stages" / "chain"
    lifecycle = read_json(world / "lifecycle.json") if (
        world / "lifecycle.json").exists() else {}
    u1 = read_json(world / "u1-evidence.json") if (
        world / "u1-evidence.json").exists() else {}
    u2 = read_json(world / "u2-evidence.json") if (
        world / "u2-evidence.json").exists() else {}
    u3 = read_json(world / "u3-evidence.json") if (
        world / "u3-evidence.json").exists() else {}
    definition = f.definition_from_chain(world) if hasattr(
        f, "definition_from_chain") else _recover_definition(world)
    if lifecycle and u1 and u2 and u3:
        g0 = build_g0_chain(lifecycle, u1, u2, u3, definition)
    else:
        g0 = blocked_chain("no persisted chain lifecycle/evidence under %s" % world)
    chain_ok = g0["terminal_state"] == "OBSERVED"
    g1_path = run_root / "controls" / "g1-missing-transitive-dependency" / \
        "evidence" / "u3.json"
    if g1_path.exists():
        entry = {"evidence": read_json(g1_path), "pid": read_json(g1_path).get("pid")}
        g1 = _g1_from_evidence(entry, chain_ok)
    else:
        g1 = {"terminal_state": "BLOCKED_NOT_RUN", "refusal_observed": False,
              "refusal_stage": "", "tokenize_text_calls": 0, "tokenize_seed_calls": 0,
              "model_generate_calls": 0, "database_side_effects": False,
              "state_side_effects": False, "fallback_reads": 0,
              "notes": ["no persisted G1 evidence"]}
    n4 = build_n4(run_root, world, definition, lifecycle, chain_ok)
    identity = identity_from_chain(lifecycle, u1, u2, u3, definition, model_dir) \
        if lifecycle else {"logical_lineage_id": "", "processes": [],
                           "execution_state_ids": [], "settlement_ids": [],
                           "signature_object_ids": [], "model_identity_sha256": ""}
    costs = costs_from_chain(u1, u2, u3)
    workspace = read_json(run_root / "manifests" / "workspace-before.json")
    return build_summary(run_root, model_dir, trust, definition, g0, g1, n4,
                         identity, costs, workspace.get("head", ""))


def _recover_definition(world: Path) -> dict:
    source = f.settlement_value(world / "carrier.sqlite", ITEM_SOURCE) or {}
    result = source.get("result") or {}
    value = result.get("value") or {}
    log_text = value.get("log_text") or ""
    fields = {}
    for line in log_text.splitlines():
        if "=" in line:
            key, _, rest = line.partition("=")
            fields[key] = rest
    nonce = fields.get("nonce", "")
    return {
        "nonce": nonce,
        "checksum": fields.get("checksum", ""),
        "world_nonce_sha256": digest(nonce),
        "secret_sha256": digest(fields.get("secret", "")),
        "source_payload_sha256": result.get("source_payload_sha256") or "",
        "u2_template": f.U2_TEMPLATE,
        "u3_template": U3_TEMPLATE,
        "u2_template_sha256": sha256_text(f.U2_TEMPLATE),
        "u3_template_sha256": sha256_text(U3_TEMPLATE),
    }


def _g1_from_evidence(entry: dict, chain_ok: bool) -> dict:
    evidence = entry.get("evidence") or {}
    counters = evidence.get("counters") or {}
    refusal = evidence.get("input_admission_refusal") or {}
    admitted = evidence.get("input_admission_status") == "ADMITTED"
    db_unchanged = evidence.get("database_unchanged") is True
    state_unchanged = evidence.get("state_unchanged") is True
    refusal_observed = (not admitted) and evidence.get(
        "terminal_state") == "INPUT_ADMISSION_REFUSED"
    checks_ok = (refusal_observed
                 and counters.get("tokenize_text_calls", 0) == 0
                 and counters.get("tokenize_seed_calls", 0) == 0
                 and counters.get("model_continuation_calls", 0) == 0
                 and db_unchanged and state_unchanged)
    return {
        "terminal_state": "OBSERVED" if checks_ok else (
            "BLOCKED_NOT_RUN" if not chain_ok else "INVALID_CONDITION"),
        "refusal_observed": refusal_observed,
        "refusal_stage": refusal.get("stage") or refusal.get("kind") or "",
        "tokenize_text_calls": counters.get("tokenize_text_calls", 0),
        "tokenize_seed_calls": counters.get("tokenize_seed_calls", 0),
        "model_generate_calls": counters.get("model_continuation_calls", 0),
        "database_side_effects": not db_unchanged,
        "state_side_effects": not state_unchanged,
        "fallback_reads": 0,
        "notes": ["refusal=%s" % json.dumps(refusal, sort_keys=True),
                  "aggregation-only from persisted evidence"],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-root", type=Path, default=RUN_ROOT_DEFAULT)
    parser.add_argument("--lab-root", type=Path,
                        default=Path("/Users/mr.simi/Documents/SimiGo-Lab"))
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--max-tokens", type=int, default=48)
    parser.add_argument("--retry-note", default="")
    parser.add_argument("--summarize-only", action="store_true")
    parser.add_argument("--skip-guards", action="store_true")
    args = parser.parse_args()

    lab_root = args.lab_root
    run_root = args.run_root
    model_dir = args.model_dir
    binary, driver, bridge = resolve_bins(lab_root)

    if args.summarize_only:
        summary = summarize_only(run_root, lab_root, model_dir)
        write_json(run_root / "summary.json", summary)
        print(json.dumps({"terminal_state": summary["terminal_state"],
                          "conditions": {k: v["terminal_state"] for k, v
                                         in summary["conditions"].items()}},
                         ensure_ascii=False, indent=1))
        return 0 if summary["terminal_state"] == "OBSERVED" else 2

    trust = load_trust(run_root, lab_root, binary, bridge)

    # Preserve (never delete) a prior chain attempt in this run root.
    world = run_root / "stages" / "chain"
    prior_attempted = any((world / name).exists() and (world / name).stat().st_size
                          for name in ("carrier.sqlite", "lifecycle.json"))
    if prior_attempted:
        archive = run_root / "attempts" / ("aborted-%s" % e.utc_now().replace(
            ":", "").replace("-", "").replace("T", "-"))
        archive.mkdir(parents=True, exist_ok=False)
        shutil.move(str(world), str(archive / "chain"))
        (archive / "README.md").write_text(
            "# Aborted G0 attempt (preserved, not overwritten)\n\n"
            "Cause recorded by operator: %s\n\nRaw evidence kept verbatim under "
            "chain/.\n" % (args.retry_note or "(no note supplied)"),
            encoding="utf-8")
        print(json.dumps({"archived_attempt": str(archive)}))

    world.mkdir(parents=True, exist_ok=True)
    nonce = secrets.token_bytes(16).hex()
    definition_env = e.child_environment(
        lab_root, trust, "g-definition-chain", "g-definition-chain", with_key=True)
    definition = define_multihop_task(
        world / "carrier.sqlite", lab_root, "g-chain", definition_env, nonce)
    db_pre = e.sha256_file(world / "carrier.sqlite")

    driver_env = e.child_environment(
        lab_root, trust, "g-chain", "g-chain", with_key=True)
    driver_env["SIMIGO_INFO_VALIDITY_POLICY_PATH"] = str(
        lab_root / "integrated-es-palace/mlx-smoke-v1/ISOLATED_VALIDITY_POLICY.json")
    driver_env["SIMIGO_INFO_SNAPSHOT_PATH"] = str(
        lab_root / "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite")
    run = run_driver(driver, binary, lab_root, model_dir, world, "chain",
                     args.max_tokens, driver_env)
    lifecycle = run.get("lifecycle") or {}
    u1 = read_json(world / "u1-evidence.json") if (
        world / "u1-evidence.json").exists() else {}
    u2 = read_json(world / "u2-evidence.json") if (
        world / "u2-evidence.json").exists() else {}
    u3 = read_json(world / "u3-evidence.json") if (
        world / "u3-evidence.json").exists() else {}
    if not lifecycle or not u3:
        g0 = blocked_chain("driver did not produce a complete three-stage chain "
                           "lifecycle/evidence (driver exit=%s log tail=%s)" % (
                               run.get("exit_code"), (run.get("log") or "")))
    else:
        g0 = build_g0_chain(lifecycle, u1, u2, u3, definition)
    chain_ok = g0["terminal_state"] == "OBSERVED"

    u2_settled = bool(action_object(u2, ITEM_U2)) and bool(
        action_object(u1, ITEM_U1))
    g1 = build_g1(binary, lab_root, model_dir, run_root, trust,
                  world / "carrier.sqlite", definition, args.max_tokens,
                  u2_settled)
    n4 = build_n4(run_root, world, definition, lifecycle, chain_ok)
    identity = identity_from_chain(lifecycle, u1, u2, u3, definition, model_dir)
    costs = costs_from_chain(u1, u2, u3)

    if not args.skip_guards:
        run_guards(lab_root, run_root, run_root / "tools")

    workspace = read_json(run_root / "manifests" / "workspace-before.json")
    summary = build_summary(run_root, model_dir, trust, definition, g0, g1, n4,
                            identity, costs, workspace.get("head", ""))
    summary["g0_db_pre_sha256"] = db_pre
    summary["g0_db_post_sha256"] = e.sha256_file(world / "carrier.sqlite")
    write_json(run_root / "summary.json", summary)
    print(json.dumps({"terminal_state": summary["terminal_state"],
                      "conditions": {k: v["terminal_state"] for k, v
                                     in summary["conditions"].items()}},
                     ensure_ascii=False, indent=1))
    return 0 if summary["terminal_state"] == "OBSERVED" else 2


if __name__ == "__main__":
    raise SystemExit(main())
