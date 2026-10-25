# Nodes-out Research Endpoint Decision v0.1

**状态**：`DRAFT / EXTERNAL ENDPOINT REVIEW REQUIRED`  
**日期**：2026-09-22  
**回应**：`57b42ab` Path/Endpoint Decision v0.1 + 双方 Path Decision 分析（DV0 方向合意）+ Research Question Coverage Audit（本文件 §2 执行并归档）  
**边界**：本文件只做研究终点判定与封存登记。不修改 Runner、baseline、Candidate A 或 Contract，不采数，不重跑 Tier-1，不启动 Swift，不创建实验分支，不定义 Track F。

## 0. 冻结锚点

| 项 | 值 |
|---|---|
| Audited Runner | `f4d880e` / Runner v2.2.1 |
| Runner SHA-256 | `ace241fc6ca22bd1dd40d2e6036662ae0b1e2e1564f49fe3a140900e26495f17` |
| Frozen baseline | `17bde28:trackE-residency/residency_policy_simulator_v3.py` |
| Baseline blob | `ff6d4e21df40db800e64bd5c949c39b3d77d22aa` |
| Definition Lock | `e5bca86` / PASS LOCKED |
| 正式开题 | `RESIDENCY_NODES_OUT_DESIGN_20260922.md`（`c3fe842` PASS / SEALED AS OPENING BASELINE） |
| 正式实验设计 | `RESIDENCY_NODES_OUT_EXPERIMENT_DESIGN_20260922.md` v0.3（预注册出口 E1/E2/E3） |
| Correctness evidence | `38043cc` / PASS |
| Effect Interpretation Contract | `0918260` / PASS |
| Tier-1 mechanism accounting | `da5efa8` / PASS |
| Mechanism Synthesis Review | `bd414a0` / PASS |
| Design Draft v0.1 | `6a31a73` / 外审 NEEDS DESIGN（已修复） |
| Design Revision v0.2 | `dbb8364` / 外审 PASS — ACCEPTED |
| Path/Endpoint Decision v0.1 | `57b42ab` / DV0 条件化推荐，双方分析合意 |
| Current effect verdict | `LOCKED` |

## 1. 研究终点判定

**判定**：Track E nodes-out 链以 **DV0 closure endpoint** 正式结束。

判定依据：

1. Research Question Coverage Audit（§2）证明在册研究问题已全部到达预注册合法出口；
2. Path Decision 分析（`57b42ab` §7/§9 + 双方对话分析）证明 runtime 测量的期望信息量不支持其成本，且 runtime effect 从未在册；
3. v0.2 外审确认 discriminating-power gate 禁止无信息量采数；为"必须产生 verdict"而继续实验将违反项目原则"先证明值得测，再设计怎么测"。

判定语义（精确）：

- **Track E CLOSED 意味着**：在册问题已答，预注册出口已闭合；effect verdict 保持 `LOCKED` 是**最终状态**，不是待解锁状态；
- **不意味着**：nodes-out 想法被证伪、机制实现失败、或方向被永久禁止。未来若重启，属于新研究问题，必须从新的 Definition / Design 门进入，且不得复用本链外推。

## 2. Research Question Coverage Audit

### 2.1 在册研究问题

正式开题 ②（PASS / SEALED）：

> 当 node-granularity externalization pathway 被取消后，residency 粒度、execution-state migration correctness 与边界成本之间的关系如何变化？
> （不窄化为"移除后性能有没有变好"）

### 2.2 覆盖矩阵

| # | 在册组件 | 预注册出口判据 | 实际回答（署名出处） | 状态 |
|---|---|---|---|---|
| 1 | migration correctness 是否仍成立 | E1：三层五元组等价 | `38043cc`：event-level（decode-step 锚）/ step-level continuation / terminal-state 逐项等价全 PASS；violation=0；L1/L2/L3 formal=0；F7 确定性 dd=0 | ✅ 已回答：成立 |
| 2 | residency 粒度如何变化 | E2：机制知识入档 | Tier-1 F2/F3/S2/S3：unit 级二态驻留；观测 pair-coherent（full=12 / partial=0 / empty=20；hot 696/696、tree 1015/1015 full-pair acquisition）；state shape 全特征化；S2 显式区分 observed ≠ structural | ✅ 已回答 |
| 3 | 边界成本如何重新定义 | E2：三通道读数 | 通道1：raw counts ×2 形状（F4）+ byte mass 恒等闭合（F5，方案 A identity mapping 锁定）；通道2：violation=0 如实报；通道3：GDN/ATT 分项账本（M09/M12 by kind）；J 兼容披露翻倍（F6/S4，非判据） | ✅ 已回答（modeled 层） |
| 4 | 78,246 KiB/node 适用性判定 | E3：判定如实入档 | 数据完备；显式判定语句原缺，**由本文件 §2.3 补记** | ✅ 补记后闭合 |
| 5 | 性能/效果优劣 | 自始不在册 | 开题②排除（"不窄化为性能"）；实验设计"不设性能 PASS/FAIL" | ⛔ 从未在册 |
| 6 | runtime effect | 自始不在册 | v0.2 定位 separately scoped，外审确认 | ⛔ 从未在册 |
| 7 | partial-demand 工作负载 | 自始不在册 | F3/S2 明令禁止 partial=0 外推 | ⛔ 从未在册 |
| 8 | 生产/真实模型/多 seed 泛化 | 自始不在册 | Contract 禁止条件 #9/#13 | ⛔ 从未在册 |

### 2.3 E3 补记（本文件新增判定，须外审确认）

Experiment Design §5 E3 要求"78,246 KiB/node 适用性判定（可映射/不可映射）如实入档"。Tier-1 报告/JSON 数据完备但缺显式判定语句，本节补记：

```text
E3 判定：在 frozen face（seed 42；hot/tree；identity mapping；pair-coherent 观测）内，
78,246 KiB/node 计账单位【可映射】。

依据（tier1_mechanism_accounting.json，GDN+ATT 分项与 baseline 逐项相等）：
  hot  rehydrate   42,762,240 + 11,696,976 = 54,459,216 KiB = baseline
  hot  externalize 42,024,960 + 11,495,304 = 53,520,264 KiB = baseline
  tree rehydrate   62,361,600 + 17,058,090 = 79,419,690 KiB = baseline
  tree externalize 61,624,320 + 16,856,418 = 78,480,738 KiB = baseline
  M07 byte exposure min = 78,246 KiB（两模型一致）

适用域：本判定仅陈述 frozen face 内 node-equivalent accounting 的可映射性；
不陈述真实 I/O 成本等价；不外推其他 trace / seed / budget / 模型类
（Contract 禁止 #9/#13）。
```

### 2.4 覆盖审计结论

E1/E2 闭合，E3 经 §2.3 补记后闭合；#5–#8 自始不在册，不构成未答问题。**在册研究问题全部到达合法出口；DV0 是合法终点，不是主动放弃实验。**

## 3. 终点命题链（Track E 最终结论）

```text
Mechanism 四层闭环
（correctness 38043cc → contract 0918260 → accounting da5efa8 → synthesis bd414a0）
    ↓
观测访问粒度 = 完整 GDN+ATT pair
（F3：full-pair acquisition = any-unit acquisition，hot 696/696、tree 1015/1015；
  每事件字节 = 78,246 KiB 完整 node，E3 补记）
    ↓
在册工作负载内未观测到 partial demand（partial = 0）
    ↓
受控解释（不外推）：在该访问模式下，node 是天然访问单元而非人为打包；
unit 粒度相对 node 粒度的字节优势 = 0
（结构推广属 S2 禁止域；若未来出现 partial-demand 模型类，
  该问题作为新研究问题重新开放）
    ↓
Accounting closure：identity mapping + zero conversion cost 下 Δ_MBL ≡ 0（F5）
    ↓
DV1 primary estimand discriminating-power FAIL（v0.2，dbb8364 外审 ACCEPTED）
    ↓
Effect verdict：无共同实测 estimand → LOCKED（最终状态）
    ↓
Runtime effect：separately scoped question（从未在册 Track E）
    ↓
Registered future prediction（§4）
    ↓
TRACK E CLOSED（待外审署名生效）
```

## 4. Registered future prediction（二层措辞）

### 4.1 已证明（署名事实）

1. Candidate A 在 frozen face 内使节点级搬运字节数保持恒等（F5，`da5efa8`/`bd414a0` 署名）；
2. 事件/簿记路径发生结构性增加：raw counts 为 baseline 的 ×2 形状（F4）；
3. 在当前模型下，任何以 modeled byte 为基础的 effect estimand 无区分度（v0.2 §3–§4，`dbb8364` 外审 ACCEPTED）。

### 4.2 待未来 runtime 实验验证的预测（登记，非已证明）

> 在相同硬件、runtime 与工作负载条件下，新增事件路径预期不产生系统级正向收益；其净 runtime effect 的方向与量级留待未来 runtime 实验验证。

### 4.3 明确不登记

任何量级数值（含百分比）。量纲推导（事件项相对字节搬运项极小）依赖未锁定的 event dispatch、allocator、copy path 与 memory hierarchy 实际成本，只作为分析背景，不构成本项目已建立的科学预测。

### 4.4 预测的检验条件（预登记）

任何未来 harness 若检验 §4.2 预测，必须先通过独立 Design Revision + 外审；若修改 Runner，必须重跑三层 correctness audit 并建立新锚点。检验结果无论方向均如实入档。

## 5. Track E 出口与 Track F 关系

1. Track E CLOSED 的生效条件：本文件外审 PASS 署名；
2. Track F（Swift / `mlx-swift-lm` / runtime measurement capability）：独立定义，当前 `NOT OPENED`、无启动依据；Track E 关闭不自动授权 Track F 任何动作；
3. 若未来 Track F 立项 runtime measurement capability，其价值主张必须独立成立（基础设施价值），不得表述为"Track E effect verdict 的延续"；
4. P4（哪些结构/状态机制构成核心驻留机制）：串行链中的独立后续环节，状态不受本判定影响；
5. Runner / baseline / Candidate A 保持 FROZEN 归档；任何复用必须建立新 provenance 锚点。

## 6. 当前门位

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
EFFECT VERDICT DESIGN REVISION v0.2        PASS / ACCEPTED（设计门关闭）
PATH / ENDPOINT DECISION                   DV0 方向合意（57b42ab + 双方分析）
RESEARCH QUESTION COVERAGE AUDIT           COMPLETE（本文件 §2，含 E3 补记）
────────────────────────────────────────────
RESEARCH ENDPOINT DECISION                 DRAFT v0.1 / EXTERNAL ENDPOINT REVIEW REQUIRED
TRACK E                                    PENDING CLOSED（待外审署名）
CANDIDATE A EFFECT VERDICT                 LOCKED（最终状态）
RUNNER / BASELINE / CANDIDATE A            FROZEN（归档）
DATA COLLECTION                            LOCKED（Track E 范围内永久）
DV1 EFFECT SAMPLING                        BLOCKED（永久）
SWIFT IMPLEMENTATION                       NOT STARTED / NO BASIS
MLX-SWIFT-LM BRANCH                        无创建依据
TRACK F                                    NOT OPENED / INDEPENDENTLY SCOPED
```
