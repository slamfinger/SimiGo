# C 阶段接口设计 I：as-of 快照、拒绝拆桶、400 终端、失败审计、幂等与采集点（设计稿 v2，裁定收口版，未实施）

状态：**设计提案，仅设计**。依据 2026-10-27 八项裁定、七项接口裁定、五项推断裁定与跨阶段硬约束。不实现、不迁移、不改产品行为。

本稿覆盖：as-of 快照（含 declared/used 两段、选择性字节与容量上限）、受管续跑拒绝拆桶、400 `INVALID_REQUEST_ENTRY` 两种原因码、失败审计事件、幂等键（含判定指纹）、快照采集点，以及「`used` 必须受 `declared` 约束」的跨阶段规则。

修订记录：

- v1（2026-10-27）：快照三段动作、S 相位、取证 vs 可重放、一致性规则、P2 逐项比对、拒绝拆桶与原因×新鲜度判定。
- v2（2026-10-27）：并入七项接口裁定——选择性字节且单对象、`settlements.input_snapshot_object_id` 可空列、新增文件算不一致、不暴露内部原因、`MIGRATED_LEGACY` 独立分码、失败审计 best-effort、v1 不回收；新增 §D–§G。
- v2 收口（2026-10-27，本稿）：并入五项推断裁定与跨阶段硬约束——①`recompute_policy_invalid` 与 `recompute_policy_conflict` 两条 400 原因码；②JSON+Base64 定稿；③`execution_id` 语义为单次执行尝试；④幂等判定改为多维指纹、v1 全局唯一；⑤容量上限 32 MiB / 48 MiB；⑥新增 §A4b：`used ⊆ declared` 且逐项摘要相同，否则 P2 拒绝。
- 审查修订（2026-10-27，本稿）：§J 纯设计一致性审查，修正 J1–J7（指纹与取证字段分离、`final` 版本字段、容量越限统一 422、P2 补 `used` 复核、errorKind 归属、索引身份核实、`execution_id` 措辞），并列出 O1–O3 未决项。
- 未决收口（2026-10-27，本稿）：O1 公开错误码改为**显式 allowlist**（公开 ≠ 内部原因）；O2 `replayable` 取 `declared ∧ used ∧ used ⊆ declared` 合取；O3 v1 **无 TTL、无自动 GC**，存储压力下拒绝新建而非删除历史证据。见 §A8b / §A4 / §A9 / §J。

---

## 0. 代码取证（只读核对）

| # | 事实 | 位置 |
|---|---|---|
| F1 | `is_objects` 写一次：`object_id` = 小写 SHA-256，UPDATE/DELETE 由触发器 `RAISE(ABORT)` | [SimiGoESISDatabase.swift:221](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L221)、[:247](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L247) |
| F2 | `writeObject` / `readObject`（读时校验哈希）/ `verifyObject` 已存在 | [:647](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L647)、[:656](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L656)、[:700](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L700) |
| F3 | 无 GC：全文没有 `DELETE FROM is_objects`，删除被触发器禁止 | 同上 |
| F4 | `is_dependency_entries` append-only，按 `(dependency_id, revision)` 记录当时的 `content_address` | [:239](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L239)、[:908](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L908) |
| F5 | `file_contents` 重扫时 UPSERT 覆盖旧 `content_sha256`/`object_id` | [:1741](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L1741) |
| F6 | `external_files.content_digest` 同样被覆盖；`reindexExternalFile` 只返回是否变化 | [:3307](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L3307) |
| F7 | 结算失效只写 `validity` + `invalidated_at`，无原因列、无事件表 | [:209](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L209)、[:3434](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L3434) |
| F8 | 拒绝桶是 `refused(String)`，内容为 `String(describing:)`；外部 422 `INPUT_ADMISSION_REFUSED` / `is_refusal` | [ContinuationAdmission.swift:46](file:///Users/mr.simi/Documents/SimiGo/SimiGo/Protocol/ContinuationAdmission.swift#L46)、[SimiGoProducerIdentity.swift:112](file:///Users/mr.simi/Documents/SimiGo/SimiGo/Model/SimiGoProducerIdentity.swift#L112)、[ContinuationSettlement.swift:90](file:///Users/mr.simi/Documents/SimiGo/SimiGo/Protocol/ContinuationSettlement.swift#L90) |
| F9 | IS 拒绝枚举 8 个 case，逐项对应准入步骤 1–7 | [SimiGoISAdmission.swift:58](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoISAdmission.swift#L58)、[:126](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoISAdmission.swift#L126) |
| F10 | `unknownSettlement` 同时代表「行不存在」与 `MIGRATED_LEGACY` | [:136](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoISAdmission.swift#L136) |
| F11 | 状态入口取最新结算按 `settled_at DESC, settlement_id DESC` | [:1469](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L1469) |
| F12 | `settlementBindings` 丢弃 `source_root_id`/`source_file_id`，没有「结算→文件」读取器 | [:1453](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L1453) |
| F13 | 检索先取对象存储（哈希匹配才用）再退磁盘，同一摘要可能来自两处 | [:2205](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L2205) |
| F14 | `canonicalDemandInput` 只读库，不校验磁盘 | [:1961](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L1961) |
| F15 | 根不可枚举时重扫直接拒绝，不当作全删（fail-closed 先例） | [:1609](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L1609) |
| F16 | `execution_states.continuation_id` 是**每个状态**生成的 UUID，参与 UI 展示与恢复，不是幂等键 | [schema:168](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L168)、[ExecutionStateGraph.swift:193](file:///Users/mr.simi/Documents/SimiGo/SimiGo/App/ExecutionStateGraph.swift#L193) |
| F17 | `is_index_entries` 是 append-only 的「identity → object」账本，支持 first/last 解析 | [:233](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L233)、[:707](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L707)、[:716](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L716) |
| F18 | `settlements` 已有 `payload_object_id`；加列沿用了 v8 的逐列 ALTER 模式 | [:170](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L170)、[:276](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L276) |
| F19 | `settleWorkRootContents` 单文件字节上限默认 1 MiB（`fileByteCap`） | [:1565](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L1565) |
| F20 | 现有 `is_index_entries.srs_identity` 前缀仅 `file:` / `chat:` / `demand:` / `settlement:` / `settlement-summary:`；`c-failure-audit:` 无碰撞 | [:966](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L966)、[:1005](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L1005)、[:1032](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L1032)、[:1064](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L1064)、[:3848](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L3848) |

**由 F5–F7 推出的结论**：失效之后库内无法回答「为什么失效」，裁定 2 的「确认可恢复输入失效」只能靠**决策时现场重核**（§B3）。

---

## A. as-of 快照

### A1. 四个动作，不能混成一个「写快照」

| 动作 | 何时 | 写什么 | 失败语义 |
|---|---|---|---|
| 构建 `construct` | P1（只读） | 无写入；内存中产出 `DeclaredDraft`（唯一 ID、确定摘要、来源集合、字节决定） | 终止，`model_calls=0` |
| 保存声明快照 `persistDeclared` | 相位 **S**（P1 后、G 前） | 只写**一个** `is_objects` 对象（可内嵌字节） | 写入/读回失败 → 500；容量越限 → 422 `snapshot_unrepresentable`；两者 `model_calls=0` |
| 记录实际使用 `recordUsed` | G | 仅内存缓冲（不落库） | G 崩溃即丢失，按限制记录 |
| 保存最终快照 + 提交 `commit` | P2 单写事务 | 写**一个**最终快照对象（引用声明对象 + 含 `used`），结算行 `input_snapshot_object_id` 指向它 | 回滚，`settlements_written=0` |

S 不是意图行：不占位、不加锁、不参与唯一性约束、无状态机、无租约、崩溃只留惰性孤儿（裁定 7/8）。

### A2. 不可变性与引用（裁定 2）

- 不可变性由既有触发器保证（F1），`snapshot_id` = 内容 SHA-256，天然去重。
- **结算行新增可空列** `input_snapshot_object_id TEXT REFERENCES is_objects(object_id)`，指向**最终**快照对象；沿用 v8 加列模式（F18）。
- 不建快照关联表；**不回填**历史结算——列为空即表示该历史结算没有此项证据，不得伪造。
- 既不用「仅挂审计记录」替代列（取证链更脆），也不把 `snapshot_id` 塞进结算 payload（污染结果语义）。

### A3. 声明快照 `declared` 的内容（S 段写入）

```
{
  "canonical_version": "c-snapshot-v1",
  "part": "declared",
  "digest_algorithm": "sha256",
  "captured_at": "…Z",
  "request": { "kind": …, "demand": {…}, "root_ids": […], "contract": {…},
               "recompute_policy": …, "idempotency_key": "…|null" },
  "anchor": { "state_id": "…", "settlement_id": "…", "payload_digest": "…" },
  "sources": [
    { "kind": "file", "root_id": "…", "relative_path": "…",
      "sha256": "…", "size": 1234, "modified": "…",
      "stat_identity": { "dev": "…", "ino": "…", "mtime_ns": "…" },
      "byte_source": "object_store|disk|embedded",
      "object_id": "…|null",
      "bytes_in_snapshot": true|false,
      "bytes_base64": "…|null",
      "replayable": true|false },
    { "kind": "settlement", "settlement_id": "…", "payload_digest": "…",
      "validity_at_capture": "valid" }
  ],
  "overall_digest": "…",
  "declared_input_digest": "…",     // 幂等指纹用：排除 captured_at、idempotency_key 与执行 ID
  "replayable": true|false
}
```

**`declared_input_digest` 的精确定义（审查后收紧）**：对 `{canonical_version, digest_algorithm, root_ids, contract, sources[] 中每项的 (kind, 标识, sha256)}` 按固定字段顺序做 canonical 序列化后取 SHA-256。**排除** `captured_at`、`request.idempotency_key`、`request.recompute_policy`（后者由请求指纹单独比较）与任何执行 ID。

理由：`declared` 对象里确实保存 `idempotency_key` 与 `captured_at` 供取证，但若让它们进入指纹，会造成两个问题——同一逻辑执行因 `captured_at` 不同而永远判「不同」，以及幂等键被自己「证明」了一遍。指纹与取证字段必须分开定义，二者同存于对象中不构成冲突。

**选择性字节（裁定 1，本稿的核心实现合同）：**

| 情形 | 处理 |
|---|---|
| 库内已有精确字节对象（`object_id` 非空，且 `readObject` 校验哈希 == `sha256`） | 只存 `object_id` 引用，不复制字节 |
| 本次新出现 / 摘要已变 / 库内无精确对象（索引模式、`object_id` 为空） | 把**本次实际读取的原始字节**嵌入本快照对象 |
| 只有同路径的历史对象、但哈希与本次摘要不符 | 视为「无精确对象」，必须嵌入；不得因路径相同就宣称命中 |

- 「精确」= 字节经 `readObject`（内部校验）或独立 SHA-256 复核与 `sha256` 一致；**仅凭历史存在不算**。
- 嵌入编码（已定稿）：规范化 JSON + base64。便于调试、审计与跨版本读取，也能明确区分「内嵌原始字节」与「对象引用」；代价是体积膨胀与内存复制，因此必须受下面的容量上限约束。
- **容量上限（v1 工程限额，非实测容量）**：
  - 所有需内嵌的输入原始字节合计 **≤ 32 MiB**；
  - 最终序列化对象（含 base64、元数据、引用信息）**≤ 48 MiB**；
  - 两个上限都必须强制；原始字节未超但最终对象超限，同样拒绝。
  - 超限一律 **fail-closed**：不得截断字节、不得「只留摘要继续生成」、不得把不可重放数据标成 `replayable=true`。
  - 这两个数值需由实现阶段的接近上限/超限测试验证；调整必须有实测依据，不得遇超限就放宽。
- 单文件仍沿用既有 `fileByteCap` 口径（F19）；单文件与整体是两个独立判定，任一超限即终止。
- 若任一必要输入无法读取/固定/保存 → 在模型调用前终止（`snapshot_unrepresentable` / `snapshot_source_*`），不进入 G。

### A4. 最终快照与两段关系（裁定 2 的分层）

| 对象 | 何时 | 内容 | 谁引用 |
|---|---|---|---|
| `declared`（对象 A） | S | A3 全部字段（含嵌入字节） | 由最终对象引用 |
| `final`（对象 B） | P2 成功时同一事务 | `schema_version:"c-snapshot-v1"`、`canonical_version`、`part:"final"`、`declared_snapshot_id`、`declared_input_digest`、`captured_at`、`verified_as_of`、`used[]`、`replayable`（按 §A4a 由逐项计算）、复核结论摘要 | `settlements.input_snapshot_object_id` |

两个对象共用同一个版本标识 `c-snapshot-v1`，用 `part` 区分；读取方必须按 `part` 分派，且遇到未知 `part` 或未知 `schema_version` 一律拒绝解析（fail-closed），不得按「看起来像 v1」猜测字段。

`used[]` 每项至少含：`kind`（file/settlement）、标识、`sha256`、`byte_source`、`replayable`，以及被注入上下文的标识。**不把声明输入误报为实际使用输入**：`used` 只由 G 段检索命中产生。

- G 段崩溃 → `used` 丢失，只剩 `declared`；此时只能宣称「声明输入已固定」，不得宣称「实际读取已完整记录」。
- P2 失败 → 不写成功结算；失败审计尽力保留 `used`（§E），写入失败必须如实标注。

#### A4a. `replayable` 的判定（裁定 O2：合取，逐项计算）

```
final.replayable = declared.replayable
                 ∧ used.replayable
                 ∧ (∀ item ∈ used: ∃ item' ∈ declared, (kind, 标识) 相同 ∧ item.sha256 == item'.sha256)
```

- `declared.replayable`：声明合同中所有必要输入都有**可验证的精确字节来源**（内嵌字节，或经哈希复核的不可变对象引用）。
- `used.replayable`：每一项都能在**实际使用的那个字节版本**上精确重建。
- 第三项是 `used ⊆ declared` 的完整形式：**不仅是集合成员关系，还要求内容摘要一致**。
- 每个条目保留自己的 `replayable` 标记；**整体标记必须由逐项证据计算得出，调用方不得直接填写**。
- 下列任一情形，整体一律**不得**标 `replayable=true`：
  - `used` 缺失或在进程崩溃后丢失；
  - `used` 含声明集合以外的输入；
  - 声明版本与实际使用的内容摘要不符；
  - 必要字节既未保存在快照中，也无法由已验证的不可变引用取得；
  - 快照版本或字节编码无法识别（§A4 的 fail-closed 解析）。
- `declared` 只能证明「事先声明了什么」，**不能替代** `used` 对「实际使用了什么」的证明。即使模型产物已成功生成，只要上述条件不满足，就不得把本次快照称为可重放快照。

### A4b. 跨阶段硬约束：`used` 必须受 `declared` 约束

仅保存一份输入清单并不构成证明；必须证明**本次执行使用的输入被该清单约束**。因此：

```
for each item in used:
    require ∃ item' in declared:  (kind, 标识) 相同
                                 且 item.digest == item'.sha256
require used 中的字节版本 == declared 中该条目的精确版本
```

- **不允许**「模型已经生成了，就把未声明/摘要不符的输入补写进 `used` 后继续提交」。这类情形判定为**输入快照不一致**，进入 P2 拒绝。
- 违例原因码：`snapshot_used_undeclared`（命中未声明条目）、`snapshot_used_mismatch`（同标识但摘要与声明版本不符）。
- 计量：`model_calls` **可能 >0**（若发现于生成之后），`settlements_written=0`，并按 §E 记失败审计。
- **允许更早发现**：检索命中在模型调用前就能核对与 `declared` 的一致性；此时终止可做到 `model_calls=0`。设计同时要求「调用前核对」与「P2 对已记录 `used` 再核对」两道闸，最终口径以实际发生阶段为准，不得把调用前发现写成生成后拒绝。
- 推论（必须写进实现约束）：P1 的声明集合必须覆盖 G 可能消费的候选范围——声明根集合下的全部文件，加上锚点结算及其依赖闭包结算。检索命中若来自声明范围之外，不是「补登记」，而是请求应当被拒绝。

### A5. 能证明什么

| 能力 | 仅摘要 | 引用精确对象 | 内嵌本次字节 |
|---|---|---|---|
| 来源身份与内容摘要 | 是 | 是 | 是 |
| 事后精确重现该项字节 | 否 | 是 | 是 |
| 成本 | 最低 | 低（去重） | 增量字节，且同一变更会在多份快照中重复（v1 无 GC） |

**口径**：没有精确字节的项一律 `replayable=false`，对外只能说「取证」；只有最终对象整体 `replayable=true`（§A4a 合取）才能说「可重放」。嵌入导致的空间增长是裁定 1 的直接代价，v1 不回收（裁定 O3）。

### A6. 一致性采集规则（构建阶段，fail-closed）

| 情形 | 判定 |
|---|---|
| 读前/读后 stat（size、`mtime_ns`、`dev`、`ino`）不一致 | 重试 ≤2；仍不一致 → `snapshot_unstable` |
| 文件在 stat 与 open 之间消失 | `snapshot_source_missing` |
| 权限 / I/O 失败 | `snapshot_source_unreadable`（与空文件区分） |
| 两次独立遍历的集合或摘要不一致 | `snapshot_inconsistent` |
| 根 locator 缺失 / 不可枚举 | `snapshot_root_unavailable`（F15 同款） |
| 符号链接 | 记录真实路径 + 目标 `dev/ino`；目标替换即视为变化 |
| 同键多值（大小写/硬链接） | 按 `(root_id, 规范化相对路径)` 去重；同键不同摘要 → `snapshot_inconsistent` |
| 单文件超上限 / 无法完整读取 | `snapshot_unrepresentable`（不截断） |

摘要语义：`sha256` 为全文件原始字节，不做换行/编码归一化；`stat_identity` 只作变化探测，不作内容证明。

### A7. P2 复核规则（裁定 3）

```
for each item in declared.sources:
    re-read; require identity present and digest == item.sha256
require 声明根集合下没有新增条目（集合成员相等）
for each item in used:  (A4b 的完整复核，不是只查新增)
    require ∃ item' in declared: (kind, 标识) 相同 且 item.digest == item'.sha256
require anchor/结算行/闭包/身份/合同/幂等键 与 P1 一致
⇒ 全部成立才提交；否则回滚 + 终止
```

- **禁止**「重算 canonical 比总体摘要」。
- 新增、删除、内容变化**任一**都算集合不一致（裁定 3）；新增文件不是「没有旧摘要所以忽略」。
- 复核只证明核验时刻；核验到提交之间仍可能变化，不得宣称「current」。

### A8. 失败面与计量

| 阶段 | 失败点 | `model_calls` | `settlements_written` | 快照证据 | 对外终端 | 内部原因（必记） |
|---|---|---|---|---|---|---|
| P1 | 准入拒绝/锚点不合格 | 0 | 0 | 无 | 422 + 入口既有分类（§A8b） | 精确 `cause` |
| P1 | 快照构建失败（根不可用/不稳定/缺失/不可读/集合不一致/单文件不可表示） | 0 | 0 | 无 | 422 + 入口既有分类 | `snapshot_root_unavailable` / `_unstable` / `_source_missing` / `_source_unreadable` / `_inconsistent` / `_unrepresentable` |
| P1 | 内嵌原始字节合计 > 32 MiB | 0 | 0 | 无 | 422 `snapshot_unrepresentable`（公开） | 同码 + 实测字节数 |
| S | 对象写入或读回复验失败 | 0 | 0 | 无 | 500（基础设施） | 存储错误类别 |
| S | 声明对象序列化后 > 48 MiB | 0 | 0 | 无 | 422 `snapshot_unrepresentable`（公开） | 同码 + 实测字节数 |
| G | 模型执行失败 | ≥0 | 0 | `declared` 保留 | 500 引擎错误 | 引擎错误类别 |
| G | 调用前发现 `used` 未声明或摘要不符 | 0 | 0 | `declared` 保留 | 422 + 入口既有分类 | `snapshot_used_undeclared` / `snapshot_used_mismatch` |
| G | 进程崩溃 | 未知/部分 | 0 | `declared` 保留，`used` 丢失 | 连接断开 | 无（无终态审计） |
| P2 | 集合/逐项/锚点/身份/合同不一致 | >0 | 0 | `declared` + 尽力 `used` | 422 + 入口既有分类 | 精确 `cause` + 阶段 |
| P2 | `used` 违反快照合同 | >0 | 0 | `declared` + 尽力 `used` | 422 + 入口既有分类（**不得**报成 400 形状错误，**不得**记成模型执行失败） | `snapshot_used_undeclared` / `snapshot_used_mismatch` + 阶段 P2 |
| P2 | 幂等冲突 | >0 | 0 | `declared` 保留 | 422 `idempotency_conflict`（公开） | 指纹差异维度 |
| P2 | 最终对象序列化后 > 48 MiB | >0 | 0 | `declared` 保留 | 422 `snapshot_unrepresentable`（公开） | 同码 + 实测字节数 |
| P2 | 提交 | >0 | 1（+ES+边+审计） | `final`，结算行引用 | 200 | — |

**对外 / 内部两列必须分开填**（O1）：右列只进内部台账与 §E 审计，**不**进 HTTP 响应；HTTP 响应里不得出现逐项摘要、绝对路径或私有内容。

**口径统一（审查修订）**：容量越限是**由请求与输入决定的可判定拒绝**，不是引擎故障，因此一律 422 `snapshot_unrepresentable`，不再出现「48 MiB 超限记 500」。500 只保留给真正的基础设施失败（对象写入/读回失败、模型引擎错误、非类型化异常）。S 的失败属基础设施，不得混入业务拒绝统计。只有 P1 终止可称「零生成」。

### A8b. 公开错误码 = 显式 allowlist（裁定 O1）

**原则**：公开码是稳定、可供调用方采取行动的接口合同；**不**把内部拒绝分类枚举直接投影成公开码。公开集合是**封闭 allowlist**，只含下表各码：

| 族 | 公开 `reasonCode` | status | errorKind |
|---|---|---|---|
| 请求形状 | `recompute_policy_invalid`、`recompute_policy_conflict` | 400 | `INVALID_REQUEST_ENTRY`（唯一新增 errorKind） |
| 快照超限 | `snapshot_unrepresentable` | 422 | 沿用所在入口既有 422 errorKind |
| 幂等键冲突 | `idempotency_conflict` | 422 | 沿用所在入口既有 422 errorKind |
| 普通准入拒绝 | 该入口**既有**的稳定外部分类（受管续跑 `INPUT_ADMISSION_REFUSED` / 结算消费 `SETTLEMENT_CONSUMPTION_REFUSED` 及其既有 `reasonCode`） | 422 | 不变 |

「沿用所在入口既有 422 errorKind」= 受管续跑用 `INPUT_ADMISSION_REFUSED`，结算消费用 `SETTLEMENT_CONSUMPTION_REFUSED`；不新增 errorKind 桶。400 族是唯一新增的 errorKind，且只覆盖请求形状错误。

**不在 allowlist 内的一律内部**（示例，非穷尽）：`snapshot_used_undeclared`、`snapshot_used_mismatch`、`snapshot_root_unavailable`、`snapshot_unstable`、`snapshot_source_missing`、`snapshot_source_unreadable`、`snapshot_inconsistent`，以及 §B2 的全部原因码（`invalidated_cause_unknown`、`dependency_invalid`、`legacy_migrated`、`identity_nonconformance`、`refusal_cause_unconfirmed` 等）。

这些内部码的对外表现：

- 对外使用**所在入口已经确定的失败分类**（422 + 既有 errorKind / 既有 `reasonCode`），实现时从现有映射表择定，**不得为此新增公开码**；
- 内部与审计必须**精确记录** `cause`、阶段（P1/S/G/P2）、证据（§E `refusal` 字段），不得压成笼统的「失败」；
- 内部来源路径、逐项摘要、私有文件内容**不进入 HTTP 响应**（与 §B5 / §E5 一致）。

**不得伪装成请求格式错误（O1 特别条款）**：模型执行之后才发现 `used` 违反快照合同，**不能**报成 400 请求形状错误，也不能笼统记为「模型执行失败」。对外走该入口既有 422 分类；内部必须明确记成「快照合同违例」（`snapshot_used_undeclared` / `snapshot_used_mismatch`），并保留 `model_calls>0`、`settlements_written=0`。

**未来新增内部 case 的规则**：每新增一个内部拒绝原因，都必须经过**显式的公开映射审查**才能出现在 HTTP 响应里；内部枚举增长**不自动**增加公开 API 码。未审查的新 case 默认只内部可见，按所在入口既有分类对外。

### A9. 生命周期（裁定 O3）

- v1 **不设自动过期时间、不做自动 GC、不按固定天数删除**。孤儿对象（声明快照无最终引用、或最终快照无结算引用）只积累。
- 即使某快照**当前引用数为零**，也可能仍被失败审计、诊断证据或后续恢复需要；**引用数为零不构成删除授权**。
- S 阶段产生、但 P2 未提交的快照对象**继续保留**；不增加 TTL、后台清理任务或隐式空间回收。
- **存储压力下的行为**：若长期积累使存储达到限制，应**拒绝新的快照创建并报告存储问题**，不得为继续服务而删除旧证据。该拒绝属基础设施失败（500），不计入业务拒绝统计，且必须在内部台账中标明是存储容量而非输入问题。
- 未来若需 GC，必须另行定义引用完整性、并发写入、失败审计保留与崩溃恢复规则，并取得独立授权；实施时不得继承「引用数为零即可删」的隐含前提，也不得为此摘除写一次触发器。
- 离线备份/清理由独立流程负责，不属本设计。

### A10. 验证设计（授权后才执行）

- **C-8 集合差异**：新增 / 删除 / 改内容三例都必须在 P2 拒绝，`settlements_written=0`。
- **C-9 逐项而非总体**：用注入的假快照证明判定走逐项比较，不读 `overall_digest` 做结论。
- **C-10 精确性**：同一路径存在哈希不符的历史对象时，断言该项被标记 `replayable=false` 且字节被嵌入；引用对象被篡改时 `readObject` 失败 → 拒绝。
- **C-10b 重放**：对 `replayable=true` 的最终快照，重放出字节逐项与 `sha256` 一致；对 `replayable=false`，断言任何字段都不宣称可重放。
- **C-10c 合取（O2）**：构造四组输入——(a) `declared` 可重放且 `used ⊆ declared` 一致 → `true`；(b) `used` 缺失（模拟 G 段崩溃）→ `false`；(c) `used` 含未声明项 → `false`；(d) `used` 同标识但摘要不符 → `false`。断言整体标记由逐项计算得出，且调用方无法直接写入。
- **C-10d 公开码 allowlist（O1）**：遍历全部内部拒绝原因，断言 HTTP 响应中出现的 `reasonCode` ∈ allowlist；`snapshot_used_*` 等不得出现在响应中；同一触发下内部审计**必须**含精确 `cause` 与阶段。
- **C-10e 存储压力（O3）**：模拟存储受限时新建快照被拒（500 + 存储错误类别），断言**没有**任何历史 `is_objects` / 结算 / 审计对象被删除。

---

## B. 受管续跑拒绝拆桶

### B1. 目标结构

```
ManagedRefusal { cause: RefusalCause, origin: RefusalOrigin, evidence: Evidence }
```

禁止由 `detail` 字符串推断原因（F8）。`detail` 之后只作日志与人类可读说明。

### B2. 原因映射（穷尽；裁定 5）

| 现有来源 | 原因码 | 可恢复性 |
|---|---|---|
| `invalidAnchor` | `invalid_anchor` | 终止 |
| `unavailable` | `authority_unavailable` | 终止（503） |
| `Refusal.noSettlement` | `no_settlement` | 终止 |
| `Refusal.unknownSettlement`（行不存在） | `unknown_settlement` | 终止 |
| `Refusal.unknownSettlement`（`MIGRATED_LEGACY`） | **`legacy_migrated`（独立分码）** | 终止；不因分码获得重算资格 |
| `Refusal.digestMismatch` | `digest_mismatch` | 终止（完整性/篡改） |
| `Refusal.invalidated` | `invalidated_cause_unknown` | 需现场新鲜度核实 |
| `Refusal.dependencyMissing` | `dependency_missing` | 需核实；默认终止 |
| `Refusal.dependencyInvalid` | `dependency_invalid` | 需核实；仅当上游结算有直接文件绑定且该文件变化才可进入 |
| `Refusal.producerBinding(v)` | `identity_nonconformance` + `v.code` | 终止 |
| `Refusal.emptyValue` | `empty_value` | 终止 |
| 非类型化 / 未知错误 | `infrastructure_or_unexpected` | 500，不产生业务码 |

`MIGRATED_LEGACY` 的分码在 IS 准入内部完成（不改判定顺序、不改准入结果），所有分派处显式映射，不用字符串或状态码反推。

**内部码表 ≠ 公开码表（O1）**：本表是**内部**原因映射。其中只有 `invalid_anchor` 与既有 `is_refusal` 已在公开合同中（§B5），其余即使名称相近也**不公开**；任何内部码要出现在 HTTP 响应里，必须先进 §A8b 的 allowlist 并经显式审查。

### B3. 双输入判定：原因 × 新鲜度

```
eligibility(cause, freshness) -> 可重算 | 终止
```

| 新鲜度 | `invalidated_cause_unknown` | `dependency_invalid` |
|---|---|---|
| `changed_verified`（直接绑定的文件磁盘摘要 ≠ 登记） | 可进入重算判定 | 仅当失效上游结算有直接文件绑定且该文件变化 |
| `unchanged_verified` | 终止 `refusal_cause_unconfirmed` | 终止 |
| `unverifiable`（缺失/不可读/根不可用） | 终止 | 终止 |
| `not_applicable`（无文件绑定） | 终止 | 终止 |

硬规定：仅凭公开码 `source_not_valid` 永远不够；`changed_verified` 也不够——还须满足锚点、身份、合同、重算许可。新鲜度必须用 §G 的同一采集器，不得另写第二套。

### B4. 未知即保守

- 分类函数对 `RefusalCause` 做穷尽 switch，**不写 `default`**；新增 case 必须编译失败。
- 无新鲜度结果时 `invalidated` 只落 `invalidated_cause_unknown` → 终止。

### B5. 外部兼容（裁定 4）

- 维持 422 `INPUT_ADMISSION_REFUSED`（`reasonCode` 仍 `invalid_anchor` / `is_refusal`），`.unavailable` 仍 503；拆桶不增加公开码。
- 结构化原因、证据、逐项摘要、文件路径**只在内部与审计**使用，不进入 HTTP 响应。
- 调用方只能通过显式 `recompute_policy` 表达权限，不能靠解读内部原因推断「服务器会不会重算」。

### B6. 拆桶的实现前置（只读或小改，未授权）

1. 「结算→文件」读取器（F12 缺失）；
2. `MIGRATED_LEGACY` 与「行不存在」分码（F10）；
3. `recoverForContinuation` 把 `Refusal` 转结构化（[SimiGoProducerIdentity.swift:101](file:///Users/mr.simi/Documents/SimiGo/SimiGo/Model/SimiGoProducerIdentity.swift#L101)），非类型化错误仍按原样上抛（500 语义不变）。

### B7. 验证设计

- **C-11 穷尽性**：每个 IS case 映射到预期原因；非 `Refusal` 恒 500。
- **C-12 双输入矩阵**：`invalidated` × 四种新鲜度；`digest_mismatch` × 任意新鲜度恒终止；`legacy_migrated` 与 `unknown_settlement` 分开断言且都不可重算。
- **C-13 兼容性**：拆桶前后 HTTP 状态、`errorKind`、`reasonCode` 逐字节一致；响应中不出现路径、逐项摘要或内部原因。

---

## C. 链路验收条件

链路：`固定锚点与输入快照 → 结构化拒绝分类 → 显式策略判定 → 事务外模型生成 → P2 复核与原子提交`

| 段 | 必须可断言 | 不许出现 |
|---|---|---|
| 锚点与快照 | 锚点为 `(state_id, settlement_id)`；S 后 `declared` 不可变 | 「最新结算」隐式选锚；库内 canonical 冒充快照 |
| 拒绝分类 | 原因来自枚举；资格 = 原因 × 新鲜度 | 解析 `detail`；用 HTTP 码判资格 |
| 策略判定 | `never` 恒不调模型；`allow_safe_recompute` 仅进入判定 | 缺省静默重算；422 视为许可 |
| 生成 | 产物绑定执行 ID + `declared` 快照；记 `model_calls`；`used` 仅内存 | 两执行共用产出；G 段持写事务 |
| P2 | 逐项 + 集合成员；单事务提交；失败回滚；结算引用 `final` | 重算 canonical 比总摘要；半结算 |
| 可重放性 | 整体 `replayable` 由 `declared ∧ used ∧ used⊆declared` 逐项算出 | 用「存了摘要」冒充可重放；调用方直填 |
| 错误码 | HTTP 只出 allowlist 内的码；内部原因进台账与审计 | 把内部枚举投影成公开码；把快照违例报成 400 |

三态计量互斥且分别可观测：`model_calls=0` / `model_calls>0 且 settlements_written=0` / 成功提交（引用 `final`、真实依赖、审计齐全）。

---

## D. 400 `INVALID_REQUEST_ENTRY` 终端（裁定 1 的接口化）

### D1. 形态

新终端 `INVALID_REQUEST_ENTRY`（400），覆盖两种**不同的**请求结构错误：

| 情形 | status | errorKind | reasonCode（本次新增的稳定码） |
|---|---|---|---|
| 未知 `recompute_policy` 取值 | 400 | `INVALID_REQUEST_ENTRY` | `recompute_policy_invalid` |
| `recompute_policy` 与 `allow_recompute` 同时出现 | 400 | `INVALID_REQUEST_ENTRY` | `recompute_policy_conflict` |

两个 `reasonCode` 都是本次设计**新增的稳定代码**，不是对现有代码的描述。不复用 422 的 `SETTLEMENT_CONSUMPTION_REFUSED` / `invalid_entry`（[SettlementConsumptionEntry.swift:253](file:///Users/mr.simi/Documents/SimiGo/SimiGo/Protocol/SettlementConsumptionEntry.swift#L253)）：那一个保持 422 语义与计数不变。新 `errorKind` 让「格式错误」与「业务拒绝」在统计上不可混。

两者都必须在模型调用与任何持久化写入之前拒绝。

### D2. 校验顺序与优先级

固定顺序，不依赖字典遍历：

1. JSON 形状/类型（字段存在但类型错）；
2. `recompute_policy` 取值合法（`never` / `allow_safe_recompute`）；
3. 两字段互斥（本条终端）；
4. 其余语义校验（身份、合同、来源）。

前三步全部发生在**任何模型调用与持久化写入之前**；命中即返回，不进入 P1。

### D3. 影响面

- 只对 C 作用域请求对象生效；普通聊天请求不解析该字段，语义不变。
- 不计入业务拒绝（422）统计；不写失败审计（尚未开始执行）。
- 未知取值的判定与冲突判定互斥：取值非法时先报 `recompute_policy_invalid`，不再继续比较另一字段是否存在。

---

## E. 失败审计事件（裁定 6）

### E1. 存储：复用 append-only 索引，不建新表

- 事件 JSON 用 `writeObject` 写入 `is_objects`（写一次）；
- 用 `appendIndexEntry(identity: "c-failure-audit:<execution_id>", objectID:)` 追加索引（F17，append-only 触发器）；
- 读取用 `resolveIndexIdentity`（`.last`）。
- 不新增表/迁移。命名空间 `c-failure-audit:` 已批准。
- **`execution_id` 的语义（已裁定）**：必须代表**一次具体执行尝试**，不是跨多次重算重复使用的逻辑任务 ID。一次尝试对应一个终态失败审计对象；不得因复用身份而覆盖或混淆记录。
- **身份冲突的处理**：若该 identity 已存在（理论上不应发生），视为**审计写入失败**——不覆写历史对象、不改原始请求失败结果，并记 `audit_persisted=false`（§E3）。
- 必须保留 append-only 语义：任何实现都不得为了让「重试」写入成功而更新或删除既有审计对象。

### E2. 字段

```
{
  "schema_version": "c-failure-audit-v1",
  "execution_id": "…",                       // 一次具体执行尝试的 ID，不可跨重算复用
  "request_kind": "continuation|consumption",
  "occurred_at": "…Z",
  "stage": "P1|S|G|P2",
  "anchor": { "state_id": "…", "settlement_id": "…" },
  "declared_snapshot_id": "…|null",
  "final_snapshot_id": "…|null",
  "used": { "present": true|false, "items": 3, "object_id": "…|null" },
  "policy": "never|allow_safe_recompute",
  "model_calls": 1,
  "settlements_written": 0,
  "states_written": 0,
  "refusal": { "cause": "…", "origin": "…", "evidence": {…} },   // 内部可见
  "model_output_digest": "…|null",            // 已生成但未提交时
  "idempotency": { "key_present": true|false, "conflict": true|false }
}
```

### E3. 持久化结果的表述

- 事件**不能**在自身内容里声称「已持久化」——写入成功才会存在该对象，失败则根本没有对象。
- 因此 `audit_persisted: true|false` 由**写入方**在执行结果/内部运行台账中记录：成功 = 对象存在且索引已追加；失败 = 标记 `audit_persisted=false` + 错误类别。
- 约束（裁定 6）：审计写失败**不得**把失败请求变成成功，**不得**把已发生的模型调用记成 0，也不得宣称「记录已完整持久化」。

### E4. 时序

P2 回滚**之后**写；best-effort。审计写失败不影响原始终止码与计量。

### E5. 验证设计

- **C-14**：P2 失败后存在审计对象且能被索引解析；注入索引写失败时，请求仍是原终止码，`model_calls>0`、`audit_persisted=false`。
- **C-15**：审计对象中不出现文件绝对路径与逐项摘要（仅计数与标识）。

---

## F. 幂等键（裁定 4 的接口化）

### F1. 字段与层

- `idempotency_key`：C 作用域请求对象（与 `recompute_policy` 同层），可选、不透明字符串（限长、不做大小写/编码归一化）。
- `consumer_es_state_id`：调用方显式指定的消费者状态 ID，可选。
- 两者可单独或同时出现；同时出现时两者都必须一致才视为同一分支（否则冲突）。

### F2. 落点（已裁定）

- `execution_states` 新增**可空列** `idempotency_key` + 部分唯一索引 `WHERE idempotency_key IS NOT NULL`；与结算在同一事务插入，唯一性冲突由该约束兜底并在事务内转成 §F4 判定。
- **不复用** `execution_states.continuation_id`：它是每状态生成的 UUID、参与 UI 与恢复（F16），语义不同；复用会破坏恢复语义。
- **v1 作用域 = 全局唯一**（在没有可靠的调用方/执行域标识之前）。若后续引入调用方作用域，**不得**静默改变既有键的含义——那需要单独裁定与迁移方案。

### F3. 指纹：不是「最终文本」

幂等判等必须**同时**比较下列各项，任一不同即不是同一逻辑执行：

| # | 成分 | 载体 |
|---|---|---|
| 1 | 请求指纹 | 规范化请求对象（需求、`recompute_policy`、解除 `idempotency_key` 本身后的语义字段） |
| 2 | 固定锚点 | `(anchor_state_id, anchor_settlement_id)` |
| 3 | 复用合同 | 合同标识 + 版本 |
| 4 | 输入快照 | `declared_input_digest`（§A3；排除 `captured_at` 与执行 ID），必要时加 `final` 快照 ID |
| 5 | 身份 | 生产者身份绑定 |
| 6 | 产出摘要 | 模型产出摘要（与结算 payload 摘要同源） |

- 只比最终文本相等就判重放是**不合格**的：不同输入可能产出相同文本，那会把一次新执行错误地合并进旧分支。
- 同理，**只比请求相等**也不合格：同请求在输入变更后可能产生不同结果，必须按冲突处理而不是重放。

### F4. 判定矩阵（P2 单写事务内）

| 键状态 | 指纹与产出 | 结果 | 计量 |
|---|---|---|---|
| 无 | — | 正常提交 | `settlements_written=1` |
| 有，同键且六项全同 | 相同 | **幂等重放**：返回既有结算，不新建分支/结算 | `model_calls>0`、`settlements_written=0`、标记 `replayed=true` |
| 有，同键但任一指纹成分不同 | 不判 | **拒绝** `idempotency_conflict`（422 业务拒绝） | `model_calls>0`、`settlements_written=0` |
| 有，同键且指纹全同但产出摘要不同 | 不同 | **拒绝** `idempotency_conflict`（同上） | 同上 |
| 指定 `consumer_es_state_id` 已被占用 | — | 主键冲突 → 拒绝（不覆盖既有状态） | `settlements_written=0` |

- **权威检测在 P2 单写事务内**，与提交同事务；P1 只可做建议性预查（快速失败），不得据此下结论。
- 「重放」只指**已提交**的同一逻辑执行；未提交的同键并发请求不算重放。
- `idempotency_conflict` 的 status/errorKind 按 §A8b：422 + 所在表面的既有 errorKind，`reasonCode` 为新码。

### F5. 并发与计量（必须写清，不留歧义）

- 不引入全局互斥，也不引入意图行；两个并发同键请求**都可能**真实执行模型。
- 只有一个能提交；落败方按 §E 记失败审计，并**必须同时记 `model_calls>0` 与 `settlements_written=0`**。
- 因此：**幂等语义不等于「模型调用只发生一次」**，只保证「成功结算写入至多一次」。任何把并发落败记成 `model_calls=0` 的汇报都是错误口径。
- `recompute_policy=never` 时不存在新分支创建，幂等键只用于「同一消费/续跑请求重复投递」的去重；重放路径不触发模型。

### F6. 验证设计

- **C-16**：同键 + 六项全同 → 返回既有结算、`settlements_written=0`、无新状态；
- **C-17**：同键但请求指纹或产出摘要不同 → 422 `idempotency_conflict`、零写入、既有分支不变；
- **C-18**：并发同键两请求都过 P1 且都调用模型 → 断言恰好一个提交，落败方 `model_calls>0 && settlements_written=0`，且不出现两个结算引用同一分支；
- **C-18b**：同键同请求但输入快照不同（`declared_input_digest` 不同）→ 不得判重放，必须冲突或按普通新分支处理（二者择一须在实现前明确，不得静默合并）。

---

## G. 快照采集点（裁定 1 与裁定 6 的时点合同）

### G1. 采集点

| 点 | 相位 | 动作 | 失败 | 留下的证据 |
|---|---|---|---|---|
| ACQ-1 | P1 | 解析根 locator、枚举声明根集合（不写） | `snapshot_root_unavailable` | 无 |
| ACQ-2 | P1 | 逐项 stat → open → 读字节 → SHA-256 → 再 stat；不稳定重试 ≤2 | `snapshot_unstable` / `_missing` / `_unreadable` | 无 |
| ACQ-3 | P1 | 决定引用还是内嵌：`object_id` 非空且 `readObject` 哈希一致 → 引用；否则内嵌本次字节 | `snapshot_unrepresentable` | 无 |
| ACQ-4 | S | 写 `declared` 对象，读回校验哈希，得到 `declared_snapshot_id` | 写入/读回失败 500；容量越限 422 | 失败即无对象；成功后为孤儿候选 |
| ACQ-5 | G | 逐次检索命中记录 `used`（内存）：标识、摘要、`byte_source`、是否可重放 | 不失败（记录失败则该次请求按 P2 处理） | 仅内存 |
| ACQ-5b | G（调用前与命中时） | 每新增一条 `used` 立即做集合成员预检：`(kind, 标识)` 是否在 `declared` 内、`digest` 是否等于其 `sha256`；命中即拒绝 | `snapshot_used_undeclared` / `snapshot_used_mismatch` | 若在任何模型调用前判定 → `model_calls=0` |
| ACQ-6 | P2 | 逐项 + 集合成员**完整**复核（ACQ-5 的全部条目重跑一遍，不是只查新增）；构建并写入 `final` 对象（引用 `declared`、含 `used`）；结算行引用 `final` | 回滚 | `declared` 保留，`used` 尽力写审计 |
| ACQ-7 | P2 | 事务内复核锚点/闭包/身份/合同/幂等键 | 回滚 | 同上 |

- **ACQ-5b 与 ACQ-6 的分工（裁定 1 的跨阶段约束）**：预检只为早失败（可能在 `model_calls=0` 时终止），**不能**代替 P2 的完整复核；P2 必须对最终 `used` 全集重跑成员与摘要判定（§A4b）。
- **禁止补写**：生成期间才出现的、不在 `declared` 中的输入，不得在 `used` 里被「事后登记」后继续提交；只能判 `snapshot_used_undeclared`。

### G2. 崩溃矩阵

| 崩溃点 | 已持久化 | 丢失 | 正确口径 |
|---|---|---|---|
| S 之前 | 无 | — | 无快照；`model_calls=0` |
| S 之后、G 之前 | `declared` | — | 孤儿快照；无执行证据 |
| G 中（预检前） | `declared` | `used` | 只能证明声明输入 |
| G 中（`used` 违规被预检拦下） | `declared` | — | 若发生在首次调用前 → `model_calls=0`；否则 `model_calls>0`、`settlements_written=0` |
| P2 提交前 | `declared` | `used`（除非审计已写） | 零结算；审计 best-effort |
| P2 提交后 | `declared` + `final` + 结算 | — | 完整 |

### G3. 可证明边界（精确表述）

- 能证明：声明输入在 S 时刻的字节/摘要；P2 复核时刻磁盘与声明一致；本次执行使用的每个输入都能对应到声明集合中的同一 `(kind, 标识)` 且摘要相等（§A4b）；结算引用的是哪份快照。
- 不能证明：P2 复核之后到提交之间文件未变（TOCTOU 残余）；G 段崩溃前模型实际读过哪些检索命中；未嵌入字节的项能被重现。
- **集合成员可证、内容完整性可证、时间窗不可证**：三者必须分开表述，不得用前两项推出第三项。
- 对外只应说「verified as of T」，不说「current」；无 `used` 时不说「已记录实际读取」；`used` 全部通过成员判定时也只能说「受声明清单约束」，不能说「字节在生成期间未变」。

### G4. 参数（实现时定值，设计不定值）

稳定性重试次数（建议 2）、单文件上限沿用 `fileByteCap`（F19）、快照上限已定（32 MiB 原始字节 / 48 MiB 最终对象，§A3）、`used` 条目上限（实现时定值）、摘要算法固定 SHA-256。超过上限 fail-closed，不截断。

---

## H. 五项推断的裁定记录（已裁定，非建议）

| # | 事项 | 裁定结果 | 落地位置 |
|---|---|---|---|
| 1 | 未知 `recompute_policy` 取值 | **400 `INVALID_REQUEST_ENTRY`**，`reasonCode=recompute_policy_invalid`；冲突用 `recompute_policy_conflict`；两者都在模型调用与持久化之前；既有 422 `invalid_entry` 不变 | §D1、§D3 |
| 2 | 内嵌字节编码 | **JSON + Base64**；必须服从上限；不得截断、不得只留摘要、不得把不可重放数据标成 `replayable=true` | §A3 |
| 3 | 失败审计索引命名空间 | **`c-failure-audit:<execution_id>`**；`execution_id` = 一次具体执行尝试，不是可复用的逻辑任务 ID；一次尝试一条终态审计；身份碰撞按审计写失败处理，不覆写、不改原始失败结果 | §E1、§E3 |
| 4 | `idempotency_key` 落点 | **`execution_states` 可空列 + 部分唯一索引**；不复用 `continuation_id`；判等必须比请求指纹/锚点/合同/输入快照/身份/产出摘要；v1 全局唯一 | §F2、§F3、§F4 |
| 5 | 快照大小上限 | **内嵌原始字节合计 ≤ 32 MiB**；**最终序列化对象 ≤ 48 MiB**；两者都强制、都 fail-closed、不截断；覆盖整个序列化（含元数据）；v1 工程限值，调整需实测依据 | §A3 |

### H1. 附带裁定的两条硬约束

- **`model_calls` 与 `settlements_written` 必须分开计量**：前者是模型执行次数，后者是成功结算写入次数；任何汇报不得用一个数替代另一个（§C 三态计量、§F5）。
- **跨阶段硬约束：`used ⊆ declared`**（§A4b）。G 段实际使用的每项输入必须能对应到 P1 固定的声明输入及其精确字节版本；不符即 P2 拒绝，且此时允许 `model_calls>0` 而 `settlements_written=0`。「保存了一份清单」不等于「本次执行受该清单约束」。

---

## I. 本设计**不**包含

- 不实现快照写入、不加 `input_snapshot_object_id`、不加 `idempotency_key`、不做迁移。
- 不改 `SimiGoISAdmission.Refusal`（含 `MIGRATED_LEGACY` 分码）、不改 `ContinuationAdmissionFailure`、不改任何 422/503 映射；新增 400 终端也只是**设计**，未接线。
- 不实现失败审计写入、不实现幂等冲突检测、不实现采集器、不实现 `used ⊆ declared` 判定。
- 不回收孤儿对象、不加 TTL / 后台清理 / 隐式空间回收、不摘除写一次触发器、不加 watcher、不做盘上复核自动化。
- 不扩大公开错误码集合（allowlist 之外一律内部）；不实现「调用方可填 `replayable`」。
- 不改 `prefix-pool` / `branch-checkpoints`、不动真实库残留根、不改普通续跑语义、不改 KV 目录行为。
- 不清理两个测试残留根（`work-00000000903bb636`、`work-0000000059acde6e`）。

---

## J. 纯设计一致性审查记录（2026-10-27，无代码改动）

对字段、错误码、索引身份、快照版本四项做了交叉核对。**已在本稿内修正**的冲突：

| # | 发现 | 处置 |
|---|---|---|
| J1 | `declared` 对象内保存 `captured_at` 与 `idempotency_key`，而 `declared_input_digest` 又被当作幂等指纹 → 同一逻辑执行永远判「不同」 | §A3 精确化：指纹只覆盖 `{canonical_version, digest_algorithm, root_ids, contract, sources(kind,标识,sha256)}`，排除 `captured_at` / `idempotency_key` / `recompute_policy` / 执行 ID；取证字段与指纹字段分开定义 |
| J2 | `final` 对象缺版本字段，只有 `part:"final"` → 与 `declared` 的 `canonical_version` 不对称，读取方无法在未知版本时 fail-closed | §A4 补 `schema_version` / `canonical_version` / `declared_input_digest` / `verified_as_of`；明确未知 `part` 或未知 `schema_version` 一律拒绝解析 |
| J3 | 容量越限在 S/P2 记 500，在 P1 记 422 → 同一类可判定拒绝出现两种状态码 | §A8 统一为 422 `snapshot_unrepresentable`；500 只留基础设施失败 |
| J4 | `used ⊆ declared` 在 §A4b 与 §G 定义了，但 §A7 的 P2 复核伪代码漏了这一步 | §A7 补入完整 `used` 复核（不只查新增） |
| J5 | `idempotency_conflict` 与 `snapshot_*` 只给了 422，未给 errorKind，可能被实现成新桶 | §A8b 定义「沿用所在表面既有 errorKind + 新 reasonCode」，400 族为唯一新增 errorKind |
| J6 | §H 原建议「需确认不与既有 SRS identity 冲突」未验证 | F20 只读核实：既有前缀为 `file:` / `chat:` / `demand:` / `settlement:` / `settlement-summary:`，`c-failure-audit:` 无碰撞 |
| J7 | `execution_id` 在 §E1 已裁定为「单次执行尝试」，但 §E2 字段注释仍写「本轮唯一执行 ID」，措辞可被读成「任务级」 | §E2 注释改为「一次具体执行尝试的 ID，不可跨重算复用」 |

**O1–O3 已裁定（2026-10-27 收口，原为未决项）**：

| # | 事项 | 裁定 | 落地 |
|---|---|---|---|
| O1 | 新增 `reasonCode` 是否全部公开 | **不全部公开**：封闭 allowlist，公开码 = 两条 400 码 + `snapshot_unrepresentable` + `idempotency_conflict` + 入口既有分类；其余内部码只内部可见；内部枚举增长不自动增加公开码；模型后 `used` 违例不得伪装成 400 或「模型执行失败」 | §A8b、§A8、§A10（C-10d） |
| O2 | `replayable` 是否取合取 | **是**：`final.replayable = declared.replayable ∧ used.replayable ∧ (used ⊆ declared 且逐项摘要一致)`；逐项标记保留、整体必须由证据计算，调用方不得填写 | §A4a、§A10（C-10c） |
| O3 | 孤儿快照保留期 | **v1 无 TTL、无自动 GC、不按天数删除**；引用数为零不构成删除授权；存储压力下**拒绝新建并报告存储问题**，不得删旧证据；将来 GC 需独立授权与引用完整性规则 | §A9、§A10（C-10e） |

补记 J8–J10（本轮修订带来的约束）：

| # | 变更 | 影响 |
|---|---|---|
| J8 | §A8 拆成「对外终端 / 内部原因」两列 | 所有验收断言必须分两层读取；只读 HTTP 无法证明内部原因，验收需内部台账（C-10d） |
| J9 | §A4 原「`replayable=true` 条件」表述改为 §A4a 的合取公式 | `declared` 可重放但 `used` 缺失时，整体必须为 `false`；此前文字可能被读成「声明可重放即整体可重放」 |
| J10 | §A9 增加存储压力条款 | 容量耗尽属基础设施失败（500），**不能**混入业务拒绝统计，也不能触发任何删除 |

**审查未发现冲突的三项**：`settlements.input_snapshot_object_id` 可空列与 v8 加列模式无冲突（F18）；`execution_states.idempotency_key` 与主键/`continuation_id` 无冲突（F16）；S 相位写单个 `is_objects` 与写一次触发器无冲突（F1）。
