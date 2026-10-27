# IS 结算与 KV 复用之间的接线缺口（机制级，含可证伪实验）

同一构建：commit `97043902075b…` + 工作树摘要 `90ca17817406e6f8`，二进制 `4f82de1c…`。
本篇只写代码级事实与结论边界；真机读数见 `ACCEPTANCE-20261026-BUILD-97043902.md`。

## 1. 产品里 KV 复用的真实键（事实）

前缀池（`SimiGo/Inference/NativeMLXPrefixPool.swift`）：

- 命名空间 = `modelID` + `kvFingerprint|think:0|1`（`:71-77`）。
- 条目键 = `"<modelID>|<kvFingerprint>|<tokenCount>|<tokenChainHash>"`（`:179`）——**哈希来自 token 序列本身**。
- 跨会话装载钩子：`installHook` 把 `ChatSession.crossSessionPrefixLookup` 设为「按来方 prompt token ids 查池 → sidecar 对账 → 装载快照」，命中即 `mode=restore`（`:125-145`，trace `poolTokenHit tokens=`）。
- 导出：轮末按「全长 + 2048 网格」边界导出快照，需 `tokenIds.count > 2048`（`:149-191`）；命名空间只绑**基配置**指纹，非基 kvSettings 会话不导出边界（`:120-124` 注释）。
- 开关：`RuntimeTuning.prefixPoolEnabled`（`SimiGo/Lifecycle/RuntimeTuning.swift:44`）。本机构建实测为开启（trace 有 `poolBind/poolExport` 记录）。
- `SimiGo/Inference/ExecutionControlling.swift:3-17` 是治理红线：五个动作「薄封装零新语义」，`restore → NativeMLX.loadSessionCache`（raw-cache 语义），并注明真共享 fork 的经济性在 admission 层（poolBind），上游原语路线已裁定关闭（`UPSTREAM_BACKUP_ON_FORK` 决策记录）。

结算/准入侧（`NativeMLX.swift:1141-1161`、`ContinuationSettlement.swift:251-300`）：IS 准入产生的 `recoveredValue` **只作为 user 文本注入消息链**；`RepresentationKind` 没有 IS 对象类型；池键里没有 settlement_id / payload_digest / 生产者身份。

## 2. 结论（由 1 的机制直接得出）

产品确实有跨会话 KV 复用，但它的身份是「token 链前缀哈希」，不是「已验证的结算」。这带来两条硬后果：

1. IS 恢复与 KV 命中在结构上互斥：IS 结算值以文本形式进入新 ES 的 prompt，新 prompt 的 token 链因此与被结算时的前缀不同 → 池键必然不同 → 必然 miss。真机读数与此一致：阶段二 `mode=cold cacheHitTokens=0 prefill 2360/2360`（阶段一为 2169 prompt tokens；差额即注入文本）。
2. 反过来，池命中的那次复用（`mode=restore`）不构成 IS 证据：它只证明「同样的 token 前缀再出现一次」，与结算有效性、依赖版本、生产者身份无关。

所以审查报告的 P0 需要精确表述为：**不是「没有 KV 复用」，而是「KV 复用不由 ES/IS 驱动，且 IS 注入方式会主动破坏命中条件」。** 避免重复计算这一命题要在产品里成立，缺的是把「已验证结算」变成执行器可消费的表示身份，而不是再优化池本身。

## 3. 最小接线（建议，未实施——需授权后动产品代码）

保持 `ExecutionControlling` 的薄封装红线，不新增第二套执行语义：

- 结算时在 `settlement_bindings` 增写两条派生绑定（现有 schema 已支持，无需新表）：
  `kv.pool_key` = 池条目键（含 tokenCount + 链哈希 + namespace），`kv.cache_fingerprint` = `kvFingerprint`；
  这样「已结算计算」第一次获得可寻址的表示身份，并可被 `is_dependency_entries` 的 revision 一同失效。
- 续跑准入时（`NativeMLX.swift:1141` poolBind 之前）：若父结算带 `kv.pool_key` 且 `validation_status=VALID`、依赖未失效、生产者身份与本请求一致 → 用该 key 直接 `load(admission)` 装载快照并绑定；任一校验不过则 fail-closed 回退全量 prefill，并在 trace 记 `isKvBindRejected reason=`。
- IS 文本注入位置改为**不参与前缀**（沿用已装载 KV 的边界，只追加新问句），否则任何 IS 恢复都注定 miss。

这一步完成后，「计算被避免」才有可观测判据：同一 ES 序列下 `cacheHitTokens>0` 且 `prefill` 只覆盖新增 delta token 区间。

## 4. 可证伪实验（服务恢复后按序执行，全部走安装版 HTTP）

- E1 正对照（不含 IS）：同一条消息链逐字节重放，**换新 session_id**，`max_tokens` 足够 → 期望 `poolTokenHit`/`poolBind`、`mode=restore`、`cacheHitTokens>0`、`cacheEff≈1.00`。证明仪器与池真的能避免计算。
- E2 IS 路径当前行为（负对照）：阶段一再阶段二（现有脚本）→ 期望维持 `mode=cold cacheHitTokens=0`。坐实结论 2.1。
- E3 注入位置实验：把问句放在已结算前缀**之后**、且不带任何新增上下文体（使 token 链与阶段一前缀逐字节一致）→ 若 `mode=restore`，说明「IS 恢复 + KV 复用」可共存，缺的只是身份接线；若仍 cold，说明还有第二条破坏因素，需继续定位。
- E4 依赖变化闭包：只对实验根（不跑全量 reconcile，避免再次触发第 5 节的卡死缺陷）改文件 → `PUT /v1/simigo/roots` → 比对 `is_dependency_entries.revision`、`content_settle.invalidated_settlements`、无关文件 revision 不变；并检查该结算是否因缺 `kv.pool_key` 而根本没有可失效的表示边。

## 5. 本轮同时确认的产品缺陷（阻碍以上实验）

`PUT /v1/simigo/roots` 的同步扫描跑在主线程串行队列上并可无限阻塞（`HTTPServer.swift:992` → `:2180` → `:1990` → `SimiGoESISDatabase.swift:1505` → `open()`），导致整个 HTTP 服务不可用且不自愈；证据见 `is-wedge-mainthread-20261026.txt`。任何 IS 注入实验都必须先把这条路由改为后台作业 + 超时，否则一次注入就能让真机链路下线。
