# G1/G3 执行载体可行性审查（Turn 22，仅审查 / 未建 CLI / 未跑模型）

## 依据（事实，均取自当前真实工作树 /Users/mr.simi/Documents/SimiGo）
1. 构建依赖图
   - 产品仓根**无 Package.swift**，构建入口为 `SimiGo.xcodeproj`；App target 直接链接 `MLX/MLXLLM/MLXLMCommon/MLXVLM/MLXHuggingFace/mlx-swift(-lm)`，并引入本地包 `Packages/SimiGoRuntime`（product：`SimiGoRuntimeContract` + `SimiGo2Experimental`）。
   - `NativeMLX`（真实模型加载/生成）= `public final class NativeMLX: Runtime`，位于 **App target**（`SimiGo/Inference/NativeMLX.swift:16`）。App target 类**不能被独立 SwiftPM 可执行目标 import**（App 不产出可复用 module，仅本 app 的测试 bundle 可 `@testable import SimiGo`）。→ 印证用户所指工程风险：在 `Packages/SimiGoRuntime` 新增 exe 无法直接复用生产 `NativeMLX`。
2. 模型加载入口（生产链）
   - `Service.swift:959 runtime = NativeMLX(info:config:)` → `:983 runtime.start(info,port:)` → LOCALB+`HTTPServer`(generateHandler) → `NativeMLX.generate` → `NativeMLX.loadModelContainer(path:)`(`:321`, nonisolated static) → `LLMModelFactory.shared.loadContainer(from:using:)`（MLXLLM/MLXLMCommon，含 VLM 回退 + `Memory.clearCache()`）。
   - 编排链自 Service 以下**全部在 App target**；仅末端 `LLMModelFactory.loadContainer` 在 MLXLLM 包内。
3. 缓存持有链（G3 需审计对象）
   - KV = MLX 内存对象 `KVCache/KVCacheSimple`（`NativeMLXPrefixPool.swift:257/264`），由 `ModelContainer`/生成分管持有；另有 prefix 池与 checkpoint 文件载体、`storageKey/continuation` 身份。
   - 进程内 `Memory.clearCache()` 仅清 Metal 分配器缓存，≠ 逻辑 KV 归属；跨进程天然不共享在内存 KV 对象。
4. 生产结算触发面（G1 需 ES1 结算）
   - 真实生产调用者为 **GUI 按钮**：`ExecutionStateGraph.swift:869 run { _ = try store.settleProducerResult(...) }`；无既有无头/参数化触发入口（`MenuApp` `@main` SwiftUI，App 内无 `CommandLine` 驱动；`tools/t4ctl` 属 Lab 工作区，非产品仓）。

## 候选载体与判定
- **V1 两次独立启动生产 app 二进制（仅共享 SQLite IS）**：最贴生产（同一实现、独立进程、独立 KV）。阻断：结算为 GUI 动作、每次启动需 LOCALB 激活仪式、SwiftUI 运行循环——需新增"程序化 generate+settle"入口才能自动化。
- **V2 把 `NativeMLX` 及其 6 个 App 内依赖（traceLogger/RuntimeTuning/ModelConfig/ModelInfo/InferenceNodeConfiguration/RuntimeLifecycleCoordinator）+ Service 选择 + `ExecutionStateGraph` 结算抽到共享库 target，app 与驱动 exe 同依赖**：从构造上"同一实现"，最 principled。改动面有限但非平凡（6 符号 + HTTPServer/LOCALB 耦合 + @MainActor/单例解耦）。
- **V3 app 测试宿主内起两个 NativeMLX（同 MemoryRelief 路径）**：非跨进程，不满足 G1"旧 ES 失去资格/新进程"与 G3"独立进程/旧 KV 不可达"，只能作廉价前置检查，**不作主证据**。
- **V4 包 exe 调 `SimiGo2Experimental` 的 `MLXExecutionStateBackend`**：研究路径，**非** Service→NativeMLX 生产路径 = 第二套实现。**明确拒绝**（正是要规避的风险）。

## 推荐（待授权后择一实施；本轮不动代码）
- 首选 **V1 变体**：给生产加一个**真实的、非测试专用**程序化入口（无头 generate + settle，复用 Service/NativeMLX/ExecutionStateGraph 原路径），父驱动脚本用 `Process` 起两次该入口进程，ES1 结算退出、ES2 从 IS 恢复续算——改动小、仍是同一实现、真跨进程。
- 若可接受较大边界重构，则 **V2** 抽共享库最干净，但需先出最小改动清单与回归计划。
- 二者都需在实施前确认"最小共享代码边界"，严禁派生第二套模型执行实现。

## 验收门当前状态（诚实标注）
- **G1：NOT VERIFIED**（真模型跨进程 结算→脱离→从 IS 恢复 U2 + 缺失/篡改/依赖变更负向对照，均未跑）。
- **G3：NOT VERIFIED**（新 ES 不借旧 KV：cache 身份/创建/释放事件审计、旧 cache 不可达负向对照，均未跑）。
- **物理内存回收：NOT VERIFIED**（须区分 缓存引用释放 / 资源回收 / 统一内存页归还；不以 RSS 瞬降单独裁定）。
- **G2（SQLite IS 行为）：已封存为 L2 证据（包测 77/77 + App Debug BUILD）**，与本轮无关，不扩展测试数量。
- 任何门在未满足"真实 MLX + 独立进程 + 访问审计 + 负向对照"前，不得标 PASS。

## 不变量核对
- 不修改冻结 G2 批次与既有实验边界；不把模拟/结构测当真实模型证据；不 commit/push；不清理无关工作树差异。
