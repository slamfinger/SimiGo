# Nodes-out Candidate A Effect Verdict Design Revision v0.2

**状态**：`DRAFT / EXTERNAL DESIGN REVIEW REQUIRED`  
**日期**：2026-09-22  
**回应**：`6a31a73` Design Draft v0.1 外审裁定 `NEEDS DESIGN`（框架 PASS；DV1 primary estimand 无区分度）  
**边界**：本文件只修订 effect verdict 设计。不修改 Runner、baseline、Candidate A 或已冻结 Contract，不采数，不重跑 Tier-1，不宣布任何 effect verdict。

## 0. 冻结锚点

| 项 | 值 |
|---|---|
| Audited Runner | `f4d880e` / Runner v2.2.1 |
| Runner SHA-256 | `ace241fc6ca22bd1dd40d2e6036662ae0b1e2e1564f49fe3a140900e26495f17` |
| Frozen baseline | `17bde28:trackE-residency/residency_policy_simulator_v3.py` |
| Baseline blob | `ff6d4e21df40db800e64bd5c949c39b3d77d22aa` |
| Effect Interpretation Contract | `0918260` / PASS |
| Tier-1 mechanism accounting | `da5efa8` / PASS |
| Mechanism Synthesis Review | `bd414a0` / PASS |
| Design Draft v0.1 | `6a31a73` / 外审 NEEDS DESIGN |
| Current effect verdict | `LOCKED` |

## 1. v0.1 外审裁定记录

| 项目 | 裁定 |
|---|---|
| 冻结证据链 | PASS |
| 与 Contract 边界一致 | PASS |
| DV0–DV3 分层 | PASS |
| 非法 estimand 排除 | PASS |
| DV2 设计方向 | PASS |
| DV3 边界 | PASS |
| Design Revision 字段完整性 | PASS |
| DV1 是否已形成可判定 effect estimand | **FAIL / NEEDS DESIGN** |

裁定含义：不退回整体设计；只修 DV1 estimand 的区分度缺失，并在采数前补入 discriminating-power gate。

## 2. 核心概念修正：accounting closure ≠ effect identification

本节为 v0.2 新增定义，须外审确认：

```text
accounting closure
    在预注册 accounting 模型中，Candidate 与 baseline 的
    modeled 量由构造恒等（identity mapping + zero conversion cost），
    差值数学闭合为 0。

effect identification
    primary estimand 在预注册模型中允许出现非零差异，
    即至少存在一个模型内可观测状态使 Δ ≠ 0。
```

推论：

1. accounting closure 是机制层/账本层的完备性证据；
2. effect identification 是 effect verdict 的必要前提；
3. 前者不能替代后者；在数学闭合模型上采数得到 Δ=0，不是"效应为零"的证据，而是定义闭合的重申。

## 3. Δ_MBL 的数学闭合事实

Tier-1 账本（`da5efa8`，`tier1_mechanism_accounting.json`）已记录：

```text
hot
  rehydrate bytes:  baseline = Candidate = 54,459,216 KiB
  externalize bytes: baseline = Candidate = 53,520,264 KiB

tree
  rehydrate bytes:  baseline = Candidate = 79,419,690 KiB
  externalize bytes: baseline = Candidate = 78,480,738 KiB
```

闭合原因由模型构造直接决定：

```text
baseline node    = 1 × (GDN + ATT)
Candidate A unit = 1 × GDN + 1 × ATT
conversion cost  = 0

→ 同一 trace 上 Σ baseline migration bytes ≡ Σ Candidate migration bytes
→ Δ_MBL ≡ 0（由定义闭合，非实验待测）
```

因此 v0.1 §5 的 DV1 primary estimand 不具备 discriminating power；此时进入采数只会复现已知恒等式，不产生 effect 信息。

## 4. normalization 判定：三条候选均不能恢复区分度

| 候选 | 判定 | 原因 |
|---|---|---|
| `MBL_per_decode_step` | 不可用 | 同一 trace → decode steps 相同、MBL 相同，Δ 仍恒为 0，只是给零差异换单位 |
| `MBL_per_node_touch` | 不可修复分子 | 分子已闭合为 0，任何 denominator 不产生非零差异；且 node touch 若不严格定义为 trace-level logical node touch（而非 Candidate unit acquisition、pair acquisition 或 decode request），将重新引入 Contract 禁止的 unit→node 隐式折算 |
| `MBL_per_node_equiv`（/78,246 KiB） | 不可用 | 78,246 KiB 仅为 node-equivalent byte size；不解决 node slot 与 unit slot 的容量语义；仍依赖 GDN+ATT=node 的 identity mapping |

结论：在当前 frozen 模型内，不存在能通过 discriminating-power gate 的 DV1 primary estimand。

## 5. DV1 重新定义

```text
旧：DV1 = Simulator accounting-effect verdict
新：DV1 = Simulator accounting-closure / accounting-effect analysis
```

1. DV1 不再作为 effect verdict 路径存在；
2. 若 MBL 恒等闭合，DV1 仅构成 accounting closure 记录；
3. DV1 的上限从 "simulator accounting verdict" 降级为 "accounting closure ledger"；
4. 未来任何 DV1-type analysis 若要升级为 effect 判定，必须先通过 §6 gate，且模型须改变（例如引入非零 conversion cost 或非 identity mapping），否则 gate 必然 FAIL。

## 6. Discriminating-power gate（新增强制门）

规则：

```text
在任何 DV 采数之前，必须先回答：
  预注册 primary estimand 在预注册模型中，
  Candidate − baseline 是否理论允许非零差异？

若答案为"数学上不允许"（由构造闭合）：
  STOP → 不采数 → 该路径记为 accounting closure
  → effect verdict 保持 LOCKED。
```

套用当前模型：

| 路径 | gate 结果 | 依据 |
|---|---|---|
| Δ_MBL（DV1） | FAIL | identity mapping + zero conversion cost 强制闭合 |
| DV2 primary estimand（实测 latency / bytes / decode） | 可通过（待 DV2 独立设计外审） | 实测路径未被 accounting 定义闭合 |
| DV3 primary estimand | 可通过，但非最小实验面 | 同上，且缺生产侧协议 |

## 7. capacity normalization 语义修正

1. C1 更名：

```text
旧：C1 slot-normalized（共同 capacity normalization）
新：C1 = model-specific capacity constraint
    baseline 12 node slots 与 Candidate 24 unit slots
    是各自模型自身的容量约束，不是共同归一化基准。
```

2. C2（byte-normalized，相同 byte capacity）：若采用，必须显式声明它改变实验预算/容量 regime，而非中性归一化；是否改变实验预算须在 Design Revision 中单独作答。

3. 在未通过 §6 gate 前，C1/C2 的选择本身不构成 effect estimand 修复。

## 8. DV1 Stop Rule

```text
若 primary estimand 在预注册模型中
由 identity mapping + zero conversion cost
数学上必然闭合为 Δ = 0：

则不进行 DV1 effect sampling；
该路径直接记为 accounting closure；
effect verdict 保持 LOCKED。
```

适用记录：Tier-1（seed 42 frozen face）已构成 DV1 的 accounting closure 证据；研究链不因"必须产生 verdict"而强行采数。

## 9. v0.2 之后的决策面

外审通过本修订后，三条路径重新定价：

| 路径 | 修订后定位 | 判定 |
|---|---|---|
| DV0 正式封存 | 机制层 + accounting 层证据闭合已完备；effect verdict LOCKED 作为最终研究结论 | 合法研究终点 |
| DV1（重定域） | 仅作为 accounting closure ledger；当前模型内无 effect 采数路径 | effect 采数被 §6 gate 禁止 |
| DV2 直接进入 runtime effect | 唯一能回答"效果"的最小实测路径；结构有效（v0.1 外审 PASS） | 需新 harness + 独立 Design Revision；若改 Runner 必须重跑 correctness audit |

v0.2 不替外审选定路径；路径选定属于下一门位动作。

## 10. Design Revision 字段表（增补）

在 v0.1 15 项字段之上新增两项必填（共 17 项）：

| 字段 | 必须回答 |
|---|---|
| discriminating power | primary estimand 在预注册模型中是否理论允许非零差异；数学闭合 → STOP |
| capacity semantics | C1 = model-specific capacity constraint；C2 = 是否改变实验预算 |

原 15 项不变；其中 verdict type 行按 §5 重定域后的 DV1 语义理解。

## 11. 当前门位

```text
BASELINE REGRESSION                         PASS
RUNNER v2.2.1                              PASS
L1 / L2 / L3                               PASS
DETERMINISM                                PASS
CORRECTNESS AUDIT                          PASS
EFFECT INTERPRETATION CONTRACT             PASS
TIER-1 MECHANISM EXTRACTION                PASS
EXTERNAL ACCOUNTING REVIEW                 PASS
MECHANISM SYNTHESIS REVIEW                 PASS
────────────────────────────────────────────
EFFECT VERDICT DESIGN v0.1                 NEEDS DESIGN（外审已裁定）
EFFECT VERDICT DESIGN REVISION v0.2        DRAFT / EXTERNAL DESIGN REVIEW REQUIRED
DV0 DESIGN                                 VALID / CLOSURE ENDPOINT
DV1 PRIMARY ESTIMAND                       RE-SCOPED TO ACCOUNTING CLOSURE / PENDING REVIEW
DV2 DESIGN                                 STRUCTURALLY VALID
DV3 DESIGN                                 VALID / NOT MINIMAL
DISCRIMINATING-POWER GATE                  ADDED / PENDING REVIEW
CANDIDATE A EFFECT VERDICT                 LOCKED
RUNNER / BASELINE / CANDIDATE A            FROZEN
TIER-1 RERUN                               NOT REQUIRED
DATA COLLECTION                            LOCKED
```
