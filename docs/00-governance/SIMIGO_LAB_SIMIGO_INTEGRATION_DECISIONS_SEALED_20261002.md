# SimiGo × InformationCore 接入边界 Gate — 决策封存

Date: 2026-10-02  
Status: `DECISIONS SEALED / MINIMAL IMPLEMENTATION AUTHORIZED`

## 1. 裁定（human 逐字要点）

| # | 裁定 | 要点 |
|---|---|---|
| 3.1 | **(c) Lab 侧 SimiGo-shaped 预研先行** | SimiGo 主仓**零 InformationCore 依赖**的事实保持不变；先验证窄边界 = 「SimiGo 形状的上层执行者能否仅通过 InformationCore 完成 store/fetch」；不预判 SimiGoRuntime 正式接口；App 直连 (b) 不作为本 Gate 方案（记忆语义不得直接耦合应用层）；(c)→(a) 为后续演进，本 Gate 不裁 (a) 的最终接口；**这不是 SimiGo 正式接入实现，只是验证正式接入所需的最小边界** |
| 3.2 | **(i) SwiftPM path dependency** | 当前目标是**最小边界验证**而非包发布治理；直接验证真实 Swift module / protocol dependency（非复制代码的伪接入）；后续若需独立发布转 (ii)，**该转换不改变 InformationCore 语义契约**；(iii) vendored 明确排除（双源漂移违反单一语义源） |

## 2. Gate 裁定结果表

| 决策点 | 裁定 | 状态 |
---|---|---|
| 3.1 接入层位 | (c) Lab 侧 SimiGo-shaped 预研先行 | PASS |
| 3.2 跨仓策略 | (i) SwiftPM path dependency | PASS |
| SimiGo 主仓正式改造 | 不做 | 保持零改动 |
| SimiGoRuntime 正式 target | 暂不决定 | 留后续 Gate |
| T4 | 不执行 | BLOCKED |
| T4 precondition | 待实现并验证 P1–P4 | 未登记 SATISFIED |

## 3. 当前形态（human 定稿）

```text
当前   SimiGo └── 无 InformationCore 依赖
本 Gate Lab / SimiGo-shaped pre-research └── InformationCore
         ├── Information
         └── InformationStore
后续（本 Gate 不裁）SimiGoRuntime └── InformationCore
```

## 4. 最小实现允许范围与四项必须证明

只允许验证：

```text
SimiGo-shaped executor → InformationCore → store / fetch
``+

| 项 | 必须证明 |
|---|---|
| P1 | 存在可运行的冷启动执行者 |
| P2 | 可复现 S1–S6 所需的 store/fetch 形状 |
| P3 | 预研上层不知道 SQLite / Physical Filing |
| P4 | 无 InformationCore → SimiGo 反向依赖；不引入 palace/taxonomy/activation/Execution State 语义 |

四项全过 ⇒ 登记 **T4 experimental precondition = SATISFIED**；
**T4 本身仍然 BLOCKED**。

## 5. 保护条件（继续有效）

```text
InformationCore 受保护文件 diff = 0
RelationCore 全文件 diff = 0
```
