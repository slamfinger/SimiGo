#!/usr/bin/env python3
"""G2 batch runner — one manifest, one run set, no retry.

Scope (G2-BATCH-AUTH-20261020-01): 3 fixtures x (A, B phase 1, B phase 2) =
9 model starts, plus 6 restore-eligibility gate processes for the two negative
controls per fixture. Hard process cap 15, retries 0.

What this runner does NOT have:
  - no `execute_demand` call, no U1 calculator, no recompute branch;
  - no retry loop, no fixture substitution, no second model directory;
  - phase 2 receives only the restored R1 and the downstream instruction.

Every file it writes is create-exclusive. Host records are written by the host
process itself and are never rewritten here; this runner only reads them and
re-derives the verdict.

Usage:
  python3 run_batch.py --manifest manifest/G2_MANIFEST.json
  python3 run_batch.py --verify-only evidence/<run-id>
"""

import argparse
import datetime
import hashlib
import json
import os
import pathlib
import platform
import shutil
import signal
import sqlite3
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[5]
G2 = HERE.parent
MODEL_DIR = G2 / "artifact-model-qwen3-coder-30b-a3b-instruct-4bit-6e302ea6"
HOST_BIN = HERE / "host" / ".build" / "release" / "G2Host"
HOST_PACKAGE = HERE / "host" / "Package.swift"
HOST_RESOLVED = HERE / "host" / "Package.resolved"
BINDING = REPO / "docs/01-questions/G2_MODEL_BINDING_20261020.json"
PREREG = REPO / "docs/01-questions/G2_PREREGISTRATION_20261020.md"
AUTH_DOC = REPO / "docs/01-questions/G2_BATCH_AUTHORIZATION_20261020.md"
MANIFEST_DIR = G2 / "manifest"
MANIFEST = MANIFEST_DIR / "G2_MANIFEST.json"
MANIFEST_SHA = MANIFEST_DIR / "G2_MANIFEST.json.sha256"
TOKEN = MANIFEST_DIR / "G2_AUTHORIZATION.token"
FIXTURES = HERE / "fixtures"
EVIDENCE = G2 / "evidence"
GATE = HERE / "carrier_gate.py"
CHECKER = HERE / "checker.py"
RUNNER_PATH = pathlib.Path(__file__).resolve()

sys.path.insert(0, str(HERE))
sys.path.insert(0, str(REPO / "execution-information-loop"))
from carrier_gate import run_gate, sha256_bytes, tree_digest  # noqa: E402
from carrier_loop import CarrierInformationLoop, digest  # noqa: E402
from checker import check_u2  # noqa: E402

RUNNER_VERSION = 1
MAX_U1_TOKENS = 256
MAX_U2_TOKENS = 128
STRIDE = 256
HOST_TIMEOUT_SECONDS = 900
TERMINATION_GRACE_SECONDS = 20
BUDGET = {
    "model_starts_planned": 9,
    "model_starts_max": 9,
    "retries": 0,
    "negative_control_processes_max": 6,
    "process_calls_max": 15,
}

EXPECTED_WEIGHTS = "d1f01c0c98db2d07a437e81372dffc49c04e728342cec8f72cc2929caeeb6abf"
EXPECTED_TOKENIZER = "9bada7c8fddefc7e91cf3bbe9b56305d5234c73e16732518dc4f3825b2d84ac3"
EXPECTED_COMBINED = "bb0b2711451cbabc1efc0aae3e282dde166db6f0e82ba245905b4848bf71ec58"

# A failed row in this set is a counterexample under G2 §8, not missing evidence.
COUNTEREXAMPLE_ROWS = {
    "u2_checker_pass", "c_missing_refused", "c_missing_code",
    "c_tampered_refused", "c_tampered_code", "canary_absent_from_r1",
    "canary_absent_from_phase2", "restored_object_id_equal",
    "restored_source_version_equal", "restored_dependency_closure_equal",
    "restored_validity_basis_equal", "settlement_object_id_unchanged",
    "no_new_settlement_in_phase2", "u1_not_reexecuted_in_phase2",
    "s1_absent_from_phase2", "phase2_hook_hits_zero", "phase2_store_still_empty",
}


class BatchStop(Exception):
    """A pre-registered stop condition. Never caught for a retry."""

    def __init__(self, message, kind="inconclusive"):
        super().__init__(message)
        self.kind = kind


class Budget:
    def __init__(self):
        self.model_starts = 0
        self.gate_processes = 0

    def start_model(self, fixture_id, arm):
        if self.model_starts >= BUDGET["model_starts_max"]:
            raise BatchStop("model start budget exhausted before %s/%s"
                            % (fixture_id, arm))
        self.model_starts += 1
        return {"fixture_id": fixture_id, "arm": arm,
                "model_start_index": self.model_starts}

    def start_gate(self, fixture_id, variant):
        if self.gate_processes >= BUDGET["negative_control_processes_max"]:
            raise BatchStop("negative-control budget exhausted before %s/%s"
                            % (fixture_id, variant))
        self.gate_processes += 1
        if self.model_starts + self.gate_processes > BUDGET["process_calls_max"]:
            raise BatchStop("process-call cap exceeded")
        return {"fixture_id": fixture_id, "variant": variant,
                "gate_process_index": self.gate_processes}

    def as_record(self, run_dir):
        return {
            "model_starts_used": self.model_starts,
            "gate_processes_used": self.gate_processes,
            "process_calls_used": self.model_starts + self.gate_processes,
            "model_starts_max": BUDGET["model_starts_max"],
            "negative_control_processes_max": BUDGET["negative_control_processes_max"],
            "process_calls_max": BUDGET["process_calls_max"],
            "retries": 0,
            "record_path": str(run_dir),
        }


def utc_now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256_file(path):
    hasher = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            hasher.update(block)
    return hasher.hexdigest()


def read_json(path):
    return json.loads(pathlib.Path(path).read_text(encoding="utf-8"))


def write_once(path, payload):
    path = pathlib.Path(path)
    with open(path, "x", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    return sha256_file(path)


def die(message, code=4):
    print("PREFLIGHT FAILURE: " + message, file=sys.stderr)
    sys.exit(code)


def git(*args):
    result = subprocess.run(["git", "-C", str(REPO)] + list(args),
                            capture_output=True, text=True)
    if result.returncode != 0:
        raise BatchStop("git %s failed: %s" % (" ".join(args), result.stderr.strip()))
    return result.stdout.strip()


def rel_to_repo(path):
    try:
        return str(pathlib.Path(path).resolve().relative_to(REPO))
    except ValueError:
        return str(pathlib.Path(path).resolve())


def count_symlinks(root):
    links = []
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        for name in dirnames + filenames:
            path = os.path.join(dirpath, name)
            if os.path.islink(path):
                links.append(os.path.relpath(path, root))
    return sorted(links)


def inventory(root):
    root = pathlib.Path(root)
    if not root.exists():
        return []
    return sorted(path.relative_to(root).as_posix()
                  for path in root.rglob("*") if path.is_file())


def artifact_check(model_dir, binding_rows):
    rows = []
    for dirpath, _dirnames, filenames in os.walk(model_dir, followlinks=True):
        for name in filenames:
            path = os.path.join(dirpath, name)
            if not os.path.isfile(path):
                continue
            rows.append({"path": os.path.relpath(path, model_dir),
                         "bytes": os.path.getsize(path),
                         "sha256": sha256_file(path)})
    rows.sort(key=lambda row: row["path"])
    expected = {row["path"]: row for row in binding_rows}
    per_file = []
    for row in rows:
        want = expected.get(row["path"])
        per_file.append({
            "path": row["path"],
            "bytes": row["bytes"],
            "sha256": row["sha256"],
            "match": bool(want and want["bytes"] == row["bytes"]
                          and want["sha256"] == row["sha256"]),
        })
    missing = sorted(set(expected) - {row["path"] for row in rows})
    canonical = json.dumps(rows, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    weight_lines = sorted("%s:%d:%s" % (row["path"], row["bytes"], row["sha256"])
                          for row in rows if row["path"].endswith(".safetensors"))
    return {
        "schema_id": "SIMIGO-G2-BATCH-ARTIFACT-CHECK-V1",
        "model_directory": str(model_dir),
        "file_count_on_disk": len(rows),
        "file_count_in_binding": len(binding_rows),
        "missing_from_disk": missing,
        "symlink_entries": count_symlinks(model_dir),
        "all_match": all(row["match"] for row in per_file) and not missing,
        "aggregate_sha256": sha256_bytes(canonical.encode("utf-8")),
        "predicted_engine_weights_digest": sha256_bytes(
            "\n".join(weight_lines).encode("utf-8")),
        "files": per_file,
    }


# --------------------------------------------------------------------------- #
# Host lifecycle
# --------------------------------------------------------------------------- #

def start_host(*, mode, out_dir, request, store_base, budget_entry):
    out_dir = pathlib.Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    store_base.mkdir(parents=True, exist_ok=True)
    request_path = out_dir / "request.json"
    request_sha = write_once(request_path, request)
    env = {key: value for key, value in os.environ.items()
           if not key.startswith("G2_")}
    env["G2_HOST_REQUEST"] = str(request_path)
    env["G2_HOST_EVIDENCE"] = str(out_dir)
    log_path = out_dir / "host.log"
    with open(log_path, "xb") as log:
        started_at = utc_now()
        started = time.time()
        process = subprocess.Popen(
            [str(HOST_BIN)], env=env, stdout=log, stderr=subprocess.STDOUT,
            start_new_session=True)
        try:
            process_group = os.getpgid(process.pid)
        except OSError:
            process_group = process.pid
    run = {
        "mode": mode,
        "budget_entry": budget_entry,
        "out_dir": out_dir,
        "request_path": request_path,
        "request_sha256": request_sha,
        "log_path": log_path,
        "store_base": store_base,
        "process": process,
        "pid": process.pid,
        "process_group": process_group,
        "started_at_utc": started_at,
        "started_monotonic": started,
        "argv": [str(HOST_BIN)],
        "env": {key: env[key] for key in
                ("G2_HOST_REQUEST", "G2_HOST_EVIDENCE", "HOME", "PATH") if key in env},
    }
    return run


def await_record(run, timeout=HOST_TIMEOUT_SECONDS):
    record_path = run["out_dir"] / "host_record.json"
    deadline = time.time() + timeout
    while time.time() < deadline:
        if record_path.exists():
            return True
        if run["process"].poll() is not None:
            return record_path.exists()
        time.sleep(0.2)
    return False


def wait_for_exit(run, timeout=HOST_TIMEOUT_SECONDS):
    try:
        exit_code = run["process"].wait(timeout=timeout)
        timed_out = False
    except subprocess.TimeoutExpired:
        os.killpg(run["process_group"], signal.SIGKILL)
        exit_code = run["process"].wait(timeout=60)
        timed_out = True
    return exit_code, timed_out


def terminate_host(run, grace=TERMINATION_GRACE_SECONDS):
    """SIGTERM, then SIGKILL on timeout; verify ESRCH and empty group."""
    process = run["process"]
    signal_sent = None
    if process.poll() is None:
        os.kill(process.pid, signal.SIGTERM)
        signal_sent = "SIGTERM"
        try:
            exit_code = process.wait(timeout=grace)
        except subprocess.TimeoutExpired:
            os.killpg(run["process_group"], signal.SIGKILL)
            signal_sent = "SIGKILL"
            exit_code = process.wait(timeout=60)
    else:
        exit_code = process.returncode

    pid_gone = False
    try:
        os.kill(run["pid"], 0)
    except ProcessLookupError:
        pid_gone = True
    except PermissionError:
        pid_gone = False
    group_gone = False
    try:
        os.killpg(run["process_group"], 0)
    except ProcessLookupError:
        group_gone = True
    except PermissionError:
        group_gone = False
    return {
        "signal_sent": signal_sent,
        "exit_code": exit_code,
        "esrch_on_pid": pid_gone,
        "esrch_on_process_group": group_gone,
        "terminated_at_utc": utc_now(),
    }


def finish_launch_record(run, exit_code, timed_out, extra=None):
    record = {
        "schema_id": "SIMIGO-G2-BATCH-LAUNCH-V1",
        "mode": run["mode"],
        "budget_entry": run["budget_entry"],
        "argv": run["argv"],
        "environment": run["env"],
        "request": {"path": str(run["request_path"]),
                    "sha256": run["request_sha256"]},
        "pid": run["pid"],
        "process_group": run["process_group"],
        "started_at_utc": run["started_at_utc"],
        "finished_at_utc": utc_now(),
        "duration_seconds": time.time() - run["started_monotonic"],
        "exit_code": exit_code,
        "timed_out": timed_out,
        "host_record_present": (run["out_dir"] / "host_record.json").exists(),
        "host_log": {"path": str(run["log_path"]),
                     "sha256": sha256_file(run["log_path"])
                     if run["log_path"].exists() else None},
    }
    if extra:
        record.update(extra)
    write_once(run["out_dir"] / "launch.json", record)
    return record


def verify_identity(record, arm_dir):
    """The P0-A2 identity is a hard gate for every model process."""
    identity = record.get("engine_content_identity") or {}
    checks = {
        "weights_digest_matches_p0_a2": identity.get("weights_digest") == EXPECTED_WEIGHTS,
        "tokenizer_digest_matches_p0_a2": identity.get("tokenizer_digest") == EXPECTED_TOKENIZER,
        "combined_digest_matches_p0_a2": identity.get("combined_digest") == EXPECTED_COMBINED,
    }
    write_once(arm_dir / "identity_check.json", {
        "schema_id": "SIMIGO-G2-BATCH-IDENTITY-CHECK-V1",
        "arm": arm_dir.name,
        "observed": identity,
        "expected": {"weights_digest": EXPECTED_WEIGHTS,
                     "tokenizer_digest": EXPECTED_TOKENIZER,
                     "combined_digest": EXPECTED_COMBINED},
        "checks": checks,
        "all_match": all(checks.values()),
    })
    if not all(checks.values()):
        raise BatchStop("engine identity deviates from the P0-A2 record in %s" % arm_dir)


def run_generation_arm(*, fixture, arm, out_dir, request, store_base, budget):
    """One model start. Returns (host_record, launch_record)."""
    entry = budget.start_model(fixture["fixture_id"], arm)
    run = start_host(mode=request["mode"], out_dir=out_dir, request=request,
                     store_base=store_base, budget_entry=entry)
    await_record(run)
    exit_code, timed_out = wait_for_exit(run)
    launch = finish_launch_record(run, exit_code, timed_out)
    record_path = out_dir / "host_record.json"
    if not record_path.exists():
        raise BatchStop("host record missing for %s/%s (exit=%s)"
                        % (fixture["fixture_id"], arm, exit_code))
    record = read_json(record_path)
    verify_identity(record, out_dir)
    if exit_code != 0 or timed_out:
        raise BatchStop("host exit %s (timeout=%s) for %s/%s"
                        % (exit_code, timed_out, fixture["fixture_id"], arm))
    if not all((record.get("checks") or {}).values()):
        raise BatchStop("host checks failed for %s/%s: %s"
                        % (fixture["fixture_id"], arm,
                           sorted(key for key, value in record["checks"].items()
                                  if not value)))
    return record, launch


# --------------------------------------------------------------------------- #
# Carrier work
# --------------------------------------------------------------------------- #

def continuation_point(fixture):
    return "g2-%s-downstream" % fixture["fixture_id"]


def create_phase1_carrier(db_path, fixture, u1_record):
    loop = CarrierInformationLoop.create(str(db_path))
    try:
        demand_id = "g2-%s-demand" % fixture["fixture_id"]
        item_id = "u1-result"
        loop.define_demand(
            demand_id=demand_id,
            continuation_point=continuation_point(fixture),
            pending_obligations=["u2-answer"],
            continuation_conditions=["settled:u1-result"],
            required_item_ids=[item_id])
        policy_body = {"policy_version": "g2-validity-v1",
                       "policy_source": "G2_PREREGISTRATION_20261020.md#7"}
        policy = dict(policy_body, policy_sha256=digest(policy_body))
        dependency_source = loop.put_source(
            demand_id=demand_id,
            item_id="s1-source",
            source_kind="fixture-source",
            source_version="v1",
            source_payload={"fixture_id": fixture["fixture_id"],
                            "s1_sha256": fixture["s1_sha256"],
                            "s1_word_count": fixture["s1_words"]},
            dependencies=[],
            validity_policy=policy)
        source = loop.put_source(
            demand_id=demand_id,
            item_id=item_id,
            source_kind="model-extraction-u1",
            source_version="v1",
            source_payload={"fixture_id": fixture["fixture_id"],
                            "s1_sha256": fixture["s1_sha256"],
                            "model_identity_weights": EXPECTED_WEIGHTS},
            dependencies=["s1-source"],
            validity_policy=policy)
        result = {
            "fixture_id": fixture["fixture_id"],
            "r1": json.loads(u1_record["r1_canonical"]),
            "r1_canonical": u1_record["r1_canonical"],
            "r1_sha256": u1_record["r1_sha256"],
        }
        basis = {
            "fixture_id": fixture["fixture_id"],
            "source_item_object_id": source["object_id"],
            "source_kind": "model-extraction-u1",
            "source_version": "v1",
            "dependency_ids": ["s1-source"],
            "dependency_object_ids": {"s1-source": dependency_source["object_id"]},
            "validity_policy_sha256": policy["policy_sha256"],
            "validity_policy_version": policy["policy_version"],
            "s1_sha256": fixture["s1_sha256"],
        }
        settlement = loop.settle(
            advancement_id="%s-u1-settled" % fixture["fixture_id"],
            item_id=item_id, result=result, basis=basis)
        state = loop.record_execution_state(
            state_id="%s-u1-settled" % fixture["fixture_id"],
            continuation_point=continuation_point(fixture),
            prior_state_id=None,
            demand_id=demand_id,
            status="ADVANCED",
            pending_obligations=["u2-answer"],
            next_continuation_point="u2-ready",
            result_digest=digest(result))
        loop.commit()
        return {
            "schema_id": "SIMIGO-G2-BATCH-CARRIER-PHASE1-V1",
            "demand": {"demand_id": demand_id,
                       "continuation_point": continuation_point(fixture)},
            "item_id": item_id,
            "source": {"object_id": source["object_id"],
                       "source_version": "v1",
                       "revision": source["revision"]},
            "dependency_source": {"item_id": "s1-source",
                                  "object_id": dependency_source["object_id"]},
            "validity_policy": policy,
            "settlement": {"object_id": settlement["object_id"],
                           "dependency_order": settlement["dependency_order"]},
            "execution_state": state,
            "result_digest": digest(result),
            "r1_sha256": u1_record["r1_sha256"],
            "execute_demand_calls": 0,
        }
    finally:
        loop.close()


def copy_carrier(source_db, target_dir):
    target_dir.mkdir(parents=True, exist_ok=False)
    target = target_dir / "g2.sqlite"
    shutil.copy2(source_db, target)
    for suffix in ("-wal", "-shm", "-journal"):
        sidecar = pathlib.Path(str(source_db) + suffix)
        if sidecar.exists():
            shutil.copy2(sidecar, pathlib.Path(str(target) + suffix))
    return target


def sqlite_digest(db_path):
    """Digest of the carrier copy itself (main file plus any sidecars)."""
    db_path = pathlib.Path(db_path)
    rows = []
    for path in sorted(db_path.parent.glob(db_path.name + "*")):
        if path.is_file():
            rows.append("%s:%s" % (path.name, sha256_file(path)))
    return sha256_bytes("\n".join(rows).encode("utf-8"))


def remove_settlement(db_path, item_id):
    connection = sqlite3.connect(str(db_path))
    try:
        connection.execute("PRAGMA foreign_keys = ON")
        identity = "settlement:%s" % item_id
        with connection:
            connection.execute("DELETE FROM is_index_entries WHERE srs_identity=?",
                               (identity,))
            connection.execute("DELETE FROM dependency_entries WHERE dependency_id=?",
                               (identity,))
            connection.execute(
                "DELETE FROM is_objects WHERE object_id NOT IN "
                "(SELECT record_object FROM is_index_entries UNION "
                " SELECT content_address FROM dependency_entries)")
        return {"removed_identity": identity}
    finally:
        connection.close()


def tamper_payload(db_path, item_id):
    connection = sqlite3.connect(str(db_path))
    try:
        connection.execute("PRAGMA foreign_keys = ON")
        row = connection.execute(
            "SELECT record_object FROM is_index_entries WHERE srs_identity=? "
            "ORDER BY append_order DESC LIMIT 1",
            ("settlement:%s" % item_id,)).fetchone()
        if row is None:
            raise BatchStop("cannot tamper: settlement index entry missing")
        object_id = row[0]
        stored = connection.execute(
            "SELECT content FROM is_objects WHERE object_id=?", (object_id,)).fetchone()
        original = bytes(stored[0])
        tampered = original[:-1] + b" " + original[-1:]
        with connection:
            connection.execute(
                "UPDATE is_objects SET content=?, byte_size=? WHERE object_id=?",
                (tampered, len(tampered), object_id))
        return {"object_id": object_id,
                "original_sha256": sha256_bytes(original),
                "tampered_sha256": sha256_bytes(tampered),
                "original_bytes": len(original),
                "tampered_bytes": len(tampered)}
    finally:
        connection.close()


def carrier_index_identities(db_path):
    connection = sqlite3.connect(
        pathlib.Path(db_path).resolve().as_uri() + "?mode=ro", uri=True)
    try:
        return [row[0] for row in connection.execute(
            "SELECT srs_identity FROM is_index_entries ORDER BY append_order")]
    finally:
        connection.close()


def settlement_history_length(db_path, item_id):
    connection = sqlite3.connect(
        pathlib.Path(db_path).resolve().as_uri() + "?mode=ro", uri=True)
    try:
        row = connection.execute(
            "SELECT COUNT(*) FROM dependency_entries WHERE dependency_id=?",
            ("settlement:%s" % item_id,)).fetchone()
        return row[0]
    finally:
        connection.close()


def record_phase2_states(db_path, fixture, restored, u2_outcome):
    loop = CarrierInformationLoop.open(str(db_path))
    try:
        demand_id = "g2-%s-demand" % fixture["fixture_id"]
        restored_state = loop.record_execution_state(
            state_id="%s-u2-restored" % fixture["fixture_id"],
            continuation_point=continuation_point(fixture),
            prior_state_id="%s-u1-settled" % fixture["fixture_id"],
            demand_id=demand_id,
            status="RESTORED",
            pending_obligations=["u2-answer"],
            next_continuation_point="u2-answer",
            result_digest=digest(restored))
        advanced_state = loop.record_execution_state(
            state_id="%s-u2-advanced" % fixture["fixture_id"],
            continuation_point=continuation_point(fixture),
            prior_state_id="%s-u2-restored" % fixture["fixture_id"],
            demand_id=demand_id,
            status="ADVANCED",
            pending_obligations=[],
            next_continuation_point="complete",
            result_digest=digest(u2_outcome))
        loop.commit()
        return {"restored_state": restored_state,
                "advanced_state": advanced_state}
    finally:
        loop.close()


# --------------------------------------------------------------------------- #
# Scans
# --------------------------------------------------------------------------- #

def scan_for(root, needle):
    root = pathlib.Path(root)
    hits = []
    encoded = needle.encode("utf-8")
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.is_symlink():
            continue
        data = path.read_bytes()
        if encoded in data:
            hits.append(path.relative_to(root).as_posix())
    return hits


def run_gate_process(*, budget, fixture, variant, db_path, phase1_r1, out_dir):
    entry = budget.start_gate(fixture["fixture_id"], variant)
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / "gate.json"
    command = [sys.executable, str(GATE),
               "--db", str(db_path),
               "--item", "u1-result",
               "--out", str(out_path),
               "--phase1-record", str(phase1_r1),
               "--expect", "refused"]
    started = utc_now()
    result = subprocess.run(command, capture_output=True, text=True, timeout=600)
    record = read_json(out_path) if out_path.exists() else {}
    return {
        "variant": variant,
        "budget_entry": entry,
        "argv": command,
        "started_at_utc": started,
        "exit_code": result.returncode,
        "stdout": result.stdout.strip(),
        "stderr": result.stderr.strip(),
        "record": record,
        "record_path": str(out_path),
    }


# --------------------------------------------------------------------------- #
# Preflight
# --------------------------------------------------------------------------- #

def preflight(manifest_path):
    manifest_path = pathlib.Path(os.path.expanduser(str(manifest_path))).resolve()
    if not manifest_path.is_file():
        die("manifest not found: %s" % manifest_path)
    manifest_sha = sha256_file(manifest_path)
    if not MANIFEST_SHA.is_file():
        die("manifest digest file missing")
    declared = MANIFEST_SHA.read_text(encoding="utf-8").split()[0].strip()
    if declared != manifest_sha:
        die("manifest digest file %s != manifest %s" % (declared, manifest_sha))
    if not TOKEN.is_file():
        die("authorization token missing; no run may start")
    token = read_json(TOKEN)
    if token.get("manifest_sha256") != manifest_sha:
        die("authorization token does not bind this manifest")
    if token.get("authorization_id") != "G2-BATCH-AUTH-20261020-01":
        die("authorization token names an unknown authorization")

    manifest = read_json(manifest_path)
    problems = []
    status = git("status", "--porcelain")
    if status:
        problems.append("working tree is not clean: %s" % status.splitlines()[:5])
    head = git("rev-parse", "HEAD")
    if manifest.get("budget") != BUDGET:
        problems.append("manifest budget does not match the runner budget")
    if sha256_file(PREREG) != manifest.get("preregistration", {}).get("sha256"):
        problems.append("preregistration digest changed")
    if sha256_file(AUTH_DOC) != manifest.get("authorization", {}).get("sha256"):
        problems.append("authorization document digest changed")
    executables = manifest.get("executables") or {}
    backend = manifest.get("backend") or {}
    if sha256_file(GATE) != (executables.get("gate") or {}).get("sha256"):
        problems.append("gate script digest changed")
    if sha256_file(CHECKER) != (executables.get("checker") or {}).get("sha256"):
        problems.append("checker digest changed")
    if sha256_file(RUNNER_PATH) != (executables.get("runner") or {}).get("sha256"):
        problems.append("runner digest changed")
    if sha256_file(HOST_BIN) != (backend.get("build_product") or {}).get("sha256"):
        problems.append("host product digest changed")
    if sha256_file(HOST_PACKAGE) != (backend.get("package_swift") or {}).get("sha256"):
        problems.append("host Package.swift digest changed")
    if sha256_file(HOST_RESOLVED) != (backend.get("package_resolved") or {}).get("sha256"):
        problems.append("host Package.resolved digest changed")
    if manifest.get("p0", {}).get("terminal_state") != "PASS":
        problems.append("manifest does not rest on a PASS P0 terminal record")
    if (manifest.get("matrix") or {}).get("fixtures") != 3:
        problems.append("manifest matrix does not fix three fixtures")
    if len(manifest.get("fixtures") or []) != 3:
        problems.append("manifest fixture list is not three entries")
    expected_identity = (manifest.get("model_binding") or {}).get(
        "expected_engine_identity") or {}
    if expected_identity.get("combined_digest") != EXPECTED_COMBINED:
        problems.append("manifest engine identity is not the P0-A2 identity")
    if manifest.get("evidence_root") != rel_to_repo(EVIDENCE):
        problems.append("evidence root in the manifest is %s, runner writes %s"
                        % (manifest.get("evidence_root"), rel_to_repo(EVIDENCE)))
    if problems:
        die("; ".join(problems))

    binding = read_json(BINDING)
    if sha256_file(BINDING) != manifest.get("model_binding", {}).get("sha256"):
        die("model binding digest changed")
    if manifest.get("model_binding", {}).get("aggregate_sha256") \
            != binding["model"]["aggregate_sha256"]:
        die("manifest aggregate does not match the binding")
    artifact = artifact_check(MODEL_DIR, binding["files"])
    if not artifact["all_match"]:
        die("model artifact does not match the binding")
    if artifact["file_count_on_disk"] != 17:
        die("model artifact file count %d != 17" % artifact["file_count_on_disk"])
    if artifact["aggregate_sha256"] != binding["model"]["aggregate_sha256"]:
        die("model artifact aggregate mismatch")
    if artifact["predicted_engine_weights_digest"] != EXPECTED_WEIGHTS:
        die("predicted weights digest != P0-A2 weights digest")
    if count_symlinks(MODEL_DIR):
        die("model directory contains symlinks; A2 copy required")

    fixtures = []
    for expected in manifest["fixtures"]:
        path = FIXTURES / expected["file"]
        if sha256_file(path) != expected["sha256"]:
            die("fixture digest changed: %s" % expected["file"])
        fixture = read_json(path)
        fixtures.append(fixture)
        if fixture["context_canary"] in fixture["s1_text"]:
            die("canary present in S1 for %s" % fixture["fixture_id"])

    return {
        "manifest": manifest,
        "manifest_sha256": manifest_sha,
        "manifest_path": str(manifest_path),
        "token": token,
        "head": head,
        "artifact": artifact,
        "fixtures": fixtures,
    }


def run_fixture(fixture, run_dir, budget):
    fixture_id = fixture["fixture_id"]
    root = run_dir / "fixtures" / fixture_id
    root.mkdir(parents=True, exist_ok=False)
    system_prompt = fixture["system_prompt"]
    checks = {}
    evidence = {}

    # ---- Arm A: continuous baseline ---------------------------------------
    a_dir = root / "A"
    a_request = {
        "mode": "continuous",
        "model_dir": str(MODEL_DIR),
        "store_base": str(a_dir / "store"),
        "instructions": system_prompt,
        "u1_prompt": fixture["u1_prompt"],
        "u2_template": fixture["u2_template"],
        "max_tokens_u1": MAX_U1_TOKENS,
        "max_tokens_u2": MAX_U2_TOKENS,
        "stride": STRIDE,
    }
    a_record, a_launch = run_generation_arm(
        fixture=fixture, arm="A", out_dir=a_dir, request=a_request,
        store_base=a_dir / "store", budget=budget)
    a_u1 = a_record["u1"]
    a_u2 = a_record["u2"]
    a_check = check_u2(a_u2["text"], json.loads(a_u1["r1_canonical"]), fixture)
    write_once(a_dir / "checker.json", a_check)
    write_once(a_dir / "r1.json", {"r1_canonical": a_u1["r1_canonical"],
                                   "r1_sha256": a_u1["r1_sha256"]})
    # Arm A is a baseline, not a G2-C criterion: its checker result is evidence,
    # never a stop condition. The pre-registration gates U2 in phase 2 only.
    evidence["arm_a"] = {"launch": a_launch["exit_code"],
                         "checker_pass": a_check["pass"],
                         "r1_sha256": a_u1["r1_sha256"]}

    # ---- Arm B phase 1 ----------------------------------------------------
    b1_dir = root / "B1"
    b1_request = {
        "mode": "phase1",
        "model_dir": str(MODEL_DIR),
        "store_base": str(b1_dir / "store"),
        "instructions": system_prompt,
        "u1_prompt": fixture["u1_prompt"],
        "max_tokens_u1": MAX_U1_TOKENS,
        "max_tokens_u2": MAX_U2_TOKENS,
        "stride": STRIDE,
        "idle_after_record_seconds": 600,
    }
    entry = budget.start_model(fixture_id, "B1")
    b1_run = start_host(mode="phase1", out_dir=b1_dir, request=b1_request,
                        store_base=b1_dir / "store", budget_entry=entry)
    if not await_record(b1_run):
        finish_launch_record(b1_run, b1_run["process"].poll(), False)
        raise BatchStop("phase-1 host wrote no record for %s" % fixture_id)
    b1_record = read_json(b1_dir / "host_record.json")
    verify_identity(b1_record, b1_dir)
    if b1_record.get("exit_code") != 0 or not (b1_record.get("u1") or {}).get("r1_parsed"):
        lifecycle = terminate_host(b1_run)
        finish_launch_record(b1_run, lifecycle["exit_code"], False,
                             {"termination": lifecycle})
        raise BatchStop("phase-1 U1 did not parse for %s" % fixture_id, kind="fail")
    store_inside_phase1 = inventory(b1_dir / "store")
    digest_inside_phase1 = tree_digest(b1_dir / "store")

    lifecycle = terminate_host(b1_run)
    b1_launch = finish_launch_record(b1_run, lifecycle["exit_code"], False,
                                     {"termination": lifecycle})
    os.chmod(b1_dir / "store", 0o000)
    checks["phase1_store_empty"] = store_inside_phase1 == []
    checks["phase1_host_terminated"] = lifecycle["signal_sent"] in {"SIGTERM", "SIGKILL"}
    checks["phase1_esrch"] = lifecycle["esrch_on_pid"]
    checks["phase1_group_empty"] = lifecycle["esrch_on_process_group"]
    write_once(b1_dir / "termination.json", {
        "schema_id": "SIMIGO-G2-BATCH-TERMINATION-V1",
        "fixture_id": fixture_id,
        "host_pid": b1_launch["pid"],
        "process_group": b1_launch["process_group"],
        "signal_sent": lifecycle["signal_sent"],
        "exit_code": lifecycle["exit_code"],
        "esrch_on_pid": lifecycle["esrch_on_pid"],
        "esrch_on_process_group": lifecycle["esrch_on_process_group"],
        "store_inventory_inside_phase1": store_inside_phase1,
        "store_digest_inside_phase1": digest_inside_phase1,
        "store_chmod": "000",
        "terminated_at_utc": lifecycle["terminated_at_utc"],
    })
    if not (checks["phase1_host_terminated"] and checks["phase1_esrch"]
            and checks["phase1_group_empty"]):
        raise BatchStop("phase-1 host lifecycle unverifiable for %s" % fixture_id)

    b1_u1 = b1_record["u1"]
    write_once(b1_dir / "r1.json", {"r1_canonical": b1_u1["r1_canonical"],
                                    "r1_sha256": b1_u1["r1_sha256"]})
    checks["phase1_u1_parsed"] = b1_u1["r1_parsed"]

    # ---- settlement -------------------------------------------------------
    carrier_dir = b1_dir / "carrier"
    carrier_dir.mkdir(parents=True, exist_ok=False)
    carrier_db = carrier_dir / "g2.sqlite"
    settlement_record = create_phase1_carrier(carrier_db, fixture, b1_u1)
    settlement_record["carrier_sha256_after_settlement"] = sha256_file(carrier_db)
    canonical_digest_after_settlement = sqlite_digest(carrier_db)
    write_once(b1_dir / "carrier_phase1.json", settlement_record)
    if settlement_record["settlement"]["object_id"] is None:
        raise BatchStop("settlement produced no object id")
    checks["phase1_settled"] = True

    # ---- negative controls ------------------------------------------------
    gate_results = {}
    for variant, mutate, expected_code in (
            ("C_missing", remove_settlement, "SETTLEMENT_MISSING"),
            ("C_tampered", tamper_payload, "OBJECT_DIGEST_MISMATCH")):
        variant_dir = root / variant
        db_copy = copy_carrier(carrier_db, variant_dir)
        mutation = mutate(db_copy, "u1-result")
        digest_before = sqlite_digest(db_copy)
        result = run_gate_process(
            budget=budget, fixture=fixture, variant=variant, db_path=db_copy,
            phase1_r1=b1_dir / "r1.json", out_dir=variant_dir)
        gate_record = result["record"]
        digest_after = sqlite_digest(db_copy)
        record = dict(result)
        record["mutation"] = mutation
        record["copy_digest_before_refusal"] = digest_before
        record["copy_digest_after_refusal"] = digest_after
        record["decision"] = gate_record.get("decision")
        record["code"] = gate_record.get("code")
        record["expected_code"] = expected_code
        record["model_loaded"] = bool(gate_record.get("model_loaded"))
        write_once(variant_dir / "gate_launch.json", record)
        gate_results[variant] = record
        checks["%s_refused" % variant.lower()] = gate_record.get("decision") == "REFUSED"
        checks["%s_code" % variant.lower()] = gate_record.get("code") == expected_code
        checks["%s_copy_unchanged" % variant.lower()] = digest_before == digest_after
        checks["%s_no_model_load" % variant.lower()] = not gate_record.get("model_loaded")
        if not (checks["%s_refused" % variant.lower()]
                and checks["%s_code" % variant.lower()]
                and checks["%s_copy_unchanged" % variant.lower()]):
            raise BatchStop("negative control %s did not refuse as designed for %s"
                            % (variant, fixture_id), kind="fail")

    # ---- restore ----------------------------------------------------------
    restored = run_gate(carrier_db, "u1-result",
                        phase1_record=read_json(b1_dir / "r1.json"))
    write_once(root / "restore_gate.json", restored)
    if restored.get("decision") != "RESTORED":
        raise BatchStop("canonical carrier restore refused: %s"
                        % restored.get("code"))
    restored_object_id = restored["settlement"]["object_id"]
    index_before_phase2 = carrier_index_identities(carrier_db)
    settlement_history_before = settlement_history_length(carrier_db, "u1-result")
    checks["restore_decision_restored"] = True
    checks["restored_object_id_equal"] = (
        restored_object_id == settlement_record["settlement"]["object_id"])
    checks["restored_source_version_equal"] = (
        restored["source"]["source_version"]
        == settlement_record["source"]["source_version"])
    checks["restored_dependency_closure_equal"] = (
        restored["dependency_closure"]["ids"]
        == sorted(["s1-source"])
        and restored["dependency_closure"]["object_ids"]["s1-source"]
        == settlement_record["dependency_source"]["object_id"])
    checks["restored_validity_basis_equal"] = (
        restored["validity_basis"]["policy_sha256"]
        == settlement_record["validity_policy"]["policy_sha256"])

    # The phase-1 artifact root must be unreadable for the whole phase-2 window.
    try:
        os.listdir(b1_dir / "store")
        checks["phase1_store_unreadable_during_phase2"] = False
    except PermissionError:
        checks["phase1_store_unreadable_during_phase2"] = True

    # ---- Arm B phase 2 ----------------------------------------------------
    b2_dir = root / "B2"
    r1_canonical = restored["settlement"]["r1_canonical"]
    u2_prompt = fixture["u2_template"].replace("{{R1}}", r1_canonical)
    b2_request = {
        "mode": "phase2",
        "model_dir": str(MODEL_DIR),
        "store_base": str(b2_dir / "store"),
        "u2_prompt": u2_prompt,
        "max_tokens_u1": MAX_U1_TOKENS,
        "max_tokens_u2": MAX_U2_TOKENS,
        "stride": STRIDE,
    }
    b2_record, b2_launch = run_generation_arm(
        fixture=fixture, arm="B2", out_dir=b2_dir, request=b2_request,
        store_base=b2_dir / "store", budget=budget)
    b2_u2 = b2_record["u2"]
    b2_check = check_u2(b2_u2["text"], json.loads(r1_canonical), fixture)
    write_once(b2_dir / "checker.json", b2_check)
    checks["phase2_u2_generated"] = (b2_u2["chunk_count"] > 0
                                     and b2_u2["completion_token_count"] is not None)
    checks["u2_checker_pass"] = b2_check["pass"]
    checks["u2_contains_transfer_secret"] = b2_check["transfer_secret_matches_fixture"]
    checks["r1_matches_phase1"] = (
        restored["settlement"]["r1_sha256"] == b1_u1["r1_sha256"])

    # ---- G2-A observations ------------------------------------------------
    store = b2_record.get("store") or {}
    observations = b2_record.get("hook_observations") or {}
    checks["phase2_new_pid"] = b2_record["pid"] != b1_record["pid"]
    checks["phase2_new_pgid"] = b2_record["process_group"] != b1_record["process_group"]
    checks["phase2_store_base_distinct"] = str(b2_dir / "store") != str(b1_dir / "store")
    checks["phase2_hook_calls_positive"] = observations.get("calls", 0) > 0
    checks["phase2_hook_hits_zero"] = observations.get("hits", None) == 0
    checks["phase2_no_phase1_prefix_match"] = all(
        value != b1_u1["prompt_token_count"]
        for value in observations.get("matched_token_counts") or [])
    checks["phase2_store_still_empty"] = (
        (store.get("inventory_before") or []) == []
        and (store.get("inventory_after") or []) == []
        and store.get("rescan_registered_artifacts") == 0)
    checks["phase2_namespace_matches_p0"] = (
        store.get("namespace_kv_fingerprint")
        == "chat-cross-session-v1-%s" % EXPECTED_COMBINED)

    os.chmod(b1_dir / "store", 0o755)
    checks["phase1_store_digest_unchanged"] = (
        tree_digest(b1_dir / "store") == digest_inside_phase1)

    # ---- canary and S1 scans ---------------------------------------------
    canary = fixture["context_canary"]
    canary_in_r1 = canary in r1_canonical
    canary_in_phase2 = scan_for(b2_dir, canary)
    canary_in_restore = canary in json.dumps(restored)
    checks["canary_absent_from_r1"] = not canary_in_r1
    checks["canary_absent_from_phase2"] = (
        not canary_in_phase2 and not canary_in_restore)
    s1_hits_phase2 = scan_for(b2_dir, fixture["s1_marker"])
    checks["s1_absent_from_phase2"] = not s1_hits_phase2
    u1_prompt_sha = sha256_bytes(fixture["u1_prompt"].encode("utf-8"))
    checks["u1_not_reexecuted_in_phase2"] = (
        b2_u2["request_sha256"] != u1_prompt_sha
        and fixture["s1_marker"] not in u2_prompt)

    # ---- carrier state after phase 2 -------------------------------------
    states = record_phase2_states(
        carrier_db, fixture,
        {"fixture_id": fixture_id, "restored_object_id": restored_object_id,
         "r1_sha256": restored["settlement"]["r1_sha256"]},
        {"fixture_id": fixture_id, "answer": b2_u2["text"],
         "checker_pass": b2_check["pass"]})
    index_after_phase2 = carrier_index_identities(carrier_db)
    appended = index_after_phase2[len(index_before_phase2):]
    checks["no_u1_compute_in_phase2"] = all(
        entry.startswith("execution_state:") for entry in appended)
    checks["no_new_settlement_in_phase2"] = (
        settlement_history_length(carrier_db, "u1-result") == settlement_history_before)
    checks["settlement_object_id_unchanged"] = (
        (run_gate(carrier_db, "u1-result").get("settlement") or {}).get("object_id")
        == restored_object_id)
    write_once(b2_dir / "execution_states.json", {
        "schema_id": "SIMIGO-G2-BATCH-PHASE2-STATES-V1",
        "states": states,
        "index_entries_appended_during_phase2": appended,
        "settlement_history_before": settlement_history_before,
        "settlement_history_after": settlement_history_length(carrier_db, "u1-result"),
        "execute_demand_calls": 0,
    })

    canonical_digest_after_phase2 = sqlite_digest(carrier_db)

    # ---- fixture verdict --------------------------------------------------
    verification = {
        "schema_id": "SIMIGO-G2-BATCH-FIXTURE-VERIFICATION-V1",
        "fixture_id": fixture_id,
        "checks": checks,
        "all_checks_pass": all(checks.values()),
        "failed_checks": sorted(key for key, value in checks.items() if not value),
        "claims": claim_rows(checks),
        "evidence": {
            "arm_a": rel_to_repo(a_dir),
            "phase1": rel_to_repo(b1_dir),
            "phase1_carrier": rel_to_repo(carrier_db),
            "phase2": rel_to_repo(b2_dir),
            "c_missing": rel_to_repo(root / "C_missing"),
            "c_tampered": rel_to_repo(root / "C_tampered"),
            "arm_a_launch": rel_to_repo(a_dir / "launch.json"),
            "phase2_launch": rel_to_repo(b2_dir / "launch.json"),
        },
        "canonical_carrier": {
            "path": rel_to_repo(carrier_db),
            "sqlite_digest_after_settlement": canonical_digest_after_settlement,
            "sqlite_digest_after_phase2": canonical_digest_after_phase2,
            "unchanged_after_negative_controls_and_phase2":
                canonical_digest_after_settlement == canonical_digest_after_phase2,
        },
        "scan": {
            "canary_in_r1": canary_in_r1,
            "canary_in_phase2_evidence": canary_in_phase2,
            "canary_in_restore_record": canary_in_restore,
            "s1_marker_in_phase2_evidence": s1_hits_phase2,
        },
    }
    write_once(root / "verification.json", verification)

    if canary_in_r1:
        raise BatchStop("canary found in R1 for %s: fixture void, batch stops"
                        % fixture_id)
    if canary_in_phase2 or canary_in_restore:
        raise BatchStop("canary found on a phase-2 surface for %s: G2-A leak"
                        % fixture_id, kind="fail")
    if not verification["all_checks_pass"]:
        raise BatchStop("fixture %s failed checks: %s"
                        % (fixture_id, verification["failed_checks"]),
                        kind="fail" if set(verification["failed_checks"])
                        & COUNTEREXAMPLE_ROWS else "inconclusive")
    return verification


def claim_rows(checks):
    groups = {
        "G2-A": [
            "phase1_host_terminated", "phase1_esrch", "phase1_group_empty",
            "phase2_new_pid", "phase2_new_pgid", "phase2_store_base_distinct",
            "phase1_store_empty", "phase1_store_unreadable_during_phase2",
            "phase2_hook_calls_positive",
            "phase2_hook_hits_zero", "phase2_no_phase1_prefix_match",
            "phase2_store_still_empty", "phase1_store_digest_unchanged",
            "canary_absent_from_r1", "canary_absent_from_phase2",
        ],
        "G2-B": [
            "phase1_settled", "restore_decision_restored", "restored_object_id_equal",
            "restored_source_version_equal", "restored_dependency_closure_equal",
            "restored_validity_basis_equal", "c_missing_refused", "c_missing_code",
            "c_missing_copy_unchanged", "c_missing_no_model_load",
            "c_tampered_refused", "c_tampered_code", "c_tampered_copy_unchanged",
            "c_tampered_no_model_load", "settlement_object_id_unchanged",
            "no_u1_compute_in_phase2", "no_new_settlement_in_phase2",
        ],
        "G2-C": [
            "phase1_u1_parsed", "phase2_u2_generated", "u2_checker_pass",
            "u2_contains_transfer_secret", "r1_matches_phase1",
            "u1_not_reexecuted_in_phase2", "s1_absent_from_phase2",
        ],
    }
    rows = {}
    for claim, names in groups.items():
        missing = [name for name in names if name not in checks]
        rows[claim] = {
            "rows": names,
            "missing_rows": missing,
            "all_rows_pass": not missing and all(checks[name] for name in names),
            "failed_rows": [name for name in names
                            if name in checks and not checks[name]],
        }
    return rows


INCONCLUSIVE_ROWS = {"phase2_hook_calls_positive", "phase1_esrch",
                     "phase1_group_empty", "phase2_u2_generated"}


def verdicts_from_claims(claims):
    verdicts = {}
    for claim, body in claims.items():
        failed = body["failed_rows"]
        if body["missing_rows"]:
            verdicts[claim] = "INCONCLUSIVE"
        elif not failed:
            verdicts[claim] = "PASS"
        elif any(name in INCONCLUSIVE_ROWS for name in failed):
            verdicts[claim] = "INCONCLUSIVE"
        else:
            verdicts[claim] = "FAIL"
    return verdicts


def fixture_verdict(verification):
    return verdicts_from_claims(verification["claims"])


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", default=str(MANIFEST))
    parser.add_argument("--verify-only")
    args = parser.parse_args()

    if args.verify_only:
        return verify_only(pathlib.Path(args.verify_only))

    pre = preflight(args.manifest)
    run_id = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_dir = EVIDENCE / run_id
    run_dir.mkdir(parents=True, exist_ok=False)

    budget = Budget()
    started_at = utc_now()
    write_once(run_dir / "preflight.json", {
        "schema_id": "SIMIGO-G2-BATCH-PREFLIGHT-V1",
        "run_id": run_id,
        "manifest": {"path": pre["manifest_path"],
                     "sha256": pre["manifest_sha256"]},
        "authorization": pre["token"],
        "head": pre["head"],
        "source_revision_at_freeze": pre["manifest"].get("source_revision_at_freeze"),
        "clean_tree": True,
        "artifact_check": pre["artifact"],
        "model_directory": str(MODEL_DIR),
        "symlink_entries_in_model_dir": count_symlinks(MODEL_DIR),
        "runner": {"version": RUNNER_VERSION, "path": rel_to_repo(RUNNER_PATH),
                   "sha256": sha256_file(RUNNER_PATH)},
        "host_product": {"path": rel_to_repo(HOST_BIN),
                         "sha256": sha256_file(HOST_BIN)},
        "budget": BUDGET,
        "argv": sys.argv,
        "host": {"platform": platform.platform(),
                 "machine": platform.machine(),
                 "python": platform.python_version()},
        "started_at_utc": started_at,
    })
    write_once(run_dir / "artifact_check.json", pre["artifact"])

    # Consume the authorization token before the first child launch.
    os.rename(TOKEN, run_dir / "AUTHORIZATION.consumed")
    write_once(run_dir / "AUTHORIZATION_CONSUMPTION.json", {
        "schema_id": "SIMIGO-G2-BATCH-AUTH-CONSUMPTION-V1",
        "authorization_id": pre["token"]["authorization_id"],
        "token_sha256": sha256_file(run_dir / "AUTHORIZATION.consumed"),
        "manifest_sha256": pre["manifest_sha256"],
        "consumed_at_utc": utc_now(),
        "consumed_by_rename": True,
        "consume_order": "before_first_child_launch",
    })

    verdicts = {}
    stopped = None
    stopped_kind = "inconclusive"
    try:
        for fixture in pre["fixtures"]:
            verification = run_fixture(fixture, run_dir, budget)
            verdicts[fixture["fixture_id"]] = {
                "claims": fixture_verdict(verification),
                "failed_checks": verification["failed_checks"],
            }
    except BatchStop as stop:
        stopped = str(stop)
        stopped_kind = stop.kind
        print("BATCH STOP: %s" % stop, file=sys.stderr)

    overall = {}
    for claim in ("G2-A", "G2-B", "G2-C"):
        values = [verdicts[key]["claims"].get(claim) for key in verdicts]
        if stopped:
            # A halted batch cannot pass a claim: only a recorded counterexample
            # survives as FAIL, everything else is missing evidence.
            overall[claim] = "FAIL" if any(value == "FAIL" for value in values) \
                else "INCONCLUSIVE"
        elif not values:
            overall[claim] = "INCONCLUSIVE"
        elif all(value == "PASS" for value in values):
            overall[claim] = "PASS"
        elif any(value == "FAIL" for value in values):
            overall[claim] = "FAIL"
        else:
            overall[claim] = "INCONCLUSIVE"

    if stopped:
        terminal_state = "FAIL" if stopped_kind == "fail" else "INCONCLUSIVE"
    elif all(value == "PASS" for value in overall.values()) and len(verdicts) == 3:
        terminal_state = "PASS"
    elif any(value == "FAIL" for value in overall.values()):
        terminal_state = "FAIL"
    else:
        terminal_state = "INCONCLUSIVE"

    terminal = {
        "schema_id": "SIMIGO-G2-BATCH-TERMINAL-V1",
        "run_id": run_id,
        "terminal_state": terminal_state,
        "claims": overall,
        "fixtures": verdicts,
        "halted": bool(stopped),
        "stop_reason": stopped,
        "stop_kind": stopped_kind if stopped else None,
        "budget": budget.as_record(run_dir),
        "started_at_utc": started_at,
        "finished_at_utc": utc_now(),
        "manifest_sha256": pre["manifest_sha256"],
        "authorization_id": pre["token"]["authorization_id"],
        "notes": [
            "A clean process exit is not a research result; G2-A, G2-B and G2-C "
            "are decided by their own evidence rows.",
            "Peak memory was not measured. The symlink reader defect (A3) was not "
            "addressed. Tokenizer digest reproducibility across directories is "
            "reported, not proven.",
        ],
    }
    write_once(run_dir / "terminal.json", terminal)
    print(json.dumps(terminal, indent=2, sort_keys=True))
    if terminal_state != "PASS":
        sys.exit(2 if terminal_state == "FAIL" else 3)


def verify_only(run_dir):
    """Re-derive the verdict from the run's own files. Never rewrites them."""
    run_dir = pathlib.Path(run_dir)
    terminal_path = run_dir / "terminal.json"
    if not terminal_path.is_file():
        die("no terminal record in %s" % run_dir)
    terminal = read_json(terminal_path)
    problems = []
    recomputed = {}
    for path in sorted((run_dir / "fixtures").glob("*/verification.json")):
        body = read_json(path)
        claims = claim_rows(body["checks"])
        recomputed[body["fixture_id"]] = {
            "all_checks_pass": all(body["checks"].values()),
            "failed_checks": sorted(key for key, value in body["checks"].items()
                                    if not value),
            "claims": verdicts_from_claims(claims),
        }
    for fixture_id, recorded in terminal.get("fixtures", {}).items():
        mine = recomputed.get(fixture_id)
        if mine is None:
            problems.append("%s: verification record missing" % fixture_id)
            continue
        if mine["failed_checks"] != recorded.get("failed_checks"):
            problems.append("%s: failed checks differ from the recorded list"
                            % fixture_id)
        for claim, verdict in recorded.get("claims", {}).items():
            if mine["claims"].get(claim) != verdict:
                problems.append("%s/%s: recorded %s recomputed %s"
                                % (fixture_id, claim, verdict,
                                   mine["claims"].get(claim)))
    for host_record in sorted((run_dir / "fixtures").glob("*/B2/host_record.json")):
        body = read_json(host_record)
        observations = body.get("hook_observations") or {}
        if not observations.get("calls", 0) > 0:
            problems.append("%s: phase-2 hook was not consulted" % host_record)
        if observations.get("hits") != 0:
            problems.append("%s: phase-2 hook recorded a hit" % host_record)
        if (body.get("engine_content_identity") or {}).get("combined_digest") \
                != EXPECTED_COMBINED:
            problems.append("%s: engine identity differs from P0-A2" % host_record)
        if body.get("checks", {}).get("store_still_empty_after") is not True:
            problems.append("%s: phase-2 store not empty after the run" % host_record)
    for launch in sorted((run_dir / "fixtures").glob("*/*/launch.json")):
        body = read_json(launch)
        exit_code = body.get("exit_code")
        if body.get("mode") == "phase1":
            # The phase-1 host is terminated on purpose after it writes its
            # record; a SIGTERM/SIGKILL exit is the designed lifecycle.
            if exit_code not in (-signal.SIGTERM, -signal.SIGKILL):
                problems.append("%s: phase-1 exit %s is not a termination"
                                % (launch, exit_code))
        elif exit_code != 0:
            problems.append("%s: non-zero exit" % launch)
    recorded_budget = terminal.get("budget") or {}
    if recorded_budget.get("model_starts_used", 0) \
            > recorded_budget.get("model_starts_max", 0):
        problems.append("model-start budget exceeded")
    if recorded_budget.get("process_calls_used", 0) \
            > recorded_budget.get("process_calls_max", 0):
        problems.append("process-call budget exceeded")
    for gate in sorted((run_dir / "fixtures").glob("*/C_*/gate.json")):
        body = read_json(gate)
        if body.get("decision") != "REFUSED":
            problems.append("%s: negative control did not refuse" % gate)
        if body.get("model_loaded"):
            problems.append("%s: negative control claims a model load" % gate)
        if not body.get("database_unchanged"):
            problems.append("%s: refused carrier copy changed" % gate)
    report = {
        "schema_id": "SIMIGO-G2-BATCH-REVERIFICATION-V1",
        "run_id": terminal.get("run_id"),
        "terminal_state_recorded": terminal.get("terminal_state"),
        "verdict_agrees": not problems,
        "problems": problems,
        "fixtures_recomputed": recomputed,
        "budget_recorded": terminal.get("budget"),
    }
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if not problems else 5


if __name__ == "__main__":
    sys.exit(main())
