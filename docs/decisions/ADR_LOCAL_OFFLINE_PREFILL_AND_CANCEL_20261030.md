# ADR：本地离线 Runtime 的 prefill 时间与取消语义（2026-10-30）

**状态：已接受（owner 裁定）。实现已在 build 31 工作树落地；编译与隔离定向回归
已执行（43 tests / 1 skipped，唯一红为心跳时序、按环境停顿记录且同构建复跑
9/9 绿，见证据）。安装版新二进制（exe `acec7decc0…`）已由 owner 手动启动服务
并在 2026-10-30 04:57–04:59 真机复验：断连 detach 与孤儿让位成立。
让位后的前缀保留/复用**未成立**（`memPoolCaptureRefused`），手动取消、
`maxDetachedRequests` 上限边界与其余 wire 尚未在真机覆盖，见证据。**

## 背景

SimiGo 的主执行基质是本地离线大模型（MLX / Apple Silicon）。冷 prefill 的耗时由
本地内存带宽与搬运决定，不是可调参数。真机读数：

- 39K token 冷 prefill 约 50–60 s（2026-10-29 02:40:39 的 37,211 token / 58.6 s
  是最后一次成功；此后 39,433 / 39,805 全部在 60 s 被客户端取消）；
- 真实客户端（Qoder / Codex 类）对 HTTP 请求有 60 s 硬超时，超时即断连；
- 断连后引擎收到 `peerClosed` → `CANCEL` → `cancelCommitSkip` →
  `poisonedSessionEvict`，已算完的前缀被丢弃，下一次重试重新冷算。

W4 预算门（`[BUDGET] verdict=… promptTokens=… prefillBudget=45000`，超出即 503）
在这条读数上只能把「慢」转换成「失败」，并且引入了样本污染（`skip_record
reason=model_warmup`）与拒绝缓存冻结旧判定两个新的正确性问题。

## 问题

1. 是否应该在产品准入路径上用 prefill 时间预算拒绝请求？
2. 客户端断连是否应当等价于用户取消？

## 候选方案

- **A. 时间门控 / 快失败**（W4 现状）：估算 prefill 耗时，超出预算立即 503。
- **B. 接受慢 + 加速复用 + 断连不取消**（本裁定）：不按时间拒绝；把成本花在
  第一次冷算上，之后靠前缀复用摊销；客户端断连不终止本地执行。
- **C. 提高并发掩盖慢**：被排除。单引擎的可变模型会话与 KV Cache 不能任意并行，
  并发必须靠隔离/队列/所有权/有界调度实现（见路线 04）。

## 最终决定

1. **不做 prefill 时间门控**：产品准入路径不再因预估 prefill 时间拒绝请求。
   `estMs` / `promptTokens` 保留为观测信号与看门狗尺寸依据，不再是拒绝条件。
2. **取消语义分层**：前端客户端断连（`peerClosed`）只做 detach，不驱动引擎取消、
   不触发 `poisonedSessionEvict`；引擎继续完成 prefill 并保留前缀。手动取消
   （菜单栏停止、UI stop、显式 cancel 端点）仍是硬取消并驱逐。
3. **忽略断连必须配有界执行**：单引擎队列需交互轮优先、孤儿轮数量上限；
   无人消费的轮在 prefill 完成后停止 decode、保留前缀，或按驻留账本的压力淘汰。
   否则会复现 2026-10-29 02:47–02:50 的读数：新会话排在旧会话 39K 冷 prefill
   之后约 44 s。**补充裁定（owner 2026-10-30 授权）**：当另一个请求已经进入
   引擎窗口（排队或正在生成）时，孤儿不再把无人消费的 decode 跑完，而是在下一个
   token 边界让位——走标准取消接线，交给 #134/#136 的前缀保留判据；无人等待时
   仍按本裁定跑完。让位不是客户端取消：不调用 `cancelGenerationHandler`、
   trace 记为 `[DETACH] stop=1 r=… reason=generation_contended`。
4. **W4 按原规格记为「路线被裁定撤销」，不记为「已修复」**。门控实现、测试与
   `[BUDGET]` 读数作为历史证据保留，不静默删除；不得用「关闭门控」或「清空样本」
   充当修复结论。

## 理由

- 60 s 硬超时是远端 API 的产物，不是本地硬件事实；用它决定本地执行生死，等于让
  远端客户端的策略支配本地 Runtime。
- 只有保留已完成的 prefill，重试才可能从冷算变成命中（#136 的 8,072-token 内存
  前缀、#134 的取消后前缀保留都是同一方向）。
- 门控的代价是确定的失败；接受的代价是可控的排队。

## 代价

- 孤儿轮会占用单引擎，首字延迟不可控；必须有界（决定 3）。
- 「忽略断连」不能推导为「无限保留」：驻留压力下仍需淘汰策略与可观测指标。

## 影响范围

- HTTP 层断连处理与生命周期状态机（`CANCEL` / `cancelled_by_client` 判定）。
- IS 结算：断连后跑完的轮**记 `recorded`、不自动提交**（owner 2026-10-30
  确认）。协议层在生成后、结算/提交前的 `guard !context.closed` 保持
  fail-closed，因此 detached 轮不可能被提升为 `committed`。
- W4 预算门的准入拒绝路径（下线或降级为观测），以及 #138 的样本污染问题——
  后者的修复不应重新引入时间门控。

## 落地记录（build 31 工作树，2026-10-30）

1. **断连 detach**：`ConnectionContext` 新增 `_detachedByClient`；客户端消失
   路径（`peerClosed`、连接 failed/cancelled、心跳与发送失败）统一走
   `terminateForClientGone`，不取消 `requestTask`、不驱动引擎取消。手动取消、
   Runtime `stop()` 仍走 `terminate(cancelGeneration: true)` 硬取消。
   取消原因在 trace 中记为 `detached_by_client`。
2. **孤儿有界**：`maxDetachedRequests = 1`，名额在 `stateLock` 内原子领取，
   任务结束后归还；超出上限的断连按旧语义取消。trace 行：
   `[DETACH] r=… slots=1`。该上限是并发度 1 单引擎下的过渡值，路线 04 落地
   后随调度器重新评估。
3. **W4 拒绝出口下线**：`RequestBudgetController.admissionEnforcementEnabled
   = false`。判定、`estMs`、样本与拒绝缓存仍照常计算；被拒绝的判定改为
   `[BUDGET] … gate=withdrawn … action=admit` 并放行，`[BUDGET]` 行追加
   `enforced=0`。`sendBudgetReject` 保留但不可达。
4. **测试**：`RequestBudgetGateHTTPTests` 由「断言 503」改为「断言判定仍被
   取得、请求照常准入」；`W4BudgetCalibrationE2ETests` 的 Phase B/C（拒绝相位）
   默认退役，仅 `W4_MEASURE_ENFORCEMENT=1` 时对旧二进制运行；Phase A 的
   8K/24K/40K 冷 prefill 读数继续有效。控制器数学测试未改。
5. **孤儿让位（决定 3 补充裁定）**：`ConnectionContext` 新增只读
   `generationStarted`（`_generationStarted && !_closed`）与一次性取走的
   `takeDetachedRequestTask()`（`closeAndTakeRequestTask` 在锁内保存
   `_detachedRequestTask`，取后置 nil，不会重复取消）。`HTTPServer` 新增
   `stopDetachedOrphanIfContended(_:)`：仅对 `detachedByClient` 的连接生效，
   判据 `otherGenerationInFlight()` 只读 server 本地 `connections`（detach 后
   本连接已移出，看到的即「别人」），命中则 `task.cancel()` 并以
   `[DETACH] stop=1 r=… reason=generation_contended` 记录；不调用
   `cancelGenerationHandler`，所以 `[CANCEL]`/客户端取消计数不受污染。取消
   后的前缀保留完全交给 #134/#136 的引擎路径（`cancelCommitSkip` →
   `captureInterruptedPrefix` → `CancelEviction.decide`），协议层的
   `guard !context.closed` 仍 fail-closed。六条 onChunk（Chat 683/1159、
   Responses 1340/1860、Completions 244/585）全部在回调首行接入探针；
   非流式 accumulators 同样接入，因此 `stream: false` 的孤儿也会让位。
   `stopDetachedOrphanIfContended` 与 `otherGenerationInFlight` 标为
   `nonisolated`（与 `sendImmediateCompletionsChunk` 同一模式），以匹配
   `@Sendable` onChunk 的调用语境。

## 证据

- **编译**：`xcodebuild build-for-testing … -enableCodeCoverage NO
  -derivedDataPath build/test`，`** TEST BUILD SUCCEEDED **`（2026-10-30，
  build 31 工作树）。
- **隔离定向回归（含让位）**：
  `build/test-isolation/20261029T204341Z-detach3/`
  （`targeted_detach3.log`、`Test-detach3.xcresult`、`snapshot_pre/post.json`、
  `noninterference_diff.json`）。4 套件 **43 tests / 1 skipped / 1 failure**：
  - `CancelPathStubHTTPTests`（6）：stream/non-stream 断连后 detach（引擎未
    观察取消、无 answer settlement/binding/advancement、客户端仍 `closed`）；
    plain 轮正常结算；服务端内部取消仍 `cancelled_internally`；新增
    `testDetachedOrphanYieldsEngineToQueuedRetry`（A6）通过——证据链为
    `[DETACH] slots=1` → 队列中的重试完成 `RETRY-ANSWER-6` →
    `[DETACH] stop=1 r=… reason=generation_contended` → 引擎观察到取消
    （`cancelObserved`）→ `generateCount == 2`（只有孤儿与重试两次）→
    `cancel.count == 0`（未走客户端取消接线）→ ES 侧仅 1 条答案结算且等于
    重试的 `answeredDemand`、1 条 advancement；孤儿会话无 chat state / 无
    `answeredDemand` / 无 `chat_execution_links`；`information_items` 无删除，
    anchors（roots/external_files）无增删。
  - `CancelChainInternalTests`（3）：`peerClosed` detach 不停生成、静默流
    心跳保活、心跳发送失败同样走 detach（`[DETACH] … slots=1`）。
  - `RequestBudgetControllerTests`（24）与 `RequestBudgetGateHTTPTests`
    （10，1 skipped 为退役的拒绝写入边界仪器）：判定数学未变；拒绝出口
    下线后六条 wire 一律准入。
- **唯一红灯如实记录**：`CancelChainInternalTests
  testHeartbeatKeepsSilentStreamAlive` 在 204341Z 窗口超时失败
  （"the silent window produced no heartbeat event"，8.874 s）。该窗口与已
  安装 App 卸载 21 GB 模型的时间重叠（`native_mlx_trace.log` 04:44:40.522
  `peak=21787MB swapUsed=2923MB`、`NativeMLX stopped`），按环境停顿记录；
  **不记为已修复，也不记为本次改动引入的回归**。同构建重跑窗口
  `build/test-isolation/20261029T204504Z-detach3b/`：
  `CancelChainInternalTests` 3/3 与 `CancelPathStubHTTPTests` 6/6 全绿，
  **9 tests / 0 failures**（`targeted_detach3b.log`、
  `Test-detach3b.xcresult`），心跳测试通过。
- **非干扰**：204341Z 窗口 `real_user_state_write_count = 1`，路径
  `~/.simigo/logs/native_mlx_trace.log`，归因为已安装 App（PID 36440，
  `/Applications/SimiGo.app/Contents/MacOS/SimiGo`）自身卸载模型写日志，
  不是隔离测试写入；`reference_changes = 0`。重跑窗口 204504Z
  `real_user_state_write_count = 0`、`reference_changes = 0`。
- **真机复验（安装版，2026-10-30 04:57–04:59）**：
  `build/a31/live-20261029T205722Z/`（README、两段 trace 窗口、完整日志快照
  sha256 `37eeda2f…`、只读库查询、客户端时间线）。安装位 PID 63514，
  exe sha256 `acec7decc0c67ccc081d463b3ac4af5e99da660fb08a7363876aeea96baa2a48`，
  2.2.1 / build 31，服务由 owner 从菜单栏启动。四个场景（均 `chat.completions`）：
  - **prefill 期断连 + 竞争**：`peerClosed r=247916` → `[DETACH] … slots=1`；
    客户端已走仍 `prefill 764/764`；B（`r=87cd8e`）到达排队后
    `[DETACH] stop=1 … reason=generation_contended` → `cancelCommitSkip` →
    A `RELEASED reason=detached_by_client`，B 完成并结算
    `3B385EB6-3712-4C6D-A3AA-9CEF8248009D`（VALID）。
  - **无竞争**：`r=6910dc` 断连后孤儿跑完 `stop=capped`（40/40 tokens），
    `RELEASED reason=detached_by_client`，无 `[DETACH] stop=1`。
  - **收到内容后断连**：`r=3bffa0` 客户端收到两个内容 chunk 后断开，
    孤儿跑完 `stop=complete`（46/64 tokens），同样 `detached_by_client`。
  - 四个场景全程 `[CANCEL]` 计数 **0**；库侧
    `chat_messages` 247/250/251 均为 `pending`，无 assistant 行、
    无答案 settlement、无 `chat_execution_links`，只有 B 的 248/249 `committed`。
  - **让位后前缀保留未成立**：A 让位路径
    `memPoolCaptureRefused session=faa7e1/main reason=committed rows (766)
    disagree with the token ledger (0)`；B 的读数
    `cacheTokens=766 cacheHitTokens=0 mode=rebuild ttft=7446ms reuse=true`。
    该根因归 #134/#136 继续核，本窗口不作 PASS。
  - **W4 观测（独立问题）**：A 让位与 B 均 `skip_record reason=model_warmup`；
    C 孤儿跑完后留下 1 条校准样本，使 D 的判定
    `gate=active samples=1 rate=299.4 estMs=5811`、`admit_within_budget`。
    detached 轮是否应进入 W4 校准样本不在本 ADR 裁定范围。
- **真机未覆盖**：手动取消（需 UI 操作）仍只有桩层证据；
  `maxDetachedRequests=1` 的第二个并发 detach 未触发；
  `responses` / `completions` wire 与真实 Codex 客户端断连未执行；
  让位前后的首字延迟对照未测（B 的 `ttft` 含排队与冷 prefill）。
- `docs/architecture/IS_EXTERNAL_TURN_CONTRACT_20261030.md` §10（并发 2 + 取消 +
  提交的真机读数）。
- `docs/knowledge/open-problems/README.md`（当前未关闭清单）。
- 历史真机窗口：`build/a30/evidence/live-20261030-0350/`（旧二进制，取消即终止）。

## 关联

- W4 设计：`research/lab/` 内的 W4 设计文档（含 owner Q1–Q3 与冷启动规则）。
- #134 取消前缀保留、#136 内存前缀续接、#90 受管入口会话身份。
- 路线 04（并发度 1/2/4）必须以本裁定的有界执行条款为前提。
