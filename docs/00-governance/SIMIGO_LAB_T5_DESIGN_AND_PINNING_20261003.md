# T5 Design and Pinning — Third Continuation Task

Date: 2026-10-03
Status: `PINNED / EXECUTION AUTHORIZED BY HUMAN DIRECTION`
Question: 在 T4 之外，再换一个不同 continuation task，重复观察
`task → Information dependency`。
Boundary: 本件只登记 T5；不宣称所有 continuation 都依赖 Information。

## 1. Structural independence

| axis | T4 | T4-2 | T5 |
|---|---|---|---|
| domain | procurement / finance | system release / ops | workshop schedule / constraint assignment |
| core operators | amount aggregation + percentages | parameter mapping + ordered rollout + go/no-go | prerequisite graph + topological levels + capacity filtering + slot/room assignment |
| output type | narrative + summary table | activation record | constraint-satisfying schedule |
| shared task vocabulary | procurement/quota/reserve | release/component/rollout/window | workshop/room/prerequisite/slot |

因此 T5 不是 T4 数据改名，也不是 T4-2 的第三个发布任务。

## 2. Pinned random facts

```text
WS-3FAB94 enrollment 29
WS-C36165 enrollment 21
WS-C7B0F0 enrollment 21
WS-394151 enrollment 10
WS-ED9D08 enrollment 30
WS-70677C enrollment 30

RM-CDB7 capacity 48
RM-5446 capacity 30
RM-8A08 capacity 21

SLOT-0222 = 09:30
SLOT-95D2 = 11:00
SLOT-176D = 14:00

WS-C36165 ← WS-3FAB94
WS-C7B0F0 ← WS-C36165
WS-394151 ← WS-3FAB94
WS-ED9D08 ← WS-C7B0F0 ∧ WS-394151
WS-70677C ← WS-C36165

WIN-8B1DE7 = frozen
```

这些值是 opaque random facts；B 指令、空工作区、通用能力均不可推导。
N-1/N-2： facts 不在 B prompt、空库或工具用法内；暴力枚举不构成
普通 continuation 路径。N-3 后验兜底：若 C-N 以未登记方式获得事实，
升级 confound audit，不直接计入 PASS。

## 3. Pre-registered arms

```text
A-run    fresh workspace + fresh db-a；生成 Dependency Plan 并 store。
B-E-run  fresh workspace + db-b-e = db-a snapshot；B prompt 可 fetch。
B-N-run  fresh workspace + fresh empty db-b-n；B prompt 逐字节同 B-E。
唯一自变量 = InformationStore 是否含 A 沉淀。
```

Pinned hashes:

```text
2d0f36f0fadd6b84e31847fd8e2a357e1795302b7717eafa87abe9549d2237cf  a-instruction.txt
e591f265b2d08af98734e28da929f19a72fe29312fa3aaeca00b6d087be6067a  b-instruction-template.txt
```

执行时 `<Dependency Plan identity>` 以 A-run 输出原样替入。B-E 与
B-N 的替入后指令必须逐字节相同；替入是 format-level D-note。

## 4. Objective completion criteria

`Workshop_Final_Schedule.md` PASS 当且仅当：

```text
C1  六个 pinned workshop 全部出现，且无第六个之外 workshop。
C2  每个 workshop 有一个 slot + room。
C3  prerequisites 使用更早 slot；同一 slot 不得违反依赖。
C4  room capacity >= workshop enrollment。
C5  同一 slot + room 只有一个 workshop。
C6  每个 workshop 只使用 Dependency Plan 中 eligible room set。
C7  dependency levels 与 plan 一致。
C8  freeze 行 `WIN-8B1DE7 = frozen` 在位。
C9  零 pinned facts 之外的 workshop/room/slot 虚构。
```

AC mapping:

```text
AC-1  B-E satisfies C1..C9。
AC-2  B-E has ordered evidence: fetch(plan identity) → fetched content
      → schedule generation; schedule facts match deposited plan。
AC-3  B-N fails to produce equivalent schedule without fabricating
      pinned facts。
```

预注册结果：

```text
PASS            AC-1 ∧ AC-2 ∧ AC-3。
FAIL            AC-1 or AC-2 不成立，或 B-N 也能等价完成。
INCONCLUSIVE    forbidden-channel / evidence-chain 混淆无法排除。
```

## 5. Non-claims

即使 T4 与 T5 都 PASS：

```text
不主张所有 continuation 都依赖 Information；
不主张 InformationCore 对一般任务必要；
不主张完整 Information Space 成立；
不主张完整 MemPalace Runtime 成立；
不引入 Relation 语义或新 Core 修改。
```

## 6. Execution discipline

三 run 均为 fresh agent session / fresh workspace；只允许 workspace 内
文件与 `./t4ctl`。A 提交前无 B 产物；B-E 使用 A 后的 db 快照；B-N
空库。执行结果先做 raw observation + pre-registered reading；最终
结论须 human declaration。

---

# REV.1 — Feasibility Repair and Rerun Pinning

Attempt #1 was invalidated before substantive attribution because the
pinned graph needed four dependency levels but only three slots existed.
This revision adds one fourth random slot and keeps every other fact,
operator, arm structure and completion criterion unchanged.

```text
added pinned fact:
SLOT-0A9332 = 16:00
ordered slots:
SLOT-0222 → SLOT-95D2 → SLOT-176D → SLOT-0A9332
```

Status after revision: `REV.1 PINNED / T5 RERUN AUTHORIZED`.
Attempt #1 remains `INCONCLUSIVE / DESIGN INVALID`; it is not merged
into any later schedule evidence.
