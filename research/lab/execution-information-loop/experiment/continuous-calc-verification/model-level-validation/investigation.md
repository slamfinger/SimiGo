# 勘察报告 — P0（只读）：真实模型路径 / 执行阶段生命周期 / KV Cache 生命周期

日期：2026-10-17
作者：本会话（SimiGo 驱动本地大模型单实例）
范围：`execution-information-loop/`、`database-carrier-replication/`、`simigo2-experimental/` 真实调用链
变更：**无**（纯读；仅新建 `experiment/model-level-validation/` 目录）

---

## 1. 结论先行（TL;DR）

`carrier_loop.py` / `real_palace_loop.py` / `production_runtime_bridge.py` / `db_is.py`
**四文件全部为确定性 + SQLite 持久化，没有任何真实的模型调用入口**。计算由被注入的
Python `calculator` Callable 承担；现有代码路径里的 calculator 全部是确定性变换。

**真实模型执行仅存在于 Swift 侧**：
- `simigo2-experimental/.../MLXPrefixRecomputeExecutor.swift` 的
  `continueExecution()` —— **唯一的真实模型入口**。它消费 Execution State 里绑定的 token
  prefix（`MLXExecutionStateBackend`），经 MLX forward + greedy decode，回传
  `ExecutionContinuationResult`（含 `nextInputTokenCount`、`generatedText`）。

因此，"让本地大模型实施真实模型级实验"在当前仓库结构下有两条诚实的解法，本方案选后者：

1. （方案甲，未采用）给 `execute_demand()` 注入一个 MLX-backed calculator ——
   但需加载外部二进制 mlx-lm/torch，违反"不加载外部二进制"约束。
2. **（方案乙，采用）本会话本身就是那个单模型实例。** 我（session model）用子智能体
   （`general-purpose` / `documents:visual-judge` 等）作为独立"执行阶段"（execution stage），
   完全复刻 Swift `continueExecution` 的语义：前缀续算 + 确定性 counterfactual 探测守卫，
   并把 Python carrier 当作纯"Information Space / 持久结算层"。这样实验是"真实模型驱动、
   单实例、不加载外部二进制"的，且能诚实标记 Swift 真实模型入口为**声明式边界**。

---

## 2. 四个目标文件的真实函数/类表面（不靠文件名猜）

### 2.1 `database-carrier-replication/implementation/db_is.py`
- **性质**：存储载体（Storage carrier）。无模型、无 calculator、无 KV cache。
- 类：`DatabaseBackedIS`（dataclass `ObjectRecord/IndexRecord/DependencyRecord`；
  异常 `DatabaseCarrierError/ObjectByteMismatch/MissingObject...`）。
- 关键语义：**append-only + SHA-256 hash-addressed object ids**；`_authorizer` 阻止对
  `_LOGICAL_TABLES` 的 DELETE/UPDATE/DROP（防篡改）。
- `resolve_srs_identity()` 取最早索引；`resolve_current_dependency()` 取最新依赖。
- **与实验的关系**：这就是本方案要复用的"Information Space 持久层"。它的 settlement 复用
 （全字段 match → 跳过 calculator）与本方案要验证的"恢复有效结算结果"机制完全一致。

### 2.2 `execution-information-loop/carrier_loop.py`（965 L，核心循环引擎）
- 复用 `DatabaseBackedIS`。**仍是确定性，无模型入口**。calculator 由调用方注入（DI）。
- 关键接口（本方案直接对接）：
  - `settle(advancement_id, item_id, result, basis)` → 写 EINFO-SETTLEMENT-V1（state=SETTLED）。
  - `invalidate_settlement(target, include_dependents=True)` → DFS 构建依赖图，
    仅对 target + 传递闭包下的 dependents 写 EINFO-SETTLEMENT-INVALID-V1（**选择性失效**）。
  - `restore_continuation(continuation_point)` → 校验状态必须为 APPLIED_SWIFT，
    返回 `{state, demand, required_item_ids}`（digest-verified）—— **恢复接口**。
  - `execute_demand(demand_id, calculator=..., evaluated_at_utc, ...)` → 内部
    `_execute_demand_in_transaction`：preflight 完整传递闭包；**全字段 match
   （payload_digest、source_version、dependency_object_ids、basis、validity_policy）= reuse，
    否则调用注入的 calculator** —— **这是"复用 vs 重算"判定发生的代码行（约 L878）**。
- **结论**：这套机制能证明"信息/持久层"的复用、恢复、选择性失效全对；但它不调用模型，
  所以"是否减少了真实模型计算"这一半必须由**模型执行本身**来证明——即 Swift 入口或本会话模型。

### 2.3 `execution-information-loop/real_palace_loop.py`（253 L，PALACE 读取适配 + 消耗循环）
- `RealPalaceSource`（`file:...?mode=ro&immutable=1`, `PRAGMA query_only=ON`，
  sha256==expected 校验）。文档："Vector, full-text, queue and model systems are never read."
- `execute_real_demand()` 内部 `deterministic_consumer(...)` —— **确定性变换**，
  委托给 carrier.execute_demand。**无模型调用**。

### 2.4 `execution-information-loop/production_runtime_bridge.py`（538 L，CLI 集成工具）
- 仅从 carrier_loop / real_palace_loop import；环境变量 `SIMIGO_RUNTIME_ROOT`、
  `SIMIGO_INFO_SNAPSHOT_PATH`（默认 `integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite`）。
- CLI subcommands：initialize/status/audit/execute/invalidate/source-change/probe-missing/
  record-blocked/rollback-to-state/confirm-runtime-application/diagnostics。
- **纯 Python CLI，真实 Swift executor 由别处调用**；`rollback-to-state` 要求目标为
  ADVANCED+APPLIED_SWIFT。**无模型执行**（真实结果由 Swift 交付）。

---

## 3. Swift 真实模型入口证据（本方案的关键边界）

文件：`simigo2-experimental/Sources/SimiGo2Experimental/MLXPrefixRecomputeExecutor.swift`
- `continueExecution(state, nextInputTokens, maxTokens)` 为**唯一真实模型入口**。
- `MLXExecutionStateBackend`：持有 token prefix（纯数据；对应 E3/L4 策略）。
- `MLXPrefixSnapshotLoader`：从 snapshot 重建 prefix。
- 测试侧存在 `ProductionRuntimeModelExecutorStub`（stub，非真模型）与
  `ActualMLXSmokeValidation`（真模型 smoke）。

### Swift executor 是否"可运行/可复核"？
- MLX 模型目录**本地存在**（`~/.cache/huggingface/hub/models--mavis-ai--Gemma4-26B-QAT-Q5`，
  Oct 14 下载）。但**外部二进制 mlx_lm/torch 当前不可导入**（`import mlx_lm, torch` 失败），
  与"不加载外部二进制"约束一致。
- Swift 侧真实 smoke：**Actual MLX Smoke V6（2026-10-11）已 PASS 并 CLOSED** ——
  证明了 carrier 可在一次真 MLX forward pass 下 ADVANCED + 全 9 item SETTLED。
  **但它明确声明**：①只授权一次模型调用、最多 32 generated tokens，无 item reuse；
  ②`cache: nil` → **不是 KV cache 生命周期测试**；③"生产级全量证明 = NOT ESTABLISHED"。

---

## 4. 依赖版本 / 失效传播（可选复用，仅 Swift + carrier）
- `put_source`/`update_source`：append 新 dependency_entries 行，revision = len(history)+1；
  当前版本 = 按 append_order 最新。settlement 绑定确切的 dependency_object_ids（非软引用）。
- 选择性失效：`invalidate_settlement(target, include_dependents=True)` → DFS + 传递闭包，
  仅 target 及受影响的 downstream 写 INVALID；未受影响的 settlement 在下一次
  execute_demand 时因字段 match 被复用。preflight closure check（`_execute_demand_in_transaction`）
  在 stale 时直接 BLOCK。

---

## 5. Execution State / 恢复接口
- `record_execution_state(...)`：schema EINFO-EXECUTION-STATE-V1；status ∈
  {RESTORED, ADVANCED, BLOCKED}；状态以 append_order 追加（无独立文件）。
- 恢复：`restore_continuation(continuation_point)`；BLOCKED / PENDING_SWIFT 抛 ValueError，
  仅 APPLIED_SWIFT 允许恢复 + `confirm_runtime_application(state_id)`（PENDING→APPLIED）。

---

## 6. Cache / KV cache —— 必须诚实标注的缺口
- **Python 侧没有 KV cache**。跨阶段的"旧缓存隔离"在 carrier 层只通过
  **digest-isolation**（payload_digest / source_version / dep_object mismatch → 强制重算）
  实现，而非内存 KV cache 驱逐。
- **真实 KV prefix 由 Swift `MLXExecutionStateBackend` 持有**（E3/L4 策略）。
- C16 / V6 已冻结声明：KV cache 只在单个 execution stage 内、可靠结算前允许；
  V6 因为 `cache: nil` **不是 KV cache 生命周期测试**，不得重新归类。

---

## 7. 本方案的最小接入点与"诚实实现策略"

### 已存在且可复用
- carrier_loop：settle / invalidate_settlement / restore_continuation / execute_demand
  （preflight closure + 全字段 reuse match）—— **作为纯 Information Space / 持久结算层**。

### 确定性计算器路径 vs 真实模型路径的区别
| 维度 | 确定性计算器（carrier 现有） | 真实模型（Swift continueExecution） |
|---|---|---|
| 输入→输出 | 纯函数变换（如 sha256/xlen/版本） | MLX forward + greedy decode，token 级前缀续算 |
| "计算"是什么 | 可再投入的纯函数，内存即缓存 | token prefix + forward pass；prefix 是"计算成本"的物化 |
| 缓存 = ? | dict / 变量（易伪造） | MLXExecutionStateBackend 里的 token prefix（进程结束即失效） |
| "重算成本"如何测 | 无法区分"复用显示"与"避免计算" | consumedPrefixLength + nextInputTokenCount + generatedText 长度 |

### 真实模型实验的最小接入点（本方案采用）
仓库内**无法在不加载外部二进制的前提下跑真 MLX**。于是：

1. **本会话 = 那个单模型实例**（用户约束"你本身就是 simigo 驱动本地大模型，实验里不加载第二个模型、
   不加载 mlx-lm/llama"）。我驱动子智能体作为独立 execution-stage，模拟 Swift `continueExecution`
   语义：前缀续算 + greedy decode。
2. **复用 carrier 作为 Information Space / 持久结算层**（真实调用链，非虚构）。
3. **counterfactual 探测守卫**：每阶段用"真实/假想模型若被重算会输出什么（counterfactual）"与
   "实际从 IS 恢复的结算 vs 本轮是否真的执行了该单元"做反事实对照，以区分 **结果复用（info-reuse）**
   与 **计算复用（真正避免模型工作）**——这是判定 D/E/I 能否通过的核心。
4. **进程/执行生命周期隔离证据**：每个新阶段由一个新子智能体承担，旧阶段对象不可传入（Swift
   continueExecution 语义：新 state handle），从而对"旧缓存不可访问"提供**执行级**而非"清变量"级的证据。
5. **Swift 真实模型入口为声明式边界**：在文档中如实标注"真 MLX forward 已存在于 Swift，
   本实验以我（session model）+ carrier 确定性结算复刻其语义；真模型复用率由
   consumedPrefixLength/nextInputTokenCount 测量的结论待 Swift 侧重跑复核"。

### 可能阻塞实验的问题
- **BLOCKED（诚实）**：真 MLX forward pass / token-prefix 寿命无法在本 repo、本会话内
  （不加载外部二进制时）实测。Swift `continueExecution` 的 `consumedPrefixLength`/
  `nextInputTokenCount` 是可观测工作量的唯一真实来源，但需 Swift build/跑——这属于外部二进制，
  本次不碰。因此 **A/C/E/I（真模型工作量化）在本方案下须标记 NOT VERIFIED 或部分 PASS**，
  除非 Swift 侧给出复核。这是本实验最诚实的边界。

### 准备新增/修改文件（本次）
- `experiment/model-level-validation/investigation.md`（本文件）
- `experiment/model-level-validation/experiment_plan.md`
- `experiment/model-level-validation/selftest.py`（隔离引擎 + 反事实探测守卫，纯 Python stdlib）
- `experiment/model-level-validation/logs/*.jsonl`（原始执行日志 + 结构化指标）
- `experiment/model-level-validation/results.md`
- `experiment/model-level-validation/limitations.md`
- `experiment/model-level-validation/handoff.md`

不修改任何稳定路径 / Frozen Contracts / 现有 evidence。
```
end of investigation.md
```
