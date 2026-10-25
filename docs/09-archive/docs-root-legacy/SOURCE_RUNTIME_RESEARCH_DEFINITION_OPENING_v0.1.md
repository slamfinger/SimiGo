# Source/Runtime Research Definition Opening v0.1

**状态**：`DRAFT / EXTERNAL DEFINITION REVIEW REQUIRED`  
**日期**：2026-09-22  
**Gate**：Definition / Opening Draft —— 本文档只覆盖 §8.1 **第①步：研究对象是什么**；第②步及以后未启动  
**边界**：只定义候选研究对象的边界与明确排除项。不定义研究问题（②）、不论证独立性（③）、不定义 estimand（④）、不设存在/不足判据（⑤⑥）、不做 discriminating power（⑦）与值得测（⑧）判定，禁止 harness 构建（⑨）与一切采数。

## 0. 锚点与依据

| 项 | 值 |
|---|---|
| 状态事实源 | `docs/RESEARCH_STATE.md` |
| Agent 行为规范 | `docs/AGENT_CONTEXT.md`（`f7f2c7b`） |
| Gate 开启依据 | 项目所有者 2026-09-22 指令：开门，范围限 §8.1 第①步 |
| Track B 冻结收敛模型 | `4184aa6`（五元组 correctness invariant，跨线边界约束） |
| nodes-out 终点 | `2cf244e` + `b6ad7c0`（CLOSED；注册预测 §4.2 保持登记态） |
| RQ-F-01 | **NOT DEFINED** —— 本文档不产生研究问题，只产生对象边界 |
| RQ-P4-01 | NOT STARTED —— 不因本文档成为默认下一步 |

## 1. 第①步要回答的唯一问题

> 在"从模拟机制到真实 source/runtime"的候选方向上，**研究对象是什么？**
> 本文只回答：候选对象的边界是什么，以及哪些对象被明确排除。

第一原则（项目所有者锁定）：从"我们究竟想在真实 runtime 中证明什么"出发，而不是从"我们已有什么工具"出发。因此工具存在性（Runner / MLX / Swift）不构成任何候选对象的入选理由。

## 2. 候选对象边界

### C1. Model Unit（模型单元）

**候选边界**：真实 Swift/MLX execution 中，可能具有独立 residency / migration 语义的对象。

入选约束（边界条件，非答案）：

1. 必须能承载 Track B 冻结不变式：以该 unit 为粒度的 migration 必须可判定 "preserves execution identity and continuation"（五元组等价可检验）；
2. 候选资格必须由**实际访问模式**推导（nodes-out 遗产：访问模式决定粒度收益；管理便利性不产生候选资格）；
3. 必须在目标 runtime（Swift/MLX）的实际内存模型中**可表达独立驻留状态**（至少 resident/externalized 二态）。

候选族（开放列举，顺序不代表优先级，本文不预选）：

- layer 级；
- block 级（如 GDN / ATT 功能块）；
- tensor slice 级（per-token / per-position KV 切片）；
- KV cache segment 级；
- 其他由真实访问模式暴露的粒度。

哪一族（或其组合）进入研究问题，属第②步，本文不得预选。

### C2. Source/Runtime Mechanism（机制对应物）

**候选边界**：已封存模拟阶段结论中的机制类，在真实 runtime 中是否存在**可观察对应物**。

机制候选族（引用封存锚点，仅登记对象来源，不作为前提）：

1. 结构信号 → 驻留控制（H-P1，`edc4dad`，CLOSED/SEALED）；
2. 粒度 / 外化通道机制（nodes-out，`b6ad7c0`，CLOSED）；
3. 频率 / 准入类机制家族（P3 链，`ac71e34` SEALED）。

边界条件：

1. 本候选只问"对象与机制是什么、是否存在可观察形态"；性能问题自始不附着（机制存在 ≠ 性能优势）；
2. 已封存结论 = 冻结事实，可引用、不可重开：任何"在真实 runtime 中重新验证"都是**新问题**，不构成对 SEALED/CLOSED 线的 continuation；
3. P3 的 R-W 等具体结论按状态词汇禁止跨线导入为前提。

### C3. Measurement / Harness Fidelity（测量保真度）——依赖候选，本步不定义

**判定**：C3 不是独立研究对象，是 **C1/C2 的派生对象**。理由：保真度要求是"被测对象 + 机制假设"的函数；在 ①② 完成前，"什么程度的 fidelity 才够"没有可定义的输入。

处置：

1. 本步明确排除 C3 的对象定义与一切 harness 构建（Gate Forbidden 项）；
2. C3 的合法重入点：⑤⑥（存在/不足判据需规定观测与噪声）与 ⑦⑧（discriminating power 与值得测需成本口径）；
3. 届时 C3 若需对象化，应作为独立定义动作重新进入边界讨论。

## 3. 明确排除项（本阶段禁止入册）

| # | 排除对象 | 依据 |
|---|---|---|
| X1 | SimiGo 1.x 产品线对象 | 1.x ≠ 2.0 research line |
| X2 | 任何性能/优劣问题 | 九步序列未到达；C2 只问存在性 |
| X3 | SEALED/CLOSED 结论的重开或继续优化 | 状态词汇约束；禁止跨线推理 |
| X4 | 生产部署 / 多租户 / SLO / 经济成本对象 | nodes-out DV3 分析：从未在册且非最小面 |
| X5 | 旧 Contract 未拆分量（如 cold-load vs historical rehydrate） | Contract 1.3：须 Runner 修订 + Design Revision，属下游 |
| X6 | 创建 `mlx-swift-lm` 实验分支 | Track F NOT DEFINED；分支创建须先问（远端纪律） |
| X7 | 修改任何 FROZEN 资产身份 | 复用仅限新锚点参考实现 |
| X8 | 一切采数 / 测量 / 原型实现 | Gate Forbidden；本文档是纯定义动作 |
| X9 | 把注册预测（endpoint §4.2）自动升级为验证问题 | 预测保持登记态；是否验证属第②步以后独立决策 |

## 4. 本步产出声明

本文档产出 = **C1/C2 候选边界 + 三候选处置 + 九项全局排除**。

本文档不产出：研究问题、RQ ID 占用、estimand、存在/不足判据、任何实验授权。

第②步（研究问题是什么）启动条件：本文档外审 PASS。

## 5. 门位快照（与 RESEARCH_STATE.md 同步修订）

```text
GATE Definition/Opening        OPEN — 限 §8.1 第①步
STEP ① 研究对象                DRAFT / EXTERNAL DEFINITION REVIEW REQUIRED
STEP ②–⑨                      NOT STARTED
RQ-F-01                        NOT DEFINED（不变）
RQ-P4-01                       NOT STARTED（不变）
FROZEN 资产                    不变
DATA COLLECTION                LOCKED（不变）
```
