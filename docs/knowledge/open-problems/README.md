# Open Problems

本页仅登记当前产品中有证据支持、尚未关闭的问题；关闭须有对应验收读数。证据原件保留在原位置，本页不复制内容。

**基线：2026-11-05（本轮源码静态审查补充）。** 云端 provider 代理已于 2026-11-03 从产品源码移除。旧代理“外部转发真机 E2E 缺失”不再作为当前产品问题；其历史合同和证据继续保留供追溯。

| # | 问题 | 状态 | 证据 / 边界 |
|---|---|---|---|
| 1 | 自动答案复用未显式绑定本轮 resolve 的 demand identity | **部分修复（2026-11-08）· 冻结交互已实证并修复** | 2026-11-05 源码静态审查的 demand-identity 缺口已由 `reusableAnswer` 的 `expectedDemandID` 严格门关闭：门要求本轮 resolve 的 demand 非空且与历史 `answeredDemand.demandID` 相等，resolve 失败即 fail-closed。2026-11-08 本机实证补上第二处真缺口：IS 冻结快照（`ISContextLedger.stabilize`）与当前候选 demand 分叉时，复用门读的是冻结 demand，跨会话新信息落地后旧答案仍被 `model_calls=0` 回放（Responses 线实测复现）；修复=分叉时整轮刷新冻结快照（渲染/结算/门三者同读一份新快照，`frozenRefresh=1` 可观测），复用门改读当前候选 resolve。同批补齐 demand 变化、resolve-failure、reuse-event provenance 回归（Chat/Responses/MCP-E2E 隔离 lane 8 用例）。残余待验：真机负载下的冻结刷新频率与前缀成本仍无实测读数。 |
| 2 | 已结算答案在后续同 scope 请求中的消费资格与安装版 replay 证据 | 未关闭（部分观察已有） | [IS 外部轮次合同](../../architecture/IS_EXTERNAL_TURN_CONTRACT_20261030.md) §10：该窗口未观测同 scope 后续消费。§11.1 的 `replay=1` 是检索上下文复用标记，不是答案结算消费；§11.3 的 `model_calls=0` 后台标题/建议复用是跨日、跨 scope 的历史观察，不能代替同 scope 受控验收。Qoder 的 24408-token `memPoolHit` 是物理前缀/KV 加速，也不是 IS 语义答案复用。尚缺“同 scope 已结算答案→后续请求消费”的受控安装版验收；不得把不同层次的 replay / reuse 合并为同一证据。 |
| 3 | 客户端断连后本地轮仍停留在 `pending`，存储状态未表达请求已结束 | 未关闭 | 同合同 §10；fail-closed 防止错误结算，但状态未终止 |
| 4 | 本地路径缺少 `request_id` / `source_provider` | 未关闭 / 待裁定 | 同合同 §10；字段当前仅由历史外部数据合同路径使用 |
| 5 | Agent 类别（后台 rollout、内部记账等）的 `thread_source` 取证与检索资格 | 未关闭 | 同合同 §9；类别值及资格规则尚未完整取证 |
| 6 | W4 校准样本污染 | 独立问题未关闭 | prefill 时间门控路线已撤销；撤销不是修复，样本污染仍需独立处理 |
| 7 | 断连→重试的前缀保留 / 冷 prefill 不匹配 | 未关闭，待安装版验收 | [取消与 prefill ADR](../../decisions/ADR_LOCAL_OFFLINE_PREFILL_AND_CANCEL_20261030.md)：build 31 detach / bounded orphan 实现已落地；真机前缀保留路径未成立 |

## 使用规则

- 只有在修复前后证据满足对应范围时才关闭问题，并链接验收读数。
- 冻结证据（`docs/audit/`、`docs/experiments/`、`docs/benchmarks/`、`docs/lessons/`、`research/`）不因索引精简而删除或改写。
- 不将已撤销路线列为当前产品待办；不把测试层通过扩大为安装版或第三方 Agent 通过。
