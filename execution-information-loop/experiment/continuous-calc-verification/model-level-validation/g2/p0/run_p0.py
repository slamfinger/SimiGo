#!/usr/bin/env python3
"""G2 P0 runner — one model start, no retry, write-once evidence.

Pre-launch (no model start consumed):
  1. source revision + clean-tree flag
  2. Package.resolved pins vs the frozen binding
  3. `swift build -c release --product G2P0Probe`
  4. artifact rows vs the binding (17 files, bytes, SHA-256) and the aggregate
     digest recomputation; the weights digest the engine will derive is
     predicted here from the binding rows

Launch (exactly once):
  5. create the run directory (exclusive), write the three pre-run records
  6. atomically rename AUTHORIZATION.json -> AUTHORIZATION.consumed
  7. start the probe in its own process group, 1200 s group-SIGKILL timeout

Post-run (never rewrites run facts):
  8. read P0_PROBE.json / terminal.json; write INCONCLUSIVE only if the probe
     left no terminal record
  9. re-derive the verdict independently -> RUN_VERIFICATION.json
"""

import datetime
import hashlib
import json
import os
import pathlib
import platform
import signal
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[5]
BINDING = REPO / "docs/01-questions/G2_MODEL_BINDING_20261020.json"
PREREG = REPO / "docs/01-questions/G2_PREREGISTRATION_20261020.md"
AUTH = REPO / "docs/01-questions/G2_P0_AUTHORIZATION_20261020.md"
PROBE_DIR = HERE / "probe"
P0_ROOT = HERE
TIMEOUT_SECONDS = 1200
MAX_TOKENS = 16
STRIDE = 256
PROMPT = "Reply with exactly one word: ready."


def utc_now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def die(message, code=4):
    print("PREFLIGHT FAILURE: " + message, file=sys.stderr)
    sys.exit(code)


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def git(*args):
    result = run(["git", "-C", str(REPO)] + list(args))
    if result.returncode != 0:
        die("git %s failed: %s" % (" ".join(args), result.stderr.strip()))
    return result.stdout.strip()


def artifact_check(model_dir, binding_rows):
    rows = []
    for dirpath, _dirnames, filenames in os.walk(model_dir, followlinks=True):
        for name in filenames:
            path = os.path.join(dirpath, name)
            if not os.path.isfile(path):
                continue
            rows.append({
                "path": os.path.relpath(path, model_dir),
                "bytes": os.path.getsize(path),
                "sha256": sha256_file(path),
            })
    rows.sort(key=lambda row: row["path"])
    expected = {row["path"]: row for row in binding_rows}
    per_file = []
    for row in rows:
        want = expected.get(row["path"])
        per_file.append({
            "path": row["path"],
            "bytes": row["bytes"],
            "sha256": row["sha256"],
            "expected_bytes": want["bytes"] if want else None,
            "expected_sha256": want["sha256"] if want else None,
            "match": bool(want and want["bytes"] == row["bytes"]
                          and want["sha256"] == row["sha256"]),
        })
    missing = sorted(set(expected) - {row["path"] for row in rows})
    canonical = json.dumps(rows, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    aggregate = sha256_bytes(canonical.encode("utf-8"))
    weight_lines = sorted("%s:%d:%s" % (row["path"], row["bytes"], row["sha256"])
                          for row in rows if row["path"].endswith(".safetensors"))
    weights_digest = sha256_bytes("\n".join(weight_lines).encode("utf-8"))
    all_match = all(row["match"] for row in per_file) and not missing
    return {
        "schema_id": "SIMIGO-G2-P0-ARTIFACT-CHECK-V1",
        "model_directory": str(model_dir),
        "file_count_on_disk": len(rows),
        "file_count_in_binding": len(binding_rows),
        "missing_from_disk": missing,
        "all_match": all_match,
        "aggregate_sha256": aggregate,
        "aggregate_rule": "sha256(UTF-8(JSON.dumps(rows={path,bytes,sha256}, "
                          "sort_keys=true, separators=(',',':'), ensure_ascii=false)))",
        "predicted_engine_weights_digest": weights_digest,
        "predicted_engine_weights_rule": "sha256(UTF-8('\\n'.join(sorted("
                                         "\"{relpath}:{bytes}:{sha256}\" for *.safetensors))))",
        "files": per_file,
    }


def main():
    binding = json.loads(BINDING.read_text(encoding="utf-8"))
    expected_aggregate = binding["model"]["aggregate_sha256"]
    model_dir = pathlib.Path(os.path.expanduser(binding["model"]["model_dir"]))

    # ---- 1. source state -----------------------------------------------------
    revision = git("rev-parse", "HEAD")
    dirty = git("status", "--porcelain")
    if dirty:
        die("working tree is not clean; P0 must build from a committed tree:\n" + dirty)
    if not model_dir.is_dir():
        die("model directory missing: %s" % model_dir)

    # ---- 2. pins -------------------------------------------------------------
    resolved_path = PROBE_DIR / "Package.resolved"
    resolved = json.loads(resolved_path.read_text(encoding="utf-8"))
    pins = {pin["identity"]: pin["state"].get("revision") for pin in resolved["pins"]}
    expected_pins = binding["runtime_binding"]["package_resolved"]
    pin_mismatches = {name: {"expected": want, "actual": pins.get(name)}
                      for name, want in expected_pins.items() if pins.get(name) != want}
    if pin_mismatches:
        die("Package.resolved pins do not match the frozen binding: %s" % pin_mismatches)

    # ---- 3. build ------------------------------------------------------------
    print("building release probe ...", flush=True)
    build_start = time.time()
    build = run(["swift", "build", "--package-path", str(PROBE_DIR),
                 "-c", "release", "--product", "G2P0Probe"])
    build_seconds = time.time() - build_start
    if build.returncode != 0:
        sys.stderr.write(build.stdout[-4000:] + "\n" + build.stderr[-4000:] + "\n")
        die("release build failed")
    product = PROBE_DIR / ".build/release/G2P0Probe"
    if not product.is_file():
        die("product not found at %s" % product)
    product_sha = sha256_file(product)
    swift_version = run(["swift", "--version"]).stdout.strip()
    dirty_after_build = git("status", "--porcelain")
    if dirty_after_build:
        die("the build modified tracked files; refusing to spend the model start:\n"
            + dirty_after_build)

    # ---- 4. artifact ---------------------------------------------------------
    print("hashing the frozen artifact (%d bytes) ..." % binding["model"]["total_bytes"],
          flush=True)
    artifact = artifact_check(model_dir, binding["files"])
    if not artifact["all_match"]:
        die("artifact does not match the binding: missing=%s mismatched=%d"
            % (artifact["missing_from_disk"],
               sum(1 for row in artifact["files"] if not row["match"])))
    if artifact["aggregate_sha256"] != expected_aggregate:
        die("aggregate mismatch: %s != %s"
            % (artifact["aggregate_sha256"], expected_aggregate))
    print("artifact ok; predicted engine weights digest = %s"
          % artifact["predicted_engine_weights_digest"], flush=True)

    # ---- 5. run directory ----------------------------------------------------
    run_id = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_dir = P0_ROOT / run_id
    try:
        run_dir.mkdir(parents=True, exist_ok=False)
    except FileExistsError:
        die("run directory already exists: %s" % run_dir)
    store_base = run_dir / "store"
    store_base.mkdir()

    (run_dir / "artifact_check.json").write_text(
        json.dumps(artifact, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    build_record = {
        "schema_id": "SIMIGO-G2-P0-BUILD-V1",
        "run_id": run_id,
        "source_revision": revision,
        "source_tree_clean_at_build": True,
        "build_mode": "swift build -c release --product G2P0Probe",
        "build_duration_seconds": round(build_seconds, 3),
        "product_path": str(product.relative_to(REPO)),
        "product_bytes": product.stat().st_size,
        "product_sha256": product_sha,
        "swift_version": swift_version,
        "package_resolved_sha256": sha256_file(resolved_path),
        "package_pins": pins,
        "probe_sources": {
            "Package.swift": sha256_file(PROBE_DIR / "Package.swift"),
            "Sources/G2P0Probe/main.swift":
                sha256_file(PROBE_DIR / "Sources/G2P0Probe/main.swift"),
        },
        "design_hashes": {
            "G2_PREREGISTRATION_20261020.md": sha256_file(PREREG),
            "G2_MODEL_BINDING_20261020.json": sha256_file(BINDING),
            "G2_P0_AUTHORIZATION_20261020.md": sha256_file(AUTH),
        },
        "host": {
            "platform": platform.platform(),
            "machine": platform.machine(),
            "python": platform.python_version(),
            "cpu_count": os.cpu_count(),
            "physical_memory_bytes": int(run(["sysctl", "-n", "hw.memsize"]).stdout.strip()),
        },
        "created_at_utc": utc_now(),
    }
    (run_dir / "build.json").write_text(
        json.dumps(build_record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (run_dir / "AUTHORIZATION.json").write_text(json.dumps({
        "schema_id": "SIMIGO-G2-P0-AUTHORIZATION-V1",
        "run_id": run_id,
        "authorization_record": str(AUTH.relative_to(REPO)),
        "authorization_sha256": sha256_file(AUTH),
        "scope": [
            "load the frozen artifact once through the ChatSession stack",
            "establish ChatSession path and cache-observation hook availability",
            "record terminal state PASS/FAIL/INCONCLUSIVE",
            "stop; no U1/U2, no fixture, no arm, no batch manifest",
        ],
        "budget": {"model_starts": 1, "retries": 0, "generations": 2},
        "prohibited": [
            "model substitution", "fixture run", "matrix expansion",
            "batch authorization or completion marker", "push",
        ],
        "consumed": False,
    }, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    # ---- 6. consume ----------------------------------------------------------
    os.rename(run_dir / "AUTHORIZATION.json", run_dir / "AUTHORIZATION.consumed")
    print("authorization consumed; starting the single model start", flush=True)

    # ---- 7. launch -----------------------------------------------------------
    env = dict(os.environ)
    env.update({
        "G2P0_EVIDENCE_ROOT": str(run_dir),
        "G2P0_MODEL_DIR": str(model_dir),
        "G2P0_STORE_BASE": str(store_base),
        "G2P0_EXPECTED_WEIGHTS_DIGEST": artifact["predicted_engine_weights_digest"],
        "G2P0_EXPECTED_AGGREGATE": expected_aggregate,
        "G2P0_PROBE_MAX_TOKENS": str(MAX_TOKENS),
        "G2P0_PREFILL_STRIDE": str(STRIDE),
        "G2P0_PROMPT": PROMPT,
        "HF_HUB_OFFLINE": "1",
        "TRANSFORMERS_OFFLINE": "1",
    })
    started = time.time()
    child = subprocess.Popen(
        [str(product)], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        start_new_session=True, env=env)
    try:
        stdout, stderr = child.communicate(timeout=TIMEOUT_SECONDS)
        timed_out = False
    except subprocess.TimeoutExpired:
        timed_out = True
        try:
            os.killpg(os.getpgid(child.pid), signal.SIGKILL)
        except ProcessLookupError:
            pass
        stdout, stderr = child.communicate()
    elapsed = time.time() - started
    (run_dir / "run.log").write_bytes(
        b"=== stdout ===\n" + stdout + b"\n=== stderr ===\n" + stderr)
    launch = {
        "schema_id": "SIMIGO-G2-P0-LAUNCH-V1",
        "run_id": run_id,
        "child_pid": child.pid,
        "child_process_group": os.getpgid(child.pid) if not timed_out else None,
        "exit_code": child.returncode,
        "timed_out": timed_out,
        "timeout_seconds": TIMEOUT_SECONDS,
        "started_at_utc": datetime.datetime.fromtimestamp(
            started, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "duration_seconds": round(elapsed, 3),
        "model_starts_consumed": 1,
        "environment_passed": {
            key: env[key] for key in sorted(env)
            if key.startswith("G2P0_") or key in ("HF_HUB_OFFLINE", "TRANSFORMERS_OFFLINE")
        },
    }
    (run_dir / "launch.json").write_text(
        json.dumps(launch, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    # ---- 8. terminal ---------------------------------------------------------
    terminal_path = run_dir / "terminal.json"
    probe_path = run_dir / "P0_PROBE.json"
    if not terminal_path.exists():
        payload = {
            "schema_id": "SIMIGO-G2-P0-TERMINAL-V1",
            "terminal_state": "INCONCLUSIVE",
            "failed_checks": ["probe_wrote_no_terminal_record"],
            "reason": "timeout" if timed_out else "child exited without a terminal record",
            "exit_code": child.returncode,
            "completed_at_utc": utc_now(),
        }
        with open(terminal_path, "x", encoding="utf-8") as fh:
            json.dump(payload, fh, indent=2, sort_keys=True)
            fh.write("\n")
    terminal = json.loads(terminal_path.read_text(encoding="utf-8"))
    probe = json.loads(probe_path.read_text(encoding="utf-8")) if probe_path.exists() else {}

    # ---- 9. independent reverification --------------------------------------
    checks = probe.get("checks", {})
    hook = probe.get("hook_observations", {})
    reverified = {
        "probe_wrote_record": bool(probe),
        "artifact_rows_match_binding": bool(artifact["all_match"]),
        "artifact_aggregate_matches_binding":
            artifact["aggregate_sha256"] == expected_aggregate,
        "engine_weights_digest_matches_binding":
            probe.get("engine_content_identity", {}).get("weights_digest")
            == artifact["predicted_engine_weights_digest"],
        "container_loaded": bool(probe.get("load", {}).get("ok")),
        "prompt_rendered": int(probe.get("prompt_render", {}).get("token_count", 0)) > 0,
        "baseline_generation_completed":
            int(probe.get("generation_baseline", {}).get("chunk_count", 0)) > 0
            and isinstance(probe.get("generation_baseline", {}).get("completion_token_count"), int),
        "hooked_generation_completed":
            int(probe.get("generation_hooked", {}).get("chunk_count", 0)) > 0
            and isinstance(probe.get("generation_hooked", {}).get("completion_token_count"), int),
        "store_initially_empty":
            int(probe.get("store", {}).get("rescan_registered_artifacts", -1)) == 0
            and probe.get("store", {}).get("inventory_before") == [],
        "hook_consulted": int(hook.get("calls", 0)) > 0,
        "hook_missed_on_empty_store": int(hook.get("hits", 0)) == 0,
        "store_still_empty_after": probe.get("store_inventory_after") == [],
        "executable_is_the_built_product":
            probe.get("executable_sha256") == product_sha,
        "one_model_start": launch["model_starts_consumed"] == 1,
    }
    derived = "PASS" if all(reverified.values()) else "FAIL"
    if terminal.get("terminal_state") == "INCONCLUSIVE":
        derived = "INCONCLUSIVE"
    verification = {
        "schema_id": "SIMIGO-G2-P0-VERIFICATION-V1",
        "run_id": run_id,
        "probe_terminal_state": terminal.get("terminal_state"),
        "probe_failed_checks": terminal.get("failed_checks", []),
        "reverified_checks": reverified,
        "reverified_terminal_state": derived,
        "verdict_agrees": derived == terminal.get("terminal_state"),
        "probe_checks_all_true": all(checks.values()) if checks else False,
        "note": "Derived independently from the probe facts and the pre-run records; "
                "the probe's own terminal record is never rewritten.",
        "created_at_utc": utc_now(),
    }
    (run_dir / "RUN_VERIFICATION.json").write_text(
        json.dumps(verification, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if not verification["verdict_agrees"]:
        (run_dir / "DISCREPANCY.json").write_text(json.dumps({
            "schema_id": "SIMIGO-G2-P0-DISCREPANCY-V1",
            "probe_terminal_state": terminal.get("terminal_state"),
            "reverified_terminal_state": derived,
            "reverified_checks": reverified,
            "created_at_utc": utc_now(),
        }, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print(json.dumps({
        "run_id": run_id,
        "run_dir": str(run_dir),
        "terminal_state": terminal.get("terminal_state"),
        "reverified_terminal_state": derived,
        "verdict_agrees": verification["verdict_agrees"],
        "failed_checks": terminal.get("failed_checks", []),
        "hook": hook,
        "exit_code": child.returncode,
        "timed_out": timed_out,
        "duration_seconds": round(elapsed, 3),
        "product_sha256": product_sha,
        "engine_weights_digest": probe.get("engine_content_identity", {}).get("weights_digest"),
    }, indent=2, sort_keys=True))
    return 0 if derived == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
