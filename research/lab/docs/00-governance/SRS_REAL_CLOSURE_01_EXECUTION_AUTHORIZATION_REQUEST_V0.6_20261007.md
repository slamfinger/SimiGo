# SRS-REAL-CLOSURE-01 — EXECUTION Authorization Request v0.6 — Corrected Provenance, CWD/Seed Binding, and Cross-Binding Closure

> **Status:** OPENED / SUBMITTED FOR HUMAN AUTHORIZATION REVIEW — NO STAGE
> AUTHORIZED
> **Date:** 2026-10-07
> **Human opening authorization, exact form:** “授权新的 corrected Request /
> records” — authorizes opening this corrected Request only. It does not approve
> A+B+C, create SAR/OAR records, authorize a campaign, or revive any old budget.
> **Supersedes:** EXECUTION Authorization Request v0.5
> @ `888a6a75022ffd2a84f5126055cef883c303c111`
> (blob `45baf0b8…`; SHA256 `bb3b9e42…`). v0.5 and records 003 @ `bda7829…`
> were consumed by INVALID campaign `exec-003-9966d31` and are not reusable.
> **Review basis:** EXEC-003 Human Evidence Audit @ `7b176d1…`, audit record
> @ `266e953…`, and canonical evidence @ `a50ff8b…`.
> **Requested authorization set upon separate APPROVE A+B+C:** four new records:
> `EXECUTION_PROVENANCE_AND_BINDING_CLOSURE_RECORD_004`, `EXECUTION SAR 004`,
> `IS_MUTATION SAR 004`, and `OBSERVER AUTHORIZATION RECORD 004`.
> **No run authority exists from opening this Request.**

## 1. Exact prior chain

```text
9966d31  exact execution repository state for EXEC-002/003;
888a6a7  Request v0.5;
bda7829  records 003;
a50ff8b  EXEC-003 INVALID evidence;
266e953  EXEC-003 Human Evidence Audit;
this governing commit introduces Request v0.6.
```

The execution repository state remains `9966d31`; later governance commits are
not execution state.

## 2. Registered defects closed by this Request

```text
Defect B / causally earlier =
  EXECUTION_CWD_AND_SEED_PATH_BINDING_DEFECT;
  driver cwd was host repository root while exact execution state was a
  detached 9966d31 worktree; frozen `tau1.seed_path =
  fixture/inputs/D.md` did not resolve; materialize exited 1 before any IS
  write.

Defect A / registered primary stop =
  PROVENANCE_RECORDER_OUTPUT_PATH_BINDING_DEFECT;
  provenance plan set `output_path` to the run directory; EPR003 raised
  IsADirectoryError after driver completion; execution_provenance.json was
  absent.
```

## 3. Inherited bindings

Request v0.5 §2 and its inherited Request v0.4 bindings remain unchanged:
Manifest v3, Completion Record v3, Acceptance Record 002, eleven fixture
artifacts, T-IMPL-01 canonical sources, deterministic adapter runtime
`e88c996b…`, ENV-PROBE-V1 with corrected expected environment identity
`ad2abb68…`, D-SEC-1 supplemental post-exit semantics, D-SEC-2 capture-pipe
classification, §9 v3 read-instance contract, ACCP-1 coverage boundary, frozen
sequence, expected decisions, effect sets, filesystem scope, no-network rule,
and stop doctrine.

The ten fixture artifacts other than `es_runner.py` remain unchanged; the exact
runner remains `9966d31` blob `875cb1d9…` / SHA256 `bc393362…`. No runner,
fixture, observer, adapter, or experiment implementation change is requested.

## 4. R-A closure — EXECUTION_PROVENANCE_RECORDER_004

EPR004 replaces EPR003 only as external governance evidence tooling. Its exact
source is Appendix A and it shall be reconstructed outside the repository.

```text
provenance_recorder_identity =
  SRS-REAL-CLOSURE-01-EXECUTION_PROVENANCE_RECORDER_004;
provenance_recorder_sha256 =
  c0aff998aabada80c87d6eec1cebdf35292e16f455e72389ec36e71ea99ee262.
```

Mandatory preflight and launch contract:

```text
output_path =
  runs/<run_id>/execution_provenance.json;
  shall be absolute, named execution_provenance.json, absent or a regular
  file before launch, with an existing parent directory; directory or symlink
  target → fail closed.

worktree_root =
  exact detached worktree of 9966d31;
  git rev-parse HEAD^{} shall equal
  9966d311e7e52ab3f5ca828e593ea569cddb008e.

expected_cwd =
  <worktree_root>/docs/02-evidence/srs-real-closure-01;
  every command cwd shall equal this exact resolved path.

exact_input_bindings =
  fixture/inputs/D.md → SHA256
    806fffadef09d3ad491d75c6b42738e99626ee1961ed1aecf2d593aefd55980c;
  fixture/inputs/D_prime.md → SHA256
    8553f52449b67de21021bb50ad6380c455bf686ee2a06cc77ed51e9f30060955;
  each shall resolve beneath the exact worktree and match SHA256 before
  launch.

driver/observer execution:
  exact absolute Python runtime, exact absolute runner/observer paths,
  exact argv, and required outputs shall pass through EPR004;
  missing required artifact, wrong executable/cwd/input identity, or
  unexpected returncode → fail closed → INVALID.
```

No repository source is modified by this recorder contract.

## 5. R-B closure — cross-binding record 004

On approval,
`EXECUTION_PROVENANCE_AND_BINDING_CLOSURE_RECORD_004` shall explicitly map:

```text
legacy_runner_embedded_observer_identity =
  SRS_REAL_CLOSURE_01_OBSERVER_AUTHORIZATION_RECORD_001;
legacy_runner_embedded_channel_identity =
  SRS-REAL-CLOSURE-01-CHANNEL-UNIVERSE-V1;

authorized_observer_authorization_identity =
  SRS_REAL_CLOSURE_01_OBSERVER_AUTHORIZATION_RECORD_004;
authorized_channel_universe_identity =
  SRS-REAL-CLOSURE-01-CHANNEL-UNIVERSE-V2.
```

The legacy constants remain preserved in raw evidence. The closure record is
authorization traceability only; it does not alter runner behavior, erase
history, or reinterpret semantic results.

## 6. New records and budget

Upon separate `APPROVE A+B+C`, create four new records:

```text
EXECUTION_PROVENANCE_AND_BINDING_CLOSURE_RECORD_004;
EXECUTION SAR 004;
IS_MUTATION SAR 004;
OBSERVER AUTHORIZATION RECORD 004.
```

All shall exact-bind execution repository commit `9966d31`. This Request
grants one new independent campaign budget. The v0.3/v0.4/v0.5 budgets and all
prior records remain consumed/non-reusable.

## 7. Required Human decision

```text
APPROVE A+B+C
  create the four records above; execute one frozen campaign through EPR004;
  STOP for evidence audit.

REVISE REQUEST   return with registered defects.
DENY REQUEST     do not execute.
```

Opening this Request authorizes no stage. Core claim
`ES1 -> IS(SRS) -> independent ES2 lawful reuse` remains **NOT ESTABLISHED**.

## Appendix A — EXECUTION_PROVENANCE_RECORDER_004 exact source

The exact UTF-8 source below has SHA256
`c0aff998aabada80c87d6eec1cebdf35292e16f455e72389ec36e71ea99ee262`.

```python
#!/usr/bin/env python3
"""SRS-REAL-CLOSURE-01 EXECUTION_PROVENANCE_RECORDER_004.

Fail-closed provenance launcher for exact-state campaigns. It validates the
output path, exact repository commit, exact command cwd, exact-state input
bindings, executable identity, required outputs, and process results before
reporting success. It produces governance evidence only.
"""
import hashlib
import json
import os
import pathlib
import platform
import subprocess
import sys
import time


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def executable_identity(path):
    st = os.stat(path, follow_symlinks=False)
    return {
        "absolute_path": os.path.realpath(path),
        "device_id": st.st_dev,
        "inode": st.st_ino,
        "size_bytes": st.st_size,
        "sha256": sha256_file(path),
    }


def artifact_fact(path):
    p = pathlib.Path(path)
    return {
        "path": str(p),
        "exists": p.exists(),
        "is_regular_file": p.is_file(),
        "size_bytes": p.stat().st_size if p.is_file() else None,
        "sha256": sha256_file(p) if p.is_file() else None,
    }


def preflight_output_path(raw):
    p = pathlib.Path(raw)
    if not p.is_absolute():
        raise RuntimeError("EPR004_OUTPUT_PATH_NOT_ABSOLUTE")
    if p.name != "execution_provenance.json":
        raise RuntimeError("EPR004_OUTPUT_PATH_NAME_INVALID")
    if p.exists() or p.is_symlink():
        raise RuntimeError("EPR004_OUTPUT_PATH_ALREADY_EXISTS")
    if not p.parent.is_dir():
        raise RuntimeError("EPR004_OUTPUT_PATH_PARENT_INVALID")
    return p


def preflight_exact_repository(root, expected_commit):
    p = pathlib.Path(root)
    if not p.is_dir():
        raise RuntimeError("EPR004_WORKTREE_ROOT_INVALID")
    got = subprocess.check_output(
        ["git", "-C", str(p), "rev-parse", "HEAD^{}"], text=True
    ).strip()
    if got != expected_commit:
        raise RuntimeError("EPR004_EXACT_REPOSITORY_COMMIT_MISMATCH")


def preflight_inputs(cwd, expected_cwd, worktree_root, bindings):
    cwd_path = pathlib.Path(cwd).resolve()
    expected_path = pathlib.Path(expected_cwd).resolve()
    if cwd_path != expected_path:
        raise RuntimeError("EPR004_COMMAND_CWD_MISMATCH")
    root_path = pathlib.Path(worktree_root).resolve()
    docs_root = (root_path / "docs/02-evidence/srs-real-closure-01").resolve()
    if expected_path != docs_root:
        raise RuntimeError("EPR004_EXPECTED_CWD_NOT_DOCS_ROOT")
    facts = {}
    for label, binding in bindings.items():
        raw = binding["relative_path"]
        if pathlib.PurePosixPath(raw).is_absolute():
            raise RuntimeError("EPR004_INPUT_PATH_NOT_RELATIVE")
        candidate = (cwd_path / raw).resolve()
        try:
            candidate.relative_to(root_path)
        except ValueError as exc:
            raise RuntimeError("EPR004_INPUT_PATH_ESCAPES_EXACT_STATE") from exc
        fact = artifact_fact(candidate)
        if not fact["is_regular_file"]:
            raise RuntimeError("EPR004_INPUT_BINDING_MISSING: " + label)
        if fact["sha256"] != binding["expected_sha256"]:
            raise RuntimeError("EPR004_INPUT_BINDING_MISMATCH: " + label)
        facts[label] = {
            "relative_path": raw,
            "resolved_path": str(candidate),
            "expected_sha256": binding["expected_sha256"],
            **fact,
        }
    return facts


def main():
    if len(sys.argv) != 2:
        print("usage: execution_provenance_recorder_004.py PLAN_JSON", file=sys.stderr)
        return 64
    plan_path = pathlib.Path(sys.argv[1]).resolve()
    plan = json.loads(plan_path.read_text(encoding="utf-8"))
    output = preflight_output_path(plan["output_path"])
    preflight_exact_repository(
        plan["worktree_root"], plan["exact_execution_repository_commit"]
    )
    expected_cwd = plan["expected_cwd"]
    started_wall = time.time_ns()
    records = []
    overall = True
    for item in plan["commands"]:
        name = item["name"]
        args = item["argv"]
        if not os.path.isabs(args[0]):
            raise RuntimeError("EPR004_EXECUTABLE_PATH_NOT_ABSOLUTE")
        cwd = item["cwd"]
        input_facts = preflight_inputs(
            cwd,
            expected_cwd,
            plan["worktree_root"],
            item.get("exact_input_bindings", {}),
        )
        ident = executable_identity(args[0])
        expected_exec = item.get("expected_executable_sha256")
        if expected_exec and ident["sha256"] != expected_exec:
            raise RuntimeError("EPR004_EXECUTABLE_IDENTITY_MISMATCH: " + name)
        started_mono = time.time_ns()
        completed = subprocess.run(
            args,
            cwd=cwd,
            env=item.get("env"),
            capture_output=True,
            text=True,
            check=False,
        )
        ended_mono = time.time_ns()
        after = {
            label: artifact_fact(path)
            for label, path in item.get("required_after", {}).items()
        }
        missing = [
            label for label, fact in after.items()
            if not fact["exists"] or not fact["is_regular_file"] or not fact["sha256"]
        ]
        command_ok = (
            completed.returncode == item.get("expected_returncode", 0)
            and not missing
        )
        overall = overall and command_ok
        records.append({
            "name": name,
            "argv": args,
            "cwd": cwd,
            "expected_cwd": expected_cwd,
            "worktree_root": plan["worktree_root"],
            "exact_execution_repository_commit":
                plan["exact_execution_repository_commit"],
            "exact_input_bindings": input_facts,
            "executable_identity": ident,
            "expected_executable_sha256": expected_exec,
            "python_executable": sys.executable,
            "python_version": sys.version,
            "platform_platform": platform.platform(),
            "started_monotonic_ns": started_mono,
            "ended_monotonic_ns": ended_mono,
            "returncode": completed.returncode,
            "expected_returncode": item.get("expected_returncode", 0),
            "stdout_text": completed.stdout,
            "stderr_text": completed.stderr,
            "required_after": after,
            "missing_required_after": missing,
            "command_ok": command_ok,
        })
    result = {
        "recorder_identity": "SRS-REAL-CLOSURE-01-EXECUTION_PROVENANCE_RECORDER_004",
        "plan_path": str(plan_path),
        "plan_sha256": sha256_file(plan_path),
        "output_path": str(output),
        "worktree_root": plan["worktree_root"],
        "expected_cwd": expected_cwd,
        "exact_execution_repository_commit":
            plan["exact_execution_repository_commit"],
        "started_wall_ns": started_wall,
        "overall_ok": overall,
        "commands": records,
    }
    output.write_text(
        json.dumps(result, sort_keys=True, indent=2) + "\n", encoding="utf-8"
    )
    print("execution provenance written:", output)
    return 0 if overall else 1


if __name__ == "__main__":
    sys.exit(main())
```
