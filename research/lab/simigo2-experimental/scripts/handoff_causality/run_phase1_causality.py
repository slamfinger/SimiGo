#!/usr/bin/env python3
"""Phase 1: recovery admission on a stage-A-only baseline.

Each case runs in its own process and its own copy of the baseline database and
durable state directory.  The only changed conditions are A1-A4; A0 is the
unmodified control.  No recovery policy is added.
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import sqlite3
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
LAB = HERE.parents[2]
RUNROOT = Path(
    os.environ.get(
        "SIMIGO_RUN_ROOT",
        str(Path.home() / "SimiGo-Agent-Runs/handoff-causality-20261022b"),
    )
)
PHASE1 = RUNROOT / "phase1"
# The run tag follows the run root so a new label (e.g. 20261022c) never
# overwrites the earlier round's evidence.
RUN_TAG = RUNROOT.name.rsplit("-", 1)[-1]
BIN = LAB / "simigo2-experimental/.build/out/out/Products/Debug/RealModelHandoff"
MODEL = Path(
    os.environ.get(
        "SIMIGO_MODEL_DIR",
        str(
            Path.home()
            / ".cache/huggingface/hub/models--mlx-community--Qwen3-Coder-30B-A3B-Instruct-4bit"
            / "snapshots/6e302ea604ad9ab206367e2c501d1571023e7b6d"
        ),
    )
)
VALIDITY = LAB / "integrated-es-palace/mlx-smoke-v1/ISOLATED_VALIDITY_POLICY.json"
BASELINE = PHASE1 / "baseline"
BASELINE_LABEL = f"phase1-baseline-{RUN_TAG}"
CASES = ["A0", "A1", "A2a", "A2b", "A3", "A4"]


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def git_text(*args: str) -> str:
    return subprocess.run(
        ["git", *args], cwd=LAB, capture_output=True, text=True, check=True
    ).stdout


def implementation_identity() -> dict:
    head = git_text("rev-parse", "HEAD").strip()
    dirty = git_text("diff", "--binary") + git_text("status", "--porcelain=v1")
    return {
        "head": head,
        "dirty_tree_fingerprint": hashlib.sha256(dirty.encode()).hexdigest(),
        "dirty_tree_status": git_text("status", "--porcelain=v1").splitlines(),
    }


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def file_identity(path: Path) -> dict:
    stat = path.stat()
    return {
        "path": str(path),
        "device": str(stat.st_dev),
        "inode": str(stat.st_ino),
        "size_bytes": stat.st_size,
        "sha256": sha256_file(path),
    }


def directory_identity(directory: Path) -> list[dict]:
    if not directory.exists():
        return []
    entries = []
    for path in sorted(directory.rglob("*")):
        if path.is_file():
            entries.append(
                {
                    "path": str(path.relative_to(directory)),
                    "size_bytes": path.stat().st_size,
                    "sha256": sha256_file(path),
                }
            )
    return entries


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(value, indent=2, sort_keys=True).encode("utf-8")
    descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
    try:
        os.write(descriptor, payload)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def copy_database(source: Path, destination: Path) -> None:
    source_connection = sqlite3.connect(f"file:{source}?mode=ro", uri=True)
    destination_connection = sqlite3.connect(destination)
    try:
        source_connection.backup(destination_connection)
        destination_connection.commit()
    finally:
        destination_connection.close()
        source_connection.close()


def run_stage_a() -> None:
    if BASELINE.exists():
        stage_a = BASELINE / "evidence/stage-a.json"
        if stage_a.is_file() and read_json(stage_a).get("terminal_state") == "STAGE_A_PASS":
            print(f"baseline exists and is complete: {BASELINE}", file=sys.stderr)
            return
        raise SystemExit(f"baseline exists but is incomplete; refusing to overwrite: {BASELINE}")
    BASELINE.parent.mkdir(parents=True, exist_ok=True)
    command = [
        str(BIN),
        "stage-a",
        "--run-dir",
        str(BASELINE),
        "--model-dir",
        str(MODEL),
        "--lab-root",
        str(LAB),
        "--run-label",
        BASELINE_LABEL,
    ]
    print("RUN", " ".join(command), file=sys.stderr)
    subprocess.run(command, check=True)
    stage_a = read_json(BASELINE / "evidence/stage-a.json")
    if stage_a.get("terminal_state") != "STAGE_A_PASS":
        raise SystemExit("stage-A baseline did not pass")
    checkpoint = stage_a["continuation"]
    if checkpoint.get("advanced_position") != 1:
        raise SystemExit("baseline is not at position 1; Phase 1 would reuse a U2 world")


def apply_intervention(case: str, case_dir: Path, baseline: Path) -> dict:
    """Copy the baseline and apply exactly one independent change."""
    case_dir.mkdir(parents=True, exist_ok=False)
    database = case_dir / "carrier.sqlite"
    state_dir = case_dir / "state"
    copy_database(baseline / "carrier.sqlite", database)
    if case == "A4":
        state_dir.mkdir()
    else:
        shutil.copytree(baseline / "state", state_dir)

    action: dict = {"case": case, "changes": []}
    if case in {"A1", "A2a", "A2b"}:
        state_path = state_dir / "execution-state.json"
        state = read_json(state_path)
        checkpoints = state.get("settlementCheckpoints", [])
        if len(checkpoints) != 1:
            raise SystemExit(f"{case}: expected exactly one baseline checkpoint")
        checkpoint = checkpoints[0]
        if case == "A1":
            state["settlementCheckpoints"] = []
            action["changes"].append(
                {"field": "settlementCheckpoints", "before": checkpoint, "after": []}
            )
        elif case == "A2a":
            before = checkpoint["resultDigest"]
            after = hashlib.sha256(b"phase1-a2a-result-digest").hexdigest()
            checkpoint["resultDigest"] = after
            action["changes"].append(
                {"field": "resultDigest", "before": before, "after": after}
            )
        else:
            before = checkpoint["validityBasis"]
            after = hashlib.sha256(b"phase1-a2b-validity-basis").hexdigest()
            checkpoint["validityBasis"] = after
            action["changes"].append(
                {"field": "validityBasis", "before": before, "after": after}
            )
        state_path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    elif case == "A3":
        connection = sqlite3.connect(database)
        connection.row_factory = sqlite3.Row
        try:
            rows = connection.execute(
                "SELECT append_order,srs_identity,record_object FROM is_index_entries "
                "WHERE srs_identity LIKE 'execution_state:%' ORDER BY append_order ASC"
            ).fetchall()
            latest = rows[-1] if rows else None
            if latest is None or not latest["srs_identity"].endswith(":runtime-applied"):
                raise SystemExit("A3: baseline latest execution state is not runtime-applied")
            connection.execute(
                "DELETE FROM is_index_entries WHERE append_order = ?",
                (latest["append_order"],),
            )
            connection.commit()
            remaining = connection.execute(
                "SELECT append_order,srs_identity FROM is_index_entries "
                "WHERE srs_identity LIKE 'execution_state:%' ORDER BY append_order ASC"
            ).fetchall()
        finally:
            connection.close()
        action["changes"].append(
            {
                "table": "is_index_entries",
                "deleted": dict(latest),
                "remaining_execution_state_rows": [dict(row) for row in remaining],
            }
        )
    elif case == "A0":
        action["changes"].append({"copy": "baseline unchanged"})
    elif case == "A4":
        action["changes"].append({"state_directory": "empty"})
    else:
        raise SystemExit(f"unknown case: {case}")

    action["database_after"] = file_identity(database)
    action["state_after"] = directory_identity(state_dir)
    return action


def expected_result(case: str, execution: dict) -> dict:
    counters = execution.get("counters", {})
    failure = execution.get("failure_label")
    common = {
        "continue_task_entered": execution.get("continue_task_entered"),
        "model_continuation_calls": counters.get("model_continuation_calls", 0),
    }
    if case == "A0":
        actions = (execution.get("continuation", {}).get("settlement_actions") or [])
        u2_actions = [a for a in actions if a.get("item_id") == "TASK-U2"]
        answer = (execution.get("output", {}) or {}).get("answer", "")
        return {
            **common,
            "recovery_succeeded": execution.get("recovery_succeeded") is True,
            "recovered_position": execution.get("recovered_position") == 1,
            "prefix_tail_matches": execution.get("stage_a_prefix_tail_matches") is True,
            "failure_absent": execution.get("failure_label") is None,
            "resumed_not_created": (
                execution.get("continuation", {}).get("created_fresh_execution") is False
            ),
            "u2_settlement_actions": len(u2_actions),
            "answer_nonempty": bool(answer),
            "matches_expected": (
                execution.get("recovery_succeeded") is True
                and execution.get("continue_task_entered") is True
                and counters.get("model_continuation_calls", 0) == 1
                and execution.get("stage_a_prefix_tail_matches") is True
                and execution.get("failure_label") is None
                and len(u2_actions) == 1
                and bool(answer)
            ),
        }
    expected_prefix = {
        "A1": "settlementCheckpointMissing:",
        "A2a": "settlementCheckpointMismatch:PRODUCTION-REAL-PALACE:result_digest",
        "A2b": "settlementCheckpointMismatch:PRODUCTION-REAL-PALACE:validity_basis",
        "A3": "informationSpaceHasNoSettledExecution:",
        "A4": "durableExecutionStateMissing:PRODUCTION-REAL-PALACE",
    }[case]
    label = failure if isinstance(failure, str) else ""
    return {
        **common,
        "failure_label": label,
        "expected_failure_prefix": expected_prefix,
        "matches_expected": (
            execution.get("recovery_succeeded") is False
            and label.startswith(expected_prefix)
            and execution.get("continue_task_entered") is False
            and counters.get("model_continuation_calls", 0) == 0
        ),
    }


def run_case(case: str, baseline: Path) -> dict:
    case_dir = PHASE1 / "cases" / case
    if case_dir.exists():
        raise SystemExit(f"case already exists; refusing to overwrite: {case_dir}")
    intervention = apply_intervention(case, case_dir, baseline)
    write_json(case_dir / "intervention.json", intervention)

    label = f"phase1-{case.lower()}-{RUN_TAG}"
    command = [
        str(BIN),
        "phase1-case",
        "--run-dir",
        str(case_dir),
        "--model-dir",
        str(MODEL),
        "--lab-root",
        str(LAB),
        "--run-label",
        label,
        "--case",
        case,
        "--baseline-dir",
        str(baseline),
        "--max-tokens",
        "32",
    ]
    environment = os.environ.copy()
    environment["SIMIGO_INFO_VALIDITY_POLICY_PATH"] = str(VALIDITY)
    print("RUN", " ".join(command), file=sys.stderr)
    process = subprocess.run(
        command, capture_output=True, text=True, env=environment
    )
    log_path = RUNROOT / "logs" / f"phase1-{case}.log"
    log_path.write_text(
        "COMMAND " + " ".join(command) + "\n"
        + "RETURNCODE " + str(process.returncode) + "\n"
        + "STDOUT\n" + process.stdout + "\nSTDERR\n" + process.stderr,
        encoding="utf-8",
    )
    evidence_path = case_dir / "evidence/phase1.json"
    execution = read_json(evidence_path) if evidence_path.is_file() else {}
    verification = expected_result(case, execution)
    record = {
        "schema_id": "SIMIGO-CAUSALITY-PHASE1-CASE-V1",
        "case": case,
        "run_label": label,
        "baseline_dir": str(baseline),
        "case_dir": str(case_dir),
        "intervention": intervention,
        "process": {
            "returncode": process.returncode,
            "stdout": process.stdout,
            "stderr": process.stderr,
        },
        "execution": execution,
        "verification": verification,
        "run_id": RUNROOT.name,
        "implementation": implementation_identity(),
        "log_path": str(log_path),
        "completed_at_utc": utc_now(),
        "terminal_state": "PHASE1_OBSERVED" if execution else "PHASE1_HARNESS_FAIL",
    }
    write_json(PHASE1 / "evidence" / f"{case}.json", record)
    return record


def main() -> int:
    if not BIN.is_file():
        raise SystemExit(f"missing binary: {BIN}")
    if not MODEL.is_dir():
        raise SystemExit(f"missing model snapshot: {MODEL}")
    (PHASE1 / "cases").mkdir(parents=True, exist_ok=True)
    (PHASE1 / "evidence").mkdir(parents=True, exist_ok=True)
    (RUNROOT / "logs").mkdir(parents=True, exist_ok=True)
    run_stage_a()
    results = {}
    for case in CASES:
        results[case] = run_case(case, BASELINE)
    summary = {
        "schema_id": "SIMIGO-CAUSALITY-PHASE1-SUMMARY-V1",
        "baseline_dir": str(BASELINE),
        "baseline_label": BASELINE_LABEL,
        "cases": {
            case: {
                "terminal_state": record["terminal_state"],
                "verification": record["verification"],
                "process_returncode": record["process"]["returncode"],
            }
            for case, record in results.items()
        },
        "all_observed_as_expected": all(
            record["verification"].get("matches_expected") is True
            for record in results.values()
        ),
        "completed_at_utc": utc_now(),
    }
    write_json(PHASE1 / "summary.json", summary)
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0 if summary["all_observed_as_expected"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
