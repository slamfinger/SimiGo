# G2 批次授权（2026-10-20）

**授权编号：`G2-BATCH-AUTH-20261020-01`**

**状态：`AUTHORIZED — ONE BATCH ONLY`**

本授权由研究负责人于 2026-10-20 签发，只覆盖一轮 G2 批次。它不表示 manifest 已生成，也不表示批次已启动；G2-A / G2-B / G2-C 目前均未通过。

## 1. 授权依据

| 依据 | 记录 |
| --- | --- |
| 冻结预注册 | `docs/01-questions/G2_PREREGISTRATION_20261020.md`（`FROZEN`） |
| 冻结模型 binding | `docs/01-questions/G2_MODEL_BINDING_20261020.json`（`SIMIGO-G2-MODEL-BINDING-V1`） |
| A2 P0 补充记录 | `docs/01-questions/G2_P0_SUPPLEMENT_A2_20261020.md` |
| A2 执行条件 | `docs/01-questions/G2_P0_A2_EXECUTION_CONDITION_20261020.json` |
| P0-A2 终态 | `…/g2/p0/20261020T075257Z/terminal.json` = `PASS`；结果记录 `P0_A2_RESULT_20261020.md` |

P0-A2 的 `PASS` 解除的是 P0 门槛，不是 G2-A、G2-B 或 G2-C 的证据门槛。

## 2. 授权范围

- 矩阵：3 个 fixture × {A 连续基线, B phase 1, B phase 2} = 9 次模型进程启动；每个 fixture 另加 2 次负对照验证进程（不加载模型）。
- 计划模型启动 9 次；**最大模型启动 9 次**；重试 0 次。
- 负对照进程最多 6 次，必须在模型加载前完成拒绝验证。
- 批次指定进程调用总上限 15 次（9 + 6）。
- P0 / P0-A2 的模型启动属于此前独立授权，不计入本批次预算。
- 只覆盖一份 manifest 和一轮批次；不得更换 fixture、模型目录、后端、依赖版本、矩阵或执行条件。

## 3. 执行前置门槛

首次模型启动前必须同时成立：

1. manifest 与冻结预注册、binding、P0-A2 终态记录逐项一致；
2. manifest 全文、摘要、执行器身份、模型目录与预算写入可审计记录，工作树干净；
3. A2 制品 17 个文件与聚合摘要再次核验，且引擎身份与 P0-A2 的结果一致；
4. 每个 fixture 的 Phase 1 数据库、独立负对照副本与 Phase 2 隔离条件按冻结设计就绪；
5. 负对照路径不加载模型，缺失 settlement 以 `SETTLEMENT_MISSING` 拒绝，篡改 payload 以 `OBJECT_DIGEST_MISMATCH` 拒绝。

任一条不满足即停止，不得修改冻结预注册或隐式扩大授权。

## 4. 执行硬约束

- Phase 1 结束后记录旧模型进程终止、旧执行状态与隔离 store 的证据；
- Phase 2 必须经 Information Space 恢复已结算结果，并在新 Execution State 中继续下游计算；
- Phase 2 不得重新执行 U1，不得把重新调用或重新调度 U1 解释为正常恢复行为；
- 按预注册扫描 canary；canary 出现在 `R1` 则判定该 fixture 无效并停止整个批次，不得静默重建后继续；
- 按预注册 §11 的终态与停止规则处理失败、超时、身份偏差与证据缺失；
- 不得重试、补跑、替换 fixture／模型／后端，或启动批次以外的模型进程。

## 5. 结果与证据

原始输出与运行记录追加保存，不覆盖、不伪造。逐条记录执行状态、模型进程身份、关键时间点、实际请求与渲染提示词、工具调用、KV/cache 观察、Information Space 与 Execution State 证据、失败与停止原因。最终分别裁定 G2-A、G2-B、G2-C；整批进程成功退出不等于研究主张成立。

未测试的峰值内存、符号链接读取器缺陷与 tokenizer 跨目录可复现性仍属未证明事项。

## 6. 明确排除

不修改 `EngineModelIdentity`、Frozen Contracts、Carrier 实现、signer 或冻结预注册正文；不删除 A2 模型副本；不进行第二轮、补充轮或扩展矩阵；G1 保持 `CLOSED`。任何超出本授权的变更须取得新的显式授权，包括本批次失败后的重跑。
