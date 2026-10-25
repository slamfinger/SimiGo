# T5 REV.1 Execution Results — Pre-registered Reading

Date: 2026-10-03  
Pin commit: `b5e9eb473829c2ce28be15919333d025bcaeb673`  
Status: `EXECUTED / RAW EVIDENCE SEALED / PRE-REGISTERED READING = REPLICATION PASS — HUMAN FINAL DECLARATION PENDING`

Attempt #1 remains `INCONCLUSIVE / DESIGN INVALID`; no evidence from it is  
merged into this result.

## 1. Execution record

| Run | fresh session | db | observation |
|---|---|---|---|
| A-run | `01a1025f-8cce-73c3-a88c-3fc8ec99d039` | fresh db-a | generated and stored Dependency Plan `69c28c24e690d2c294c2b1ad`; stopped before schedule |
| B-E-run | `01a10261-aca8-7b33-9d86-ab97c703ee1d` | db-b-e = db-a snapshot | fetched plan, generated Final Schedule, stored schedule and COMPLETE todo |
| B-N-run | `01a10261-ae47-7371-ad77-099c39c71505` | fresh db-b-n | fetch `not-found`; generated blocker only; zero schedule facts |

B-E and B-N prompts were byte-identical:  
`09ab15e7282302806a75374514439da4129e81aa5b04d69509912edb3962db9b`.

## 2. Mechanical completion audit

| criterion | reading | evidence |
|---|---|---|
| C1 exactly six pinned workshops | PASS | all six appear; no extra workshop |
| C2 slot + room for each | PASS | six complete rows |
| C3 prerequisites earlier | PASS | L1→L2→L3→L4 placements satisfy every edge |
| C4 capacity >= enrollment | PASS | 48≥29, 30≥21, 30≥21, 21≥10, 48≥30, 48≥30 |
| C5 no duplicate room in slot | PASS | duplicates absent in every slot |
| C6 only eligible rooms | PASS | every room is in the plan's eligible set |
| C7 dependency levels match plan | PASS | L1/L2/L2/L3/L3/L4 exactly |
| C8 freeze row | PASS | `WIN-8B1DE7 = frozen` present |
| C9 no fabricated facts | PASS | no extra workshop/room/slot values |

Schedule facts:

```text
SLOT-0222 / WS-3FAB94 / L1 / RM-CDB7
SLOT-95D2 / WS-C36165 / L2 / RM-5446
SLOT-95D2 / WS-394151 / L2 / RM-8A08
SLOT-176D / WS-C7B0F0 / L3 / RM-5446
SLOT-176D / WS-70677C / L3 / RM-CDB7
SLOT-0A9332 / WS-ED9D08 / L4 / RM-CDB7
```

## 3. Attribution reading

```text
AC-1 = PASS  B-E schedule satisfies C1..C9。
AC-2 = PASS  fetch(plan identity) → dependency-plan-fetch.txt →
             schedule generation；schedule facts match deposited plan。
AC-3 = PASS  B-N fetch = not-found；no final schedule；no pinned
             workshop/room/slot fabrication。
```

按 T5 预注册三落点，本次 raw reading 落入：

```text
REPLICATION PASS
```

## 4. Evidence boundary

本读数只支持：在该 T5 constraint-assignment 任务域中，再次观察到  
Information boundary 对 cold-start continuation 的同向必要性证据。  
不主张所有 continuation 都依赖 Information；不主张完整 Information  
Space；不主张完整 MemPalace Runtime。

## 5. Close-out

按预注册纪律，`T5 = CLOSED / REPLICATION PASS` 的最终宣告归 human。  
在宣告前：

```text
T5 = EXECUTED / RAW EVIDENCE SEALED /
     PRE-REGISTERED READING = REPLICATION PASS /
     AWAITING HUMAN DECLARATION
```
