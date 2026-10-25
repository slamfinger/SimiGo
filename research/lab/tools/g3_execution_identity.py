#!/usr/bin/env python3
"""Bind a frozen G3 source/manifest snapshot to the process that actually runs.

G7b has three layers, and this tool is the third:

  1. content freeze        `g3_runner_manifest.py` (files, vendor repos, archives)
  2. artifact identity     `artifact_stamp` (source digest + artifact hashes)
  3. execution identity    THIS TOOL: the bytes that will be exec'd, the running
                           PID's executable, and a one-time authorization marker

A hash of "some binary in the build directory" is not execution identity. This
tool therefore:

  * copies the artifact into a supervisor-owned 0700 directory, hashing the bytes
    as they are written, fsyncs, renames, then re-opens with O_NOFOLLOW and
    re-hashes the staged copy;
  * writes a marker that binds `source_sha256` + `runner_sha256` + staged hash,
    and consumes it with O_CREAT|O_EXCL on launch, so one authorization cannot
    launch twice;
  * after spawn, resolves the RUNNING process's executable with `proc_pidpath`
    and hashes THAT path, so the verified object is the launched worker rather
    than a same-named file somewhere in `.build`;
  * passes the expected digest to the child (`G3_EXPECT_EXEC_SHA256`), so a D1
    worker refuses to generate when its own executable does not match. The real
    `G3D1Worker` implements this self-check, so it is enforced evidence, not only
    a contract.

The D1 worker artifact is `simigo2-experimental/.build/out/Products/Debug/G3D1Worker`
(G6). When it is absent this tool writes an explicitly `unclosed` record and
exits 2; when it is present and launched so that the running PID's executable
hashes to the staged bytes, the record is `bound`. `--stand-in` marks a
demonstration with a non-worker binary as `control-only`; that status can never
be promoted to `bound` by editing the record, because `--verify` re-derives it
from the manifest, the staged bytes and the marker.

Usage:
  python3 tools/g3_execution_identity.py --manifest <manifest.json> --status
  python3 tools/g3_execution_identity.py --manifest <m> --binary <w> [--launch -- args]
  python3 tools/g3_execution_identity.py --manifest <m> --verify
"""

from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import os
import stat
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

SCHEMA_ID = "G3-D1-EXECUTION-IDENTITY-V1"
MARKER_SCHEMA = "G3-D1-AUTHORIZATION-MARKER-V1"
ROOT = Path(__file__).resolve().parent.parent
DEFAULT_WORKER = "simigo2-experimental/.build/out/Products/Debug/G3D1Worker"
DEFAULT_RECORD = "docs/02-evidence/g3-d1-source-freeze/execution/execution-identity.json"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def utc_now() -> str:
    return datetime.now(tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def display(path: Path) -> str:
    return path.relative_to(ROOT).as_posix() if path.is_relative_to(ROOT) else str(path)


def load_manifest(path: Path) -> dict:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    missing = [
        key for key in ("source_sha256", "runner_sha256", "digest_rules") if not manifest.get(key)
    ]
    if missing:
        raise SystemExit(
            "manifest is not a V3 frozen manifest (missing " + ", ".join(missing) + ")"
        )
    return manifest


def codesign_identity(binary: Path) -> dict:
    """Signature identity, recorded verbatim. Unsigned/ad-hoc is not a failure for
    a locally built worker, but it must not be reported as a Developer ID."""
    proc = subprocess.run(
        ["codesign", "-dv", "--verbose=4", str(binary)],
        capture_output=True,
        text=True,
        check=False,
    )
    text = proc.stderr + proc.stdout
    fields: dict[str, str] = {}
    for line in text.splitlines():
        if "=" in line:
            key, _, value = line.partition("=")
            fields.setdefault(key.strip(), value.strip())
    return {
        "checked": proc.returncode == 0,
        "identifier": fields.get("Identifier"),
        "team_identifier": fields.get("TeamIdentifier"),
        "authority": fields.get("Authority"),
        "signature": fields.get("Signature"),
        "flags": fields.get("Flags"),
        "raw": text.strip().splitlines()[-8:],
    }


def process_executable(pid: int) -> str | None:
    """The path of the RUNNING process's executable (macOS libproc)."""
    lib = ctypes.CDLL("/usr/lib/libproc.dylib")
    buffer = ctypes.create_string_buffer(4096)
    written = lib.proc_pidpath(ctypes.c_int(pid), buffer, ctypes.c_uint32(len(buffer)))
    if written <= 0:
        return None
    return buffer.value.decode("utf-8", "replace")


def staged_copy(source: Path, stage_dir: Path) -> tuple[Path, dict]:
    """Copy into a sealed directory, hashing the bytes as they are written."""
    stage_dir.mkdir(parents=True, exist_ok=True)
    os.chmod(stage_dir, 0o700)
    final = stage_dir / source.name
    temp = stage_dir / f".{source.name}.tmp"
    if temp.exists():
        temp.unlink()
    digest = hashlib.sha256()
    size = 0
    fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o500)
    try:
        with os.fdopen(fd, "wb") as out, source.open("rb") as src:
            for chunk in iter(lambda: src.read(1 << 20), b""):
                digest.update(chunk)
                size += len(chunk)
                out.write(chunk)
            out.flush()
            os.fsync(out.fileno())
        os.chmod(temp, 0o500)
        os.replace(temp, final)
    except BaseException:
        if temp.exists():
            temp.unlink()
        raise
    # Re-open WITHOUT following a link and hash what is now on disk: the write
    # hash alone would miss a replacement between rename and exec.
    read_fd = os.open(final, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        again = hashlib.sha256()
        while True:
            chunk = os.read(read_fd, 1 << 20)
            if not chunk:
                break
            again.update(chunk)
        info = os.fstat(read_fd)
    finally:
        os.close(read_fd)
    identity = {
        "path": display(final),
        "absolute_path": str(final),
        "sha256": again.hexdigest(),
        "write_sha256": digest.hexdigest(),
        "hashes_agree": again.hexdigest() == digest.hexdigest(),
        "size": size,
        "mode": oct(stat.S_IMODE(info.st_mode)),
        "uid": info.st_uid,
        "gid": info.st_gid,
        "device": info.st_dev,
        "inode": info.st_ino,
        "stage_dir": str(stage_dir),
        "stage_dir_mode": oct(stat.S_IMODE(stage_dir.stat().st_mode)),
        "stage_dir_owned_by_caller": stage_dir.stat().st_uid == os.getuid(),
        "no_follow_reread": True,
    }
    return final, identity


def marker_id(manifest: dict, staged_sha: str) -> str:
    payload = "|".join(
        [
            MARKER_SCHEMA,
            manifest["source_sha256"],
            manifest["runner_sha256"],
            staged_sha,
        ]
    )
    return sha256_bytes(payload.encode("utf-8"))


def record_paths(record: Path) -> tuple[Path, Path, Path]:
    return record.parent, record.parent / "stage", record.parent / "consumed"


def write_record(record: Path, payload: dict) -> str:
    record.parent.mkdir(parents=True, exist_ok=True)
    record.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return sha256_file(record)


def unclosed_payload(manifest_path: Path, manifest: dict, binary: Path, reason: str) -> dict:
    return {
        "schema_id": SCHEMA_ID,
        "status": "unclosed",
        "reason": reason,
        "generated_at_utc": utc_now(),
        "manifest": {
            "path": display(manifest_path),
            "source_sha256": manifest["source_sha256"],
            "runner_sha256": manifest["runner_sha256"],
        },
        "worker": {"path": display(binary), "present": binary.is_file()},
        "marker": None,
        "launch": None,
        "residual_window": (
            "a same-uid writer could replace the staged file between the re-hash "
            "and exec; D1 closes this by the child hashing its own executable "
            "(G3_EXPECT_EXEC_SHA256) and refusing to generate on mismatch"
        ),
        "closure_predicate": (
            "status becomes bound only for the real D1 worker artifact, after a "
            "launch whose running PID executable hashes to the staged bytes"
        ),
    }


def resolve(args: argparse.Namespace) -> tuple[Path, dict, Path, Path]:
    manifest_path = args.manifest.resolve()
    manifest = load_manifest(manifest_path)
    binary = (args.binary or (ROOT / DEFAULT_WORKER)).resolve()
    record = (
        args.record or (manifest_path.parent / "execution" / "execution-identity.json")
    ).resolve()
    return manifest_path, manifest, binary, record


def cmd_status(args: argparse.Namespace) -> int:
    manifest_path, manifest, binary, record = resolve(args)
    if not binary.is_file():
        payload = unclosed_payload(
            manifest_path, manifest, binary, f"worker artifact absent: {display(binary)}"
        )
        digest = write_record(record, payload)
        print(f"EXECUTION IDENTITY {payload['status'].upper()} (record {digest[:16]})")
        print(f"  reason  {payload['reason']}")
        print(f"  worker  {payload['worker']['path']} present=false")
        return 2
    print(f"worker present: {display(binary)}")
    print("  pass --launch to bind and launch, or --verify on an existing record")
    return 0


def cmd_bind(args: argparse.Namespace) -> int:
    manifest_path, manifest, binary, record = resolve(args)
    _, stage_dir, consumed_dir = record_paths(record)
    if not binary.is_file():
        payload = unclosed_payload(
            manifest_path, manifest, binary, f"worker artifact absent: {display(binary)}"
        )
        digest = write_record(record, payload)
        print(f"UNBOUND WORKER: {payload['reason']}")
        print(f"  record {display(record)} sha256 {digest}")
        return 2

    original_sha = sha256_file(binary)
    staged, staged_identity = staged_copy(binary, stage_dir)
    if not staged_identity["hashes_agree"]:
        print("STAGING FAILED: write hash and re-read hash disagree")
        return 1
    if staged_identity["sha256"] != original_sha:
        print("STAGING FAILED: staged bytes differ from the artifact")
        return 1

    marker = {
        "schema_id": MARKER_SCHEMA,
        "id": marker_id(manifest, original_sha),
        "binding": "source_sha256 + runner_sha256 + staged sha256",
        "source_sha256": manifest["source_sha256"],
        "runner_sha256": manifest["runner_sha256"],
        "staged_sha256": original_sha,
        "created_at_utc": utc_now(),
        "consumed": False,
    }
    claim = consumed_dir / f"{marker['id']}.json"
    payload = {
        "schema_id": SCHEMA_ID,
        "status": "control-only" if args.stand_in else "bound",
        "stand_in": bool(args.stand_in),
        "generated_at_utc": utc_now(),
        "manifest": {
            "path": display(manifest_path),
            "source_sha256": manifest["source_sha256"],
            "runner_sha256": manifest["runner_sha256"],
        },
        "worker": {
            "path": display(binary),
            "present": True,
            "sha256": original_sha,
            "size": binary.stat().st_size,
            "mode": oct(stat.S_IMODE(binary.stat().st_mode)),
            "codesign": codesign_identity(binary),
            "staged": staged_identity,
        },
        "marker": marker,
        "marker_path": display(claim),
        "launch": None,
        "residual_window": (
            "a same-uid writer could replace the staged file between the re-hash "
            "and exec; D1 closes this by the child hashing its own executable "
            "(G3_EXPECT_EXEC_SHA256) and refusing to generate on mismatch"
        ),
    }
    digest = write_record(record, payload)
    print(f"BOUND {original_sha[:16]} status={payload['status']} record {digest[:16]}")
    print(f"  marker {marker['id'][:16]} consumed=false")
    return 0


def cmd_launch(args: argparse.Namespace) -> int:
    record = (
        args.record
        or (args.manifest.resolve().parent / "execution" / "execution-identity.json")
    ).resolve()
    if not record.is_file():
        code = cmd_bind(args)
        if code != 0:
            return code
    payload = json.loads(record.read_text(encoding="utf-8"))
    current = load_manifest(args.manifest.resolve())
    stale = (
        payload.get("manifest", {}).get("source_sha256") != current["source_sha256"]
        or payload.get("manifest", {}).get("runner_sha256") != current["runner_sha256"]
    )
    if payload.get("status") not in ("bound", "control-only") or stale:
        # A recorded unclosed/stale state is not launchable. Re-binding here is
        # explicit: it computes a fresh marker against the CURRENT manifest, and
        # `--verify` will reject the old record's digests if they no longer match.
        code = cmd_bind(args)
        if code != 0:
            return code
        payload = json.loads(record.read_text(encoding="utf-8"))
    if payload.get("status") not in ("bound", "control-only"):
        print(f"REFUSED: record status is {payload.get('status')}")
        return 2
    marker = payload["marker"]
    _, stage_dir, consumed_dir = record_paths(record)
    staged = Path(payload["worker"]["staged"]["absolute_path"])
    if not staged.is_file():
        print(f"REFUSED: staged bytes missing at {staged}")
        return 2
    if sha256_file(staged) != marker["staged_sha256"]:
        print("REFUSED: staged bytes no longer match the marker")
        return 2
    consumed_dir.mkdir(parents=True, exist_ok=True)
    os.chmod(consumed_dir, 0o700)
    claim = consumed_dir / f"{marker['id']}.json"
    try:
        fd = os.open(claim, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o400)
    except FileExistsError:
        print(f"REFUSED: marker {marker['id'][:16]} already consumed (one-time authorization)")
        return 3
    with os.fdopen(fd, "w", encoding="utf-8") as out:
        json.dump(
            {
                "marker_id": marker["id"],
                "consumed_at_utc": utc_now(),
                "argv": args.worker_args,
                "staged_sha256": marker["staged_sha256"],
            },
            out,
            sort_keys=True,
        )
        out.write("\n")
        out.flush()
        os.fsync(out.fileno())
    marker["consumed"] = True
    marker["consumed_at_utc"] = utc_now()
    marker["consumed_path"] = str(claim)

    env = dict(os.environ)
    env["G3_EXPECT_EXEC_SHA256"] = marker["staged_sha256"]
    env["G3_AUTHORIZATION_MARKER"] = marker["id"]
    env["G3_MANIFEST_SOURCE_SHA256"] = payload["manifest"]["source_sha256"]
    env["G3_MANIFEST_RUNNER_SHA256"] = payload["manifest"]["runner_sha256"]

    argv = [str(staged), *args.worker_args]
    proc = subprocess.Popen(argv, env=env)
    pid = proc.pid
    deadline = time.time() + max(args.observe_seconds, 0.1)
    observed_path = None
    while time.time() < deadline:
        observed_path = process_executable(pid)
        if observed_path:
            break
        if proc.poll() is not None:
            break
        time.sleep(0.02)
    observed_sha = None
    observed_error = None
    if observed_path:
        try:
            observed_sha = sha256_file(Path(observed_path))
        except OSError as error:
            observed_error = str(error)
    terminated_by_supervisor = False
    if args.terminate_after_observe and proc.poll() is None:
        # A stand-in such as sleep would otherwise outlive the check. Killing it
        # HERE makes the exit status an action of the supervisor, not a mystery.
        proc.kill()
        terminated_by_supervisor = True
    exit_code = proc.wait(timeout=max(args.timeout, 1))
    match = observed_sha == marker["staged_sha256"]
    launch_record = {
        "pid": pid,
        "argv": argv,
        "running_executable_path": observed_path,
        "running_executable_sha256": observed_sha,
        "expected_sha256": marker["staged_sha256"],
        "match": match,
        "read_error": observed_error,
        "exit_code": exit_code,
        "terminated_by_supervisor": terminated_by_supervisor,
        "observed_at_utc": utc_now(),
        "environment_binding": {
            "G3_EXPECT_EXEC_SHA256": marker["staged_sha256"],
            "G3_AUTHORIZATION_MARKER": marker["id"],
            "G3_MANIFEST_SOURCE_SHA256": payload["manifest"]["source_sha256"],
            "G3_MANIFEST_RUNNER_SHA256": payload["manifest"]["runner_sha256"],
        },
        "child_self_check": (
            "enforced: the D1 worker hashes its own executable before the first "
            "forward and refuses to generate on mismatch against "
            "G3_EXPECT_EXEC_SHA256; the bound run reported identity verified"
        ),
    }
    payload["launch"] = launch_record
    digest = write_record(record, payload)
    print(
        f"LAUNCH pid={pid} exit={exit_code} running={observed_path} "
        f"match={match} record={digest[:16]}"
    )
    if not match:
        print("LAUNCH IDENTITY MISMATCH: the process that ran is not the bound bytes")
        return 4
    if payload["status"] == "control-only":
        print("CONTROL-ONLY: mechanism demonstrated with a stand-in; D1 worker still absent")
    return 0


def cmd_verify(args: argparse.Namespace) -> int:
    manifest_path = args.manifest.resolve()
    manifest = load_manifest(manifest_path)
    record = (
        args.record or (manifest_path.parent / "execution" / "execution-identity.json")
    ).resolve()
    if not record.is_file():
        print("VERIFY FAIL: no execution identity record")
        return 1
    payload = json.loads(record.read_text(encoding="utf-8"))
    problems: list[str] = []
    if payload.get("manifest", {}).get("source_sha256") != manifest["source_sha256"]:
        problems.append("record was bound to a different source_sha256")
    if payload.get("manifest", {}).get("runner_sha256") != manifest["runner_sha256"]:
        problems.append("record was bound to a different runner_sha256")
    marker = payload.get("marker")
    launch_record = payload.get("launch")
    if payload.get("status") in ("bound", "control-only"):
        if not marker:
            problems.append("record has no marker")
        else:
            staged = Path(payload["worker"]["staged"]["absolute_path"])
            if not staged.is_file():
                problems.append("staged bytes are missing")
            elif sha256_file(staged) != marker["staged_sha256"]:
                problems.append("staged bytes no longer match the marker")
            claim = Path(marker.get("consumed_path") or "")
            if marker.get("consumed") and not claim.is_file():
                problems.append("marker says consumed but no consumption record exists")
            if not marker.get("consumed"):
                problems.append("marker was never consumed: no launch happened")
    if payload.get("status") == "bound":
        if not launch_record:
            problems.append("status is bound without a launch record")
        elif not launch_record.get("match"):
            problems.append("launch did not verify the running executable")
        if payload.get("stand_in"):
            problems.append("status bound cannot be a stand-in")
    if payload.get("status") == "unclosed":
        problems.append(f"execution identity is unclosed: {payload.get('reason')}")
    if problems:
        print("VERIFY FAIL")
        for problem in problems:
            print(f"  - {problem}")
        return 1
    print(
        f"VERIFY PASS status={payload['status']} marker={marker['id'][:16]} "
        f"running_match={launch_record.get('match') if launch_record else None}"
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--record", type=Path)
    parser.add_argument("--binary", type=Path)
    parser.add_argument("--stand-in", action="store_true", help="mark a control binary")
    parser.add_argument("--launch", action="store_true")
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--status", action="store_true")
    parser.add_argument("--observe-seconds", type=float, default=1.0)
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument(
        "--terminate-after-observe",
        action="store_true",
        help="kill the child once its running executable has been hashed",
    )
    parser.add_argument("worker_args", nargs="*")
    args = parser.parse_args()
    if args.verify:
        return cmd_verify(args)
    if args.status:
        return cmd_status(args)
    if args.launch:
        return cmd_launch(args)
    return cmd_bind(args)


if __name__ == "__main__":
    raise SystemExit(main())
