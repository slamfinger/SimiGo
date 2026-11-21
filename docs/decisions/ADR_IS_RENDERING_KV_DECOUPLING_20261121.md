# ADR：IS 渲染与 KV 解耦——续轮信封豁免 demand/注入（2026-11-21）

**状态：已接受（owner 2026-11-21「同意，实施」）。本 ADR 是对
`ADR_LOCAL_OFFLINE_PREFILL_AND_CANCEL_20261030` 的补编：前者授权了「靠前缀复用摊销
冷预填」的生存方向，本 ADR 纠正服务该方向时累积出的、未与研究起点 reconciled 的架构耦合。**

## 背景：漂移是怎么发生的

研究起点（`docs/research/es-is/`，地图 V0.1 / 术语正本 / 运行时形态）：

- §8「复用不是键的属性」，`key` 只是 `admissible(settlement, declaration, t)` 的一个输入。
- P2 恢复是**重判**（七步准入 fail-closed），不是重建；朴素键缓存是反例（Arm B）。
- P3 续算根据是**关系**（`dependency_edges`），不是物质/位置。
- demand＝「检索单元：规范输入」；C 路红线「把观测冒充执行」。
- coverage audit 不变量：「Official Semantics First」「不应恢复第二 KV authority」。

工程生存压力（实测，见 2026-10-30 ADR 背景）：本地 MLX 39K 冷预填 50–60s，客户端 60s
硬超时→断连→`poisonedSessionEvict`→前缀丢弃→重试再冷算的死亡螺旋。owner 裁定选项 B：
接受慢、靠 KV 前缀复用摊销、断连不取消。**这把载体层的 KV 字节一致抬成了生存主轴。**

为保前缀命中，prompt 必须字节稳定；而 IS 上下文注入会改消息→断前缀（`ISContextLedger`
注释实测 2026-10-27 build 30：19/19 reuse miss，56KB 在 offset 52303 的 `[Information Space]`
处分歧，42–108s/turn）。于是造冻结账本按键回放注入块。这一步把 **IS 渲染绑上 KV 字节一致**：
IS 块成了 prompt 字节，其稳定性由 KV 前缀需求支配，而非 IS 的有效性/依赖/准入。

2026-11-21 的 occurrence 修复（键 `(scope,userText)`→`(scope,index,userText)`）本想修
「块回放到错误 occurrence」，却使**每个工具续轮都成新 occurrence**→每轮在前移尾部新注入
4–6.5KB→前缀照样断→每轮冷预填，摊销失效。

## 问题（实测 + 代码定位）

手动会话 `6a0a50a7`（21:22–21:26，装机 3c5343db）trace：

| leg | 尾部 user 消息 | inject idx | demand | delta tok | ttft |
|---|---|---|---|---|---|
| 真实问题 | 「列出电脑琢桌面文件」 | 9 | 0c4863 | — | 冷 |
| 续轮 | 纯 `<system-reminder>` 信封 | 12 | f49d02 | 2512 | 10.5s |
| 真实问题 | 「查看参考文件」 | 15 | ee0e11 | — | — |
| 续轮 | 纯信封 | 18 | f49d02 | 2523 | 9.8s |
| 续轮 | 纯信封 | 24 | f49d02 | 2885 | 15.2s |

根因链（代码锚点）：

1. `InformationLoop.retrievalQuery`（InformationLoop.swift:920）剥信封后若为空，**回退到
   信封全文**。纯信封续轮因此得到一个非空 query。
2. `prepareInformationTurn`（HTTPServerChat.swift:265）`querySource = queryOverride ?? lastUser`，
   `lastUser`＝尾部 user 消息＝纯信封；`target = messages.lastIndex(role==user)`（:319）＝前移尾部。
3. 于是每个续轮：拿信封造 demand（f49d02）→resolve→render→在尾部注入新块→前缀断→冷预填。

对照 0.5–1s 基线（11-20 `8c9839`，codex 形态）：真实问题钉在稳定 index=4，块字节不变回放，
delta 仅 122–590 tok。差异不在模型/硬件，在**注入位置是否随续轮前移**。

两条底线被触动：

- **demand 语义**：纯信封是观测/预算提醒，不是信息需求；拿它造 demand 是「把观测冒充需求」，
  与 C 路红线同型。代码注释已记摘要轮造出 394 行假 info-* 问答，并用
  `eligibility.skipsContextAssembly` 挡了内部动作——**但续轮信封没被豁免**。
- **§8/P3**：注入回放由物理位置键驱动、落在准入门之外，是一个第二 KV 权威。

诚实限定：IS 语义准入层本身仍重判有效性（`InformationLoop` resolve 过滤 invalidated、
`reusableAnswer` 须 `validity=="valid"`），P2/C9 在该层成立；`468d655` 的 ADVANCED 重解析有
`cachedIfStillCurrent` 守卫，不算破坏。tools-empty 复用门与冻结账本都是初始提交 `ded5674`
的原始设计（门有 documented 理由：settled text 不能满足 tool-call 合同），不是本次新增。
漂移是授权方向下的**未对账累积**，不是一次性推翻研究。

## 决定

**IS 渲染收回 IS 侧；续轮信封豁免 demand/注入。** 具体：

1. **纯信封续轮回指真实需求**：`prepareInformationTurn` 检测尾部 user 消息剥信封后为空
   （纯信封）时，把 query 与注入 target 回指到消息链中**最后一个真实 user 问题**
   （剥信封后非空）。该问题的冻结块在稳定 mid-chain index 字节不变回放→前缀守住；
   信封尾部保持 un-augmented→不产生新 delta 块；query＝真实问题→复用其不可变检索，
   不造新 demand。
2. **续轮复用真实问题的 pending 行（仅入口点）**：`prepareInformationTurn` 在确认尾部为
   纯信封、已回指真实问题后，经只读 lookup `pendingUserMessageID(sessionID:content:)`
   收养该问题仍 pending 的行（无叙述的纯工具轮会留下 pending 行），避免续轮重复落问题行。
   **`appendChatMessage` 的 request-scoped 契约不动**：同文本的另一请求（重试/并发）必须
   拿到自己的行，否则一个请求的取消会终结另一个请求的轮。曾尝试在 `appendChatMessage`
   全局放宽 dedup，被 4 个契约用例否决（`testConcurrentIdenticalLocalTurnsKeepPendingRowsRequestScoped`
   等），故收窄到入口点：收养的前提是上一 leg 的 handler 已返回（客户端收到响应才会发续轮），
   没有活请求持有该行。结算仍绑定真实 demand（工具循环是一个信息需求，最终答案落一次结算）。
3. **冻结账本降级**：账本不再冻结信封 occurrence（回指后信封不进 stabilize）；仅服务真实
   问题的 occurrence 回放。**完整移除/IS 渲染全量解耦列为后续**——本步先切断信封耦合，
   不动真实问题的冻结回放（移除会断历史前缀）。

## 不做（边界）

- 不动 tools-empty 只读复用门（原始设计，另有理由）。
- 不动 IS 语义准入层（resolve/admit/consume 仍重判）。
- 不声称已做「IS 渲染全量解耦/账本移除」——那是后续 ADR。
- #330 branch-scoped invalidation 对 C9 闭包的影响仍挂起待专审，本 ADR 不下断言。

## 验证

- 契约套件 `swift test --package-path Packages/SimiGoRuntime --filter SimiGoRuntimeContractTests`
  须全绿（含新增：`envelopeStripped` 纯信封判定、`pendingUserMessageID` lookup 边界回归；
  request-scoped 既有用例必须保持绿）。
- 装机后真实多 leg 复现：续轮 `replay=1`、inject idx 稳定回指真实问题、delta 回到几百 tok、
  ttft 亚秒–2s；载体不再新增信封 demand 行；收养时 trace 有 `[IS] continuationRowReuse`。
  合成双轮不足以验收（须真实工具循环）。

## 影响范围

- `Packages/.../InformationLoop.swift`：新增 `envelopeStripped`，`retrievalQuery` 行为不变。
- `SimiGo/Protocol/HTTPServerChat.swift`：`prepareInformationTurn` query/target 回指真实需求。
- `Packages/.../ESISDatabaseInformationSpace.swift`：新增只读 `pendingUserMessageID`；
  `appendChatMessage` 保持原 request-scoped 语义。
- 研究地图缺口：注入/冻结子系统仍未补进 `docs/research/es-is`（锚点+测试+读数），列为后续。
