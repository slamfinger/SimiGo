# PALACE-1 Phase B Audit External Review

日期：2026-09-30  
Review artifact：`docs/00-governance/SIMIGO_LAB_PALACE1_MINIMAL_DURABLE_UNIT_AUDIT_20260930.md`  
Reviewed commit：`8f5ec9e`  
Audited code HEAD：`db188ac`  
Verdict：`PASS / REGISTRATION_REQUIRED`  
Role：external methodological review only

本文件是 review decision，不是 repository registration。PASS 不推进 BACKEND-1，
不授权存储选型，不定义 Palace schema，不实现 Llama adapter。

## 1. Verdict

Phase B audit passes because it:

1. answers registered opening subquestions B1–B7;
2. names a contract-level minimal durable unit;
3. preserves the Phase A `D / R / P / O / T` boundary;
4. separates Execution State from representation, binding, history, and transient work;
5. defines recoverable-set closure instead of treating snapshots as isolated rows;
6. gives identity / tombstone, continuation, availability, crash-window, and
   discarded-state rules;
7. keeps all storage and adapter boundaries closed;
8. records targeted clean-HEAD evidence: 57 / 57 PASS.

## 2. Registered conclusion under review

The review accepts this narrow Phase B conclusion:

```text
minimal durable unit = Execution Semantic Snapshot

fields =
  id
  lineage.root
  lineage.parent
  position
  continuation.nextInput
  continuation.continuationID
  lifecycle

recoverable set =
  snapshots
  + required lineage tombstones
  + optional separately typed representation binding relations
```

This is an inferred architecture contract, not a selected storage implementation.

## 3. Boundary checks

| Boundary | Result |
|---|---|
| No SQLite / KV / event log / remote selection | PASS |
| No Palace database schema or implementation | PASS |
| No persistence file format | PASS |
| No Llama adapter implementation | PASS |
| No oversized-specific semantics | PASS |
| No performance benchmark claim | PASS |
| Lifecycle history not promoted to minimum D | PASS |
| RepresentationRef / binding kept outside minimum D | PASS |

## 4. Evidence check

The audit correctly used a clean `db188ac` worktree because the main worktree had
unrelated uncommitted Swift changes. The later documentation-only commit does not
invalidate the code evidence.

Test evidence is sufficient for this architecture audit:

```text
SimiGoRuntimeContractTests: 15 / 15 PASS
SimiGo2ExperimentalTests:   42 / 42 PASS
Total:                      57 / 57 PASS
```

This remains targeted structural evidence, not an end-to-end durability proof.

## 5. Conditions carried into registration and later engineering

1. **Tombstone closure is mandatory.**  
   A surviving child's `root` / `parent` IDs must remain resolvable, at minimum as
   tombstones, unless a future registered lineage rule proves otherwise.

2. **Continuation equivalence is not assumed.**  
   `nextInput` remains D in the current Lab contract. Transcript-derived recovery
   requires bounded equivalence evidence before replacing it.

3. **No universal representation digest exists.**  
   Durable reattachment needs an explicit P-layer content claim and validation
   policy before implementation.

4. **Binding relation must remain separately typed.**  
   `runtimeAddress` is R; relation generation is relation metadata; neither may be
   promoted into Execution identity.

5. **Crash recovery is classification, not storage design.**  
   The registered audit defines required outcomes for ambiguous or partial states;
   it does not authorize a transaction protocol or persistence format.

6. **Concurrency remains a known gap.**  
   Coordinator locking, discarded-binding guard, and durable identity reservation
   must be resolved only inside a separately registered engineering gate.

## 6. Gate state

```text
Phase A review           = PASS / REGISTERED
Phase B opening          = PASS / REGISTERED
Phase B boundary audit   = PASS / REGISTRATION_REQUIRED
Phase C / BACKEND-1      = STILL GATED
Current blocker          = explicit human/repository registration
```
