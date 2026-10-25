# PALACE-1 Phase B Audit — Minimal Durable Unit

日期：2026-09-30  
状态：`PHASE_B_CODE_AUDIT_COMPLETE / AWAITING_REVIEW`  
Audited HEAD：`db188ac`  
范围：`simigo2-experimental` registered opening B1–B7  
性质：`architecture contract audit only`

本文不选择 SQLite / KV / event log / remote，不定义 Palace schema，不定义持久化
file format，不实现 Llama adapter。所有结论区分：

```text
observed code fact ≠ inferred durable contract ≠ selected implementation
```

## 1. Evidence basis

审计基于 `db188ac` 的 clean HEAD worktree。主工作区当时存在与本审计无关的
未提交 Swift 源码改动，因此没有把那些改动混入验证。

Targeted tests：

```text
swift test --filter 'ExecutionContinuityContractTests|ExecutionContinuityLifecycleTreeTests|ExecutionContinuityCoordinatorTests|Fork3StructuralBattery|ExecutionStatePrefixPoolTests|PrefixSnapshotStoreTests|MaterializationCoordinatorTests|OversizedBackendAtomicityTests|PrefixPoolSessionLifecycleTests|BackendConformanceMatrixTests'

SimiGoRuntimeContractTests bundle: 15 / 15 PASS
SimiGo2ExperimentalTests bundle:   42 / 42 PASS
Total:                             57 / 57 PASS
```

summary artifact:

`simigo2-experimental/results/backend-conformance/palace1-phase-b-audit-tests-20260930.json`

## 2. Named minimal durable unit

Inferred contract-level unit:

```text
Execution Semantic Snapshot
```

It is the durable projection of one `ExecutionStateHandle`:

```text
id
lineage.root
lineage.parent
position
continuation.nextInput
continuation.continuationID
lifecycle
```

The recoverable durable set is not merely an unordered collection of active
executions. It must satisfy this closure:

```text
active/restored snapshot
+ discarded tombstones whose IDs may still be referenced or must remain reserved
+ parent IDs reachable from child lineage
+ optional, separately typed Execution→Representation relation records
```

Lifecycle event history is not part of the minimum unit.

## 3. Field disposition

| Field | Disposition | Reason |
|---|---|---|
| `id.rawValue` | D | Execution identity |
| `lineage.root` | D | Stable branch-tree root |
| `lineage.parent` | D | Fork linkage |
| `position.value` | D | Canonical logical position |
| `continuation.nextInput` | D in current Lab contract | Current semantic continuation input |
| `continuation.continuationID` | D | Logical continuation label |
| `lifecycle` | D | Includes active and discarded terminal state |
| coordinator `handles` | R | Process-local map of D |
| lifecycle `records` / `sequence` | O / History | Replay and observability, not minimum D |
| representation history | R + P | Restore accelerator, not semantic state |
| opaque payload / token prefix | P | Backend representation |
| `RepresentationRef` | P | Locator and content claim |
| binding relation | separate relation | Only if reattachment is required |
| `runtimeAddress` | R | Process/runtime addressing |
| binding generation | relation metadata | Ordering/versioning, not Execution identity |
| `boundAt` | O | Relation history |
| pool stats / recency tick | O + T | Policy and observability |
| physical-use counts / in-flight work | T | Transient protection |

## 4. B1 — Identity and tombstones

Observed facts:

- `ExecutionID` is an opaque caller-supplied `String`.
- Coordinator rejects duplicate IDs only within process-local `handles`.
- `create` sets `lineage.root = id` and `parent = nil`.
- `fork` sets child `root = parent.lineage.root` and `parent = parent.id`.
- Backend operations cannot redefine identity, lineage, position, or continuation.

Inferred durable rule:

```text
Canonical identity = exact ExecutionID.rawValue.
Discarded IDs remain reserved until an explicit GC policy retires them.
Duplicate creation against active or reserved-discarded IDs fails closed.
A child lineage reference requires its root/parent identity to remain resolvable,
at minimum as a tombstone.
```

`root` and `parent` are semantic lineage metadata, not alternative identity keys.
They must not be used to synthesize a new `ExecutionID`.

## 5. B2 — Continuation source

Observed fact: current Lab has no transcript authority in the Execution Continuity
path. `ExecutionContinuation.nextInput` is carried by the logical handle and copied
through lifecycle transitions.

Contract decision for this audit:

```text
continuation.nextInput is D in the current Lab contract.
continuation.continuationID is D.
A transcript-derived replacement is not assumed equivalent.
```

If a future transcript path becomes canonical, it must pass a bounded equivalence
plan before `nextInput` is reclassified:

1. same execution ID and lineage;
2. same logical position;
3. same rendered/tokenized continuation under the same backend capability set;
4. same generated-token identity on the validation workload;
5. explicit failure on missing, divergent, or ambiguous transcript input.

Until then, removing `nextInput` from D would be an implementation change, not an
audit result.

## 6. B3 — Evolution representation

Observed facts:

- Coordinator keeps the latest handle per execution.
- It also keeps an append-like lifecycle record list and per-execution
  representation history.
- `continueExecution` advances logical position by exactly `+1`.
- `fork` commits a child only after physical derivation succeeds at the same
  parent bound position; without a parent representation, fork is lazy.
- `restore` requires a captured representation at the target position.

Inferred minimum:

```text
One latest valid semantic snapshot per non-discarded execution.
Discarded snapshots become tombstones according to B1/B7.
Full lifecycle records remain observability/replay data.
```

The minimum representation of evolution is therefore state-oriented, not
event-oriented. This does not forbid an event log; it only says an event log is not
required by the semantic contract.

## 7. B4 — Representation relation

`RepresentationRef` is P-layer locator/claim data. It must not become a field of
the Execution Semantic Snapshot.

If recovery wants to reattach an existing artifact instead of recomputing, the
durable relation must be a separate record. Contract-level fields are:

```text
executionID
representation key / ref
boundPositionAtBind
binding state
relation generation
```

Disposition:

```text
executionID              = relation key, not new identity authority
representation key/ref   = P locator/claim
boundPositionAtBind      = consistency metadata
binding state            = relation state
generation               = relation ordering/version metadata
runtimeAddress           = R; never durable semantic addressing
boundAt                  = O
```

If no such relation is durable, the execution can still recover semantically, but
its representation outcome is `rematerializationRequired`.

## 8. B5 — Physical availability matrix

| Representation condition | Required recovery outcome |
|---|---|
| No durable binding | `unbound` semantic state; recompute when needed |
| Binding + live representation verified at same position | `reattach` |
| Artifact present and claim/content valid | `reattach` after explicit load/commit |
| Namespace, token count, or chain hash mismatch | loud fail; invalidate/quarantine candidate; recompute |
| Artifact missing | `rematerializationRequired` |
| Artifact unreadable/corrupt | loud fail; do not bind; recompute |
| Foreign payload type | loud fail |
| Backend bound position ≠ logical position | loud fail |
| In-flight physical use | defer deletion; wait or recompute; never silently delete |
| Ambiguous multiple claims at same position | choose none silently; fail closed or force explicit selection |

Observed support exists for position mismatch, foreign payload, namespace/token/
hash mismatch, missing snapshot, and in-flight delete deferral. A universal content
digest for every backend payload is not present.

## 9. B6 — Crash-window recovery semantics

Observed ordering:

```text
fork:
  physical derive succeeds → child semantic snapshot commits

restore:
  backend representation restore succeeds → logical restored snapshot commits

discard:
  current representation release succeeds → discarded snapshot commits

prefix artifact export:
  temp snapshot written → moved to final snapshot → atomic sidecar written →
  pool entry registered

physical deletion:
  deletion request → if in-flight, defer → delete after release
```

Inferred recovery classification:

| Window | Recovery rule |
|---|---|
| `D` without relation | semantic state survives; representation is unavailable; recompute or create relation separately |
| relation without `D` | orphan relation; do not instantiate an execution from it; mark for review/GC |
| representation without claim | unavailable candidate; do not bind |
| claim without representation | unavailable candidate; do not bind |
| fork derivation failed before child commit | no child D; parent unchanged; retry allowed |
| child D committed but caller response lost | child exists; recovery must not create a second child with the same ID |
| logical continue committed but representation rebind missing | logical position remains authoritative; stale binding is invalid; recompute |
| logical restore committed but binding stale | validate position/content before use; otherwise recompute |
| release succeeded but discard tombstone missing | old active state survives; representation unavailable; retry discard |
| tombstone committed but release not observed | lifecycle stays discarded; physical release may be retried only as cleanup |
| snapshot without sidecar | unavailable; rescan skips |
| sidecar without snapshot | unavailable; rescan skips |
| ambiguous pair | fail closed; no silent repair |

This defines recovery classification, not a storage transaction protocol.

## 10. B7 — Discarded state

Observed facts:

- Discard sets lifecycle to `.discarded`.
- Later operations through `guardKnown` reject a discarded execution.
- Discard releases only the current representation after success.

Inferred contract:

```text
discarded = terminal semantic tombstone.
It preserves identity reservation and may preserve lineage reachability.
It is not active, restored, or automatically reusable.
Collection requires an explicit GC rule and must preserve every parent/root
reference required by surviving executions.
```

Observability history of a discarded execution may outlive the tombstone, but that
history is not semantic state.

## 11. Current implementation gaps

These findings do not change the opening boundary, but must accompany the contract:

1. No durable Execution State store exists in the audited Lab path.
2. `ExecutionID` has no durable allocator or cross-restart reservation.
3. `attach` accepts a handle as supplied; it does not independently validate the
   handle's lineage closure.
4. `bindRepresentation` checks only that the execution exists, not that lifecycle is
   non-discarded.
5. `ExecutionContinuityCoordinator` is not internally locked.
6. Generic `ExecutionRepresentation` has no universal content digest.
7. Restore selects the last representation matching a position; if several exist,
   content identity must be resolved explicitly.
8. Lazy fork at a different child position creates a semantic child without a
   bound representation; later consumption fails rather than silently redefining
   position.
9. BindingRegistry comments describe append-only history, but supersede/detach
   mutate rows in place. This is acceptable only as runtime relation behavior; it
   must not be read as a durable event log.
10. Snapshot + sidecar is not a single atomic crash transaction.

## 12. Fail-closed test plan

Phase B contract implementation/verification must add or preserve tests for:

1. duplicate active ID after restart;
2. duplicate reserved-discarded ID after restart;
3. missing parent/root tombstone in a recovered lineage closure;
4. discarded ID referenced by a surviving child;
5. transcript/continuation equivalence, only if transcript is later introduced;
6. namespace mismatch;
7. token-count mismatch;
8. chain-hash mismatch;
9. missing snapshot or sidecar;
10. foreign payload;
11. backend bound-position mismatch;
12. stale binding after logical continue;
13. stale binding after logical restore;
14. interrupted fork before and after semantic commit;
15. interrupted restore before and after semantic commit;
16. failed discard release leaving active state retryable;
17. orphan relation not instantiating an execution;
18. in-flight deletion deferred until release.

## 13. Gate consequence

Phase B supports this narrow answer:

```text
The minimal durable unit is an Execution Semantic Snapshot.
A recoverable set is the closure of snapshots plus required lineage tombstones.
RepresentationRef and binding relations are separate layers.
Lifecycle event history, pool stats, and in-flight work are not minimum D.
```

This does not establish:

```text
a storage engine
a schema
a serialization format
a transaction implementation
a cross-backend artifact format
a Llama adapter
```

Next required action is external review of this Phase B audit.
