# PALACE-1 Phase B Opening Registration

日期：2026-09-30  
状态：`REGISTERED / PHASE_B_OPEN / CODE_LEVEL_AUDIT_NEXT`  
Registration authority：explicit human approval in research session  
Approved instruction：

```text
登记两项 PASS，并激活 Phase B opening。
```

## 1. Registered review decisions

| Artifact | Verdict | Registration |
|---|---|---|
| `SIMIGO_LAB_EXECUTION_STATE_PHASE_A_EXTERNAL_REVIEW_20260930.md` | `PASS / REGISTRATION_REQUIRED` | REGISTERED |
| `SIMIGO_LAB_PALACE1_PHASE_B_DRAFT_EXTERNAL_REVIEW_20260930.md` | `PASS / ACTIVATION_REQUIRED` | REGISTERED |

The human instruction above explicitly approved both decisions in one registration.

## 2. Registered Phase B opening

Registered opening：

`SIMIGO_LAB_PALACE1_MINIMAL_DURABLE_UNIT_DRAFT_20260930.md`

The reviewed draft is now the registered PALACE-1 Phase B opening. Its research
question is:

> 在 Phase A 边界内，一个 Execution 的最小 durable semantic unit 是什么，才能在
> 进程退出、runtime binding 失效或 Physical Representation 不可用后恢复 execution
> semantics，而不把 Runtime Binding、Backend State 或 Physical Representation
> 错误提升为 Durable Semantic State？

## 3. Authorization boundary

This registration opens only the Phase B code-level architecture audit.

It does not authorize:

```text
❌ SQLite / KV / event log / remote storage selection
❌ Palace database schema or implementation
❌ persistence file format
❌ Llama adapter implementation
❌ oversized special semantics
❌ performance benchmarking
```

## 4. Next gate

```text
Phase A review               = PASS / REGISTERED
Phase B draft review         = PASS / REGISTERED
Phase B opening              = REGISTERED / OPEN
Current work                 = Phase B code-level audit
Next decision point          = external review of the Phase B audit
```
