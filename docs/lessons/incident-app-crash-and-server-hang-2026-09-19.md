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
