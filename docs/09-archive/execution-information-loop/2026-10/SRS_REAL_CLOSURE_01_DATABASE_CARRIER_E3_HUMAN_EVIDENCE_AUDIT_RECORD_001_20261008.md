# SRS-REAL-CLOSURE-01 — Database-Carrier E3 Human Evidence Audit Record 001

> **ARCHIVED** 2026-10-20 · line: E-I 连续计算 · original: docs/00-governance/SRS_REAL_CLOSURE_01_DATABASE_CARRIER_E3_HUMAN_EVIDENCE_AUDIT_RECORD_001_20261008.md
> Evidence status: unchanged (content frozen; moved only)


> **Status:** READ-ONLY HUMAN EVIDENCE AUDIT — ACCEPTED AS INVALID / NON-ADJUDICATIVE
> **Date:** 2026-10-08
> **Campaign:** exec-dbcarrier-003-c6c8b6f
> **E3 evidence commit:** 1ac081b0304a72205685a11bd610d65e8a6c8109
> **E3 execution base:** c6c8b6fb0b532aa94496ac860f4e5faaa8cd05e7
> **Implementation:** 7392fcb79fb7e8465b73f9e1837c4634e56c0409
> **Evidence-path release:** 712aee56c523845440276923ac7053dc3ea91b3c

## 1. Audit ruling

The E3 campaign is confirmed **INVALID** because the harness failed while
persisting the observer verdict after O5.

The audit accepts the following as raw campaign facts:

    29/29 evidence-path preflight passed;
    accepted fresh database was copied and opened successfully;
    O0 through O5 observation artifacts were produced;
    transaction log records materialize, ES1, ES2 continuation and N1 commits;
    final database reached 4 objects / 2 index entries / 2 dependency entries;
    SQLite integrity remained OK;
    ES2 adapter observed REUSE / REUSE_PATH;
    ESN adapter observed BLOCK / BLOCKED_NON_RECOMPUTE_PATH;
    N1 state reached revision-2 in O4/O5.

These are **raw observations only**.

The following are NOT established by this audit:

    EQ-1 through EQ-8;
    REJ-1 through REJ-14;
    CarrierSQLite equivalence;
    observer-authoritative evidence;
    any broader Execution State / SimiGo claim.

## 2. O0–O5 causal state chain

The preserved observations are internally consistent:

    O0:
      objects=0, index=0, dependencies=0

    O1:
      D object 806fff... written;
      D-1 revision-1 dependency mapping;
      objects=1, index=0, dependencies=1

    O2:
      SRS object 260258... written and indexed;
      D revision-1 retained;
      objects=2, index=1, dependencies=1

    O3:
      continuation object 1703f2... written;
      continuation index entry CR:CR-ES2-r2;
      D revision-1 retained;
      objects=3, index=2, dependencies=1

    O4:
      D' object 8553f5... written;
      D-1 current mapping becomes revision-2;
      historical revision-1 remains;
      objects=4, index=2, dependencies=2

    O5:
      same logical state as O4;
      current D-1 remains revision-2;
      no additional logical mutation after ESN.

This matches the transaction log, which records four logical write groups:

    materialize = D + dependency revision-1;
    ES1         = SRS + index entry;
    ES2         = continuation + index entry;
    N1          = D' + dependency revision-2.

## 3. Adapter decision attribution

The preserved adapter outputs are:

    ES2:
      primaryDecision = REUSE;
      decisionPath = REUSE_PATH;
      typedFailures = [];
      evidenceDisclaimer =
        NOT OBSERVER_AUTHORITATIVE_EXECUTION_EVIDENCE.

    ESN:
      primaryDecision = BLOCK;
      decisionPath = BLOCKED_NON_RECOMPUTE_PATH;
      typedFailures =
        HARD_BLOCK.dependencyUnresolved(D-1),
        HARD_BLOCK.dependencyBlockingInvalidation(D-1);
      evidenceDisclaimer =
        NOT OBSERVER_AUTHORITATIVE_EXECUTION_EVIDENCE.

The adapter outputs are therefore consistent with the frozen decision boundary,
but they remain subordinate evidence in this INVALID campaign.

## 4. Confirmed harness defect

The exact campaign source computes observer field:

    observer["C3_persisted_vs_resolved_byte_equality"]

but then attempts:

    require(observer["C3"], "C3 mismatch")

The required key `C3` does not exist.

Therefore the campaign fails with a key-binding exception after O5 and before
observer verdict persistence. This defect is in the campaign harness evidence
layer, not in:

    database carrier semantics;
    fixture;
    τ;
    T-IMPL-01;
    ES2 decision logic;
    ESN decision logic.

## 5. Missing authoritative artifacts

Because the failure precedes observer verdict persistence, the following remain
absent or non-authoritative as campaign outputs:

    observer_verdict.json;
    preflight_verification.json;
    runtime_provenance.json;
    eq_rej_matrix.json;
    campaign_outcome.json;
    campaign_db_validation.json;
    final campaign SHA256SUMS.

Post-stop process/stderr capture is treated only as failure evidence and does
not retroactively complete the frozen campaign evidence package.

## 6. Semantic finding disposition

The audit does **not** convert the raw observations into equivalence claims.

The correct formal state is:

    semantic sequence executed to O5 = ACCEPTED FACT;
    raw ES2 REUSE observation       = OBSERVED / NON-AUTHORITATIVE;
    raw ESN BLOCK observation       = OBSERVED / NON-AUTHORITATIVE;
    complete evidence chain         = NOT ESTABLISHED;
    EQ/REJ adjudication             = NOT ESTABLISHED;
    CarrierSQLite equivalence       = NOT ESTABLISHED.

The accepted EXEC-006 document-form bounded finding is unchanged.

## 7. Budget disposition

    third campaign budget        = CONSUMED;
    third IS mutation budget     = CONSUMED;
    third observer budget        = CONSUMED BY FAIL-CLOSED ATTEMPT;
    rerun                         = NOT AUTHORIZED;
    harness repair                = NOT AUTHORIZED;
    automatic renewal             = FORBIDDEN;
    old evidence reuse            = FORBIDDEN.

## 8. Next lawful governance object

This audit closes the Human Evidence Audit for EXEC-DB-003.

A future corrected campaign requires a **new independent Human-directed
Request**, with new implementation/harness correction scope and fresh campaign
budget. This audit does not authorize that correction or campaign.

Until then:

    CarrierSQLite equivalence = NOT ESTABLISHED;
    broader claim = NOT ESTABLISHED.
