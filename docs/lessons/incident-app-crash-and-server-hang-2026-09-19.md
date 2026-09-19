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
