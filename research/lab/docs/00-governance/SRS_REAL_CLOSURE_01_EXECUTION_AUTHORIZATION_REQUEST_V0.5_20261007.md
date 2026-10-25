# SRS-REAL-CLOSURE-01 — EXECUTION Authorization Request v0.5 — Corrected Provenance and Cross-Binding Closure

> **Status:** OPENED / SUBMITTED FOR HUMAN AUTHORIZATION REVIEW — NO STAGE
> AUTHORIZED
> **Date:** 2026-10-07
> **Human opening authorization, exact form:** “授权起草一份新的 corrected
> EXECUTION Request / record set，以处理 A 类 exact-artifact provenance 问题
> 及 B 类 cross-binding mismatch” — authorizes opening this Request only. It
> does not approve A+B+C, authorize a campaign, create SAR/OAR records, or
> authorize implementation.
> **Supersedes:** EXECUTION Authorization Request v0.4
> @ `79ce4e3d313f13b66f946e2ed1e948745e4a1e82`
> (blob `0b892d66…`; SHA256 `d64e4ebc…`), whose campaign authorization was not
> used because EXEC-002 stopped INVALID before approval.
> **Review basis:** EXEC-002 forensic audit @ `7b176d1…`. Candidate A: exact
> artifact execution chain not established. Candidate B: pre-authorization
> `_001/V1` ↔ `_002/V2` cross-binding mismatch.
> **Requested authorization set upon separate APPROVE A+B+C:** four new records:
> `EXECUTION_PROVENANCE_AND_BINDING_CLOSURE_RECORD_003`, `EXECUTION SAR 003`,
> `IS_MUTATION SAR 003`, and `OBSERVER AUTHORIZATION RECORD 003`.
> **No run authority exists from opening this Request.**

## 1. Authorization-chain history

```text
79ce4e3  EXECUTION Request v0.4;
86df16b  EXECUTION/IS_MUTATION/OAR records 002;
9966d31  exact execution repository state for EXEC-002;
c46537d  EXEC-002 INVALID evidence;
7b176d1  EXEC-002 forensic audit;
this governing commit introduces Request v0.5.
```

The v0.3 campaign, v0.4 authorization opportunity, and `c454687…` records are
consumed and not reusable. No old budget is revived.

## 2. Exact inherited bindings

All bindings in Request v0.4 §2, §2.1, and §2.2 are inherited unchanged,
including Manifest v3, Completion Record v3, Acceptance Record 002, all eleven
fixture artifacts, and the three T-IMPL-01 canonical sources. The exact
content bindings remain those stated in Request v0.4 @ `79ce4e3…`.

## 3. Exact execution state

```text
exact_execution_repository_commit =
  9966d311e7e52ab3f5ca828e593ea569cddb008e;

boundary = later governance commits introducing this Request or future
  records are authorization objects, not execution state;

fixture/source/experiment implementation = unchanged from 9966d31.
```

## 4. R-A closure — exact-artifact execution provenance

The v0.4 failure class was `returncode = 0` with mandatory evidence absent.
Therefore this Request adds `EXECUTION_PROVENANCE_RECORDER_003`, defined
byte-for-byte in Appendix A, as a mandatory external launch/evidence-completeness
governance recorder.

```text
provenance_recorder_identity =
  SRS-REAL-CLOSURE-01-EXECUTION_PROVENANCE_RECORDER_003;
provenance_recorder_sha256 =
  492f6f0e5c4a7207a04365c008c0f0a61b841a621e1109c9ead0a88cd6438a79;
recorder_runtime = exact Python runtime bound by Request v0.4 §5.3;
provenance_output =
  runs/<run_id>/execution_provenance.json.

mandatory launch rule:
  driver and observer shall be launched only through
  EXECUTION_PROVENANCE_RECORDER_003;
  each command shall use an exact absolute executable path and exact argv;
  recorder shall record executable device/inode/size/SHA256, argv, cwd,
  PID-adjacent Python runtime facts, monotonic start/end, returncode,
  stdout/stderr, and required artifact existence/hash;
  missing required artifact or nonzero expected-return mismatch →
  CAMPAIGN_EVIDENCE_ARTIFACTS_MISSING → INVALID.

prohibited:
  direct shell launch of driver/observer;
  PATH-resolved executables;
  post-hoc provenance reconstruction;
  returncode treated as evidence without recorder manifest.
```

This is an external evidence-governance recorder. It does not modify runner,
observer, fixture, experiment design, or repository sources.

## 5. R-B closure — authorization cross-binding record

Exact runner state `9966d31` embeds legacy instrument constants:

```text
OBSERVER_AUTHORIZATION_IDENTITY =
  SRS_REAL_CLOSURE_01_OBSERVER_AUTHORIZATION_RECORD_001;
CHANNEL_UNIVERSE_IDENTITY =
  SRS-REAL-CLOSURE-01-CHANNEL-UNIVERSE-V1.
```

This Request requires a new `EXECUTION_PROVENANCE_AND_BINDING_CLOSURE_RECORD_003`
on approval. That record shall explicitly bind the campaign to:

```text
authorized_observer_authorization_identity =
  SRS_REAL_CLOSURE_01_OBSERVER_AUTHORIZATION_RECORD_003;
authorized_channel_universe_identity =
  SRS-REAL-CLOSURE-01-CHANNEL-UNIVERSE-V2;
legacy_runner_embedded_observer_identity =
  SRS_REAL_CLOSURE_01_OBSERVER_AUTHORIZATION_RECORD_001;
legacy_runner_embedded_channel_identity =
  SRS-REAL-CLOSURE-01-CHANNEL-UNIVERSE-V1;
```

Raw embedded values remain preserved in evidence and must be reported as
legacy constants. The closure record is an authorization traceability mapping;
it does not erase them, modify the runner, or reinterpret semantic results.

## 6. New records and budget

Upon separate `APPROVE A+B+C` of this Request, create four new records:

```text
EXECUTION_PROVENANCE_AND_BINDING_CLOSURE_RECORD_003;
EXECUTION SAR 003;
IS_MUTATION SAR 003;
OBSERVER AUTHORIZATION RECORD 003.
```

All shall exact-bind execution repository commit `9966d31`. The Request grants
one new independent campaign budget. The v0.3/v0.4 budgets and all prior
records remain consumed/non-reusable.

## 7. Inherited campaign and boundaries

The frozen sequence, effect sets, filesystem scope, no-network rule, D-SEC-1
supplemental post-exit semantics, D-SEC-2 capture-pipe classification, §9 v3
read-instance contract, ACCP-1 coverage boundary, expected environment identity
`ad2abb68…`, expected decisions, and stop doctrine are inherited unchanged from
Request v0.4. The only substantive additions are Sections 4 and 5 plus the new
record set and budget.

`EXECUTION`, `IS_MUTATION`, Observer campaign, runner repair, fixture repair,
and implementation remain NOT AUTHORIZED by opening this Request.

## 8. Required Human decision

```text
APPROVE A+B+C
  create the four records above; then execute one frozen campaign through
  EXECUTION_PROVENANCE_RECORDER_003 and STOP for evidence audit.

REVISE REQUEST   return with registered defects.
DENY REQUEST     do not execute.
```

Core claim `ES1 -> IS(SRS) -> independent ES2 lawful reuse` remains
**NOT ESTABLISHED**.

## Appendix A — EXECUTION_PROVENANCE_RECORDER_003 exact source

The exact UTF-8 source below has SHA256
`492f6f0e5c4a7207a04365c008c0f0a61b841a621e1109c9ead0a88cd6438a79`.

```python
#!/usr/bin/env python3
"""SRS-REAL-CLOSURE-01 EXECUTION_PROVENANCE_RECORDER_003.

Reads a provenance plan, executes each command by exact absolute executable,
records executable identity/argv/process facts, and fails closed if any declared
artifact is absent after the command exits. This recorder produces governance
evidence; it does not interpret semantic results.
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


def artifact_manifest(paths):
    out = {}
    for label, raw in paths.items():
        p = pathlib.Path(raw)
        out[label] = {
            "path": str(p),
            "exists": p.exists(),
            "size_bytes": p.stat().st_size if p.exists() else None,
            "sha256": sha256_file(p) if p.is_file() else None,
        }
    return out


def main():
    if len(sys.argv) != 2:
        print("usage: execution_provenance_recorder.py PLAN_JSON", file=sys.stderr)
        return 64
    plan_path = pathlib.Path(sys.argv[1]).resolve()
    plan = json.loads(plan_path.read_text(encoding="utf-8"))
    started_wall = time.time_ns()
    records = []
    overall = True
    for item in plan["commands"]:
        name = item["name"]
        args = item["argv"]
        if not os.path.isabs(args[0]):
            raise RuntimeError("EXECUTABLE_PATH_NOT_ABSOLUTE: " + args[0])
        ident = executable_identity(args[0])
        expected = item.get("expected_executable_sha256")
        if expected and ident["sha256"] != expected:
            raise RuntimeError("EXECUTABLE_IDENTITY_MISMATCH: " + name)
        before = artifact_manifest(item.get("required_absent_before", {}))
        started_mono = time.time_ns()
        completed = subprocess.run(
            args,
            cwd=item.get("cwd"),
            env=item.get("env"),
            capture_output=True,
            text=True,
            check=False,
        )
        ended_mono = time.time_ns()
        after = artifact_manifest(item.get("required_after", {}))
        missing = [
            label for label, fact in after.items()
            if not fact["exists"] or not fact["sha256"]
        ]
        command_ok = completed.returncode == item.get(
            "expected_returncode", 0
        ) and not missing
        overall = overall and command_ok
        rec = {
            "name": name,
            "argv": args,
            "cwd": item.get("cwd"),
            "executable_identity": ident,
            "expected_executable_sha256": expected,
            "python_executable": sys.executable,
            "python_version": sys.version,
            "platform_platform": platform.platform(),
            "started_monotonic_ns": started_mono,
            "ended_monotonic_ns": ended_mono,
            "returncode": completed.returncode,
            "expected_returncode": item.get("expected_returncode", 0),
            "stdout_text": completed.stdout,
            "stderr_text": completed.stderr,
            "required_absent_before": before,
            "required_after": after,
            "missing_required_after": missing,
            "command_ok": command_ok,
        }
        records.append(rec)
    finished_wall = time.time_ns()
    result = {
        "recorder_identity": "SRS-REAL-CLOSURE-01-EXECUTION_PROVENANCE_RECORDER_003",
        "plan_path": str(plan_path),
        "plan_sha256": sha256_file(plan_path),
        "started_wall_ns": started_wall,
        "finished_wall_ns": finished_wall,
        "overall_ok": overall,
        "commands": records,
    }
    out = pathlib.Path(plan["output_path"])
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    print("execution provenance written:", out)
    return 0 if overall else 1


if __name__ == "__main__":
    sys.exit(main())
```
