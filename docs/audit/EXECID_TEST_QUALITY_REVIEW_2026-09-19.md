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
