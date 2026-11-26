# digest 替换态消费契约 v0.1

初稿：2026-11-26；successor15 解封：2026-11-27。状态：**已通过 successor13 L3 语义/结构验收；不构成物理 KV 复用结论**。

本件规定 digest 替换时随呈现携带的来源信息、拒收/回退行为和可宣称边界。术语只引用 [ES/IS 术语正本](TERMINOLOGY_V0.1_20261109.md)，不在本件另立定义。

## 1. 被测问题与结论

被测问题是：推理前缀中的逐字历史换成 digest 后，模型是否仍能选择 current source，并给出与 IS 账本一致的 source ID、version、value、status 与 dependency 绑定。

`spike_pe_e2_successor13_l3_20261126` 的九格 raw/digest 配对结果为：

| arm | valid | contract pass | rate | selection | envelope | binding | types | parse | stale | fabricated |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| raw | 9 | 7 | 0.7778 | 8 | 8 | 7 | 7 | 8 | 0 | 0 |
| digest | 9 | 9 | 1.0000 | 9 | 9 | 9 | 9 | 9 | 0 | 0 |

`model_calls=117`。九个有效配对中 raw 通过 7 格、digest 通过 9 格，raw − digest = −0.2222。该读数支持 **L3 授权研究隔离呈现下的 digest 消费保真**；raw 不是完美控制，差值不单独归因于替换。

三方链一致：

- runner 汇总：`records/SUMMARY.md`，digest 9/9，九格 B6 各 13 条且 `hit>0` 全为 0。
- 独立验收：`records/independent-audit.json`，`audit_pass=true`、`l3_accepted=true`、`formal_scores_rewritten=false`，授权 `E25329FF-B700-4E0E-B65C-A4BBA271E07D` / `51ED78A7-6833-4BEC-999C-223B9D51DE67`。
- 巡更窗原始证据复算：`0FA26BFD`。successor13 freeze `53d97674` 封存未改；审计副本 successor14 freeze `64869b287e2f1d3b4b9ccb40d29a85e7baef378158021c96ad9f3e5e3f2b7e6c` 的 15/15 文件 MATCH。

## 2. 实现契约

### 2.1 来源载体与裁决分离

digest 后追加逐字 source carrier，至少携带 `source_id`、`version`、`status`、`supersedes`、`value`。载体用于让模型看见来源裁决所需的精确字段；最终 current/source/version/value 仍由模型按消费合同输出，载体不是答案模板。

代码锚点：

- [TurnDigest.swift:99](../../../Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/TurnDigest.swift#L99)：`digestWithSourceCarrier`。
- [TurnDigestScheduler.swift](../../../SimiGo/App/TurnDigestScheduler.swift)：增量 drain 与补录 `fillMissing` 写入同一载体。
- [HTTPServerChat.swift](../../../SimiGo/Protocol/HTTPServerChat.swift)：暖摘要写入同一载体，渲染时解析来源块。

### 2.2 坏载体不进入替换前缀

L3 来源块损坏时，从受损 turn 起保逐字历史，不用坏来源块继续替换。替换仍取最长合法连续覆盖前缀；其余保 raw。压实时必须保留完整来源块，不能把 source ID/version 与 value 拆散或丢弃；预算不足时回退 raw，而不是截断 carrier。

代码锚点：

- [DigestPrefixCompaction.swift:78](../../../SimiGo/Protocol/DigestPrefixCompaction.swift#L78)：`briefPreservingSources`。
- [HTTPServerChat.swift:1067](../../../SimiGo/Protocol/HTTPServerChat.swift#L1067)：来源预算不足记 `l3_source_budget` 并回退。

### 2.3 诊断不等于放宽格式门

`TurnDigestText.parse` 的接受/拒收语义不变。拒收只增加稳定 reason 与不含模型原文的诊断：session 短标识、turn index、raw SHA-256、UTF-8 字节数、非空行数。稳定 reason 为 `unlabelled_line_count`、`unlabelled_keyword_count`、`empty_digest`、`missing_keywords`、`empty_keywords`。

代码锚点：

- [TurnDigest.swift:292](../../../Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/TurnDigest.swift#L292)：parse 与 `onReject`。
- [TurnDigestScheduler.swift:82](../../../SimiGo/App/TurnDigestScheduler.swift#L82)：`traceParseRejection`。
- 测试：[TurnDigestSearchTests.swift](../../../Packages/SimiGoRuntime/Tests/SimiGoRuntimeContractTests/TurnDigestSearchTests.swift) 的 `testDigestParseReportsStableRejectionReasons`。

### 2.4 命名空间与隔离端口

`scopedKind` 先剥旧 `@scope`，再按认证 scope 重挂，保证单后缀且不能逃逸认证命名空间。历史双后缀行不改写。

暖摘要 fallback 端点按 `SIMIGO_PORT` → 持久化 `AppConfig.apiPort` 解析，不再对隔离端口失明。该改动不放开生产 8000，也不改变安全联锁。

代码锚点与测试：

- [ESISDatabaseInformationSpace.swift:2184](../../../Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/ESISDatabaseInformationSpace.swift#L2184)；`MCPInformationSpaceTests/testScopedKindIsIdempotentAndCannotEscapeAuthenticatedScope`。
- [TurnDigestScheduler.swift:68](../../../SimiGo/App/TurnDigestScheduler.swift#L68)；`TurnDigestRetryTests/testDigestRequestUsesEnvironmentPortBeforePersistedPort` 与 `testDigestRequestUsesPersistedPortWithoutEnvironmentOverride`。

## 3. 逐轴更正轨迹

以下是对同一封存九格证据的审计/呈现修正，不是新模型运行，也不回写正式分：

| 轴 | L3 前诊断 | L3 后 | 修正对象 |
|---|---:|---:|---|
| delivery_types 首阻 | 8 | 0 | 审计器把零 blocker 误判为未清 |
| binding / dependency / value_exact | 0 | 9 | L3 载体交付 |
| source_id_exact | 1 | 9 | L3 载体交付 |
| version_exact | 2 | 9 | L3 载体交付 |
| selection | 3 | 9 | L3 载体交付 |
| stale | 3 | 0 | L3 载体交付 |

早前 `raw 7 / digest 0` 是审计器对 L3 交付的伪影，不是 digest 臂的模型语义 0/9。修正后正式汇总为 raw 7/9、digest 9/9；原正式分与 successor13 freeze 均保持不变。

## 4. 验收边界

本契约**只证明**：

- 一个本地 Ornith 模型、一个 L3 产品 build 身份、每臂单次运行、greedy、无工具。
- `research_isolated` 呈现模式下，经授权的 L3 source carrier 能维持九格消费合同的语义/结构读数。
- digest 九格的 stale、fabricated source ID、foreign prompt/retrieval 均为 0。

本契约**不证明**：

- 物理 KV 复用或缓存收益。digest 九格 B6 共 117 条回执，`cache_hit_positive=0`；不能从 raw 臂命中外推 digest 臂收益。
- 产品模式 lineage join、IR adapter、E3 产品修改或自主 IS 检索。
- 非 greedy、跨模型、跨 backend、跨平台、工具调用或一般 supersede 能力。
- 九格相互独立。九格是有序序列，raw 也不是完美控制。

车道三 B/D/A 的长期运行、fork 恢复与产品修改验证仍待单独授权和执行；本件不代替那些读数。

## 5. 证据入口

实验编号、授权与原始件位置见 [实验索引](../../experiments/README.md)。宣称只可复述本件第 1 节的真实读数与第 4 节边界；不得删去 `cache_hit_positive=0` 或把语义/结构验收改写成物理复用验收。
