# ADR：IS 渲染快照持久化——打通跨进程 poolBind 的最小缺口（2026-11-22）

**状态：已实施（PR #335，feat/rendering-snapshot-persistence；契约级验证绿：ISRenderingSnapshotTests 8/8、全套契约 597/597、xcodebuild 全 app BUILD SUCCEEDED。集成验收——磁盘池 ON + 真重启 + 历史多 occurrence → poolBind refHash==E3——待研究窗执行）。**
补编 `ADR_IS_RENDERING_KV_DECOUPLING_20261121`（该 ADR 把「IS 渲染全量解耦/账本移除」列为后续；本 ADR 不做全量解耦，只做其先决最小件：让冻结渲染快照跨进程可重建）。
驱动证据：`ES-IS-research/docs/research/SPIKE_A_H50_KVQUANT_BIND_20261122.md` §4 T4（bind-es3-1795341069，2026-11-22 18:02 真重启）。

## 问题（实证 + 代码锚点）

受管 ES bind 的 A-2 授权链已全通：`continuation_settle` 写 `kv.*` 行（ESISDatabase.swift:4074）→ `ISKVBindAuthority.register`（HTTPServerResponses.swift:578）→ 重启 `poolRescan` → consumer `checkBindAuthority`（SQLite kv 行跨进程读取 ✓）。**物理 bind 在同进程冷重建（suspend/resume）可达且只预填 delta（T3：poolHit messages=8 → poolBind delta=2 refHash=f933f201）；跨进程被渲染链分叉结构性阻断（T4）。**

T4 铁证：真重启 `poolRescan entries=9` → `continuation_admitted`（授权照常）→ `continuation_branch_cold err=no live source session` → **无 poolHit/poolBind** → `poolExport messages=11 refHash=ec4d1a8b`（≠E3 的 70d784bf；**同 11 条消息但字节不同 = 历史注入块缺失**）。

根因链：
1. `ISContextLedger` 纯内存 FIFO512（ISContextLedger.swift:35-37），重启即空；其自述「a process restart legitimately costs one rebuild」（:27-30）。
2. `chat_messages` 只存**未增广原文**（权威行不动，ISContextLedger.swift:25-27）→ 历史注入块不在 chat 行里。
3. 重启后 `prepareInformationTurn` 只在**当前 target** 注入新块（HTTPServerChat.swift:366 stabilize）；历史 user 轮的块靠 `contextFreezingEnabled` 回放循环 `ledger.frozenBlock(scope:userText:index:)`（HTTPServerChat.swift:496-505）——账本空 → 全部 nil → 历史轮渲染**缺块** → 渲染链字节分叉 → `PrefixMessageChain.stream` 链哈希 ≠ 导出边界 → admit 静默 miss → 授权 unused、冷预填。

**缺口不在授权，在「持久渲染快照」。** 与 KV 量化无关（fp16/量化同阻）；与替换与否无关（替换 OFF 全文臂阻于历史冻结块；替换 ON 的 digest 链已 durable，但 frontier 冻结块仍内存）。

## 决定（最小件）

**把 ISContextLedger 的冻结渲染快照变成写穿持久存储的温缓存；重启后按 occurrence 逐字节回放历史注入块。** 不做渲染全量解耦。

1. **持久渲染快照表**（ES/IS DB，新表 `is_render_snapshots`）：键 = occurrence `(scope, index, user_text_sha256)`（继承 2026-11-21 occurrence 修复，杜绝跨 occurrence 误回放）；值 = `block`（渲染字节正本）+ `resolution_json`（声明检索，供结算同源）+ `created_at`。块字节是**当时渲染的正本**（含已 stale 的命中），不从当前 IS 项重渲染（重渲染会因 invalidated/changed 分叉）。
2. **写穿**：`stabilize`/`refresh` 首次冻结（insert）时落 durable 行。**门控 `RuntimeTuning.prefixPoolEnabled`（磁盘池）**——产品默认磁盘池 OFF 时零写开销（跨进程 KV 复用本就不尝试，持久渲染快照无消费者）；研究模式磁盘池 ON 才写。
3. **温加载（lazy）**：`stabilize`/`frozenBlock` 内存 miss 时查 durable 行 → 命中则载入内存并 `isReplay=true` 回放。无需启动全量 rescan（按 scope 首次访问懒加载，与 pool rescan 同哲学但更省）。
4. **有界**：durable 行按 scope FIFO + 行预算逐出（ponytail：渲染快照小、会话有界；先 FIFO 行预算，跨 scope LRU 若实测 churn 再加）。逐出只使该 occurrence 退回冷重建，绝不渲染错内容。

## 安全 / 哲学对账

- **持久的是渲染配方，不是 KV。** KV 池 artifact 仍可逐出、admission 仍 fail-open 冷预填——「persisted KV must never be a continuity requirement」（ISContextLedger.swift:29-30）不变。渲染快照只是去掉「渲染分叉」这一阻塞，使**若** KV artifact 存活则可跨进程复用；KV 本身永不是连续性要求。
- **IS 语义准入不动**：resolve 仍重判有效性（过滤 invalidated）、reusableAnswer 仍须 validity=="valid"。回放冻结块只为前缀字节稳定（与今日进程内行为一致），不绕过准入；`refresh` 仍在需要时从当前信息作答。
- **fail-open**：durable 行缺失/损坏/版本不符 → 退回今日行为（fresh render + 冷预填），绝不渲染错内容。
- **occurrence 键继承**：durable 键 = `(scope,index,user_text_sha)`，与内存账本同；同文本不同 index 是不同 occurrence，杜绝 2026-11-21 那类误回放。
- **权威行不动**：chat_messages 仍未增广；渲染快照是独立派生存储，可重建、可逐出。

## 不做（边界）

- 不做 IS 渲染全量解耦 / 账本移除 / pool 链哈希改语义键（那是后续更大 ADR；本件是其先决）。
- 不改 IS 语义准入层、不改 tools-empty 复用门、不改 appendChatMessage request-scoped 契约。
- 不改产品默认姿态（内存池 ON / 磁盘池 OFF）；本件门控磁盘池，产品默认零行为变化。
- 不在本 ADR 实施受管 C 路 kv 行 G 相位接线（另件，见 KV_QUANT_CONCLUSION_CORRECTION §4）。

## 验证

- **契约套件**（`swift build --target SimiGoRuntimeContractTests` + xctest，绕开 MLX）：新增 durable 渲染快照 round-trip（冻结 → 新账本实例温加载 → frozenBlock 逐字节回放）、occurrence 键隔离、fail-open（缺行/坏行）、写穿门控（磁盘池 OFF 不写）。既有 ISContextLedgerTests 必须保持绿。
- **集成（研究模式，zcode 窗）**：磁盘池 ON + 持久渲染快照 ON，复跑 bind T4：真重启 → `poolHit`/`poolBind` 命中（refHash == E3）、只预填 delta。进而打通「量化 × 替换 × 磁盘池 × 真重启 → poolBind」格。合成双轮不足以验收（须真重启 + 历史多 occurrence）。

## 影响范围

- `Packages/.../ISContextLedger.swift`：写穿 + 温加载 + durable 存储协议（注入存储后端，契约包不直接依赖 SQLite——经协议由 app 侧 ESISDatabase 实现，保持 MLX-free/可测）。
- `Packages/.../ESISDatabaseInformationSpace.swift`：`is_render_snapshots` 表 DDL + 读写（幂等 DDL，独立于编号迁移）。
- `SimiGo/Protocol/HTTPServerChat.swift`：回放循环（:496）无需改（frozenBlock 温加载后自然命中）；写穿门控接 RuntimeTuning。
- 研究地图缺口：渲染/冻结子系统补进 `docs/research/es-is`（锚点+测试+读数），承 2026-11-21 ADR 后续。

## 与既有裁定的关系

- owner「进内存池，不开磁盘池」= 产品默认热路径（内存 digest 喂给已实施，feat/digest-memory-feed c575c25）。本 ADR 服务**研究格**的跨进程复用（磁盘池研究模式），不改变产品默认。
- 三平面（IS 真值 / ES 计算 / KV 物化）：渲染快照属 IS 渲染配方的持久化，落 IS 侧；KV 物化层仍可选。量化漂移仍关在物化层（承 DC130B56 / 7A162B5F / 956A8E43）。
