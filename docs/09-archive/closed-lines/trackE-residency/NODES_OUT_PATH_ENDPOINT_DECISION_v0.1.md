# Nodes-out Path / Endpoint Decision v0.1

**状态**：`DRAFT / EXTERNAL DECISION REVIEW REQUIRED`  
**日期**：2026-09-22  
**回应**：`dbb8364` Design Revision v0.2 外审 `PASS — EFFECT VERDICT DESIGN REVISION ACCEPTED`；设计门关闭，项目进入路径/终点决策门  
**边界**：本文件只做路径决策分析与预注册决策规则。不选择实施路径，不修改 Runner、baseline、Candidate A 或 Contract，不采数，不重跑 Tier-1，不启动 Swift，不创建任何实验分支。

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
| Design Draft v0.1 | `6a31a73` / 外审 NEEDS DESIGN（已修复） |
| Design Revision v0.2 | `dbb8364` / 外审 PASS — ACCEPTED |
| Current effect verdict | `LOCKED` |

## 1. v0.2 外审裁定记录

**裁定**：`PASS — EFFECT VERDICT DESIGN REVISION ACCEPTED`。

该 PASS 的精确语义：v0.1 唯一阻断项（DV1 discriminating-power 缺陷）已实质修复，**设计门关闭**。它不等于：effect verdict PASS、DV2 获准实施、可以采数、可以改 Runner、可以启动 Swift、Track E 全部结束。

外审八项独立攻击全部 PASS：缺陷修复方式、normalization 封闭性、discriminating-power gate、DV2 非预选、capacity semantics、Stop Rule 硬度、证据链零改动、状态边界拆分。

### 外审携带义务（对本文档的硬约束）

1. 必须独立论证 DV0 / DV2 / DV3 的选择理由，不得直接引用"DV2 是唯一能回答效果的最小路径"作为选择结论；
2. 本决策是**研究价值决策**，不是技术可行性决策；
3. 最终路径选择权在外审，本文档最多给出条件化推荐。

## 2. 决策问题

外审正式提出的研究决策问题：

```text
在已经证明当前 accounting 模型无法识别 effect 的前提下，
SimiGo 是否有足够的研究问题价值，值得引入 runtime measurement；
还是应把 Nodes-Out 研究正式封存在 DV0 closure endpoint？
```

## 3. DV0：封存终点的独立论证

### DV0 交付的最终命题

机制层四层闭环（correctness → contract → mechanism → accounting）已完备。封存时研究链交付的结论是：

```text
在 identity mapping + zero conversion cost 的 accounting 语义下，
nodes-out（unit 级 residency）与 baseline（node 级 residency）
按构造 byte 等价；
任何真实差异只能存在于该假设抹去的 runtime 层面，
且在本研究内未被测量。
```

这是完备、可审计的研究结论，不是失败。

### DV0 的适用条件

1. 研究目标即 accounting 语义特征化——该目标已完全达成；
2. 或项目未声明"unit 级 residency 真实 runtime 效果"为研究问题；
3. 或不具备 DV2 所需的测量资源（harness、硬件口径、基准协议容量）。

### DV0 的代价

runtime 层问题被正式悬置。若未来重启，必须从新设计门进入，且 frozen face 的 provenance 价值随时间衰减。

## 4. DV2：runtime 路径的独立论证

### 独立推导（不引用 v0.2 的路径表述）

机制层已固定的两个受控事实：

1. F5（raw count shape）：同 trace 下 GDN/ATT raw event count 为 baseline 的 2 倍；
2. accounting closure：byte mass 恒等闭合。

两事实联立，得到一个机制层已经产生、但尚未检验的可证伪预测：

```text
事件数 ×2 且 byte 总量不变
→ 若 unit 级存在真实 runtime 差异，只可能来自：
  (a) per-event 固定开销（负向：×2 的调用 / 簿记 / 同步）
  (b) 粒度相关的 cache / allocation / copy 效应（方向未知）
```

frozen accounting 模型把 per-event 成本隐式设为 0——这正是 DV2 要移除的唯一假设。因此 DV2 测量的量（per-event overhead 与粒度效应的净和）在构造上未被闭合，不是"为了产出 verdict 而强行实验"，而是对机制层既有预测的直接检验。

### DV2 的适用条件

1. 研究问题明确包含"unit 级 residency 的真实 runtime 效果"；
2. 具备测量资源：新 harness、共同硬件口径、交替运行 / 冷热态 / p50-p95-p99 协议容量。

### DV2 的成本与风险

1. 新 harness 设计 + 独立 Design Revision + 独立外审；
2. 若修改 Runner，三层 correctness audit 全量重审，frozen face 语义切换需新锚点；
3. 结论域限于 harness / hardware / trace family，不得外推生产。

## 5. DV3：生产路径的独立论证

DV3 需要的产物当前全部缺失：生产 trace 采样协议、真实模型层形状与 unit 定义、production KV allocator/cache 行为、multi-tenant 干扰模型、SLO / failure / 成本模型。

更重要的是逻辑顺序：DV3 的测量靶点是"生产环境下的 runtime 效果"，而 harness 级效应是否存在尚属未知。在 DV2 信号出现之前，生产测量没有可检验对象。因此 DV3 逻辑上后置于 DV2 信号，本轮任何条件下不可选。

## 6. 预注册决策规则

```text
R1  若研究问题声明包含真实 runtime 效果，
    且测量资源可用：
    → 进入 DV2 Design Revision（独立成文、独立外审）

R2  若研究问题已被 accounting 语义特征化满足，
    或测量资源不可用：
    → DV0 正式封存，Track E 终点

R3  DV3 本轮任何条件下不可选

R4  无论选择哪条路径：
    Candidate A effect verdict 保持 LOCKED，
    直至所选路径完成其全部前置门
```

## 7. 条件化推荐与不选定声明

1. 就项目已声明的目标（nodes-out 机制语义特征化）而言，DV0 已经构成完备终点；封存不损失任何已得证据。
2. DV2 的必要性不来自路径偏好，而来自 §4 的独立推导：F5 与 accounting closure 联立产生了一个未闭合、可证伪的 runtime 预测。若项目选择追问该预测，DV2 是其唯一检验面。
3. R1 与 R2 的分岔取决于一个只有项目方才能回答的问题：**"unit 级 residency 的真实 runtime 效果"是否是本项目的在册研究问题？**
4. 本文档不替外审选定路径；路径选定属于外审裁定。

## 8. 当前门位

```text
BASELINE REGRESSION                         PASS
RUNNER v2.2.1                              PASS
L1 / L2 / L3                               PASS
DETERMINISM / ARTIFACT BINDING             PASS
CORRECTNESS AUDIT                          PASS
EFFECT INTERPRETATION CONTRACT             PASS
TIER-1 MECHANISM EXTRACTION                PASS
EXTERNAL ACCOUNTING REVIEW                 PASS
MECHANISM SYNTHESIS REVIEW                 PASS
EFFECT VERDICT DESIGN v0.1                 NEEDS DESIGN（已由 v0.2 修复）
EFFECT VERDICT DESIGN REVISION v0.2        PASS / ACCEPTED（设计门关闭）
────────────────────────────────────────────
PATH / ENDPOINT DECISION                   DRAFT v0.1 / EXTERNAL DECISION REVIEW REQUIRED
DV1 EFFECT SAMPLING                        BLOCKED（当前模型，永久）
DV2 / DV3                                  候选路径，未授权
CANDIDATE A EFFECT VERDICT                 LOCKED
RUNNER / BASELINE / CANDIDATE A            FROZEN
RUNNER MODIFICATION                        LOCKED
DATA COLLECTION                            LOCKED
TIER-1 RERUN                               NOT REQUIRED
SWIFT IMPLEMENTATION                       NOT STARTED / NO BASIS
MLX-SWIFT-LM BRANCH                        无创建依据
TRACK F                                    NOT OPENED
```
