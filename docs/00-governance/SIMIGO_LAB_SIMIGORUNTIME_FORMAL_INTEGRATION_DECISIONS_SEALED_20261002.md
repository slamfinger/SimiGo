# SimiGoRuntime 正式接入 Gate — 决策封存（1–5）

Date: 2026-10-02  
Status: `DECISIONS SEALED / MINIMAL IMPLEMENTATION AUTHORIZED`

## 1. 裁定表（human 逐字要点）

| # | 裁定 | 核心理由 |
|---|---|---|
| 1 | **(b) 新薄 target `SimiGoRuntimeMemory`** | 本 Gate 目标 = 正式接入而非重设计 contract 层；SimiGoRuntimeContract 保持纯 contract/零外部依赖；既有 ExecutionState/Continuity/RuntimeBackend contract **不因名字相邻而把 InformationCore 变成其一部分** ⇒ A5 更易零变化 |
| 2 | **(a) 直接消费 `any InformationStore`** | 复用已冻结 S1–S6；加 facade = 新语义接口（须回答与 InformationStore 是否一一对应/错误语义谁定/是否重包装 S1–S6/是否产生第二套 memory contract——均非本 Gate 问题）；**正式接入只消费既有 InformationStore，不重新解释它** |
| 3 | InformationCore 零 SimiGo 知识 | 硬规则确认；保护条件延续 |
| 4 | **(a) SimiGo2Experimental 本 Gate 不接入** | 当前 Gate 只验证「runtime 正式层能否获得 Information memory boundary」；SimiGo2Experimental 是 Contract+MLX 实验线，同步接入会把正式边界与实验实现线绑定；后续需要再单独处理 |
| 5 | **(c) 未提交本地 path dependency 过渡** | (b2) 独立包可能是终态但同时引入包拆分/独立仓库/版本治理/发布策略/仓库边界重裁——非本 Gate 唯一问题；**不得把 path dependency 写成最终架构承诺**；未来需要独立包时：InformationCore package extraction → 另立小 Gate → 重新验证 A1–A10/dependency integrity |

## 2. 最终边界（human 定稿）

```text
                         SimiGo
                           │
                           ▼
                 SimiGoRuntimeMemory
                   （新薄正式 target）
                           │ any InformationStore
                           ▼
                    InformationCore
                           │
                    ┌──────┴──────┐
                    │             │
              Information      Store
                    │
                    ▼
              existing S1–S6
```

旁路保持：SimiGoRuntimeContract = pure contract = 零改动；
SimiGo2Experimental = 零接入；RelationCore = 零改动。

## 3. 最小实现范围（六项）

1. 新薄 target（SimiGoRuntimeMemory）
2. target → InformationCore path dependency
3. 一个最小 runtime 消费点
4. 直接持有/消费 `any InformationStore`
5. 用既有 S1–S6 形状验证
6. 不修改既有 contract

随后执行已登记的 A1–A10。

## 4. 收口登记与 Git 纪律

通过后登记：`SimiGoRuntime × InformationCore = FORMAL INTEGRATION
PASS`；**T4 = BLOCKED 不因本 Gate 自动开放**。

5(c) 纪律：path dependency **保持未提交**（SimiGo 仓工作区态），
完整 diff 归档至 Lab 证据目录留档；不 squash 不 rewrite。
