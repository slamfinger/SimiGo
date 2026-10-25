# C-Impl Revision Audit — `aca117163904`

Date: 2026-10-03  
Status: `C-IMPL REVISION AUDIT FAIL / REVISE REQUIRED`  
Baseline: `1771000b86d3`  
Audit object: [`aca117163904`](https://github.com/slamfinger/SimiGo-Lab/commit/aca117163904)  
Study source SHA-256:
`b457bc79eb974c0665808fac5fc952ba2fe97512caf7bd91d83497ba22bf6250`  
C-Execute: `NOT AUTHORIZED`  
R-C1: `NOT RUN`

## 1. Mechanical verification

```text
Release build                         = PASS
ExecutionCore tests                   = 4/4 PASS
CContinuation tests                   = 4/4 PASS
InformationCore/RelationCore/ExecutionCore diff = 0 bytes
Answer constants in continuation runtime = ABSENT
Direct Core store/fetch/raw semantic IDs = ABSENT
```

These checks are necessary but not sufficient for implementation audit.

## 2. Resolution of prior blockers

| Prior blocker | Result |
|---|---|
| B-1 C-A semantic pollution | RESOLVED |
| B-2 C-B answer/change leakage | RESOLVED |
| B-3 raw Information IDs | RESOLVED |
| B-4 bypassed ExecutionScope | RESOLVED |
| B-5 asserted forbidden checks | IMPROVED, but evidence lifecycle has a new failure |
| B-6 fragmented old process | RESOLVED |
| B-7 non-frozen evaluator | RESOLVED |
| B-8 physical-change evidence hooks | RESOLVED |

## 3. New blocking findings

### R-A1 — Fresh process destroys old-process evidence

The old process appends its evidence:

```text
trackD-memory/Sources/CContinuationStudy/main.swift:311
StudyJSON.appendLine(evidence, to: StudyPaths.evidence(root))
```

But the fresh continuation process replaces the same file:

```text
trackD-memory/Sources/CContinuationStudyContinue/main.swift:220
StudyJSON.write(evidence, to: StudyPaths.evidence(root))
```

After cold start, the old process invocation, forbidden-channel observations,
carrier-write acknowledgement, PID, and lifecycle audit trail are lost. The
final workspace therefore cannot prove that the pre-termination process
satisfied the confirmed protocol. This violates the required separation and
preservation of old-process, termination, and fresh-process evidence.

Required fix: preserve both evidence records. Either append both to the same
JSONL stream with explicit process phase identifiers, or write separate
old/fresh evidence files and include both paths in the evaluator input. Do not
change X-1…X-5.

### R-A2 — A missing C-C Relation can be masked

For C-C, the fresh process first observes the persisted Relation:

```text
trackD-memory/Sources/CContinuationStudyContinue/main.swift:94-107
```

If the Relation is absent, it falls back to the independent `s0` and `s1`
pointers:

```text
trackD-memory/Sources/CContinuationStudyContinue/main.swift:109-128
```

The blocker check at `main.swift:141` considers only `charter`,
`beforeSnapshot`, and `afterSnapshot`; it never requires the C-C Relation to
be found. Consequently, a C-C workspace with a missing or corrupted Relation
can still produce `blocker = "none"` and pass full continuation.

This masks the C-C carrier definition and prevents a valid C-B/C-C evidence
comparison. It is not resolved by treating X-4 as exploratory.

Required fix: for C-C, a missing Relation must set a distinct blocker such as
`relation_not_found` and make the run invalid or non-full-success. C-B must
retain its independent-Information path unchanged. Do not add Relation
semantics to C-B.

## 4. Non-blocking conditions for C-Execute pinning

```text
1. The orchestrator must prove that S0/S1 snapshots refer to the declared
   Physical Space source and overwrite reference.
2. The orchestrator must verify actual old-process exit after the pre-exit
   termination marker and before fresh-process launch.
3. C-Execute evidence must preserve both old/fresh PIDs and marker files.
```

These may require execution orchestration changes, not C-Spec or C-Design
changes.

## 5. Gate result

```text
B Track   = CLOSED
C Gate    = OPEN
C-Spec    = FROZEN / HUMAN RE-AUDIT PASS
C-Design  = CONFIRMED / HUMAN RE-AUDIT PASS WITH CONDITION
C-Impl    = REVISED / AUDIT FAIL / REVISE REQUIRED
C-Execute = NOT AUTHORIZED
R-C1      = NOT RUN
```
