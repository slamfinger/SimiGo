# Gate Spec — SimiGoRuntime 正式接入 Gate（仅 Spec，零实现）

Date: 2026-10-02  
Status: `GATE OPENED（SPEC 已登记；决策点 1–5 待 human 裁定）`  
位置：Phase 2 CLOSED / pre-research PASS 之后、T4 之前的**正式接入裁定与实现 Gate**  
Gate 唯一问题（human 逐字）：

> **SimiGoRuntime 能否把 InformationCore 正式纳入 runtime 层的
> 记忆边界，而不改变 InformationCore / RelationCore 已冻结语义，
> 也不把 palace / SQLite / taxonomy / activation 等外部语义带入
> runtime？**

## 0. 现场事实（2026-10-02 勘察）

```text
SimiGo/Packages/SimiGoRuntime（本地 SwiftPM 包）
├── targets
│   ├── SimiGoRuntimeContract   # 零依赖纯 contract 层：
│   │                           #   ExecutionContinuityContract.swift
│   │                           #   ExecutionStateBackendContract.swift
│   │                           #   RuntimeBackendContract.swift
│   └── SimiGo2Experimental     # deps = Contract + MLX 全栈
└── dependencies                # mlx-swift @ ef5f1b6b（与 Lab 根包同 revision）
                                # mlx-swift-lm / swift-transformers
```

**关键事实**：① SimiGoRuntimeContract = 零依赖 contract 层（新
依赖接入的最自然位置，但接入即给零依赖层加依赖——决策点 1）；
② Contract 已含 ExecutionState/Continuity contract 文件——**命名
与本 Gate 相邻，本 Gate 只接 InformationStore，零改动这些文件的
语义**（防混淆声明）；③ mlx-swift 已是 SimiGoRuntime 既有依赖
且与 Lab 根包同 revision——决策点 5 的依赖图合并风险因此降低。

## 1. 决策点 1 — 哪个 target 消费 InformationCore

| 选项 | 内容 | 代价/收益 |
|---|---|---|
| (a) | **SimiGoRuntimeContract 直接依赖 InformationCore**（contract 层声明记忆边界：InformationStore 引用类型进 contract 面） | 零依赖层获得首个外部依赖（方向合法：Contract → InformationCore）；语义边界声明最正式 |
| (b) | 新薄 target（如 `SimiGoMemoryBoundary`）依赖 InformationCore；Contract 保持零依赖 | Contract 纯度保持；多一层间接 |
| (c) | SimiGo2Experimental 直接依赖（MLX 实验层消费） | 最浅；但把语义核心接进 MLX 实验层，层位最不正式 |

记录者预分析：(a) 与 (b) 均合法；(a) 更符合「记忆边界属于
runtime contract」的架构直觉，(b) 更保守。**待裁**。

## 2. 决策点 2 — 直接依赖 InformationStore vs 薄 facade

| 选项 | 内容 | 依据/风险 |
|---|---|---|
| (a) | runtime 消费者直接绑定 `any InformationStore`（pre-research ColdStartExecutor 模式平移；Information 语义原样通过） | 零重新解释；S1–S6 契约直接适用 |
| (b) | 薄 facade 协议（SimiGo 形状的域方法） | 新协议 = 新抽象（负空间纪律：不经裁定不加）；且 facade 包装有重新解释语义的风险 |

记录者预分析：(a)。**待裁**。

## 3. 决策点 3 — InformationCore 保持完全不知道 SimiGo（确认项）

**human 已定向为硬规则（非选项）**：

```text
SimiGoRuntime → InformationCore ✓
InformationCore ─X→ SimiGoRuntime
InformationCore ─X→ SimiGo
```

## 4. 决策点 4 — SimiGo2Experimental 是否接入

| 选项 | 内容 |
|---|---|
| (a) | 本 Gate **不接入** SimiGo2Experimental（零改动）；仅决策点 1 选定的 target 消费 InformationCore |
| (b) | SimiGo2Experimental 同步接入 |

记录者预分析：(a)——最小边界原则；SimiGo2Experimental 的记忆
消费是后续真实需求出现时的事。**待裁**。

## 5. 决策点 5 — path dependency 在正式接入阶段的去留

| 选项 | 内容 | 依据/风险 |
|---|---|---|
| (a) | 保留本地 path dep（SimiGoRuntime → ../../../SimiGo-Lab）并**提交** | 本地立即可用；但路径绑机器，推送到 SimiGo origin 后他机/CI 破坏 |
| (b) | **现在执行 3.2(ii) 迁移**：(b1) url 引用 SimiGo-Lab 仓（mlx 已是共同依赖且同 revision，依赖图合并风险低；但版本耦合重、拉全 Lab 包）或 (b2) **InformationCore 拆独立包**（最干净；此前 3.2 裁定「后续转 (ii) 不改语义契约」——现在正是那个「后续」） | (b2) 是正式接入最干净的终态；(b1) 是低工作量过渡 |
| (c) | 过渡混合：本地 path dep **不提交**（或标注本地覆盖），(b) 迁移登记为紧随的独立小 Gate | 避免 (a) 的机器绑定入库；多一次 Gate 往返 |

记录者预分析：(b2) 为正式接入终态最干净；(c) 为零风险的节奏
保真方案（本 Gate 先用未提交本地 path dep 完成 A1–A10，迁移
(b2) 另立小 Gate）。**待裁**（含 (b1)/(b2) 子项）。

## 6. 硬边界与负空间

```text
SimiGoRuntime → InformationCore ✓（单向）
InformationCore ─X→ SimiGoRuntime / SimiGo
InformationCore 五保护文件 diff = 0
RelationCore 全文件 diff = 0
```

禁止作为正式接入语义：palace/MemPalace、SQLite/Physical Filing、
taxonomy、activation、Diary、retrieval/ranking、ExecutionState
语义进入 InformationCore、MemoryCore/Adaptive Memory Budget、
T4 实验逻辑。

**防混淆声明**：SimiGoRuntimeContract 既有
ExecutionStateBackendContract / ExecutionContinuityContract /
RuntimeBackendContract 零改动——本 Gate 只新增 InformationStore
接入，不触其语义（ExecutionState 语义仍在负空间）。

## 7. 验证目标（human A1–A10 照录 + 证据方式）

| 项 | 必须证明 | 证据方式 |
|---|---|---|
| A1 | SimiGoRuntime 可编译并消费 InformationCore | swift build 全包（含 MLX 图） |
| A2 | runtime 层实际经 `InformationStore` 完成记忆边界访问 | 消费代码审计 + 实跑（或最小调用链） |
| A3 | InformationCore 无反向依赖 | 双向符号/import 审计 |
| A4 | SimiGo 上层无需知道 SQLite/Physical Filing | 消费层源码零 backend 符号（剥离注释审计） |
| A5 | 既有 contract / execution semantics 零变化 | Contract 三文件 + SimiGo2Experimental diff = 0（或仅依赖声明变更）+ 既有测试零回归 |
| A6 | Information/Relation 语义不被重新解释 | 语义类型零 diff；消费层零包装/重解释层 |
| A7 | pre-research P1–P4 在正式 runtime 形态保持 | 同构审计（预研与正式形态结构对照） |
| A8 | SimiGo 主运行链现有测试零回归 | SimiGoTests 实跑（如环境可执行）+ 结果登记 |
| A9 | 保护文件 diff = 0 | git diff 审计 |
| A10 | 无新开放语义进 Core | 声明级负空间审计 |

## 8. 允许修改范围（按裁定分档）

```text
SimiGo 仓：SimiGoRuntime/Package.swift（依赖接线）+ 决策点 1
           选定 target 的新增文件；（b2) 档另涉 InformationCore
           包拆分——须作为裁定一部分显式登记
SimiGo-Lab 仓：受保护文件 diff = 0；（b2) 档的拆分改动按裁定登记
```

## 9. Pass / Fail

- **PASS** = 决策点 1–5 封存 + A1–A10 全过 ⇒ 登记
  `SimiGoRuntime × InformationCore = FORMAL INTEGRATION PASS`
- **FAIL** = A5/A6/A9 任一不成立，或接入需改动受保护文件/语义
  ⇒ 停止、登记、重开裁定

## 10. 推进方式

human 对决策点 1–5 裁定（可整批 + 改动点）→ 封存 → 最小实现 →
A1–A10 验证 → 收口 → 整链推送。**Spec 阶段零代码。**
