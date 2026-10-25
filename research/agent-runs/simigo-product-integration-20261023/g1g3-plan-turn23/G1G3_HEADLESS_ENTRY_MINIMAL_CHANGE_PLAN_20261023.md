# A｜V1 变体：受控无头生产入口 — 最小改动清单（仅设计，待审查，未改任何代码）

目标：用最小改动取得 G1/G3 所需「真实模型 + 独立进程 + 缓存生命周期」证据；无头入口**只复用现有生产实现**，不新写推理/结算/KV 管理。

## 0. 已核实的可复用生产接缝（事实）
- 模型解析：`Config.swift:213 SimiGoModelDiscovery.resolve(ref)` → 外部 HF 缓存（与 GUI 同一路径）。
- 运行时创建+真实生成：`Service.swift:959 NativeMLX(info:config:)` → `runtime.start` → `NativeMLX.generate(requestId:sessionId:messages:tools:config:onChunk:)`（`:749`，public，HTTP 处理器即调用它）。
- 真实结算权威：`ExecutionStateGraph.swift:869 store.settleProducerResult(generatedText:boundToState:)`（UI 按钮同款），内部经原生 gate→`recordNativeSettlement` 写 SQLite IS。
- IS 权威库：`SimiGoPaths.databaseURL`（simigo.sqlite3）；回读 `readSettlementReceipts`/`readGraph`（新 ES 只从 SQLite 重建）。
- KV/缓存载体与既有打点（G3 审计落点）：`~/.simigo/prefix-pool`（PrefixPool.swift:84）、`~/.simigo/branch-checkpoints`（NativeMLX.swift:2084，meta 写 :1881）；trace 已有 `[LIFECYCLE] resume/suspend`、`[MLX] cacheSave/cacheLoad/reuseMiss/prefixMismatch/poolBind/action=checkpointFailed`。

## 1. 涉及文件（改动面）
- **新增（唯一新增生产代码，thin orchestration，env 默认关闭）**：`SimiGo/Headless/SimiGoG1G3Entry.swift`
  - 仅调用上面已存在的 public 生产 API 完成两个角色；**不定义新加载器/新结算/新 KV 逻辑**。
- **最小 hook（一处、受 env 门控、默认不改 GUI 行为）**：`SimiGo/App/MenuApp.swift` 的 `MenuApp` 加 `init()` 前置守卫：当 `SIMIGO_HEADLESS_ROLE` 存在 → 运行 headless 角色 → `exit()`，不进入 GUI scene。常规启动无该 env → 行为完全不变。
- **纯增量插桩（trace/计数，无行为改变）**：`SimiGo/Inference/NativeMLX.swift` 增：
  - 每实例 `cacheIdentity`(UUID) + 在 `performLoad`/`generate` 前/后打 `cache_create`/`prefill_tokens`/`forward_calls`；
  - 生成路径记录是否发生 prefix 命中（复用既有 reuseMiss/prefixMismatch/poolBind 语义，新增结构化输出，不改判定）。
- **驱动与验证器在 agent-runs（不进产品仓）**：父驱动脚本（用 `Process` 起两次内置 headless 的产品二进制）+ 独立验收器 `validate_g1_g3.py`。产品包/工程保持干净。

## 2. 跨进程编排（父驱动，产品仓外）
- 一次性隔离 `SIMIGO_HOME=<temp>`（ES1/ES2 共享同一 simigo.sqlite3；不污染真实家目录）。
- 真实权重：`Qwen3-Coder-30B-A3B-Instruct-4bit`（HF 缓存 root_id+相对）。
- **ES1（角色 produce，进程 A）**：`NativeMLX.start` → 真实 `generate` 产出 U1 → `settleProducerResult` 把 U1 语义值结算进 IS → 记录 pid/cacheIdentity/prefill 计数/输出 → **进程退出**（旧 ES 彻底失去执行资格，其内存 KV 随进程消亡）。
- **ES2（角色 consume，新进程 B）**：全新进程全新 `NativeMLX`（自有新 KV）→ 从 `SimiGoPaths.databaseURL` `readSettlementReceipts`/`readGraph` 恢复 U1 已结算语义值作 `nextInput` → 真实 `generate` 续算 U2 → 记录其 cacheIdentity、是否新建 KV、prefill 计数、对旧 cache 文件的访问尝试。

## 3. G1 验收（同时审计 IS 恢复 + 真实模型调用）
- 必证：ES2 的 U2 输入来自 IS 回读（digest 匹配 ES1 结算），非来自进程 A 内存；两角色都发生真实 forward/prefill（计数 >0）；结算回读一致。
- **重要限制（如实标注）**：跨进程不共享内存 ≠ 已避免重算。若 ES2 对 U1 全文重新 prefill，则本实验仅证明「跨进程恢复 + 继续生成 + 复用已结算**结果值**」，**不**声称避免已完成计算的重算。G1 报告将**分列**：`result_reuse_via_IS = true/false`、`u1_reprefill_observed = true/false`、`forward_calls_ES2 = n`。二者不合并成单一 PASS。
- 负向对照：缺失结算记录 / 篡改 payload digest / 依赖版本变化 → 原生 gate 拒绝，fail-closed（不写、不恢复出伪造值）。

## 4. G3 验收（旧 KV 实际不可达 + 三层分列）
- **逻辑不可达（必证项）**：ES1 退出后，令其 `~/.simigo/prefix-pool`、`branch-checkpoints` 对 ES2 不可达（删除/权限隔离/改指空目录），ES2 仅凭 IS 有效信息仍完成 U2 → 证明新 ES 不读/不借/不间接复用旧 ES 的 KV。ES2 侧 `reuseMiss/prefixMismatch/新建 cache_create` 为正向证据；明确排除「旧 KV 快照或 Prefix Pool 命中被伪装成新建 cache」。
- **三层分列报告（不互相代替）**：
  1. `cache_reference_release`：ES1 的 `KVCache/ModelContainer` 随进程消亡（对象生命周期 + 进程退出）。
  2. `resource_reclaim`：进程内 `Memory.clearCache()` 等 Metal 分配器缓存回收事件。
  3. `physical_page_return`：统一内存物理页归还是**单独测量**（footprint / `memory_pressure` / compressor / page-out 观察），**不以 RSS 或 footprint 瞬时下降单独裁定 G3**，也不宣称省去全部 prefill/FLOPs。
- 访问审计覆盖**正式执行路径**（NativeMLX/PrefixPool 内的既有打点），不仅 harness 计数。

## 5. 回归测试（改动前后）
- 包测 `swift test`：维持 **77/77**（headless 改动不触包）。
- app 全量 `SimiGoTests`（宿主执行）：无失败；常规启动 env 缺省 → headless 守卫短路，GUI 行为零改变（新增断言：无 `SIMIGO_HEADLESS_ROLE` 时不进入 headless）。
- app `xcodebuild build` Debug：BUILD SUCCEEDED。
- 插桩为纯 trace/计数，不改判定/生命周期语义（回归对照 suspend/resume/checkpoint 既有测）。

## 6. 失败回滚方式
- 新增均为：1 个新文件 + 1 处 `init()` env 门控守卫 + NativeMLX 内纯增量 trace。回滚 = 删新文件 + 还原 MenuApp `init()` + 删增量 trace 行。
- 无 DB/schema 变更（沿用已封存 v3）；无数据迁移；驱动/验证器在 agent-runs，产品仓零残留。
- 回滚后 tracked-modified 复原至基线（当前 10），不 commit/push。

## 7. 证据格式（每门独立）
- 机读报告 `g1_report.json` / `g3_report.json`：run ID、ES1/ES2 pid、model revision、后端版本、OS/硬件、commit、cacheIdentity、prefill/forward 计数、IS 回读 digest 匹配、旧 cache 不可达对照结果、三层内存指标、各负向对照结论。
- 每门状态取值 `PASS / FAIL / BLOCKED / NOT_INSTRUMENTED`；注明失败条件；未打点/不可观测不得写成 PASS。附原始日志 + trace 摘录 + `validate_g1_g3.py`（issue_count）+ sha256。

## 8. 当前状态
- **G1 = NOT VERIFIED**、**G3 = NOT VERIFIED**、物理内存回收 = NOT VERIFIED。
- **本轮未改任何代码**；仅交付本清单待审查。不变量：不动冻结 G2 批次/既有边界；不把模拟/结构测当真实模型证据；不 commit/push；不清理无关差异。
