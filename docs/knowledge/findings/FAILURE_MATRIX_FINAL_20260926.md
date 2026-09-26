<!-- Publicly curated from SimiGo-Lab. Source: docs/00-governance/SIMIGO2_FAILURE_MATRIX_FINAL_20260926.md on exp/simigo2-experimental. Internal recovery/governance material has been excluded. -->

# SimiGo-Lab — Failure Matrix Full Re-run (Final Audit Round) — 2026-09-26

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
