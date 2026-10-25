# R-C1 Attempt #4 Evidence Audit

> **ARCHIVED** 2026-10-20 · line: 通用治理 / 其他 · original: docs/00-governance/SIMIGO_LAB_RC1_ATTEMPT4_EVIDENCE_AUDIT_20261003.md
> Evidence status: unchanged (content frozen; moved only)


Date: 2026-10-03  
Status: `LAYER 1 EVIDENCE INTEGRITY = PRESERVED`  
Run root:
`docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375`  
Implementation baseline: `569fe540d1ff`

## 1. Lifecycle integrity

```text
old process → external overwrite → termination → fresh process → continuation
```

Evidence:

```text
C-A old PID = 57377; fresh PID = 57378
C-B old PID = 57396; fresh PID = 57405
C-C old PID = 57407; fresh PID = 57408
old evidence = invocation-evidence.jsonl
fresh evidence = continuation-evidence.json
old/fresh termination/start markers preserved
```

All old/fresh PIDs are distinct. No fresh evidence overwrote old evidence.

## 2. Physical-change integrity

Each arm recorded the declared external overwrite:

```text
before = alpha=17;mode=quiet
after  = alpha=42;mode=active
before SHA-256 = 3ab5fbd4c17336875f0e8939cc4caa97df9731a2e6e99fb0e6d0908db6408d44
after  SHA-256 = cec1d7b02f402b1924a1f37ae2e193240bd17816208b0d90dc49926eeca3973a
```

Per-arm overwrite references:

```text
RC1-A4-C-A-EXTERNAL-001
RC1-A4-C-B-EXTERNAL-001
RC1-A4-C-C-EXTERNAL-001
```

## 3. Carrier separation

```text
C-A: no Information/Relation carrier
C-B: information.sqlite present; relation.json absent
C-C: information.sqlite present; relation.json present
```

C-C persisted:

```text
subject  = I-S1
predicate = observed-change-of
object   = I-S0
```

Fresh C-C carrier reads were:

```text
relation → I-S1 → I-S0 → I-TASK → I-PROGRESS
```

No C-B Relation read occurred.

## 4. Forbidden-channel runtime observations

All runtime audit observations for all arms returned `passed = true`:

```text
old_process_memory
old_model_context
old_execution_core_runtime
undeclared_filesystem_scan
environment_as_answer_input
harness_answer_injection
implicit_cache
```

This is runtime execution evidence only; it is not a universal security claim.

## 5. Nonblocking format observation

`invocation-evidence.jsonl` contains one pretty-printed JSON object rather than
newline-delimited JSON. The object parses successfully and old/fresh evidence
remain separate. Because the no-modification rule was active, this is recorded
as a nonblocking evidence-format observation, not repaired during the run.
