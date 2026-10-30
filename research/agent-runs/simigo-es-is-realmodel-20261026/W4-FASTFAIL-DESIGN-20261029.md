# W4 / A 方案：请求预算快速失败（prefill budget fast-fail）设计与验收定界

**日期：** 2026-10-29
**状态：** **仅设计，未实施**。owner 2026-10-29 裁定：采纳「先 A、后 B」；本文件只交付 A 的设计与验收边界，**当前没有新增产品代码授权**；B（W3 前缀续算）不在本文件范围内，也不因 A 先行而获得授权。
**上游事实来源：** `hang121-20261029/TIMELINE.md` 与冻结 trace（`SHA256SUMS.txt`）；本节不重跑，不引用未冻结数据。

---

## 0. 一句话目标

在**调用模型之前**判定「这一轮在当前请求预算内不可能交付」，并返回**可识别的拒绝**；不启动预填、不写答案结算、不污染会话池。

明确不承诺：**这不能使 40,363 token 那个任务变得可完成**（那是 B/W3 的事）。A 的通过只证明空耗被控制。

## 1. owner 五条验收要求（本设计的约束来源）

| # | 要求 | 对应设计节 |
| --- | --- | --- |
| 1 | 调用模型前用可靠 token 计数与预算规则识别不可行请求，避免启动约 60 s 全长预填 | §3.1 §3.3 §3.4 |
| 2 | 返回可识别预算拒绝，不伪装成成功答案，不产生虚假答案结算或 ES 完成状态 | §3.5 §3.7 |
| 3 | 该路径没有启动模型生成，也没有会话池污染或不必要的 `poisonedSessionEvict` | §3.4 §5-A1 |
| 4 | 保留正常大小请求既有路径；不把单次 661.6 tok/s 固化成速度常数 | §3.2 §3.8 |
| 5 | 失败后只有在输入缩短/预算调整等实际条件改变时才重试，不能同 payload 高频重放 | §3.6 §5-A5 |

## 2. 可复用的既有机制（不新造轮子）

| 机制 | 位置 | 复用方式 |
| --- | --- | --- |
| 上下文安全门（字节快门 → tokenizer 精确复核 → 抛 `contextDemandExceeded`） | [NativeMLX.swift:1066](file:///Users/mr.simi/Documents/SimiGo/SimiGo/Inference/NativeMLX.swift#L1066) | 复用「字节先筛、精确后判」的两级形态与错误族 |
| 内容 token 精确计数 | [NativeMLX.swift:213](file:///Users/mr.simi/Documents/SimiGo/SimiGo/Inference/NativeMLX.swift#L213) | 作为**下界**参考；**不足以**做时间门（见 §3.1） |
| 拒绝风暴抑制（10 s 同键聚合，头笔完整/成员抑制/尾行收口） | [RuntimeLifecycle.swift:72](file:///Users/mr.simi/Documents/SimiGo/SimiGo/Lifecycle/RuntimeLifecycle.swift#L72) | 直接复用为「同 payload 高频重放」的抑制器 |
| 校验错误族 | [LifecycleGates.swift:3](file:///Users/mr.simi/Documents/SimiGo/SimiGo/Inference/LifecycleGates.swift#L3) | 新增一个 case，与 `contextDemandExceeded` 平级 |
| 每轮 `promptTokens` / `promptTime` 实测 | [NativeMLX.swift:1859](file:///Users/mr.simi/Documents/SimiGo/SimiGo/Inference/NativeMLX.swift#L1859) | 速度模型的采样来源 |
| 预填进度回调里的**精确总量** `total` | [NativeMLX.swift:1050](file:///Users/mr.simi/Documents/SimiGo/SimiGo/Inference/NativeMLX.swift#L1050) | 估算器的对账基准（不是门本身） |

## 3. 设计

### 3.1 判定输入：必须用渲染后的精确 token 数

现成的 `contextEstimate = incomingBytes / 4`（[NativeMLX.swift:1498](file:///Users/mr.simi/Documents/SimiGo/SimiGo/Inference/NativeMLX.swift#L1498)）在本批样本上**低估 1.85×**：`est=21838` vs 实际 `promptTokens=40363`（其中 30 个工具定义与模板开销不在 bytes/4 里）。**因此它不能当门槛输入。**

`contentTokenDemand` 是严格下界（不渲染模板），用它算时间是「下界的时间下界」，会放行本轮这种真超预算的请求。**也不能单独当门槛。**

设计取 `tokenizer.applyChatTemplate(messages:)` → `encode` 的**渲染后计数**（swift-transformers 已提供该入口）。三条硬约束：

1. **同源渲染**：估算与真实生成必须共用同一套模板/工具序列化参数；一旦两套实现漂移，估算就不再可信。
2. **必须对账**：每轮把 `estimatedTokens` 与 `prefill.progress` 的 `total` 差写入 trace（`[BUDGET] est=… actual=… delta=…`），供验收统计误差分布。
3. **失败关闭**：渲染/分词失败（模板缺参、tokenizer 不可用）→ **不放行也不拒绝**，走「无法估算 ⇒ 门失效」并记 `[BUDGET] estimate_unavailable`，维持现有行为（正常请求不受影响）。

### 3.2 速度模型：测量 + 悲观分位，禁止常数

- 采样：每轮成功生成后取 `promptTokens / promptSeconds`（同 [NativeMLX.swift:1862](file:///Users/mr.simi/Documents/SimiGo/SimiGo/Inference/NativeMLX.swift#L1862) 的值），按**冷/热**两桶分别维护（`reuse=false` 与 `reuse=true`；两者速度差一个数量级，混池必错）。
- 估计值取**悲观分位**（最近 K 笔的 P10，K≈8），而不是均值；样本 < K 时用「已有样本的 P10」，样本为 0 时门失效（放行）。
- 速度对内存压力极敏感：`RuntimeTuning.prefillStepSize` 的注释记录了同机 2048 档从 510 tok/s 掉到 <48 tok/s 的实测（[RuntimeTuning.swift:176](file:///Users/mr.simi/Documents/SimiGo/SimiGo/Lifecycle/RuntimeTuning.swift#L176)）。所以样本必须**带时间衰减**（半小时前的读数不应压住现在的判断），并记录采样时的 `swapUsed`，用于事后解释误拒/漏拒。
- **不写任何形如 `661.6` 的常量**；661.6 只作为「本批样本的一个观测点」出现在证据里。

### 3.3 预算规则

```
effective_budget_ms = 请求头 X-Simigo-Deadline-Ms
                    ?? 设置项（默认见 §3.8）
reserve_ms          = max(5000, max_tokens / decode_rate * 1000)   // 给生成留时间
prefill_budget_s    = (effective_budget_ms - reserve_ms) / 1000
estimated_s         = estimatedTokens / rate_p10(reuseBucket)
reject  ⟺  estimated_s * 1.25 > prefill_budget_s          // 25% 安全边际
```

- `reuse=true` 的轮次估算的是 **delta**（`incoming - currentHistory`）而非全量——否则暖会话会被误拒。
- 复用命中的轮次（[HTTPServerChat.swift:462](file:///Users/mr.simi/Documents/SimiGo/SimiGo/Protocol/HTTPServerChat.swift#L462) / [:960](file:///Users/mr.simi/Documents/SimiGo/SimiGo/Protocol/HTTPServerChat.swift#L960)）**先短路返回，不经此门**：复用不预填，没有时间风险。

### 3.4 门的位置（关键）

候选位置与取舍：

| 位置 | 精确度 | ES/IS 写入 | 能否给出真 HTTP 状态 |
| --- | --- | --- | --- |
| P1：`prepareInformationTurn` 之前 | 低（看不到 IS 注入块，实测该块 4–8 KB ≈ 2–4 K token） | 零写入 | 能 |
| **P2：prepare 之后、生成之前（推荐）** | 高（含 IS 块、含工具） | 写 user chat 行 + demand + is-retrieval 快照 | 能（流式在发头前拦截） |
| P3：引擎内、`generate()` 开头 | 最高 | 同 P2 | **不能**——流式 header 已在 [HTTPServerChat.swift:542](file:///Users/mr.simi/Documents/SimiGo/SimiGo/Protocol/HTTPServerChat.swift#L542) 发出，只能 200+error 帧 |

推荐 **P2**，理由是：IS 注入块恰是把「刚好来得及」推过线的那部分；P1 会系统性漏判。代价是拒绝轮会留下 demand 与检索快照（都不是答案结算，见 §3.7）。

需要新增一个**只读的**引擎口子（不建 session、不进生成 gate、不写 `prefillStep`）：`estimateRenderedPromptTokens(messages:tools:) async -> Int?`，内部只做 `applyChatTemplate` + `encode`。

六条 wire 的插入点（流式与流式/非流式各一）：

| wire | 调用点 |
| --- | --- |
| chat 流式 | [HTTPServerChat.swift:589](file:///Users/mr.simi/Documents/SimiGo/SimiGo/Protocol/HTTPServerChat.swift#L589)（在 :542 发头之前） |
| chat 非流式 | [HTTPServerChat.swift:1046](file:///Users/mr.simi/Documents/SimiGo/SimiGo/Protocol/HTTPServerChat.swift#L1046) |
| responses 非流式 | [HTTPServerResponses.swift:1307](file:///Users/mr.simi/Documents/SimiGo/SimiGo/Protocol/HTTPServerResponses.swift#L1307) |
| responses 流式 | [HTTPServerResponses.swift:1761](file:///Users/mr.simi/Documents/SimiGo/SimiGo/Protocol/HTTPServerResponses.swift#L1761) |
| completions ×2 | [HTTPServerCompletions.swift:218](file:///Users/mr.simi/Documents/SimiGo/SimiGo/Protocol/HTTPServerCompletions.swift#L218) / [:541](file:///Users/mr.simi/Documents/SimiGo/SimiGo/Protocol/HTTPServerCompletions.swift#L541) |

### 3.5 拒绝形状

HTTP **503**，JSON 体（流式亦然，因为拦在发头之前）：

```json
{"error":{
  "type":"prefill_budget_exceeded",
  "code":"prompt_exceeds_deadline",
  "message":"prompt ~40363 tokens needs ~61.1s to prefill at 661 tok/s; budget 60000ms leaves 55000ms after reserving 5000ms for generation",
  "prompt_tokens":40363,
  "estimated_prefill_ms":61100,
  "budget_ms":60000,
  "samples":8
}}
```

响应头：`X-Simigo-Retry-Policy: on-input-or-budget-change`。**不发 `Retry-After`**——它暗示「等一会就好」，而这正是我们不想鼓励的行为。

与既有 `context_length_exceeded`（[HTTPServerChat.swift:747](file:///Users/mr.simi/Documents/SimiGo/SimiGo/Protocol/HTTPServerChat.swift#L747)）的关系：两者是不同类。前者是「超出模型能力，压上下文再来」；后者是「在预算内来不及，缩短输入或放宽预算再来」。类型名不得复用，避免客户端把预算拒绝误当成上下文超限去压缩。

### 3.6 重放抑制（要求 5 的落地方式）

两层：

1. **判定缓存**：key = `sha256(渲染后 prompt 文本) + budget_ms + model`。命中即原样返回上一条拒绝体，**不重复分词**，耗时 O(1)。TTL 10 分钟（与 `RejectBurstTracker` 的 10 s 风暴窗口不同层，互不替代）。
2. **trace 风暴抑制**：复用 `RejectBurstTracker`（[RuntimeLifecycle.swift:97](file:///Users/mr.simi/Documents/SimiGo/SimiGo/Lifecycle/RuntimeLifecycle.swift#L97)），同会话 10 s 内多笔只留头笔，尾行聚合 `burstSuppressed`，避免把日志刷成噪音。

必须诚实写清能力边界：**服务端无法阻止客户端重试**（Qoder 在本批 0.2 s 内就重发）。A 能保证的是「每次重放都不消耗模型工作、不写任何回答」；「客户端不再高频重放」只能靠错误类型 + 策略头告知，或在客户端侧退避——后者记录为**外部条件**，不能拿来替代服务端保护。

### 3.7 与 ES/IS 的关系（要求 2 的落地）

选 P2 后，一次被拒请求会产生的行：

| 行 | 是否产生 | 说明 |
| --- | --- | --- |
| `chat_messages`（user） | 是 | prepare 已写，属事实（用户确实提了这问） |
| `chat_messages`（assistant） | **否** | 没有回答 |
| `information_demands` | 是 | 需求存在，但不会被满足 |
| `settlements`（`is-retrieval:*`） | 是 | 检索快照，属事实 |
| `settlements`（答案） | **否** | — |
| `information_advancements` | **否** | 没有任何「已满足」的声明 |

即：**ES 不会有完成态，IS 不会出现可复用答案**。被拒的 demand 在现有状态机里停在未完成态，本设计**不新增 demand 状态**（避免 schema 变更），但要求 trace 写明 `[BUDGET_REJECT]` 以便事后把它与「用户放弃」区分开。若 owner 认为需要显式 `REJECTED` 状态，作为独立小项另议。

### 3.8 开关与默认值

- 主开关：`SIMIGO_REQUEST_BUDGET_MS`（0 = 关闭）。设置项同名，UI 后置。
- **默认值待 owner 裁定**（见 §7-Q1）。技术事实：本客户端实测 60.003 s 关连接；如按「默认开启」设计，代价是任何超过约 55 s 预填的请求都会被拒，包括用户可能愿意等的场景。

## 4. 明确不做

- 不做 W3/KV 前缀保留、不碰 `poisonedSessionEvict` 语义、不碰上游 ledger。
- 不碰复用门（`(tools ?? []).isEmpty`）——那是 #126 的合同问题。
- 不碰 `context_length_exceeded` 的既有行为与文案。
- 不做「首 turn 预热」（W4 的另一半）；预热会改变常驻内存曲线，需要单独的验收。
- 不改任何已冻结证据、不改 §3.33 原文。

## 5. 验收边界（把五条要求变成可测判据）

每一条都要**同窗正对照**（同一构建、同一进程、同一模型会话），否则不成立。

| 判据 | 测法 | 通过条件 |
| --- | --- | --- |
| **A1 无模型工作** | 打一条超预算请求，取 trace 与 DB | 无 `[MLX] prefill`、无 `sessionAdopt`/`sessionAdoptMiss`、无 `prefillStep`；`residencyLedger sessions=` 前后不变；无 `cancelCommitSkip`、无 `poisonedSessionEvict` |
| **A2 拒绝可识别** | 同一条请求的 HTTP 响应 | 状态 **503**（不是 200，流式请求也一样）；`type=prefill_budget_exceeded`；含 `prompt_tokens`/`estimated_prefill_ms`/`budget_ms`；无 `data:` 帧 |
| **A3 无虚假结算** | 只读 DB，按该轮 session/query 查 | 答案 `settlements` 零增、`information_advancements` 零增、assistant chat 行零增；demand 停在未完成态 |
| **A4 常规路径不变** | 同窗小 prompt（<8 K） | 正常 `stop=complete` + 一次答案结算 + 一次 advancement；且样本不足时门不拒绝 |
| **A5 重放成本≈0** | 同 payload 连续 3 次 | 3 次均 503、单次耗时可测（目标 <100 ms，且远小于 60 s）；三次之间无引擎事件；把输入缩短到预算内后**放行并正常完成**（正对照） |
| **A6 估算误差** | 每轮 `[BUDGET] est=… actual=…` | 统计 N≥20 轮，`|est-actual|/actual` 的中位数 ≤5%，P95 ≤15%（阈值可议，但必须先定） |

**A 通过 ≠ 任务可完成**：40,363 token 这一轮在 A 之后仍然不会成功，只是从「60 s 空转×N」变成「立即说不行」。要让它成功，需要 B。

## 6. 实施前必须先做的校准（否则 A 不可验收）

1. 干净窗口（`build/aN` 规程）里对目标模型跑 8K / 24K / 40K 三档冷预填各 3 次，记录 `promptTokens`、`promptTime`、`prefill stepSize`、`swapUsed`。
2. 取各档 P10 作为速度模型初值；写进「标定表」，并在实施后由运行时继续用实测更新（标定值只是冷启动种子）。
3. 记录同机并发/换页状态下速度的下降幅度（09-13 实测 2048 档 510 → <48 tok/s），用于设定安全边际是否要从 1.25 抬到更高。

## 7. 待 owner 裁定的三个开放问题

| # | 问题 | 选项 | 我的倾向 |
| --- | --- | --- | --- |
| Q1 | 预算默认值 | (a) 默认 60000 ms 开启；(b) 默认关闭，只认请求头/设置 | (b) —— 服务端无法确知客户端耐心；默认开会在「用户愿意等」的场景造成误拒。但这意味着 **A 默认对 Qoder 不生效**，需要用户/客户端显式给预算 |
| Q2 | 门位置 | (a) prepare 前（零 IS 写入，估不准）；(b) prepare 后（含 IS 块，留 demand/检索快照） | (b)，理由见 §3.4 |
| Q3 | 状态码 | 503 / 429 / 422 | 503（不是「你请求太快」，而是「这个请求在预算内不可服务」） |

Q1 直接决定 A 能不能止住本批观测到的活锁：若选 (b) 且 Qoder 不发预算头，则 A 只是能力而非行为改变——这一点必须在实施前说清，不能用「已实现」冒充「已止血」。

## 8. 交付物与授权边界

- 本文件 = 设计 + 验收边界 + 开放问题，**不含代码**。
- 实施需要单独授权；实施范围限于本文件 §3 所列，不得顺带改 W3 / 复用门 / IS 合同。
- 校准跑（§6）属于「新实验」，同样需要授权，且不得复用 §3.33 冻结证据以外的读数。

---

## 9. owner 裁定（2026-10-29）与冷启动规则补全

> 本节为追加。§0–§8 原文保持不动；原文哈希记录在本节末尾。裁定原文要点见验收文档「3.33 续三」。

### 9.1 Q1–Q3 最终裁定

| 项 | 裁定 | 本设计的落地 |
| --- | --- | --- |
| Q1 | **(a) 默认开启，60,000 ms** | `effective_budget_ms = 请求头 X-Simigo-Deadline-Ms（>0 时） ?? 本地设置 SIMIGO_REQUEST_BUDGET_MS（默认 60000）`；请求头缺失**不关闭**预算治理；`0` 仅作为**本地显式关闭**（运维/测试），请求头传 0 或负数视为无效并回落到本地设置 |
| Q2 | **prepare 后、发流头前** | 顺序固定为：prepare（含 IS 注入）→ 渲染后计数 → 预算判定 → 发头 → 生成。Responses 流式现先把 200 SSE 头发在 prepare 之前，需把 continuationGate + prepare 上移到发头之前（纯顺序调整，不改协议语义），否则该 wire 无法满足本裁定 |
| Q3 | **HTTP 503** | `503` + `type=prefill_budget_exceeded` + `X-Simigo-Retry-Policy: on-input-or-budget-change`；**不发 `Retry-After`**；不把 503 当作「重试循环已停止」的证据——客户端行为只能在 §6 实测 |

保留冷、热两类独立样本；最近 K 笔（K=8）P10 + 时间衰减；**禁止把 661.6 tok/s 写成常数**。

### 9.2 冷启动与「无样本」规则（编码前必须补齐的缺口）

原 §3.2 的「样本不足 → 门失效放行」单独成立会留下缺口：首次冷请求可能仍耗 60 s，即使 Q1 默认开启。补全后的判定顺序如下（每一步都写 trace，且**不得把放行报成拦截**）：

| 序号 | 条件 | 行为 |
| --- | --- | --- |
| R1 | 匹配身份下有 **n ≥ 1** 个冷/热样本 | `estimated_s = tokens / P10(最近 K 笔，时间衰减)`；`n < 3` 时安全边际用 **1.5**，`n ≥ 3` 用 **1.25**；`estimated_s × margin > prefill_budget_s` ⇒ 拒绝 |
| R2 | 无匹配样本，但**同一渲染后 prompt** 有本进程/持久化的超预算观测（见 R3） | 用观测证据直接判定；证据成立即拒绝，不启动模型 |
| R3 | 无匹配样本，但有**匹配身份的校准记录**（§6 产物：同 model + tokenizer + 模板身份，≤30 天） | 以校准记录作为样本参与 R1（记录本身是实测值，非伪造） |
| R4 | 以上都无 | **门未生效**：放行，并写 `[BUDGET] verdict=insufficient_samples samples=0`；报告与验收必须把这一轮单独计数，**禁止计入「已拦截」** |

补充规则：

- **不得**用 `661.6`、`510`、任何硬编码吞吐量填充样本；估算失败（渲染/分词抛错）记为 `verdict=estimate_unavailable` 并放行，不改既有行为。
- **同一 payload 的超预算观测**：每次真实预填都在 `prefill.progress` 里记录 `processed/total` 与墙钟起点；若该轮**未在预算内完成预填**（被取消时 `processed < total` 且已耗时 ≥ 预算，或实测 `tokens / observed_s` 推断超预算），写入观测索引（key = 渲染后 token 序列摘要 + 模型/分词器/模板身份，TTL 30 min）。下一次**完全相同**的 payload 命中该索引即拒绝，理由 `prior_attempt_exceeded`，并在拒绝体里带上观测到的 `processed/total/elapsed_ms` 与来源 `request_id`。这是「不能让每次重试都被当成完全没有历史的新请求」的落地方式。
- **缓存身份**：`promptDigest = SHA256(渲染后 token id 序列)`（token 序列已隐含 tokenizer/模板）；速率样本 key 另带 `modelIdentity + tokenizerProbeDigest + templateProbeDigest`。跨模型/跨分词器/跨模板**不得**共享样本。
- **首次未知请求的保护边界**：若既无样本、无校准记录、也无同 payload 观测，第一次请求仍会被放行（这是 R4 的诚实代价）。它最多消耗一次预算；被取消后写入观测索引，同一 payload 的第二次重试即快速失败。§6 报告必须分别列出「首轮放行 / 次轮拦截」。

### 9.3 拒绝轮写入语义（修正原「零写入」表述）

Q2 选 prepare 后，原 §3.7 的「拒绝轮零 ES/IS 写入」**不按字面成立**。不变量精确化为：

| 操作 | 超预算拒绝时的要求 |
| --- | --- |
| prepare 已写入的用户行、demand、检索快照 | **允许保留**，并如实记录 |
| assistant 答案行、答案 settlement | **不得新增** |
| advancement、成功执行终态 | **不得新增** |
| 因本轮拒绝而新建的生成会话 | **不得发生** |
| 因预算拒绝而逐出已有 session | **不得发生** |
| 实际模型生成 | **不得启动** |

### 9.4 原文哈希与追加记录

| 项 | 值 |
| --- | --- |
| §0–§8 原文件 sha256（追加前） | `b648c7ef9a64d27d61dd63f6aa5aa540a9030272a53726d5875e8f682c80b468`（187 行） |
| 追加性质 | 仅追加 §9；§0–§8 一字未改 |
| 本次授权范围 | W4 产品实现 + W4 专用测试 + 构建/定向回归/§6 隔离校准；**不含 W3**、不含提交/推送/安装/发布 |

## 10. #138 冷启动样本污染与冻结拒绝（实现 + 代码门，W4 仍 OPEN）

| 项 | 值 |
| --- | --- |
| 处置对象 | (a) 加载后第一笔完成预填的计时被当作稳态吞吐；(b) 拒绝缓存 600s 冻结旧判定，新证据到达不解冻；(c) 缓存键未含 maxTokens（生成预留改变 prefill 预算） |
| 修法 | `PostLoadWarmupTracker`：每次模型加载/恢复复位，只消费一次；只有**可记录轮**（非 restore、非池恢复、有真实预填计时）才消费，预热轮不记速率样本、不留「已完成」观测（成功与取消两条路径一致，均 `[BUDGET] skip_record reason=model_warmup`）。`evidenceEpoch`：任何新样本/观测/校准装载递增；`decide` 在锁内发现缓存 epoch 过期即删除并按新证据重算。拒绝键加入 `maxTokens`。 |
| 未做（禁止项） | 未清空校准样本、未关闭预算门、未改动准入策略与 margin；样本不足仍如实 `insufficientSamples`（不伪造拦截） |
| 构建 | `build/dd`（mlx-swift-lm `6f88129b`，#136 能力在包内）；`xcodebuild build-for-testing -enableCodeCoverage NO` → `** TEST BUILD SUCCEEDED **`（build/w4-138-build3.log） |
| 定向测试 | 隔离根 `build/w4-138-iso`：`RequestBudgetControllerTests` 24/24 通过（含 4 个新增：#138 观测失效 / 样本失效 / 生成预留分键 / 预热只消费一次）；`RequestBudgetGateHTTPTests` 10/10 通过（build/w4-138-test.log, build/w4-138-test-gate.log） |
| 非干扰 | rc_noninterference pre/post diff：violations=0, real_user_state_write=0（build/w4-138-iso-diff.json） |
| 证据等级 | **仅代码-测试证据**。真实设备窗口尚未跑：需观测「加载后首笔完成预填 skip_record=model_warmup」且「第二笔起进入 P10 窗口」、取消→重试不再被旧拒绝 replay。W4 状态 **OPEN**，不得据此宣告修复完成。 |
