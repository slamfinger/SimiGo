# 路线 B · DeepSeek ES/IS 语义提案推进建议

**Status**: ROUTE RECOMMENDATION — 内部路线材料；未授权对外发送、公开仓库或提交任何外部材料
**Date**: 2026-11-05
**Scope**: 面向 DeepSeek 及更广泛开源生态的 ES/IS 语义提案路线；与路线 A（llama.cpp 工程上游，见 `docs/experiments/UPSTREAM_ISSUE_DRAFT_kv_prefix_sharing_cow.md`）相互独立
**Boundary**: 遵守 `OPEN_SOURCE.md` 的公开证据边界：不把有界证据升级为 universal / backend-independent / mathematically minimal 宣称

---

## 0. 姿态修订（2026-11-05，用户裁定）

路线 B 的目标由「向开源生态提出 ES/IS 架构」调整为「**向相关技术社区开放 ES/IS 研究，邀请独立审查与复现**」。定位为 Research Note / Independent Technical Review：不要求任何对象接受 ES/IS，把判断权交给审查者；不预设普遍适用性，不预设任何项目需要采用它。对方认为没有新意、发现互补、复现成功、最终不采用——都是有效审查结果。

定位文本、分对象邀请矩阵、证据前置条件（P1–P3，P2 硬前置）与纪律见 [ROUTE_B_RESEARCH_NOTE_POSITIONING_20261105.md](ROUTE_B_RESEARCH_NOTE_POSITIONING_20261105.md)。§3 的 working title（"A Semantic Architecture for..."）降为内部工作标题；B4 交付物相应改为 Research Note v0。

---

## 1. 路线定位

| | 路线 A · 工程实现 | 路线 B · 架构语义 |
|---|---|---|
| 面向 | llama.cpp 上游 | DeepSeek 及开源模型 / 推理引擎 / Agent 生态 |
| 解决 | 引擎能力缺口：可寻址、可验证的 sequence/branch fork 与生命周期管理 | 语义问题：执行生命周期结束后，哪些结果仍具备可靠续接价值，以及如何在新生命周期中恢复 |
| 交付物 | 最小 API 提案 + 实现 + 测试 + 真实模型复刻证据 | 语义规范 + 最小形式化 + 机制说明 + 实验证据 + 复刻指南 |
| 失败影响 | llama.cpp 不接受 → 不影响路线 B | DeepSeek 不采纳 → 不影响 SimiGo 与路线 A |

两条路线共享 SimiGo 这一个参考实现与证据库，但提案文本、受众、节奏完全分开。任何一条停滞都不拖垮另一条。

## 2. 必须先修正的一个假设：渠道现实

路线 A 有明确的公共接纳机制（GitHub issue / PR）。路线 B 所设想的"向 DeepSeek 技术部门提交"目前不存在对应的公开 intake 流程：DeepSeek 的开源资产是模型权重与算子/系统组件（FlashMLA、DeepEP、DeepGEMM、3FS 等），没有面向外部架构提案的受理通道。

因此建议把路线 B 的定义从"提交给 DeepSeek"改为：

> 以公开、可复刻的语义规范为核心交付物；DeepSeek 是目标受众之一，而不是受理机构。

现实可行的次序：

1. **公开发布语义成果**：规范文档 + 参考实现 + conformance，使其成为任何人（包括 DeepSeek）都可以讨论、实现、复刻的开放技术成果；
2. **第一优先受众改为能落地实现的生态**：深度支持 DeepSeek 架构的推理引擎（vLLM、SGLang 等）与 Agent 框架——ES/IS 作为语义层，最可能先在"服务 DeepSeek 模型的系统"里被采用；
3. **对 DeepSeek 本身的触达**作为独立的 outreach 步骤（官方渠道、开源社区、研究接触），放在材料成熟之后，且逐次单独确认授权。

这样修正后，路线 B 不再依赖"是否有人收件"；DeepSeek 的参与成为加分项而非前置条件。

## 3. 提案主题与核心论点

Working title：

**Execution State (ES) and Information Space (IS): A Semantic Architecture for Reliable Continuation Across Model Execution Lifecycles**

> 命名裁定（2026-11-05）：IS = Information Space（信息空间），沿用仓库既有名称，不引入 "Information State"。

五个核心论点（每条必须绑定证据，不允许概念自证）：

1. **ES — 执行续接权威**：管理执行进展、分支、续接与结算，不绑定单一模型或引擎的 KV 生命周期。
2. **IS — 信息结算账本**：保存已结算、语义充分、依赖完整、可验证的结果，及其来源、版本、依赖与有效性依据。
3. **Carrier independence**：KV cache、sequence、slot、数据库等只是载体，不是执行或信息的最终权威。
4. **Selective re-execution**：已结算且有效 → 恢复使用；缺失、失效或依赖变化 → 才重新执行。
5. **Model & engine independence**：语义不限定于 DeepSeek、llama.cpp、MLX 或任何特定 Agent 框架。

反论点（必须显式写入提案，可信度取决于此）：

- 这不是 KV Cache 优化；
- 这不是"把历史对话存入数据库"；
- 这不是通用 checkpointing 的重新命名——与相关工作的差异见 §5。

## 4. 提案文档骨架（v0 结构）

1. Problem statement（执行生命周期结束后的可靠续接问题）
2. Semantic core：ES/IS 定义、结算判定、有效性谓词、载体独立原则（最小形式化：状态空间、转移、结算与失效规则；不需要完整定理化，但必须精确到可实现）
3. Mechanism：参考实现如何执行这些语义（SimiGo）
4. Evidence：实验与测试映射（见 §6）
5. Related work 与差异（见 §5）
6. Non-goals 与证据边界（引用 `OPEN_SOURCE.md` 的边界声明）
7. Replication：冻结的 Execution State Contract + conformance 套件 + 独立实现指引（CC-BY-4.0 规范层 / Apache-2.0 运行时层）
8. Open questions（明确保留未验证部分，延续 `docs/research` 的 hypothesis 分层原则）

## 5. Related work：最大的学术风险点

审阅者的第一反应大概率是："这就是 checkpointing / session persistence"。这一节必须先行准备，逐项给出差异：

| 已有方向 | 代表 | ES/IS 的差异点（待论证） |
|---|---|---|
| KV cache 复用/卸载 | vLLM prefix caching、LMCache、CacheGen、CacheBlend | 它们复用计算结果，但不定义"结算与有效性"的权威；ES/IS 以结算账本决定何时可信复用、何时必须重执行 |
| Durable execution | Temporal 等 workflow 引擎 | 持久化的是控制流状态，不是模型执行语义（分支恒等、续接、跨载体迁移） |
| Agent checkpointing | LangGraph 等 | 保存对话/图状态，不提供结算有效性依据与载体独立性 |
| 会话恢复 API | 各厂商 resume/continuation | 供应商内建的载体绑定恢复，无开放语义契约 |

注意：本表"差异点"一列目前是主张而非已验证结论——按 `docs/research` 原则应作为 hypothesis 处理，在提案 v0 中明确标注。

## 6. 证据基础：从现有仓库可直接导出的映射

| 语义主张 | 已有实现 / 测试 / 实验材料 |
|---|---|
| 分支生命周期 | `SimiGoTests/LOCALBBranchLifecycleTests.swift`、`SimiGoTests/LOCALBManagementEntryTests.swift`、`docs/decisions/BRANCH_FORK_PROTOCOL_DRAFT.md` |
| 结算契约 | `SimiGoTests/ResponsesContinuationSettlementContractTests.swift`、`SimiGoTests/ResponsesSettlementConsumptionHTTPTests.swift` |
| 跨路径恒等 | `SimiGoTests/CrossPathSettlementIdentityHTTPTests.swift` |
| 续接准入 / 预算 | `SimiGoTests/ResponsesContinuationAdmissionGateTests.swift`、`SimiGoTests/RequestAdmissionHTTPTests.swift`、`SimiGoTests/RequestBudgetTests.swift` |
| 取消链语义 | `SimiGoTests/CancelChainInternalTests.swift`、`SimiGoTests/CancelPathSupport.swift` |
| 分叉实验线（Track B） | `docs/research/EXECUTION_STATE_RESEARCH_STORY_20260922.md` 及其 F 系列实验记录 |
| 合同冻结与许可 | `OPEN_SOURCE.md`（CC-BY-4.0 规范层 / Apache-2.0 运行时层） |

原则：提案中的每条核心论点都应能引用至少一条上述证据；引用不到的论点降级为 open question，不提前升级。

## 7. 推进顺序（全部为本地工作，无外部动作）

| 步骤 | 工作 | 产出 |
|---|---|---|
| B0 | 中英术语表（15 项：正/反定义、实现映射、OPEN 清单；仅冻结术语对应关系，不冻结未证明语义边界） | [B0_ESIS_GLOSSARY_20261105.md](B0_ESIS_GLOSSARY_20261105.md) — **ACCEPTED**（2026-11-05；OPEN 收敛为 OQ-1 / OQ-3 / OQ-8） |
| B1 | 最小形式化（关系骨架 ES_n ──Settlement──▶ IS ──Admission──▶ ES_{n+1}；规则 R1–R6；状态转换；恢复时约束；KV = 可选载体；三项 OPEN 显式保留） | [B1_ESIS_MINIMAL_FORMALIZATION_20261105.md](B1_ESIS_MINIMAL_FORMALIZATION_20261105.md) — **ACCEPTED**（2026-11-05 定案；Settled(ρ) 按解释性定案，不改正文） |
| P2 | 真机实验方案与公开复刻链（四阶段：真实模型结算 / 旧 KV 实际释放 / IS 恢复 / 全新 ES 续推；每阶段含可观测证据、复现步骤、预期读数、反例判据、阶段因果；两条验收红线） | [P2_EXPERIMENT_PLAN_20261105.md](P2_EXPERIMENT_PLAN_20261105.md) — **G1 PASS · CLOSED**（2026-11-05）；[配置记录](P2_CONFIG_RECORD_20261105.md)：①②③定案、④提案待裁定、⑤未起草；[交接报告](HANDOVER_TO_NEXT_AGENT_20261105.md)（移交新 Agent 实施）；实验执行授权另行保留 |
| B2 | 从测试/实验导出 evidence map（固化 §6） | 证据映射文档 |
| B3 | related-work 对照与差异论证（§5 由 hypothesis 升级或降级） | 对照文档 |
| B4 | Research Note v0（研究定位优先于架构定位；按 §4 骨架成文，受定位文档 P1–P3 证据前置门控，P2 硬前置） | 研究说明文档 |
| B5 | 复刻指南（外部实现者视角：只依赖冻结合同 + conformance；与定位文档 P1「面向外部的精简语义说明」合并推进） | 复刻指南 |
| B6 | 渠道盘点（llama.cpp 第一优先，其余后续；一次一个对象；只调研，不发送——授权边界不变） | 渠道清单 |

与路线 A 的耦合：B2/B5 的证据与复刻材料可与路线 A 共享，但提案文本、受众与时间线完全独立。

## 8. 状态声明

- 本文件是内部路线建议，不构成对外发送授权。
- 任何公开或提交动作（公开仓库、发送材料、创建 issue/PR、联系任何组织）都需要届时单独确认。
