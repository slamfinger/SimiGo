# SimiGo-Lab — Failure Matrix Full Re-run (Final Audit Round) — 2026-09-26

> **ARCHIVED** 2026-10-20 · line: 通用治理 / 其他 · original: docs/00-governance/SIMIGO2_FAILURE_MATRIX_FINAL_20260926.md
> Evidence status: unchanged (content frozen; moved only)


Status: FAILURE_MATRIX_COMPLETE / P1_ZERO / P2_REGISTERED
Baseline: 4e45b07 chain (D1 approved + Step1 cancellation + Step2
reconcile all landed). 13 operations × {success / physical failure /
cancellation / mid-exception / repeat / concurrency} × five state layers
(Execution State / Representation / Residency / Physical MLX / HTTP).

## Per-operation verdicts

| Operation | success | physical fail | cancel | mid-exc | repeat | concur |
|---|---|---|---|---|---|---|
| create | 🟢 | ⚪ N/A | 🟢 | 🟢 | 🟢 dup-reject | 🟠* |
| attach | 🟢 | ⚪ N/A | 🟢 | 🟢 | 🟢 | 🟠* |
| continue | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 advance | 🟠* |
| fork | 🟢 | 🟢 transactional | 🟢 | 🟢 | 🟢 dup-reject | 🟠* |
| restore | 🟢 | 🟢 physical-first | 🟢 | 🟢 | 🟢 idempotent | 🟠* |
| reattach | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 idempotent | 🟠* |
| discard | 🟢 | 🟢 transactional | 🟢 | 🟢 | 🟢 retryable | 🟠* |
| bindRepresentation | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 overwrite | 🟠* |
| releaseRepresentation | 🟢 | 🟢 foreign-guard + physical-first | 🟢 | 🟢 | 🟢 idempotent | 🟠* |
| materialize | 🟢 | 🟡 reader-fail pre-update ✓ | 🟢 | 🟡 update partial = FM-08 | 🟢 | 🟠* |
| evict | 🟢 | 🟢 DIRTY visible | 🟢 | 🟢 | 🟢 | 🟠* |
| generate | 🟢 | 🟠 token-boundary ABORT ✓; commit-section crash = FM-08 | 🟢 unit-boundary ABORT ✓ | 🟠 post-commit throw = visible ✓ | 🟢 restore-replay ✓ | 🔴 serialized by AsyncLock ✓* |
| newSession | 🟢 | 🟢 fail-fast propagate | 🟢 | 🟢 | 🟢 | 🟠* |
| HTTP request | 🟢 | 🟠 transport-fail after commit → client retry judged by canonical state ✓ | 🟢 cancel → ABORT ✓ | 🟠 | 🟢 | 🟢 single-flight |

*concurrency: the ENGINE serializes via AsyncLock (safe for direct
callers); the COORDINATOR used standalone (O6 scenario) remains
unserialized — registered as GA (direct multi-task coordinator use).

## INV / FM disposition

```text
INV-1 (log ≡ bookkeeping)      PASS — audited per unit + per pressure
INV-2 (frontier oracle)        PASS — registered test oracle
INV-3 (bookkeeping ≡ physical) PASS — production reconcile per turn;
                                 divergence → recover → re-check → fail
FM-01 generate atomicity       CLOSED (f495a85)
FM-02 fork transactionality    CLOSED (a209944)
FM-03 lifecycle serialization  CLOSED (a209944)
FM-04 cancellation contract    DEFINED (D1) + IMPLEMENTED (phase-boundary
                               observation; ABORT/COMMIT two-outcome)
FM-05 cross-layer boundary     DEFINED (D1): atomic pair = representation
                               binding + logical position; Residency =
                               mechanics layer (INV-1), outside the
                               conversation transaction
FM-06 INV-3 production         CLOSED (per-turn reconcile integrated)
FM-07 budget core double-count CLOSED (f495a85)
FM-08 MLX-internal faults      BETA BOUNDARY (registered, GA)
FM-09 reattach obligation      DEFINED (lazy; next-forward admissions)
FM-10 oversized fork/branch    BETA SCOPE (registered)
```

## Residual (all non-blocking, registered)

```text
P2  coordinator standalone concurrency (direct multi-task use) — GA
P2  INV-3 C_model calibration review before GA — registered
P2  MLX-internal fault injection — beta boundary (FM-08)
⚪  oversized fork/branch product surface — beta scope
⚪  floor redesign — GA, parameter disabled
```

## Verification evidence

```text
core tests           89/89 PASS (incl. 2 atomicity + coordinator fork)
product strict E2E   2 tests PASS (cancellation-abort + canonical
                     completion) on real device
real-device          overallPass TRUE, swap ≤ baseline, pressure green
```

Artifacts: `results/o5-sweep/app-realdevice-selftest-*.json`;
`results/o5-sweep/matrix2-*.json`; engine + coordinator sources.

---

## Addendum — Token Ledger failure surfaces — 2026-09-27

The Token Ledger (3ba44f7 + 07b210d) adds one append point per committed
transition and one per restore. Surface-by-surface disposition against the
existing matrix — no full re-run triggered (single narrow addition; every
surface maps to an already-registered disposition):

```text
generate turn-commit append   post-commit throw window (ledger append sits
                              between logical commit and INV-3 observation) —
                              existing disposition "post-commit throw =
                              visible; canonical state governs client retry"
                              applies unchanged; a ledger invariant throw is
                              divergence-class and fails loudly (I-L1/I-L2)
restore marker append         marker bound = furthest-ever committed
                              position; the coordinator gates targets on
                              representation existence BEFORE the physical
                              restore commits, so the ledger bound is
                              unreachable defense in depth. The interim
                              ahead-of-growth-only guard (which DID create a
                              post-commit half-apply window for forward
                              restores) was caught by this review and closed
                              in 07b210d before any device run hit it
markSuperseded                infallible (flag-and-retain)
unit battery                  7-case (96/96 total): forward growth,
                              rejection without growth-point consumption,
                              rewind + superseded retention, resume marker,
                              beyond-history rejection, isolation
device evidence               E5 replay chain bootstrap/turn!S/restoreMarker/
                              turn PASS (app-selftest-tl-gate.json); rewind
                              path byte-identical after 07b210d
```

---

## Addendum 2 — I-L3 enforcement closure — 2026-09-27

Code-level audit at e29fce7 found I-L3 was cross-REFERENCED but not
cross-CHECKED: `append()` never verified `prefixLength`, the restore
marker's value was ledger-self-derived, so a ledger/backend prefix
divergence was undetectable. Closed the same day (this addendum's
commit): the ledger now carries a REQUIRED authority closure over the
backend binding record (`boundPrefixLength(executionID:position:)` with
no-binding + position-mismatch guards) and enforces I-L3 on every append
of every kind — mismatch throws divergence-class, nothing recorded. The
restore marker's prefixLength is backend-derived (coordinator.restore
re-binds the historical prefix before returning); the ledger-self-derived
helper is deleted. Ownership wording unified in the gate definition
(conceptual owner: Execution State representation layer; implementation
owner: OversizedSegmentedEngine — no migration, registered as deferred).
No full matrix re-run triggered (narrow, single-invariant addition; the
physical commit paths are untouched — the authority only READS the
binding record). Targeted surfaces:

```text
turn/bootstrap append, wrong length    divergence-class throw post-commit;
                                       entry not recorded; canonical state
                                       governs client retry (existing
                                       post-commit disposition unchanged)
append with no backend binding         divergence-class throw (was:
                                       silently recordable — closed)
binding at another position            divergence-class throw via
                                       position-mismatch guard (was:
                                       undetectable position drift)
restore marker, wrong prefixLength     divergence-class throw BEFORE
                                       sessionInfo update surfaces; retry
                                       safe (markSuperseded idempotent)
unit battery                           11-case (100/100 total): the 7
                                       prior cases re-pinned through the
                                       independent backend stub + 4
                                       deliberate-mismatch cases
device evidence                        unchanged (app-selftest-tl-gate
                                       chain); re-run NOT triggered — the
                                       change adds a read-only check on
                                       the existing commit path
```
