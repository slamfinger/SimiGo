# 信任边界裁定：单机可信 与 多人多权限

**日期**：2026-11-12
**状态**：生效（Owner 裁定）
**范围**：IS 信息空间的信任前提，以及 Responses 结算通道上 `result_contract` 的职责边界

## 1. 裁定

1. **当前语义前提**：单机、单人、局域网、生产环境本身可信。在这个前提下，`result_contract`
   不承担防伪职责——它是「这次结算用了哪一版验收规则」的声明通道，权威在生成之后、落库之前
   一次用尽；复用只看 payload digest、有效期与上游闭包，不看契约本身，也不需要第二套签发机制。
   2026-11-12 的实测（陌生消费者复用成功、契约正文不入库）是这条的直接证据。
2. **多人多权限不属于 IS 语义**：它要解决的是「谁能往空间里写、谁能读哪个房间」，属于 SimiGo
   侧的认证与写闸，需另行开发。IS 不因为这件事改 schema，也不在结算行上加签发。
3. **研究状态**：身份、授权、多人边界**曾经进入研究方向**，但摊子铺得过宽，在架构收敛阶段被
   暂时封存，之后没有继续。现存 `docs/` 里没有成篇记录，只剩 §3 那三处旁证。所以第 1、2 两条
   是**裁定**，不是从既有研究里推出来的结论；也不要把「文档里没写」读成「从来没想过」。

## 2. 为什么现在写这一条

不动这一条，会反复出现两种误读：把契约当成权限或防伪机制（它没有这个职责，实测也做不到），
或者把「多人多权限」当成 IS 该顺手解决的事（它不是，硬塞进来会把 schema 和语义一起拖脏）。
写清楚，是为了让后面每一次讨论都能从同一个前提开始。

## 3. 现有旁证（现状描述，不是研究结论）

| 位置 | 内容 |
|---|---|
| `docs/AGENT-ACCESS.md` §2.7 | 明文回环不要求 LOCALB 证明（Owner 裁定 2026-10-26），响应带 `unprotected-by-LOCALB`；非回环必须 TLS；TLS 下身份只能来自签名 JSON 字段，header 选身份一律拒绝 |
| `docs/AGENT-ACCESS.md` §4 | `MCP 工具粒度鉴权：未做`；`MCP 身份自证：model / tokenizer 由调用方自报，SimiGo 无法察觉谎报，它记录的是声明` |
| `docs/decisions/V4_5_STABLE_FOUNDATION_BASELINE.md` §7 | `LAN 多用户并发吞吐`是性能实验轨道（batched decode），不是权限模型 |

## 4. 未做的事

- 没有身份、授权、租户隔离的任何实现或实验。
- 任何进入多人多权限的尝试都要重开研究，不能在这条裁定上打补丁：认证放哪一层、写闸粒度
  （空间 / 房间 / 行）、读权限与检索索引的关系，全部空白。
- 本裁定不授权任何代码改动。它只固定「现在按单人可信走」这个前提。

## 5. 实证补充（2026-11-12，build 56 真库）

事实：

- `settlements` 共 1441 行，其中 **18 行 `result_contract_id` 非空**，`validation_status` 全为
  `VALID`，`result_contract_digest` 均为 64 位十六进制。声明值只有两个：
  `simigo.continuation.restatement`（15 行）与 `simigo.result-contract`（3 行）；`contract_version`
  单一取值 `simigo.result-contract/v1`。也就是说「这次结算用了哪一版验收规则」已经落在真实结算行上，
  不再只是设计。
- 落库的是 id 与 digest，不是验收规则正文——与 §1 第 1 条「契约正文不入库」一致。
- 准入不比较消费者身份：`ISAdmission.admit` 第 150 行是 `_ = consumer`，注释写明签名留给既有调用方、
  语义准入不比较消费者身份与生产者出身；身份仍在第 6 步读出作为溯源。真正的身份比较留在物理侧，
  `ISKVBindAuthority` 与 `NativeMLXPrefixPool` 调用 `SettlementIdentityBinding.evaluate` 判断某个
  KV 表示能否被当前引擎恢复。
- 因此 `SimiGoTests/ExecutionStateGraphAdmissionTests` 里断言「不同模型产出即拒绝」的用例属于
  2026-11-12 之前的语义，已改写为 `testStoreAdmitsValueProducedByDifferentModelAsProvenance`
  （断言可准入、`recoveredValue` 与 `verifiedBindings` 正确）；旧名 `testStoreRefuses…` 不再存在。

边界（这段没有证明的）：

- 同族断言其余仍成立且未改：`GovernedContinuationKVRestoreRealModelE2ETests` 的 A12（身份不匹配
  期望 422）、A13（依赖变更期望拒绝）与池声明篡改用例断言的都是**物理 KV 恢复**前的拒绝，属于上面
  说的物理侧，不是准入门。
- 18 行都来自本机同一进程的写入，没有跨模型 A→B 的受控读数；「换模型后旧结算仍可准入」本轮只在
  测试层验证，未在真机换模型跑。
- 这只是准入读取路径的读数，不构成「跨模型 KV 复用可行」的证据：物理表示绑定在准入第 6b 步由引擎
  recompute + verify，不匹配即 decline 并回落冷 prefill。
- `simigo_es_settle` 仍要求 `model` 与 begin 一致（`HTTPServerMCP.swift` 的 begun-model 检查未改）。
  这条约束的是执行主体的声明一致性，不是准入门。
