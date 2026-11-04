# PERF-CONVERGENCE-1 — 2026-09-29 · Gate Reproducibility Record

> 性能收敛阶段全程矩阵归档（v2.0.0-beta.4 的验证证据链）。
> 阶段方法：审查 → 独立复核 → 窄 scope 实施 → 差分审计 → 实测淘汰伪优化 →
> Full Gate → push。基线 `5fa3d38`，已推送（b24c122..5fa3d38 → origin/main）。

## 1. Commit 账本（6 项，单项独立 commit + 差分回归 + benchmark）

| commit | 项 | 内容 |
|---|---|---|
| `e0cb8c9` | #6 | 工具参数 encode-once + `ParsedToolCall.argumentsJSON` 构造时缓存（Codable wire 三字段不变） |
| `22095b3` | #9 | `splitResponsesEnvelope` 直读 `object["role"]?.string`，删除 jsonValueDictionary 全量往返 |
| `de05b5d` | #8 | Chat messages 走 `JSONValue.any`（Chat-only；Completions/Responses 未纳入） |
| `1524859` | audit fix | `JSONValue.any` 不再将 JSON 整数 0/1 折叠为布尔（CFBoolean 类型 ID 判别）——**correctness fix**，Responses 路径已潜伏，差分测试捕获 |
| `b37d88f` | #1 | retention 预算前置门（未超预算零 decode；eviction 触发条件严格 `>`，数学等价） |
| `5fa3d38` | #4 | PrefixPool 边界哈希 → `PrefixChain.cumulative` 单遍查表（vendor 公开 API，零 pin 变更） |

## 2. Benchmark 实测（swiftc -O standalone，与生产逐机制一致；脚本 /tmp 未入库）

| 场景 | 改前 | 改后 | 提升 |
|---|---|---|---|
| #8 messages 转换（200 msgs × 1KB） | 3.12 ms | 0.30 ms | 10.4× |
| #9 envelope role 读取（100 msgs） | 2.53 ms | 0.003 ms | ~840× |
| #6 工具参数序列化 | 53 µs ×2 | 26 µs ×1 | 2× |
| #4 边界导出 @100k tokens | 7.04-7.92 ms | 0.27 ms | 26-29× |
| #4 边界导出 @237k tokens | 40.4-42.3 ms | 0.68-0.76 ms | 56× |
| #1 retention 常态（95 对，63GiB 级） | 19.67 ms | **1.25 ms** | 16× |
| #1 超预算跨越轮（decode ×95 + 驱逐） | — | 21-22 ms（一次性） | R3 收口 |

## 3. Shelved（正式工程结论，benchmark 证据）

- **#2 isPrefix 指纹缓存**：现行签名物化实测 0.11-0.65ms/轮；逐字节 FNV 替代反而更慢（0.9-1.4ms）——Swift 插值物化+memcmp 快于字节循环哈希。唯一严格更优变体=直接字段比较（~0ms），收益不足以支付状态一致性风险。
- **#3 makeChatMessages delta 缓存**：全量重建 ~0.84-0.96ms/轮（几乎全在 parseToolCalls JSON 机制），不值 ManagedSession 状态边界风险。
- **方法论结论**：渐近复杂度/分配量分析不能替代真实 Swift runtime benchmark。
- **R1（retention 去 decode 化，mtime+filename）**：#1 proposal 三案对比后 R3 收口；重开硬验收=collision/mtime 异常/fork copy/重复保存下**预算收敛性质**证明。

## 4. 回归演进与 Full Gate

- CPU-only 子集（-skip 4 套件）逐项演进：77 → 81(#6) → 86(#9) → 88(#8) → 91(audit fix) → 94(#1) → 98(#4)，全程 0 failures。
- **Full Gate（无 skip，`-enableCodeCoverage NO`）：111 executed / 8 skipped / 0 failures @440.6s**。
  BranchFork、PrefixPoolDailyPathE2E、OversizedRuntimeE2E、GenerationLifecycleRace 全部实跑；
  GenerationLifecycleRace 的 GPU eval 在无并发条件下正常通过（对照：负载下 488s Metal 超时属环境性失败）。
- 复现命令：`xcodebuild -project SimiGo.xcodeproj -scheme SimiGo -destination 'platform=macOS' -derivedDataPath build/test-dd -enableCodeCoverage NO test`
- 前置条件：**服务停止 + 无 GPU 并发 + 15-25 分钟窗口**（活数据安全：BranchFork/PrefixPool E2E 触碰真实 `~/.simigo` 路径）。

## 5. 差分审计记录

- 三路审查（协议层/支撑层代理 + 引擎热路径精读）→ 外部复核 4 点修正（#4 常数、#2 指纹 32-bit、#8 范围、#7 共享 encoder 禁用）。
- 承重发现全部经第二读者或本人读码核实；`1524859` 为审计期间捕获的真实边界 bug（宽 Bool 转型）。
- 实施期间两次安全止损：活服务冲突即刻终止测试，两次核损均为活目录零变动、服务无恙。

## 6. 阶段定性

Optimization Convergence Phase **CLOSED / FULL GATE PASSED / PUSHED**。
`5fa3d38` = 稳定性能基线；后续优化重开须逐项授权（R1 类须先过预算收敛性质验收）。
