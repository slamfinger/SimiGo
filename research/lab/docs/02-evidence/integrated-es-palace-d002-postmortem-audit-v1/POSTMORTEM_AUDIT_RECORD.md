# D-002 Postmortem Replay-Adapter Audit Record

> **Status:** READ-ONLY AUDIT COMPLETE / FIRST FAULT LOCALIZED / EXACT EXCEPTION NOT ESTABLISHED
> **Date:** 2026-10-09
> **Audit ID:** `D002-POSTMORTEM-REPLAY-ADAPTER-AUDIT-001`
> **Audited execution:** D-002 final campaign instance `18FE111C-C258-4A12-B6F6-C184A2078625`
> **D-001 Decision Core executions during audit:** 0
> **D-002 reruns during audit:** 0

## 1. Result

```text
manifest completeness gate       = PASS;
replay execution                 = 1 / EXECUTED;
observed replay record           = PASS / 7 records produced;
frozen three-component vectors   = FAIL / only N-MISSING matched;
unresolved materialization       = ALL 7 CASES;
Decision Core executions in audit = 0;
PALACE/snapshot mutation         = NONE;
D-001 core mutation              = NONE;
forbidden channels              = NONE.
```

## 2. Localized fault

All seven decisions entered the unchanged D-001 Decision Core's unresolved
fallback encoding:

```text
closure_id         = UNRESOLVED-{CASE};
closure_revision   = UNRESOLVED;
next_action_id     = null;
target_digest      = null;
continuation_class = BLOCKED_DEFECT;
typed label        = MISSING_INFORMATION_BLOCK.
```

This proves the failure occurred before D-001 semantic precedence could classify
the six otherwise registered cases. It does not prove a PALACE representation
defect or a Decision Core defect.

## 3. Layer findings

```text
A0 evidence integrity                         = PASS;
A1 retained source selection review           = PASS / NOT REGENERATED;
A2 R-I1..R-I10 fixture representation        = PRESENT / 70 R-I FAMILY ROWS AUDITED (INCLUDING REGISTERED DUPLICATE BINDINGS);
A3 typed mapping record                       = PRESENT;
A4 closure translation                        = ADAPTER TRANSLATED;
A5 provenance translation                     = ADAPTER TRANSLATED;
A6 NEXT_ACTION / boundary translation         = ADAPTER TRANSLATED;
A7 invocation translation                     = MANIFEST PACKAGE BINDING PRESENT;
A8 carrier snapshot / REUSE translation       = ADAPTER TRANSLATED;
A9 D-001 reconstruction validation trace      = NOT CAPTURED;
A10 unresolved fallback encoding              = CONFIRMED;
A11 observer/reconciliation mismatch analysis = OBSERVER CORRECTED AND CORRECT;
A12 final first-fault                         = EVIDENCE_INFRASTRUCTURE_DEFECT.
```

The prior adapter closure-digest ordering defect was corrected in source before
Attempt-003. The final unresolved result therefore cannot be attributed to that
specific placeholder digest ordering defect.

## 4. Classification

```text
primary_class   = EVIDENCE_INFRASTRUCTURE_DEFECT;
secondary_label = D002_REPLAY_ADAPTER_UNRESOLVED_INPUT_DEFECT;
exact exception = NOT_ESTABLISHED.
```

The write-once replay evidence did not capture the exception that triggered
D-001's unresolved fallback. Because rerun is prohibited, the exact internal
exception cannot be recovered from existing evidence.

The evidence supports these conclusions:

```text
PALACE representation defect        = NOT IMPLICATED;
typed mapping semantic defect       = NOT PROVEN;
D-001 Decision Core semantic defect = NOT IMPLICATED;
Carrier defect                      = NOT IMPLICATED;
Observer defect                     = NOT IMPLICATED;
manifest package-binding omission   = CORRECTED AND PASSED.
```

The audit does distinguish a residual open question: whether the adapter
omitted required materialization work or mishandled a field during translation.
Existing evidence is insufficient to choose between those without new
authorized instrumentation.

## 5. Frozen evidence and code

The audit used only the sealed Attempt-003 evidence, D-002 implementation, D-001
read-only implementation, retained fixtures, PALACE source, and prepared
snapshot. No file under those frozen roots was modified.

## 6. Correction proposal boundary

`CORRECTION_PROPOSAL.json` and `CORRECTION_PROPOSAL.md` are non-executable audit
outputs. They do not authorize rerun, repair, implementation mutation, a new
campaign, or equivalence claims.
