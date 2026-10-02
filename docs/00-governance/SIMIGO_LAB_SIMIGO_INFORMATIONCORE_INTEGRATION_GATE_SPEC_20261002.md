# Gate Spec — SimiGo × InformationCore 接入边界 Gate（仅 Spec，零实现）

Date: 2026-10-02  
Status: `GATE OPENED（SPEC 已登记；决策点待 human 裁定）`  
位置：Phase 2 CLOSED 与 T4 资格之间的**接入边界确认 Gate**  
纪律：T4 = BLOCKED（本 Gate 通过最多登记
`T4 experimental precondition = SATISFIED`，不执行 T4）

## 1. 目的（唯一窄问题）

> **SimiGo 是否能够以 `InformationCore` 作为记忆边界，在不把
> palace 机制、SQLite 机制或未来 taxonomy/activation 等开放语义
> 带入 Core 的情况下完成接入？**

不是把 InformationCore 塞进 SimiGo 就完事，也不是证明 T4 成功；
通过后只登记：

```text
SimiGo + InformationCore
        ↓
T4 experimental precondition = SATISFIED
```

## 2. 现场事实（2026-10-02 只读勘察）

```text
SimiGo 仓（main @ a90e391）
├── SimiGo.xcodeproj          # Xcode 应用工程
├── SimiGo/                   # 应用源码：App / Inference / Lifecycle /
│                             #   Model / Observability / Protocol / System
├── Packages/SimiGoRuntime/   # 本地 SwiftPM 包
│   └── 库：SimiGo2Experimental / SimiGoRuntimeContract
└── SimiGoTests/

SimiGo-Lab 仓（本仓）
└── trackD-memory/Sources/
    ├── InformationCore/      # 已验收（Information/InformationStore/SQLiteStore，S1–S6）
    └── RelationCore/         # 已验收（Relation/RelationStore/R1–R6）
```

两仓分离，InformationCore 目前**未被 SimiGo 任何层引用**。

## 3. 四个验收重点（human 定向）→ 决策点

### 3.1 接入边界（哪一层能看到 Information / InformationStore）

| 选项 | 内容 | 影响 |
|---|---|---|
| (a) | SimiGoRuntime 包内新建薄 target（如 `SimiGoMemoryBoundary`），仅 import InformationCore，向上暴露记忆边界服务 | runtime 层获记忆能力；App 层经 runtime 间接使用；边界层次清晰 |
| (b) | 仅 App target 接入（Xcode 侧直接引 InformationCore） | 最浅；但记忆能力绕过 runtime 包，App 层耦合语义核心 |
| (c) | **Lab 侧预研形态**：SimiGo-Lab 内建 SimiGo-shaped 消费者（镜像 SimiGoRuntime 的调用形态）验证边界，SimiGo 主仓零改动；真实接入后置单独 Gate | 接入预研最小形态；T4 precondition 证据先在 Lab 侧成立 |

记录者预分析：若本 Gate 目标是「预研 + T4 precondition」，(c) 为
最小形态；(a) 是真实接入形态，可作为本 Gate 的实现段或下一段。
两者不互斥：(c) 先行 → (a) 后置。**待裁**。

### 3.2 依赖方向与跨仓策略

**硬规则（非选项）**：SimiGo → InformationCore，绝不
InformationCore → SimiGo；InformationCore/RelationCore 受保护
文件 diff = 0。

| 选项 | 跨仓策略 | 风险 |
|---|---|---|
| (i) | SwiftPM **path dependency**（SimiGoRuntime → SimiGo-Lab） | 本地开发期最快；路径绑机器，不可推送为主依赖 |
| (ii) | InformationCore 独立成 git 包（或以 tag 引用 SimiGo-Lab 子目录产品） | 干净、可推送；需先做包拆分决策（新 Gate 或本 Gate 实现段） |
| (iii) | vendored 复制源码进 SimiGoRuntime | 有双源漂移风险，违反单一事实源纪律，**不推荐** |

若选 3.1(c)，跨仓策略整体后置（Lab 内零跨仓）。**待裁**。

### 3.3 语义不泄漏（双向）

```text
禁止注入 Information（SimiGo 侧）：
  Execution State / palace 机制状态 / WAL / 物理 filing / taxonomy /
  activation / diary / 任何 SimiGo 业务语义字段

禁止流入 SimiGo（Core 侧）：
  InformationCore/RelationCore 不得 import SimiGo；
  Core 不得感知 Execution/Lifecycle/Inference
```

验证 = 双向符号审计 + 受保护文件 diff = 0 + 负空间声明审计。

### 3.4 T4 前置资格清单（Gate PASS 时逐项登记）

```text
T4-P1  冷启动执行者可用（fresh 会话/进程，无历史沉淀）
T4-P2  Information 边界在 SimiGo 环境可 store/fetch（S1–S6 形状可复现）
T4-P3  上层对 backend 零知识（替换不触上层，I8 同构）
T4-P4  语义面零泄漏（3.3 双向审计通过）
⇒ 全满足 = T4 experimental precondition = SATISFIED（仅登记资格，
  T4 实验方案/执行仍需单独 human 指令）
```

## 4. 允许修改范围（按 3.1 裁定分档）

- (c) 档：Lab 内新增 harness target/文件 + Package 接线；SimiGo 仓**零改动**
- (a) 档：SimiGoRuntime 新增薄 target + 依赖接线；Lab 仓零改动
- 任何档：受保护五文件 + RelationCore 全文件 diff = 0

## 5. Negative Space（human ❌ 清单全项）

❌ T4（本 Gate 只登记资格）❌ taxonomy 裁定 ❌ diary schema
❌ activation 形状 ❌ KG 自由端点入 RelationCore ❌ retrieval/
ranking ❌ 重建 palace ❌ 决定 SQLite 最终 backend ❌
MemoryCore（Adaptive Memory Budget）与本线合并——
`trackD-memory/README.md` 的自适应内存线与本 Gate 正交，且该
README 与 InformationCore 落位存在目录语义分叉（已在全景中
提醒），本 Gate 不处理。

## 6. Pass / Fail

- **PASS** = 按 3.1 裁定档完成最小实现/预研；3.3 双向审计通过；
  受保护文件 diff = 0；T4-P1…P4 逐项登记结论
- **FAIL** = 接入需触碰受保护文件/引入负空间/依赖方向倒置
  ⇒ 停止、登记、重开裁定

## 7. 推进方式

human 对 3.1 / 3.2 裁定（含 (c) 先行与否）→ 裁定封存 → 按档
最小实现 → 审计与实跑 → Gate 收口 → 证据链成段推送。
**Spec 阶段零代码**。
