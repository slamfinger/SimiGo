# PALACE-1 Phase B Audit Registration

日期：2026-09-30  
状态：`REGISTERED / PHASE_B_BOUNDARY_REGISTERED / PHASE_C_DECISION_NEXT`  
Registration authority：explicit human approval in research session  
Approved instruction：

```text
登记 Phase B audit PASS。
```

## 1. Registered review decision

| Artifact | Verdict | Registration |
|---|---|---|
| `SIMIGO_LAB_PALACE1_PHASE_B_AUDIT_EXTERNAL_REVIEW_20260930.md` | `PASS / REGISTRATION_REQUIRED` | REGISTERED |

The registered audit under review is
`SIMIGO_LAB_PALACE1_MINIMAL_DURABLE_UNIT_AUDIT_20260930.md`（audited code HEAD
`db188ac`，clean-HEAD targeted evidence `57 / 57 PASS`）。

## 2. Registered Phase B boundary conclusion

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

This is a registered architecture contract，不是 selected storage implementation。
Evidence remains targeted structural validation，不是 end-to-end durability proof。

## 3. Conditions carried into every later gate

```text
1. lineage tombstone closure — surviving child 的 root / parent 必须可解析，
   至少以 tombstone 形式
2. transcript equivalence proof — nextInput 保持 D；transcript-derived recovery
   须先给出 bounded equivalence evidence
3. explicit representation content claim / validation policy — durable
   reattachment 前必须先登记
4. binding relation separately typed — runtimeAddress 仍是 R；relation
   generation 是 relation metadata；不得提升进 Execution identity
5. crash-window recovery 是 classification — 只登记 ambiguous / partial state
   的 required outcomes，不授权 transaction protocol 或 persistence format
6. concurrency / durable identity reservation — coordinator locking、
   discarded-binding guard、identity reservation 须在独立 engineering gate 内解决
```

## 4. Authorization boundary

This registration registers the Phase B boundary verdict only. It does not
authorize:

```text
❌ SQLite / KV / event log / remote storage selection
❌ Palace database schema or implementation
❌ persistence file format
❌ Llama adapter implementation
❌ oversized special semantics
❌ performance benchmarking
```

## 5. Next gate

```text
Phase A review               = PASS / REGISTERED
Phase B opening              = PASS / REGISTERED
Phase B boundary audit       = PASS / REGISTERED
Phase C / BACKEND-1          = boundary precondition SATISFIED / activation
                               still requires its own decision point
Current blocker              = none on the Phase B boundary
Next decision point          = Phase C / BACKEND-1 activation decision
                               （route: SIMIGO_LAB_EXECUTION_STATE_RESEARCH_
                               ROUTE_REDEFINITION_20260929.md §Phase C）
```

Phase C activation不继承任何存储选型授权；BACKEND-1 opening
（`SIMIGO18_BACKEND1_LLAMA_RESEARCH_OPENING_20260928.md`）仍须对照本登记边界
重新审阅后才可进入执行。
