# Open Problems

本页仅登记当前产品中有证据支持、尚未关闭的问题；关闭须有对应验收读数。证据原件保留在原位置，本页不复制内容。

**基线：2026-11-05（本轮源码静态审查补充）。** 云端 provider 代理已于 2026-11-03 从产品源码移除。旧代理“外部转发真机 E2E 缺失”不再作为当前产品问题；其历史合同和证据继续保留供追溯。

| # | 问题 | 状态 | 证据 / 边界 |
|---|---|---|---|
| 1 | 自动答案复用未显式绑定本轮 resolve 的 demand identity | **高优先级待核验 / 待修复** | 2026-11-05 源码静态审查：HTTP Chat 的 `prepareInformationTurn` 先 resolve 当前 demand，自动 shortcut 再调用 `reusableAnswer`；MCP `simigo_es_begin` 则直接按 session + query 调用同一 `reusableAnswer`，不先 resolve 当前信息空间。该函数未接收本轮 `resolution.demandID`，也未比较历史 `answeredDemand.demandID` 与当前 demand。新增 committed chat row、文件或摘要可能改变当前信息空间，而旧 answer / retrieval settlement 仍可能有效。另一个审计风险：HTTP `recordReusedAnswer` 写 reuse event 时优先采用本轮 `turn.resolution.demandID`，因此若 shortcut 错误命中旧答案，消费记录可能被归到新 demand，不能单凭该 event 的 demand ID 证明答案来源与当前 demand 一致。尚无真实机器复现；不得写成已确认实机缺陷。建议先补 demand 变化、resolve-failure 与 reuse-event provenance 回归，再实施 fail-closed 比较；MCP 路径也须覆盖。 |
| 2 | 已结算答案在后续同 scope 请求中的消费资格与安装版 replay 证据 | 未关闭（部分观察已有） | [IS 外部轮次合同](../../architecture/IS_EXTERNAL_TURN_CONTRACT_20261030.md) §10：该窗口未观测同 scope 后续消费。§11.1 的 `replay=1` 是检索上下文复用标记，不是答案结算消费；§11.3 的 `model_calls=0` 后台标题/建议复用是跨日、跨 scope 的历史观察，不能代替同 scope 受控验收。Qoder 的 24408-token `memPoolHit` 是物理前缀/KV 加速，也不是 IS 语义答案复用。尚缺“同 scope 已结算答案→后续请求消费”的受控安装版验收；不得把不同层次的 replay / reuse 合并为同一证据。 |
| 3 | 客户端断连后本地轮仍停留在 `pending`，存储状态未表达请求已结束 | 未关闭 | 同合同 §10；fail-closed 防止错误结算，但状态未终止 |
| 4 | 本地路径缺少 `request_id` / `source_provider` | 未关闭 / 待裁定 | 同合同 §10；字段当前仅由历史外部数据合同路径使用 |
| 5 | Agent 类别（后台 rollout、内部记账等）的 `thread_source` 取证与检索资格 | 未关闭 | 同合同 §9；类别值及资格规则尚未完整取证 |
| 6 | W4 校准样本污染 | 独立问题未关闭 | prefill 时间门控路线已撤销；撤销不是修复，样本污染仍需独立处理 |
| 7 | 断连→重试的前缀保留 / 冷 prefill 不匹配 | 未关闭，待安装版验收 | [取消与 prefill ADR](../../decisions/ADR_LOCAL_OFFLINE_PREFILL_AND_CANCEL_20261030.md)：build 31 detach / bounded orphan 实现已落地；真机前缀保留路径未成立 |
| 8 | MCP `reusable_answer` 命中没有新的 ES 消费 / advancement 路径 | **源码静态审查发现 / 待合同裁定** | `simigo_es_begin` 首次调用先创建 active ES，再返回历史答案提示；命中只读，不写 reuse event、settlement 或 advancement。当前九个 MCP 工具中没有独立消费此答案并推进新 ES 的操作；若 Agent 跳过模型调用并直接采用答案，新 ES 留在 begun-but-unsettled。不能把 `model_calls=0` 当成新 ES 已消费旧结算的证据。尚无第三方 Agent 实际调用序列验收。 |
| 9 | MCP begin → settle 未绑定同一 tokenizer identity | **源码静态审查发现 / 待回归验证** | `simigo_es_begin` 将 `model` 写入 `execution_states`，resume 时只比较已存 model；`tokenizer` 仅用于 begin 时查询答案复用，没有写入 ES。`simigo_es_settle` 再由调用方提供 tokenizer，并用该值建立 producer binding，但未与 begin 时 tokenizer 比较。因此同一 state 可在 begin 时声明 tokenizer A、settle 时声明 tokenizer B；这不等于身份已被跨生命周期固定。尚无实机复现；应补 begin(A) → settle(B) 的拒绝测试，再决定最小修复。 |
| 10 | 显式 settlement consumption 的 consumer ES identity 与 consumer binding 可分别声明 | **低优先级 API 不变量缺口 / 待核验** | `SimiGoSettlementConsumption.Request` 同时接收 `consumerModelIdentity` 与 `consumerIdentity`。当前消费路径用 `consumerIdentity` 对源 settlement 做 admission / 写入 consumer binding，却用独立的 `consumerModelIdentity` 创建 consumer ES；未见二者 model 字段必须相等的入口不变量。调用方与现有测试通常传相同值，但 API 本身允许不一致声明。尚无错误调用实证；建议先补 mismatch 拒绝测试，再决定是否在 initializer 或 `consume` 前置校验。 |

## 使用规则

- 只有在修复前后证据满足对应范围时才关闭问题，并链接验收读数。
- 冻结证据（`docs/audit/`、`docs/experiments/`、`docs/benchmarks/`、`docs/lessons/`、`research/`）不因索引精简而删除或改写。
- 不将已撤销路线列为当前产品待办；不把测试层通过扩大为安装版或第三方 Agent 通过。
