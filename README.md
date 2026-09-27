# SimiGo-Lab — SimiGo 2.0 Runtime 实验室

**性质**：SimiGo 2.0 预研与工程实验仓。  
**核心定位**：**面向 Execution State 的 Runtime 实验**。

SimiGo-Lab 当前不试图重新实现 MLX、Llama 等底层模型执行系统，也不以提出一个独立的“全新推理架构”为目标。当前实验围绕一个更具体的问题展开：

> **Execution State 是否正好是模型执行语义与物理资源管理之间缺失的边界？**

如果这一边界能够在真实 Backend 上成立，SimiGo 的工作重点就是验证一种 **Execution-State-oriented Runtime integration**：把执行的逻辑身份、连续性与分支语义，与 KV / Tensor / Residency / Materialization 等物理表示和资源生命周期分离。

**产品仓**：`github.com/slamfinger/SimiGo`（1.x 线；与本仓严格分离）。  
**当前状态真源**：`docs/RESEARCH_STATE.md`。本 README 提供定位与工作区导览，不替代状态真源或具体 gate 文档。

## 当前 Runtime 实验

当前工程链：

```
Execution State
      │
      ├── Identity / Lineage / Position
      ├── Continuation
      └── Fork / Restore / Reattach / Discard
              │
              ▼
      SimiGo Runtime Contract
              │
              ├── Fake Runtime
              ├── MLX Execution-State Adapter
              └── Residency Integration
```

当前门位：

- **E1 — Execution Continuity Contract：VERIFIED**
- **E2 — Fake Execution Backend lifecycle tree：VERIFIED**
- **E3 — MLX Execution-State Adapter：VERIFIED**
- **E4 — Continuity + Residency Integration：NEXT**
- **E5 — End-to-End Execution State scenario：未开始**

最新已登记的 E3 验证提交为 `646bc098`：**84/84 PASS**。当前实现使用 Backend Representation Strategy 与 Execution State Contract 对接；物理表示仍由 Backend 管理，SimiGo 不建立第二个 KV authority。

## 核心边界

```
Execution State ≠ KV Cache
Execution State ≠ Residency State
Execution Continuity ≠ Computation Semantics
SimiGo Runtime ≠ Backend
```

核心原则：

> **SimiGo Runtime 管理 Execution Continuity 与 Resource Lifecycle；Backend 管理物理模型执行和计算语义。**

Representation migration 必须保持 Execution Identity、Lineage、Position、Next Input、Continuation Semantics 与后续状态演化。

因此，Resident / Evicted / Materialized / Checkpointed / Restored / Migrated 描述的是**物理表示状态**，不能被当作 Execution Identity 本身。

## 当前实验不是在做什么

- 不重新实现 MLX / Llama 等优秀开源 Backend；
- 不建立第二套 KV / physical-state authority；
- 不重新打开已冻结的 Track B 研究；
- 不因为 Execution State 抽象存在而开启 Predictor、Router/Expert、Speculative Execution 等研究；
- 不把已有 Residency 结果包装成新的通用推理架构；
- 不从当前结果宣称性能优势或普适性。

## 研究问题与工程路径

当前工作的价值不在于“重新造一个更强的模型执行引擎”，而在于验证：

> **一个长期存在的 Execution State，是否可以作为 Runtime 中独立于物理表示的逻辑实体存在，并在真实 Backend 的 representation migration、residency 与 restore 过程中保持连续性。**

工程顺序固定为：

```
E1  定义边界
 ↓
E2  在 Fake Runtime 中验证边界
 ↓
E3  接入真实 Backend
 ↓
E4  与 Residency 合流
 ↓
E5  真实端到端验证
```

研究深度仍遵循：**证据到哪里，结论到哪里。**

## 档案体系

完整档案入口：

`docs/ARCHIVE_INDEX.md`

当前链：

```
Question
  → Hypothesis
  → Design
  → Evidence
  → Finding
  → Decision
  → Runtime Experiment
  → Closure / History
```

历史 FROZEN / SEALED / CLOSED 资产不得因当前工程实验而重新解释或自动重开。

## 边界规则

1. 实验室代码与 SimiGo 1.x 产品线严格分离。
2. Git 与登记文档是项目状态真源，Conversation Memory 不替代 Git。
3. 研究结论、工程事实、假设和未来目标必须保持语义分离。
4. 不因为抽象存在就扩大研究范围。
5. 未经新 gate 授权，不重新打开已冻结研究线。
