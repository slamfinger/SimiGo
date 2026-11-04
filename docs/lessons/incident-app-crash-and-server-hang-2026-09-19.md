# 事件记录：App 空闲崩溃 + 服务全局挂起（2026-09-19 凌晨）

**二进制**：两起事件均在 v1.5/v1.6-era 构建（7ccd136 基线，/Applications 安装版）——
**S1–S5 新代码不在其内，V1.6 五分片免责**；两起均为 V1.6.1 候选生产缺陷。

## 事件 A：空闲 SIGABRT 崩溃（03:39:26）

- 现场：App 空闲约 20 分钟（首份矩阵冒烟提交后），无请求在途
- 崩溃签名：EXC_CRASH / SIGABRT，主线程，`_objc_fatal → lookUpImpOrForward`
  （ObjC 运行时 fatal，疑似向已释放实例发消息）
- 崩溃历史：同签名家族 .ips 在 Sep 18 17:05 / 19:48 / 23:28 与 Sep 13 03:14
  均有出现——**反复发生的既有问题**，非本晚首发
- 证据：`~/Library/Logs/DiagnosticReports/SimiGo-2026-09-19-033926.ips`
  （已拷贝至 V17_RUNTIME_MATRIX/evidence/）

## 事件 B：服务全局挂起（04:03:03 后）

- 现场：calibrated harness 依次完成 r1（cold 9.4k）/ r2（rebuild ~18k）后，
  warm-setup 请求被 accept（TCP ESTABLISHED）但**永远无响应**；此后
  /v1/models 等全部端点同样挂起（连接 accept 但零响应）
- 关键观测：trace 中**无该请求的 `[EXEC] begin`**——请求从未进入 generate()；
  卡点在 HTTPServer 请求处理层（generate 之前）
- sample（5s，17 线程）：主线程正常 AppKit 事件循环；MLX C++ 线程池全部
  空闲等待；**未捕获任何 SimiGo Swift 处理线程**——处理该连接的 Swift
  任务要么不存在要么 sample 未覆盖 Swift 并发线程池
- 证据：`evidence/simigo_hang_sample_0418.txt`（full sample）
- 恢复：SIGTERM→SIGKILL 重启后服务需手动开启（正常行为）

## 初步判读（待复现验证）

- 事件 A/B 是否同根未知（A 是 ObjC 层 abort，B 是 Swift 层处理停滞）
- 事件 B 的"accept 后零处理"指向 HTTPServer 连接处理线程死亡或
  全局串行队列被上一请求占死——**V1.6.1 最优先候选**：给 HTTPServer
  加存活探针 + 卡死请求超时 + 连接处理线程状态可观测
- 复现路径候选：矩阵 harness 的长会话反复 rebuild 序列（r1 cold →
  r2 rebuild → warm-setup 挂）

## 关联

- V1.7-0 harness 冒烟：`docs/experiments/V17_RUNTIME_MATRIX/`
- 事件期间 harness/样本均已保全，无数据丢失

## 复现确认（2026-09-19 06:07，2/2 同签名）

事件 B 在校准 harness 复跑中**再次复现**——签名完全一致：

```text
r1（cold，9.4k tok）→ r2（rebuild，cacheEff=0）→ 第 3 个请求
    ↓
TCP ESTABLISHED 但零响应，trace 全静默，无 [EXEC] begin
    ↓
服务全局挂起（/v1/models 同挂）
```

- 第 1 次：04:03 r2 后 warm-setup 挂（sample_0418 已保全）
- 第 2 次：05:55 r2 后 warm-setup 挂（sample_2nd 已保全）
- 两次均在 S1–S5 代码在场的二进制上——**V1.6.1 确认级 P1**：
  "rebuild 轮完成后的下一请求使 HTTPServer 全局冻结"
- 复现配方已固化（runtime_matrix.py 10K 档即可稳定触发），后续修复
  PR 以此为回归验收

## 诊断突破（2026-09-19 11:02，sample #3 / 第三次复现）

第 3 次复现（同配方）+ sample #3 拿到**卡死线程的完整签名**：

```text
卡死线程（4276/4276 满采样）：
_dispatch_call_block_and_release
  → ___os_state_request_for_self_block_invoke (libsystem_trace)
  → _dispatch_sync_f_slow
  → __DISPATCH_WAIT_FOR_QUEUE__
  → _dispatch_thread_main_event_wait_slow
  → __ulock_wait
```

同时**主线程健康**：正常 AppKit 事件循环（mach_msg 待事件，非阻塞）。

**判读**：卡死点在系统级 os_state/logd 子系统——处理请求的线程进入
os_state "for self" 请求并 `dispatch_sync` 等待主队列/主事件，而主
runloop 处于不投递该事件的模式/状态 → 同步等待永挂。该路径与 SimiGo
业务代码的直接关系待查（疑点：请求处理线程上的某个 os_log/trace 调用
触发 logd 状态捕获），但**机制本身是系统框架交互**，非业务逻辑死锁。

**V1.6.1 缓解方向不受影响且更加确立**：请求级 watchdog 超时 + 存活
探针 + 卡死请求主动 abort——即使系统级同步挂起，服务也能自愈而非
全局冻结。

## 根因确认与第一修复（2026-09-19 12:xx）

**根因确认**：`HTTPServer.queue`（com.simigo.httpserver.connections）
是全部连接共享的**串行** DispatchQueue——连接 I/O 回调与其上的卡死
（os_state dispatch_sync 等主事件）阻塞整条队列 → 所有连接 I/O 与
监听回调冻结 → 服务全局无响应。与三次复现签名完全吻合。

**修复**：accept 时改为**每连接独立串行队列**
（`com.simigo.httpserver.conn.<key>`）——连接内回调顺序保留（串行），
连接间隔离（单连接卡死不再扩散）。listener 回调仍走原共享队列
（轻量低频）。残余风险：卡死连接自身仍挂（客户端超时兜底），
请求级 watchdog 留 V1.6.1 后续项。

**回归验收**：修复后二进制重跑 runtime_matrix 10K 档——若不再复现
全局挂起即为通过（卡死单连接场景由客户端超时兜底）。

## 回归结果：队列隔离修复未通过（2026-09-19 11:24-11:31）

修复后二进制（每连接独立队列）重跑 10K 档：build r1 cold ✅ → r2
rebuild 后 **warm-setup 请求再次冻结**，探针 12 连 http=000（11:25:04
→11:29:40），/v1/models 同挂——**全局冻结与 I/O 队列无关**。

## 根因锁定（2026-09-19 11:4x，frozen sample + 三 sample 交叉验证）

卡死线程位于 **`com.apple.libtrace.state.block-list`**（os_log 统一日志
的状态捕获串行队列）：

```text
某请求路径上的 os_log 调用
  → libtrace 状态捕获 ___os_state_request_for_self
  → dispatch_sync 等待主事件（主 runloop 不投递该事件）
  → __ulock_wait 永挂
```

该 **block-list 是 libtrace 全局串行队列**——其后所有经过 os_log 的
请求路径（含 NWFoundation 内部日志）全部排队冻死 → 全局无响应。
**三份 sample（0418/2nd/3rd）100% 一致**；队列隔离无效的原因由此
解释（冻结不在我们的 I/O 队列层）。

## 缓解实验（进行中）

`launchctl setenv OS_ACTIVITY_MODE=disable` + 重启 App（PID 54415）：
抑制 os_log → 状态捕获不发生 → 预期不再冻结。等待用户开启服务后
重跑 10K 档验证。若通过：矩阵实验期间以该环境变量运行；正式修复
需定位触发 os_log 的具体调用点（系统框架内部亦可触发，非我方代码
直接调用）。

## 第六轮（2026-09-19 11:45）：OS_ACTIVITY_MODE=disable 未阻断 + 关键新事实

- **4/4 复现**：disable 模式下仍在同一位置冻结（r1 cold 完成 → r2 请求
  挂起），os_log 抑制假设排除
- 本轮**全程零 UI 自动化**——AX 干扰假设亦排除
- CPU 0%（阻塞非自旋）；/v1/models 与矩阵请求同挂 → 全局阻塞点存在
- **frozen sample 关键事实：16 线程中不存在卡死请求的 Swift 处理
  线程**——第 3 请求的 handler 任务从未启动（或已消失）；sample 中
  wedge 的 libtrace 状态线程疑为 sample 命令自身的受害者
- **未解之谜收窄**：第 3 请求在 HTTPServer 层（generate 之前）消失，
  且新连接的 /v1/models 也无人处理——accept/派发层停摆

## 下一步诊断（登记）

1. 冻结发生瞬间（r2 完成后 ~5s 内）立即 sample——抢在污染前捕获
2. HTTPServer.readRequest/route 入口加 trace 行（第 3 请求走到哪一步）
3. 排查 r2 rebuild 路径是否遗留未释放的锁/任务
  （LifecycleGates acquire/release 配平、ConnectionContext 生命周期）

## 决定性证据（2026-09-19 12:08 冻结现场，带埋点二进制）

新埋点（[HTTP] recv / handler enter）下的冻结现场：

```text
12:08:20.630  [EXEC] end status=completed          ← r2（rebuild 轮）正常完成
12:08:20.663  [HTTP] recv POST /v1/chat/completions ← REBUILD 轮已进入 route()
              （此后全进程零 trace 输出；handler enter 从未出现；
                accept/派发层死亡——新连接 TCP 可建但永不处理）
```

**消失点钉死**：route() 入口之后、handleNonStreaming 入口之前
（即 route switch 内的 body decode / 分派段）。

**冻结形态**：该请求消失的同时，accept/派发层整体停摆（新连接
TCP ESTABLISHED 但永不产生 recv）→ 非单请求挂起，是**处理管线级死亡**。
sample 显示唯一异常线程 = libtrace state block-list 队列上的
os_state for-self dispatch_sync 等主事件永挂——该队列属系统统一日志，
其死亡会冻结一切经过 os_log 的路径（含 NW/Foundation 内部日志）。

**一致性**：4/4 复现全部死在同一点（r2 rebuild 完成后的下一请求），
与队列隔离修复、OS_ACTIVITY_MODE、UI 自动化均无关。

## 二次隔离 + watchdog（2026-09-19 12:41）

- `newConnectionHandler` 不再在 listener 回调队列内直接执行 `accept()`；
  新连接先转入并发 `acceptQueue`。这样 `NWConnection.start` / 系统
  状态捕获路径被挂起时，listener 状态回调仍可继续收到事件。
- `HTTPServer.start()` 建立连接 watchdog；`stop()` 显式取消，避免重启后
  旧 watchdog 堆积。已 recv 但未进入 generation 的连接 60s 终止；
  已进入 generation 且超长无终态的连接 30min 兜底终止。
- 回归：`xcodebuild test` 73 项通过、5 项模型门控跳过。生产验收仍需
  用 `runtime_matrix --depths 10000` 复跑至 r2 后第 3 请求。

## Release 回归：Task watchdog 未触发（2026-09-19 12:49）

- Release 构建 + 10K 档复跑：r1 cold ✅、r2 rebuild ✅、第 3 请求
  `chat-nonstream enter` 后再次全局冻结。
- 冻结 90s+ 后无 watchdog trace；`/health` 超时。sample 显示主线程与
  MLX 线程均空闲，但没有任何 Swift 并发/NW 处理线程在工作。
- 结论：挂起再次发生在 Swift 并发任务层；**watchdog 本身不能再用
  `Task.sleep`**，否则会被同一故障面吞掉。
- 修复改为专用 `DispatchSourceTimer`（独立 queue，30s 周期），不依赖
  Swift cooperative pool。
- 证据：`evidence/simigo_hang_sample_release_taskwatchdog.txt`、
  `evidence/release_taskwatchdog_regression.log`。

## Dispatch watchdog 首轮结果（2026-09-19 13:01）

- Release 回归再次冻结在第 3 请求 `chat-nonstream enter` 后。
- **独立 queue watchdog 正常触发**：13:01:27 记录
  `watchdog terminate conn pre-generate stale`，冻结请求客户端收到
  connection closed。
- 但 `/health` 仍超时——证明冻结面不止单个请求，`NWListener` 自身已
  停止派发；杀掉 stale connection 不足以恢复 accept。
- 第三轮修复：watchdog 终止 stale connection 后立即
  `cancel` 旧 `NWListener` 并重建 listener。
- 回归证据：`evidence/release_dispatch_watchdog_regression.log`、
  `evidence/simigo_sample_after_dispatch_watchdog.txt`。

## Listener 立即重建结果（2026-09-19 13:10）

- 第三轮 Release 回归仍触发同一冻结签名；watchdog 正常终止 stale
  connection。
- listener 立即重建日志出现，但随后 `/health` 变为 connection refused；
  判读为旧 `NWListener` 异步释放端口期间，新 listener 未能稳定接管。
- 第四轮修复：listener 重建延后 3 秒，先等待端口释放。
- 已将最新 Release 构建同步部署到 `/Applications/SimiGo.app`；生产回归
  待第四轮复跑。

## 根因精确定位（2026-09-19 13:32）

细粒度埋点显示第 3 请求（warm setup）已经完成 body decode、handler
进入、messages 解析，并成功进入 generation gate：

```text
chat parse messages-ok count=8
（此后无 parse done / EXEC begin）
```

卡点收窄到 `parseChatParams` 的 tools 编码段。该请求是首个
`"tools": null` 请求；旧代码执行：

```swift
try? JSONSerialization.data(withJSONObject: json["tools"]!)
```

`NSNull` 不是 JSON write 的合法 top-level type。`JSONSerialization`
抛出的是 **ObjC exception**，Swift 的 `try?` 不能捕获，进入 ObjC
异常/系统状态路径后表现为全局冻结。最小复现脚本确认 `NSNull` 传入
`JSONSerialization.data` 直接 `NSInvalidArgumentException`。

**根因修复**：只有 `json["tools"]` 成功 cast 为非空
`[[String: Any]]` 时才编码；`null` 直接视为无 tools。

证据：`evidence/release_stage_trace_regression.log`、
`evidence/release_stage_trace_frozen_trace_tail.txt`。

## 最终回归通过（2026-09-19 13:40）

- Release 构建 + `/Applications/SimiGo.app` 生产路径复跑 10K 档完整矩阵。
- 关键的 `tools=null` warm-setup 请求不再冻结，正常完成并进入后续测量。
- 全流程通过：`build r1/r2 → warm setup → warm → restore → rebuild →
  cold`，结束后 `/health` 仍为 200。
- 指标：warm cacheEff=1.00 / promptTime=0.1s；restore=27.4s；
  rebuild=23.2s；cold=24.7s；footprint=21.9G。
- 结果：`results_release_rootfix_regression.json`；
  日志：`evidence/release_rootfix_regression.log`。

## 最小补丁确认（2026-09-19 13:54）

- 撤除临时 accept 队列隔离、watchdog、listener 重建；仅保留
  `tools=null` 的类型守卫与回归测试。
- Release 构建 + `/Applications/SimiGo.app` 复跑 10K 档完整矩阵通过。
- `tools=null` warm-setup 正常完成；warm cacheEff=1.00 / promptTime=0.2s；
  restore=24.6s；rebuild=24.4s；cold=25.4s；footprint=22.0G。
- 回归后 `/health` 保持 200。
- 结果：`results_release_minimal_rootfix_regression.json`；
  日志：`evidence/release_minimal_rootfix_regression.log`。
