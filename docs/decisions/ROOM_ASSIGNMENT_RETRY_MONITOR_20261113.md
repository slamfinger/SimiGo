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
3. `pending > abandoned` 才继续；没有可再试的欠账就**停表**（行留在表里，设置页
   数得出来）；
4. `retryPendingSpaceAssignments()`：**一次最多处理一批**（默认 64 行，`maxRows`）。
   已放弃与未到点的行在 `LIMIT` 之前就排掉，不占窗口；到点的判一次归属，成功删行；
   失败 `attempts+1` 并按退避定下次时间。`deferred` / `abandoned` 用两条 COUNT 数全表，
   只是报数，不把整张队列读进内存；
5. 再看一次状态，`pending <= abandoned` 就停表；
6. 关连接。

「到没到时间」只由 `next_attempt_at` 决定；监视器只负责叫醒，不参与判定。

## 终止

**欠账清空就停表，但停之前要核对代数。** 一跳结束时再看一次队列：没有待办、或只剩
已放弃的行，就 `cancel` 掉定时器，不再每 30 秒空转。

核对这一个动作是为了堵一个真实的交错：心跳拿到「空队列」快照之后，写的一方可能刚好
入队并叫醒（`startRoomAssignmentRetryMonitor()` 会推进代数）。如果心跳照旧把表关掉，
那一行就要等到下一次摘要写入才动。所以停表只在「心跳开始之后没人再叫过醒」时生效；
心跳自己重放时也不再叫醒自己，否则它永远停不下来。

下一次有欠账时由三条路重新把它起来：

- 宿主服务启动成功（`Service.swift:858` / `:943`）；
- 新的一轮摘要写入；
- 设置页「重放」（重放完立刻起表，让没到点的行还能被叫醒）。

它是进程内的对象，进程退出自然带走；产品路径不额外调 `stop()`，停表只发生在
「没欠账」这一种情况。由此三件事要清楚：

- 有欠账在退避等待时，每 30 秒一次计数查询（一个连接 + 两条 COUNT），直到清空；
- 清空之后不再有空转；
- 进程休眠后 `DispatchSourceTimer` 的触发会被合并或延后，不是「醒来补齐每一跳」。

## 验证到哪

- 已验证：`testDuePendingRowIsAssignedByMonitorAlone`（App 层）。间隔压到 0.2 秒，
  一条到期的待办在**不调用任何重放**的情况下被监视器自己判上、销账；CI 隔离运行里
  通过。同一用例继续断言：销账之后监视器**自己停表**，不等人来关。
- 已验证：`testMonitorDoesNotStopWhenNewRetryArrivesAtIdleBoundary`（App 层）。用注入口
  在「空队列快照之后、停表之前」塞一条新欠账 + 一次叫醒，断言监视器没被关掉、那一行
  最终被自己判上。
- 未验证：真机 30 秒节奏下的多跳行为（含退避跨 30s / 60s / 2m 的连续跳）；长时间
  运行下连接与日志的累积。

## 优化方向（未做）

按最早 `next_attempt_at` 排一次性定时器，替代固定 30 秒轮询；队列清空即停表。
代码更多、收益只是少些空转，目前按最简可行保留轮询。
