# C-Impl Audit — Remote `CContinuationStudy` @ `1771000`

Date: 2026-10-03  
Status: `C-IMPL AUDIT FAIL / REVISE REQUIRED`  
Audited commit: [`1771000b86d3`](https://github.com/slamfinger/SimiGo-Lab/commit/1771000b86d3)  
Audited source SHA-256:
`13dbf06655833fa2bd846d22060e37c0f6333d5a0428b411645bdc45974232f9`  
C-Execute: `NOT RUN`

## 1. Non-blocking verification

```text
Release build                        = PASS
ExecutionCore unit tests             = 4/4 PASS
Protected Core diff vs 3016844       = 0 bytes
Changed files                        = trackD-memory manifest + harness only
```

This verifies compilation and existing Core regression tests only. It does
not authorize C-Execute and does not cure the design-conformance blockers
below.

## 2. Blocking findings

### B-1 — C-A Execution State carries forbidden change semantics

`main.swift:85-88` persists:

```text
progress    = S0 observed; external S0→S1 change declared outside runtime
nextAction  = REQUEST_HEALTH_CHECK
```

The confirmed C-Design permits C-A to retain minimal lifecycle state, but
forbids change narratives and derived continuation answers. This makes
C-A partially answer X-5 from Execution State alone and contaminates the
C-A control.

### B-2 — C-B progress Information carries the answer path

`main.swift:93` persists:

```text
S0 observed; external S0→S1 change declared outside runtime|nextAction=REQUEST_HEALTH_CHECK
```

Even though C-Spec permits factual change descriptions in principle, the
confirmed C-Design deliberately chose not to use that allowance. This record
encodes the change narrative and X-5 answer, undermining the C-B/C-C
comparison.

### B-3 — Information identity formation bypasses the mechanism minter

`main.swift:146-150` creates Information with manually chosen identities
such as `task`, `s0`, `s1`, and `progress`.

Frozen InformationCore semantics require mechanism-side identity minting.
The backend provides `makeInformationID(content:provenance:)`; raw semantic
IDs must not be hand-authored.

### B-4 — C-B/C-C bypass the confirmed ExecutionCore consumer boundary

`main.swift:90,100,121,134` invokes `SQLiteStore` directly. The confirmed
architecture uses `ExecutionScope` as the first consumer boundary over
Information/Relation stores. Direct store calls turn this harness into a
parallel consumer path.

### B-5 — Forbidden-channel evidence is asserted, not audited

`main.swift:164-168` hardcodes every forbidden-channel check to `false`.
There is no mechanical validation of invocation, environment, persistence,
or carrier-read provenance. This fails the sole implementation-time
condition attached to C-Design confirmation.

### B-6 — Lifecycle process model diverges from C-Design

The confirmed chain requires one old process to observe S0 and S1 before
termination, followed by a fresh process. The implementation exposes
separate `prepare` and `observe-after` CLI invocations (`main.swift:186-193`),
so S0 and S1 formation can occur in different processes before the declared
cold-start continuation.

### B-7 — Success evaluation is not the frozen X-1…X-5 evaluator

`main.swift:140` treats X-2/X-3 as non-nil rather than exact frozen S0/S1
recovery, and treats X-4 as any non-nil direction string. `inferDirection`
at `main.swift:170-175` checks only that JSON differs and labels it
`S0 → S1`. There is no independent machine-checkable X-1…X-5 evaluator,
partial-success record, or invalid-run classification.

### B-8 — Physical-change evidence hooks are absent

The implementation has no source snapshot/hash fields or declared overwrite
evidence required for the later C-Execute chain. A future orchestrator could
supply this outside the binary, but C-Impl currently neither records nor
makes auditable the required evidence shape.

## 3. Non-blocking observations

```text
Relation direction remains explicit in C-C.
C-B can infer a difference from independent Information, as allowed.
No Core source was modified.
No experiment was executed during this audit.
```

The alternative uncommitted local implementation present before this audit
was stashed as `unaudited local CImpl alternative` and is not part of this
ruling.

## 4. Gate result

```text
B Track   = CLOSED
C Gate    = OPEN
C-Spec    = FROZEN / HUMAN RE-AUDIT PASS
C-Design  = CONFIRMED / HUMAN RE-AUDIT PASS WITH CONDITION
C-Impl    = IMPLEMENTED / AUDIT FAIL / REVISE REQUIRED
C-Execute = NOT AUTHORIZED
```

Revision must return to the confirmed C-Design. It may add detection and
audit capability, but may not add semantic capability or alter X-1…X-5.

## 5. External human confirmation — 2026-10-03

An independent human check of audit object `1771000b86d3` confirmed this
`FAIL / REVISE REQUIRED` ruling and all eight blockers. The stashed local
alternative remained excluded from the judgment.

The human also confirmed that the final remote change only made C-B's
comparison deterministic by comparing sorted JSON; it still returned
`S0 → S1` unconditionally, so B-7 remains unresolved.

Revision constraints are sealed:

```text
May add: audit/detection capability and evidence machinery.
May not add: Change/Observation semantic types, a new Relation mechanism,
automatic real-change inference, new success semantics, new C-A/B/C
definitions, or any change to X-1…X-5 / REQUEST_HEALTH_CHECK.
```

Required next object for re-audit is one new, locatable revision commit or
diff. The stashed implementation must not be merged into that audit object.

R-C1 remains `NOT RUN`; C-Execute remains `NOT AUTHORIZED`.
