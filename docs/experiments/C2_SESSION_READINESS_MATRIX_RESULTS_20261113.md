# C2 Session Readiness 矩阵 — 执行结果记录（2026-11-13）

> 独立结果记录，对应预注册 `C2_SESSION_READINESS_MATRIX_20260922.md`（§11 要求的执行结果节）。
> 观察与解释分离；时延读数受内存压力污染，不作稳态性能声明；n=1（单机/单 build/单模型/单日）。

## 1. 环境（固定坐标）

| 项 | 值 |
|---|---|
| SimiGo build | **2.2.6 (60)**，/Applications/SimiGo.app（运行中 PID 12963；仓 HEAD 已到 2.2.7(1) 但被测二进制固定为 60） |
| 模型 | peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX（qwen3_5_moe，与 09-17 事故同族） |
| 设备 | Apple Silicon 真机（darwin 27.2.0 arm64）；实验窗口 swap 4.1→5.7GB |
| 载体 | 产品路径 HTTP `POST /v1/chat/completions`（127.0.0.1:8000），无测试专用装配 |
| 固定参数 | `stream=false`、`max_tokens` 20–60、显式 `session_id` + header `X-SimiGo-Agent: c2matrix` |
| trace | `~/.simigo/logs/native_mlx_trace.log`（实验窗口 07:16–07:50，trace 总行 170191） |
| 驱动与工件 | `~/.zcode/workspace/draft-a66c589d-1284-42fa-97c6-94727fefa3ec/c2_driver.py` + `c2_artifacts/`（每轮响应 JSON 与日志留档） |

**现行实现关键语义（相对 09-22 预注册时基线的变化）**：

1. **同 key 定义**：`mapKey = storageKey + 首条消息(+kvFingerprint)`（NativeMLX.swift sessionMapKey）；复用条件 = `incoming.count > history.count && fp同 && isPrefix`，miss 时输出 `reuseMiss count/fp/prefix`。按 messages 前缀推导身份已删除（身份解析 §3.4「每个 HTTP request 独立」）——同 key 必须显式 `session_id` + 逐字节相同首条消息。
2. **取消向量**（ADR 2026-10-30）：客户端断连 = **detach**（孤儿名额 1），断连本身不取消；唯一可达的预填中途硬取消 = **contended orphan yield**——新请求进入 `acquireGenerationAdmission` 时 `yieldDetachedOrphansForContention()` 取消在途孤儿，取消点落在预填循环 chunk 边界，协议层 fail-closed（不结算、不提交）。`stopDetachedOrphanIfContended` 在 60 中无调用点（死代码）。
3. **取消收口**：`cancelCommitSkip`（不提交）→ #136 `memPoolCapture`（引擎自证前缀捕获，`interruptedPrefixBoundary()` 逐层核验）→ `CancelEviction.decide(rawEventCount, reusedSameSession, adoptedForeignShard, retainedLedgerTokens, cacheProcessedTokens)`（纯函数）：`rawEv==0 && !reused` 时仅「账本>0 且=物理行数」才 `retainProvenPrefix`，否则 `evictFreshShard`（trace 标记沿用 **poisonedSessionEvict**）；reused 轮一律 keepResident。
4. **会话注册时机未变**：新 ChatSession 在预填前写入 `sessions[mapKey]`（与 09-17 事故结构同型）。
5. **Route B 前缀池**：取消轮捕获的引擎自证前缀进共享池（内容寻址、A-2 续跑准入门禁）；实验 filler 主体跨 marker 相同 → 出现跨 key 池命中（设计行为，非污染，见 §6-B4 注）。

## 2. 执行矩阵数据表

`reusedSession` 取该轮 trace `reuse=` 字段；`readiness-at-end` 为观察归纳：`READY`=stop=complete 且 history 已提交；`INTERRUPTED-KEPT`=cancelCommitSkip 后无逐出行；`INTERRUPTED-EVICTED`=poisonedSessionEvict；`ABSENT`=池中无该 key 分片。

### Case A — 新建 + 成功生成（9 次，全部 READY 入池）

| Run | session | reused | outcome | readiness-at-end | rawEv | cacheEff | mode | 备注 |
|---|---|---|---|---|---|---|---|---|
| A1 | c2a1 T1 | false | complete | READY | 1 | 0.00 | cold | 10401 tok，14.4s |
| A2 | c2b1 T1 | false | complete | READY | 1 | 0.00 | cold | （kill 失误意外轮，转记 A） |
| A3 | c2b3 T1 | false | complete | READY | 1 | 0.00 | cold | （同上） |
| A4–A9 | c2d2/c2d3/c2e1/c2e2/c2e3/c2h1 T1 | false | complete | READY | 1 | 0.00 | cold | 全部入池，后续格的基座 |

### Case D — 就绪/复用 + 成功生成（3 次，全部保持 READY）

| Run | session | reused | outcome | rawEv | cacheEff | mode | 备注 |
|---|---|---|---|---|---|---|---|
| D1 | c2a1 T2 | **true** | complete | 2 | **0.51** | prefix | cacheHit 10403 |
| D2 | c2d2 T2 | **true** | complete | 2 | **0.51** | prefix | cacheHit 5529 |
| D3 | c2d3 T2 | **true** | complete | 1 | **0.51** | prefix | cacheHit 5515 |

### Case B — 新建 + 预填中途取消（4 条有效链 + 1 次 kill 失误；每次取消后立即同 key 重试）

| Run | session | 取消落点 | reused | rawEv | capture | 判定 | pool-after | 同 key 重试 |
|---|---|---|---|---|---|---|---|---|
| B1 | c2b2 | 信号@6033/10054（预填中），落点=预填后首 chunk | false | **1** | refused（rows 10056 vs ledger 0） | **keepResident**（静默） | 毒分片驻留（history=0） | **reuse=true** → mode=cold cacheEff=0.00 全量重预填 14.0s → complete，无挂死 |
| B2 | c2b4 | 落点@5949/9914（预填中） | false | **0** | **成功**：`memPoolCapture tokens=7932 layers=10a/30r` | `cancelPrefixUnproven ledgerTokens=0 captured=7932` → **poisonedSessionEvict** | 分片逐出；引擎自证前缀 7932 进池 | **reuse=false** 新建（exec 614501）+ 池恢复 `cacheHitTokens=7932 cacheEff=0.81 mode=prefix`（墙钟 5.2s）→ complete |
| B4 | c2b5 | 落点@9599 行（预填尾部） | false | **0** | **拒收**（验证 44.5s 后 rows 9599 vs ledger 0，captured=0） | **poisonedSessionEvict** | 分片逐出；前缀未捕获 | **reuse=false** 新建（exec 0a13d8）+ 池恢复 7932（命中 B2 捕获的共享 filler 前缀，跨 key）cacheEff=0.83 → complete |
| B5 | c2b6 | 信号@+5s，落点@9666 行 | false | **1** | refused（rows 9666 vs ledger 0） | **keepResident**（静默） | 毒分片驻留（history=0） | **reuse=true** → mode=cold cacheEff=0.00 全量重预填 10.3s → complete，无挂死 |
| B3 | c2b3 | **kill 失误**：轮询落后落盘、kill 落在完成后 → 轮正常完成 | false | 1 | — | — | — | 转 Case A3 记录 |

原始证据行（B2 为例）：

```text
[DETACH] r=req-0c5efeed slots=1
[DETACH] stop=1 r=req-0c5efeed reason=generation_contended
[MLX] cancelCommitSkip session=c2matrix/c2b4/main history=0 rawEv=0 rawB=0 emitB=0
[MLX] memPoolCapture session=c2matrix/c2b4/main tokens=7932 bytes=226836480 layers=10a/30r es=main
[MLX] cancelPrefixUnproven session=c2matrix/c2b4/main ledgerTokens=0 processedTokens=0 captured=7932 rawEv=0
[MLX] poisonedSessionEvict session=c2matrix/c2b4/main history=0 aliases=1 keys=4/main
[LC] RELEASED r=0c5efe s=c2b4 reason=detached_by_client path=RUNNING→CANCELLING→DRAINING→RELEASING→RELEASED
[CHAT_TURN_TERMINAL] session=c2b4 state=detached committed=0
```

### Case E — 就绪/复用 + 预填中途取消（3 次链）

| Run | session | reused（取消轮） | rawEv | 判定 | 同 key 重试 |
|---|---|---|---|---|---|
| E1 | c2e1 T2 | **true**（cancelCommitSkip history=2） | 0 | capture refused → **keepResident**（无逐出行） | T3 **reuse=true** → mode=cold cacheEff=0.00 全量重建 25.7s → **complete** |
| E2 | c2e2 T2 | true（history=2） | 0 | keepResident | T3 reuse=true → cacheEff=0.00 重建 21.1s → complete |
| E3 | c2e3 T2 | true（history=2） | 0 | keepResident | T3 reuse=true → cacheEff=0.00 重建 22.9s → complete |

### Case G — 取消/失败后的正常完成恢复腿（5 次）

B1/B5 与 E1/E2/E3 的重试腿即 G：全部 stop=complete。复用被中断但保留的分片时官方层一律 `mode=cold cacheEff=0.00`（账本 0 行 vs 物理行 → 官方拒延长、全量重渲——09-17 文档「reusedSession=true × 官方 rebuild」层间错位的新证据形态）。

### Case H — 失效/逐出 + 同 key 请求（3 次，两个逐出源）

| Run | 逐出源 | 同 key 结果 |
|---|---|---|
| H1 | c2b4 poisonedSessionEvict | reuse=false，新建 exec=614501，池恢复 7932，complete |
| H2 | c2b5 poisonedSessionEvict | reuse=false，新建 exec=0a13d8，complete |
| H3 | **[MEM] session LRU evicted**（limit=8 触顶） | reuse=false，新建 exec=ae690f，mode=cold，complete |

**空闲挂起臂未触发**：实验窗口内 App 摘要轮持续重置引擎空闲钟（相邻轮间隔 <240s），`suspend_done` 未出现；LRU 逐出与取消逐出两源已覆盖 H 格。挂起清池边在实验前自然观察过一次（07:00:58 `suspend_done released_sessions=1`），操作性存在。

### Case C / F — 生成失败路径：本 build 不可达，未执行

- 协议层校验在 session 注册之前拒绝（BUDGET reject、参数 400），不存在「已注册后确定性生成失败」的产品路径触发器；
- 运行时停止（markCancelledByRuntime）会取消全部在途轮并清空观察对象，超出受控矩阵范围；
- 按 §2「不得静默重定义」，C/F 记为 **N/A-this-build**，不冒充通过。

## 3. 与验收/证伪条件对照（§6/§7）

| 验收项（§6） | 结果 |
|---|---|
| 未达 readiness 的新建 session 取消后绝不被同 key 复用 | **部分成立**：rawEv=0 取消 → 逐出，绝无复用（2/2）；rawEv=1 取消 → 分片被保留且**会被选中**（2/2），但选中后官方层强制全量冷重建，无一次产出未经验证的输出（0 挂死）。选择谓词层面「sessions[key] 存在即候选」仍成立；安全性由官方账本↔物理对账兜底 |
| 成功 session 可不读 KV 内部即判可复用 | 成立（D 3/3：stop=complete+提交 → reuse=true cacheEff 0.51） |
| 复用 session 的取消可由生命周期事件分类，cancelled≠invalid | **成立**（E 3/3：keepResident + reuse=true + 官方重建 + complete） |
| 同 key 选择可表达为 readiness 谓词而非 sessions[key] 存在 | **以分布式谓词形态成立**：SimiGo 侧 `CancelEviction`（rawEv/复用/引擎自证前缀 → 逐出/保留）+ 官方侧账本↔物理对账（延长 vs 重建）。无单一 SimiGo 自有状态机（见 §4 解释） |
| 不需要第二套 token ledger / Physical KV authority | 成立：#136 只消费引擎自证（`interruptedPrefixBoundary()` 逐层 offset 核验），账实不符即拒收（B4 44.5s 验证后拒收为直接证据）；V5.0 所有权边界全程未破 |
| 与官方 ChatSession 语义兼容 | 成立（重建/逐出/池恢复全部走官方与既有 A-2 门禁路径） |

§7 证伪条件五项**均未触发**。09-17 毒挂死模式（复用被取消新建 session → 零输出挂死）在 9 条取消/重试链上 **0 复现**。

## 4. 解释（与观察分离）

1. **H1 的支持形态比预注册设想更窄也更具体**：build 60 没有单一 SimiGo 自有 readiness 状态机，但 `CancelEviction` + #136 捕获 + 官方账实对账合起来构成一个**分布式最小 readiness 谓词**——这正是预注册 §10 预期的「最小生命周期/就绪接缝」。证据支持 H1 的弱形式（readiness 是 Logical/Execution 生命周期语义、可在不拥有第二套 KV 权威的前提下控制复用资格），不支持强形式（SimiGo 单侧显式状态机必要）：单侧谓词会把 rawEv=1 的保留分片误判为可延长，而实际安全性来自官方层拒绝延长。
2. **「取消落点」必须区分「信号点」与「落地点」**：kill（客户端断连）在预填中发出 ≠ 取消在预填中落地；落点由 chunk 边界决定（B1/B5 落在预填尾/后，B2/B4 落在中途）。rawEv 是否为 0 完全由落点决定，两分支行为系统分化（逐出+池捕获 vs 静默保留+冷重建）。预注册 §4「记录确切中断点而非归并所有取消」的要求由此在 build 60 具体化为两个变量。
3. **rawEv==0 仍是逐出的必要非充分条件**：B2（capture 成功）与 B4（capture 拒收）同为 rawEv=0、同被逐出（毒分片不留存），但 B2 的引擎自证前缀进了池、重试只付差价（5.2s vs 14s+），B4 无前缀可恢复——**逐出的语义从 v1.4 的「纯丢弃」演进为「分片必逐、可证前缀可留」**。
4. **异常观察（不作根因结论）**：B4 的 #136 验证耗时 44.5s（B2 同路径 2.6s），期间引擎 tps 跌至 0.6、contend 客户端超时脱离（让位已在其准入时触发，链路不受影响）；窗口内 swap 4.1→5.7GB、LRU 多次触发。验证成本方差与内存压力的关系单次样本不足，留观。

## 5. 偏离预注册协议清单

1. 中断向量由「客户端超时取消」改为「断连 detach + contended orphan yield」（ADR 10-30 后 build 60 唯一可达的预填中途硬取消）；每轮分别记录信号点与落点。
2. C/F 格 N/A-this-build（§2 末）。
3. 同 key 按 build 60 语义操作化（mapKey 三条件）；显式 session_id 隔离于 `c2matrix/` agent 域，与 App 摘要轮（default 域）互不可见（`differentAgent` 候选行为证）。
4. 超出原 8 格的追加观察（明确标注，非新格）：Route B 跨 key 池命中 4 例、#136 捕获成功/拒收两态、LRU 逐出边、keepResident 静默路径。filler 主体跨 marker 相同导致池命中是内容寻址的设计行为（mapKey 仍逐格唯一）。
5. 重复数：A×9、D×3、B×4 有效链（+1 kill 失误轮如实转记 A）、E×3、H×3（两逐出源）、G×5 腿；全部 ≥3（除 B 的 kill 失误已补足）。空闲挂起臂未触发如上。
6. n=1 与时延污染：单机单 build 单模型单日；swap 4.1–5.7GB、tps 0.6–37 波动，时延读数不作稳态声明（与 ESIS 臂豁免纪律同口径）。

## 6. 结论

**H1：supported（弱形式）**——Session Readiness 可由不拥有第二套 KV 权威的最小生命周期谓词控制；在 build 60 中该谓词以「CancelEviction + 引擎自证前缀捕获 + 官方账实对账」的分布式形态存在并被 9 条受控链验证。**强形式（SimiGo 单侧显式状态机的必要性）未被证明**，且现行分布式形态在全部受控路径上无毒性复现——按预注册 §10 纪律，**不建议**在无新事故证据的情况下把该谓词升格为单侧状态机。

研究问题 Q_SESSION_READINESS 的 C2 通道至此关闭（C3 生产 trace 长时回归仍在验收条件清单上，本记录不覆盖）。

## 7. 工件索引

- 驱动：`docs/experiments/C2_SESSION_READINESS_MATRIX_RESULTS_20261113_evidence/c2_driver_20261113.py`
  （原件在 `~/.zcode/workspace/draft-a66c589d-1284-42fa-97c6-94727fefa3ec/c2_driver.py`，入库的是同一份副本，仅改名以带日期）
- 每轮响应/日志：同目录 `c2_artifacts/`（a1-*, b1-*…h1-*, contend-*, census-*）
- 原始 trace：`~/.simigo/logs/native_mlx_trace.log`（窗口 07:16–07:50；文中证据行均出自该文件，未转引）
- 关联：`C2_SESSION_READINESS_MATRIX_20260922.md`（预注册）、`Q_SESSION_READINESS_20260922.md`、`lessons/cancel-mid-prefill-poisoned-session-2026-09-17.md`、`INVARIANT_SESSION_READINESS_BEFORE_REUSE.md`
