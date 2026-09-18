# 外审四轮登记：S1 测试质量收紧（2026-09-19）

**基线**：`0fec012`（V1.6 S1 + 竞态测试首版）
**结论**：Core 通过；无 P0；无新增生产级 P1；S1 ExecutionID 方向正确可
继续；V1.6 架构方向维持，不扩大实现范围。三项测试质量收紧点全部采纳。

## 采纳与执行状态

| 项 | 级别 | 修复 |
|---|---|---|
| 竞态测试零命中仍通过，"未命中"不得称完整竞态验证 | P1 | 结果语义分层：
  `RACE_WINDOW_HIT`（窗口真实覆盖+generate 存活=完整验证）与
  `PROTECTION_PASS_NO_HIT`（仅保护不变量成立）显式区分 |
| `suspendIdleTimeoutOverrideSeconds` 全局可变测试开关 | P2 | `#if DEBUG`
  隔离——Release 构建符号不存在，生产写入从治理约束升级为编译期强制 |
| 异步 defer 恢复 InferenceNodeConfiguration 悬挂窗口 | P2 | 恢复改为
  可等待路径：do/catch 双路 `await restoreConfig()`，测试退出前恢复
  确定执行；固定端口 8765 改 port 0（系统分配） |
| headless 错误断言过宽（任意错误即过） | P2 | 收紧为
  `catch RuntError.notLoaded` 精确匹配 + 意外类型 XCTFail |

## 复跑验证（收紧后）

- 门控竞态测试：`outcome=RACE_WINDOW_HIT suspendWins=1`，27.4s 全过
- headless 回归：typed error 断言 + 状态断言通过

## 六轮外审追补：测试开关显式恢复（2026-09-19，已修复）

**发现**：竞态测试置 `suspendIdleTimeoutOverrideSeconds = 0` 后未在清理
路径显式恢复 nil——同进程后续测试可能继承残留值（P2/测试间状态污染）。

**修复**：统一清理路径新增 `resetTestSeam()`（#if DEBUG、幂等），与
`stopRuntime()`/`restoreConfig()` 同序执行：异常 → reset → stop →
restore → rethrow；正常 → stop → reset → restore。

**复跑**：门控竞态测试 `RACE_WINDOW_HIT suspendWins=1`（33.8s）+
headless 回归全绿。

**S3 准入确认**：外审建议顺序第 1、2 步完成；ExecutionFacts 的 var/
构造入口/快照时点审查留待 S3 接线时一并做（外审 §四登记）。

## 五轮外审追补：测试资源生命周期（2026-09-19，已修复）

**发现**：竞态测试成功/异常路径均未调用 `runtime.stop()`——
`start()` 持有的 ModelContainer/HTTPServer/会话 KV 在测试结束后驻留，
污染后续测试的内存与 MLX cache（P1 候选/测试隔离）。

**修复**：统一可等待清理路径 `stopRuntime()`（幂等 flag + 非 throwing
`stop()` 不会掩盖原始错误），do/catch 双路与 `restoreConfig()` 同序
执行：异常 → stop → restore → rethrow；正常 → stop → restore。

**复跑**：门控竞态测试 + headless 回归全绿（75s，含 stop 卸载）。

## 外审认可（登记）

- S1 边界诚实：`parent=-` 占位，不虚构 fork 血统；ExecutionID 当前
  回答"日志属于哪次生成"，lineage 归属留后续分片——目标一致不扩圈
- V1.6 无"架构先行、实现过度"回潮

## 七轮外审（S3 复核，2026-09-19）：通过 + P2 已修

**结论**：S3 核心实现通过——配置面合并 ✅ / 单请求快照 ✅ / Decision gate
与 checkpoint save 同快照 ✅ / 默认行为等价 ✅ / ExecutionPolicy 纯函数
边界保持（不偷读 RuntimeTuning）✅ / ExecutionFacts 不提前接线 ✅。

**P2 已修**：ExecutionPolicyGateTests 快照隔离测试的恢复值写死 8192 →
改为恢复进入前原值（`original`），与五轮 seam 污染同类问题关闭；
ExecutionPolicy.swift 头部"留待 S3"陈旧注释顺手清。

**七轮外审 S3 审查重点已入册**（S4 期间重点盯）：
ExecutionControlling 薄协议面是否只是"命名抽象"，还是悄悄产生第二套
运行语义。

## 八轮外审（51e13d6，2026-09-19）：P0/P1/P2 三清零，放行 S4

外审确认：P2（恢复值写死）已正确关闭；S3 快照纪律未破（gate 与
checkpoint save 同快照）；ExecutionPolicy 未偷回运行权；ExecutionFacts
不提前接线正确。S4 审查红线升级：五动作必须直映射既有路径，P0/P1
风险 = "产生第二套执行语义"。

## S4 执行记录（2026-09-19）

**落地**：`SimiGo/Inference/ExecutionControlling.swift`——协议面五动作
（execute/continue/checkpoint/restore/fork）全部直映射既有路径：
execute/continue → generate；checkpoint → saveSessionCache；restore →
loadSessionCache；fork → forkSessionBranch（BranchFork v1）。映射表
写入文件头作为唯一事实源。

**红线遵守**：零新执行语义、零新状态、continue 与 execute 当前同映射
（lineage 区分留 S5，注释明示）；ExecutionID = AgentExecutionKey 三元组
直映射（不升级 S1 遥测 id8）。

**验收**：headless 委托证明 3/3（未加载实例五动作错误透传 =
纯委托证明）；全量 66 执行 0 失败。

## 九轮外审（043fe3b，2026-09-19）：S4 通过 + 三项收尾已修

**结论**：S4 五动作映射全 ✅、无新增运行状态、无第二套执行语义、S3 单
快照纪律未被绕开——P0=0 / P1=0；S4 不返工。

**收尾三项（本轮已修）**：
1. P2-1 委托证明收紧：execute/continue/checkpoint/restore/fork 测试
   从"任意 error 即过"收紧为 `RuntError.notLoaded` 精确匹配 + 意外类型
   XCTFail——真正证明"底层错误透传"而非仅"失败行为"
2. P2-2 CheckpointID 契约漂移：按外审方案 A 处理——不改动已稳定的
   checkpoint API；CheckpointID 注明为 S5 lineage 关联模型预留，当前
   非协议参数类型
3. P2 增强 协议面调度验证：新增 `testProtocolExistentialDispatch`——
   经 `any ExecutionControlling` existential 调用，证明
   协议定义→conformance→existential→调用 全链

**复跑**：ExecutionControllingTests 4/4 全绿；全量 SimiGoTests 通过。
**S4 正式封版**，下一道架构关 = S5 lineage。
