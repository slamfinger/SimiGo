# V1.5 Post-Freeze Code Audit — P0 体检执行记录（2026-09-19）

**性质**：不改行为的代码体检（外审清单 P0 三项本轮执行完毕；
范围 `main@1fa8938`，聚焦 NativeMLX/RuntimeTuning/Protocol 五条链）

## P0-1：Execution 状态判断重复审查 — ✅ 健康

- **决策单点**：extend/restore/rebuild 决策全部收敛在
  `NativeMLX.generate` 单处（`rollforwardRisk` → `conditionalRestoreGate`
  → `rollforwardCompatible` → kvFingerprint 守卫 → sessionReplaced
  身份守卫）；决策逻辑均为 static 纯函数 + 单测覆盖
- **Protocol 层零复判**：HTTPServer/Chat/Completions/Responses grep
  证实无 reuse/restore/rollforward 判断（外审"同一事实多处重判"风险
  不存在）
- **登记（非缺陷）**：①rollforward 后 trace 重算 estAscii/estCJK 用
  restored ledger——语义正确（记录本轮真实 fragment 规模，与门判定
  用的 live ledger 口径不同），非重复判断；②两个 chars→tokens 估算器
  并存（gate=compactJSON 全字符÷4；阶梯选档=content-only 字节÷4），
  输入与用途不同，V1.6 ExecutionPolicy 收敛时再统一命名

## P0-2：checkpoint 生命周期/失败路径 — ✅ 闭环

| 路径 | 行为 | 兜底 |
|---|---|---|
| save 失败 | `checkpointFailed` log，生成继续 | 下轮 compat 检查 → `checkpointStale` → 回退 extend |
| save 中间态 | cache 官方 API 写（非 atomic）+ meta `.atomic` | kvFingerprint + rollforwardCompatible 双守卫 |
| load 失败 | `rollforwardFailed` log，回退活会话 | recoverable，不影响本轮 |
| 恢复后池被换 | `sessionReplaced` 守卫放弃恢复态 | 防 detached session 收尾回写落空 |
| 文件累积 | 固定名覆盖写 | 无孤儿增长问题 |

## P0-3：identity 边界 — ✅ 各司其职

- `storageKey`（sessions 池寻址）/ `traceKey`（日志短串）/
  `kvFingerprint`（KV 配置指纹）/ `ManagedSession` 对象身份（原子替换
  守卫）——职责不互相替代，sessionID ≠ kvFingerprint 已成立
- **预留位登记**：独立 ExecutionID/ParentID 尚不存在——V1.6 Execution
  抽象的第一块地基，本轮不建

## P1 遗留项状态

| 项 | 状态 |
|---|---|
| harness race / session binding | ✅ 已修（`4c534a1`，外审二轮） |
| flag 收敛 | 登记：`rollforwardEnabled`（旧 rf 无条件路径）与
  `conditionalRestoreEnabled` 并存，V1.5 冻结期不动，V1.6 去 flag 化时
  合并为 ExecutionPolicy |

## P1 三专项审查（2026-09-19 续轮执行）

### 错误传播链 — ✅ 一处真实问题已修

- Protocol 层分类完备：`CancellationError` → 取消契约（SSE error chunk
  + [DONE]），其余 → `model_execution_error` + HTTP/SSE 终态；
  resume 失败重抛 `loadFailed`
- NativeMLX 内 recoverable 路径（checkpointFailed / rollforwardFailed /
  rollforwardSkip 家族）全部有 log + 回退语义
- **已修**：`suspendIfIdle()` catch 静默 `return false`——suspend 失败
  在 trace 上不可见（"空闲未挂起"无解释）；补
  `[LIFECYCLE] suspend_failed` 日志（唯一改动，零行为变化）

### 并发边界静态审查 — ✅ 单执行假设结构性受保护

- `SessionGenerationGate.withExclusive(key)` 按 executionKey 串行化——
  官方 ChatSession 非线程安全的假设被 gate 结构性封口（P0-3 单并发
  DONE 的延续）
- 共享状态三类：`state` 全局池（Mutex）、`gateHolder`（Mutex）、
  checkpoint performSave 在持 gate 期间调用（防重入，注释在案）
- 登记：真正多 Execution 并发出现前，"哪些对象假定单 execution"清单
  = ManagedSession/ChatSession + historyJSON 尾部变异 + lastJSON；
  V1.6 Execution lineage 设计时必须逐个过 gate 语义

### Instruments 级内存审查 — ⏳ 需交互会话

- 静态部分：suspend 走 `Memory.clearCache()`、LRU 驱逐 + afterEvict
  footprint 采样、checkpoint 固定名覆盖——生命周期骨架在位
- 动态部分（retain cycle / 延迟释放 / 重复物化）需 Instruments 模板
  交互跑（63.6k≈1.53GB 规模），列入 V1.6 开工前专项

## P2 登记项

- 日志三类前缀体系（Runtime/Performance/Diagnostic）——建议采纳，
  随 V1.6 telemetry 正式化一并做
- dead code：本轮未发现（bench `trace_tail_lines` 仍被 preflight 使用）

## 明确不做（外审暂缓项）

KV Tree / COW / BranchManager / 大规模 Execution 重构 / 新 restore
heuristic——均不启动。
