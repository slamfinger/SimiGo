# 归属重试监视器：启动与终止（2026-11-13）

状态：当前实现 · 对应 #187 / PR #190

`TurnDigestScheduler` 里的一个进程级轮询：每 30 秒看一眼 `space_assignment_retry`，
还有没放弃的欠账就重放一次。本文只讲它怎么起、每一跳做什么、怎么停；缺口口径见
[信息空间缺口账](IS_GAP_LEDGER_20261113.md)。

## 它不是 ES/IS 语义里的新组件

结算归 ES；IS 接收并保存（`put`，不判定完成）；`ESISDatabase` 是被调用、被读写的
存储实现，不会自己判断执行是否完成，也不推动 ES 继续。谁欠一次归属由 SimiGo
记账，什么时候重判由 SimiGo 的进程决定。

所以这个监视器按「SimiGo 运行时协助」审，不按「让 IS 自主运行」审。常驻轮询是
工程效率问题，不是 IS 生命周期设计问题。

## 启动

自动启动，但不是进程一起来就无条件跑。两条路都是「顺带」起来的：

| 路径 | 触发时机 | 位置 |
|---|---|---|
| 启动时重放 | 信息空间服务 `runtime.start` 成功；或模型服务启动成功 | `Service.swift:858` / `:943` → `replayPendingRoomAssignmentsAtLaunch()` |
| 摘要写入后重放 | 每轮摘要落库之后 | `write()` → `replayPendingAssignments(label: "摘要写入后")` |

两路都汇到 `replayPendingAssignments`，它第一件事是 `startRoomAssignmentRetryMonitor()`；
`RoomAssignmentRetryTimer.start` 在锁里 `guard source == nil`，**一个进程只起一次**，
重复调用是空操作。

推论：两个宿主服务都没启动成功、也从没写过摘要的进程，监视器不会起——这种进程里
也没有新欠账可等。

## 每一跳做什么

1. 新开一个 `ESISDatabase` 连接（`createIfNeeded: true`）；
2. `spaceAssignmentRetryStatus()`：待办行数、其中已放弃的行数、最近一条 `last_error`；
3. `pending > abandoned` 才继续；全部放弃了就什么都不做（行留在表里，设置页数得出来）；
4. `retryPendingSpaceAssignments()`：到点的判一次归属，成功删行；失败 `attempts+1`
   并按退避定下次时间；没到点计 `deferred`；
5. 关连接。

「到没到时间」只由 `next_attempt_at` 决定；监视器只负责叫醒，不参与判定。

## 终止

**产品路径不终止它。** 它挂在 `static let roomAssignmentRetryTimer` 上，生命周期等于
进程：进程退出即销毁。没有「停止服务」时的 cancel，也没有「队列空就停」。
`stopRoomAssignmentRetryMonitor()` 只给测试用（跑完立刻停，否则它会带着出厂节奏
接着打真实库）。

由此三件事要清楚：

- 队列空时，每 30 秒仍有一次计数查询（一个连接 + 两条 COUNT）。低频，但常驻。
- 停止/重启宿主服务不重置它；重启后的重放走的还是同一个已存在的定时器。
- 进程休眠后，`DispatchSourceTimer` 的触发会被合并或延后，不是「醒来补齐每一跳」。

## 验证到哪

- 已验证：`testDuePendingRowIsAssignedByMonitorAlone`（App 层）。间隔压到 0.2 秒，
  一条到期的待办在**不调用任何重放**的情况下被监视器自己判上、销账；CI 隔离运行里
  passed 0.385s。
- 未验证：长时间空闲下按 30 秒节奏持续唤醒；连接与日志的累积；服务停止后监视器
  仍在跑这件事的实际影响（代码上成立，未做运行观察）。

## 优化方向（未做）

按最早 `next_attempt_at` 排一次性定时器，替代固定 30 秒轮询；队列清空即停表。
代码更多、收益只是少些空转，目前按最简可行保留轮询。
