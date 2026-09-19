# SimiGo v1.6 发布说明

日期：2026-09-19
依赖基准：mlx-swift-lm `dc3ca6197171`、mlx-swift `0.31.6`（与 v1.5 一致，
未升级）；Runtime 行为与 v1.5 零回归（S1–S5 每片零行为变更验收）

## 本版主题：V1.6 Execution Runtime 架构定型（五分片收官）

v1.5 回答了"Conditional Restore 能否成为稳定的 Runtime 行为"；v1.6 不加
性能优化点，而是把 Execution 概念边界显式化——建立
**事实 → 策略 → 决策 → 执行 → 血统** 五层，每片独立提交、独立验收、
零行为回归。

## 变更清单（S1–S5）

### S1 ExecutionID（血统遥测起点）

- 每次 generate 生成完整 UUID executionId；`[EXEC] begin/end` 配对 +
  完成行 `exec=` 字段——"这条日志属于哪次执行"可精确回答

### S2 ExecutionPolicy（判定收敛）

- 判定纯函数簇（rollforwardRisk / conditionalRestoreGate / delta 估算 /
  兼容守卫 / diff 诊断 / render 对账族，17 函数）自 NativeMLX 搬家至
  ExecutionPolicy.swift，函数体逐字节不变；Protocol 层零复判

### S3 Configuration Snapshot（配置冻结）

- 三 flag（rollforwardEnabled / conditionalRestoreEnabled /
  conditionalRestoreMaxDeltaTokens）合并为
  `ConditionalRestoreConfiguration`；generate 每请求 `current()` 一次性
  快照，gate 判定与 checkpoint save 门全程只消费快照——配置 reload 与
  长生成并存时不再跨时刻拼凑

### S4 ExecutionControlling（统一入口）

- 五动作协议面（execute / continue / checkpoint / restore / fork），
  全部直映射既有路径（generate / saveSessionCache / loadSessionCache /
  forkSessionBranch），零新执行语义、零新增运行状态——外审红线
  "不得产生第二套执行语义"通过

### S5 ExecutionLineage（血统）

- `ExecutionLineage` 有界血统日志（128 FIFO）+ ExecutionStatus /
  ExecutionRecord / BranchForkEvent 模型
- `[EXEC] end status=` 终态（completed/failed/cancelled）、
  `[EXEC] checkpoint` 关联、`[EXEC] fork` 分支派生真值（storageKey 级，
  仅 fork 全成功后记录）

### 工程质量

- 生命周期竞态测试（generate × suspendIfIdle 锤击，RACE_WINDOW_HIT 实证
  generate 存活）、挂起-恢复往返、重复挂起幂等
- `suspendIfIdle()` 失败日志补齐；typed error 断言；测试缝隙 #if DEBUG
  隔离；可等待配置恢复

## 已知边界

- ExecutionFacts 尚未接线（S3 后待快照纪律接线，S4 期不提前吞并）
- Execution Fork 真共享等待上游原语（RFC mlx-swift-lm#629 在册）；
  BranchForkEvent 为 storageKey 级分支 provenance，非 execution lineage
- ExecutionLineage 容量 128 条/实例（FIFO），观测用途非审计账本

## 验收

- 全量 SimiGoTests **71 执行 / 0 失败 / 5 门控跳过**（含
  ExecutionPolicyGateTests 3、LifecycleRaceTests 2、
  ExecutionLineageTests 4、ExecutionControllingTests 3 新增族）
- 外审多轮复核：S1–S5 逐片通过，Post-Freeze Audit P0×3 + P1×4 闭环，
  终局决策与上游 RFC 均在册
- DMG `hdiutil verify` VALID；内嵌 app 版本 1.6、codesign 校验通过

## v1.6 稳定替换（Build 3，2026-09-19）

### 修复

- 修复 OpenAI 客户端发送 `"tools": null` 时的全局冻结：`NSNull` 不再进入
  `JSONSerialization` 写出路径；只有非空 `[[String: Any]]` 会按 tools 编码。
- 保留 checkpoint 落盘、Lineage 状态与 checkpoint 失败日志；取消成功路径的
  `[EXEC] begin/checkpoint/end` 与 `[MLX] session=` 噪音埋点。
- `BranchForkTests` 与 `RollForwardExperimentTests` 移入 `SimiGoTests/BranchFork/`，
  保持测试代码与生产 target 分离。

### 验收

- 全量 `SimiGoTests`：73 执行 / 0 失败 / 5 模型门控跳过
- Release 10K 完整矩阵通过；`tools=null` warm-setup 正常完成，回归后
  `/health=200`
- 成功路径新增日志中 `[EXEC] checkpoint`、`[MLX] session=`、`[EXEC] end`
  均为 0 条
- 证据：
  `docs/experiments/V17_RUNTIME_MATRIX/results_release_minimal_rootfix_regression.json`

### 发布物

- `SimiGo-v1.6.dmg` 替换为 Build 3；内嵌 app 版本仍为 1.6
