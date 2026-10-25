# Gate Result — SimiGo × InformationCore 接入边界 Gate = PASS

Date: 2026-10-02  
Spec: `SIMIGO_LAB_SIMIGO_INFORMATIONCORE_INTEGRATION_GATE_SPEC_20261002.md`  
Decisions: `SIMIGO_LAB_SIMIGO_INTEGRATION_DECISIONS_SEALED_20261002.md`（3.1(c) / 3.2(i)）  
Status: `GATE = PASS / T4 EXPERIMENTAL PRECONDITION = SATISFIED（T4 仍 BLOCKED）`

## 1. 交付物

```text
pre-research/SimiGoShapedPreResearch/          # 独立 SwiftPM 包（Lab 侧）
├── Package.swift
│     // 3.2(i) 真实 path dependency → SimiGo-Lab 根包，
│     // 消费 product InformationCore（非复制伪接入）
└── Sources/SimiGoShapedExecutor/
    ├── Executor.swift
    │     // SimiGo-shaped 冷启动执行者（P3 结构证明层：
    │     //   仅 import InformationCore，仅绑定 any InformationStore）
    └── main.swift
          // 组合根（唯一 backend 感知处）+ P1/P2 + S1–S6 runner
```

SimiGo 主仓**零改动**（3.1(c) 硬约束保持）。

## 2. P1–P4 读数

| # | 必须证明 | 结果 | 证据 |
|---|---|---|---|
| P1 | 可运行冷启动执行者 | ✅ | 独立进程实跑；fresh DB、零持久化历史；执行者仅携带 InformationCore 边界 |
| P2 | S1–S6 形状复现 | ✅ | S1 new persist / S4 present 同值 / S5 absent nil / S2 same no-op 确认 / S3 conflicting no-op first-write-wins——全 PASS |
| P3 | 上层零 SQLite/Physical Filing 知识 | ✅ | Executor.swift 剥离注释后 backend 符号 0 命中（2 处命中 = P3 不变量自述注释，处置在案） |
| P4 | 零反向依赖 + 零外部语义 | ✅ | 依赖面 = 仅 SimiGo-Lab path 一项；InformationCore/RelationCore 代码层零 simigo 引用（2 处命中 = 治理文件名注释，处置在案）；零 palace/taxonomy/activation/ExecutionState/Relation 声明 |

**跨包真实性**：path dependency 解析成功（真实外部包图，含根包
全量依赖解析），非复制伪接入——module/protocol 边界由 SwiftPM
物理表达。

## 3. Gate 判定

**PASS** —— P1–P4 全过 + Build 零警告 + 保护条件全满足
（InformationCore 受保护文件 + RelationCore 全文件 vs HEAD diff
= 0；pre-research 零负空间声明）。

⇒ 登记结论（human 定向措辞）：

```text
SimiGo + InformationCore
        ↓
T4 experimental precondition = SATISFIED
```

**T4 本身仍然 BLOCKED**——实验方案/执行需单独 human 指令。

## 4. 实现内决策（登记，可重开）

1. Executor/main 双文件分工：消费层（P3 零 backend 符号）与组合
   根（唯一 backend 感知处）分离——I6/I8 同构
2. 冷启动 = fresh DB + 零持久化历史的新进程（P1 的 pre-research
   级定义；T4 正式定义仍待其专门 Gate）
3. S3 冲突探针纳入 pre-research 首轮（直接复现 S3 first-write-wins）

## 5. 未变项

Phase 0 = FROZEN；Phase 1 = CLOSED；Phase 2 = CLOSED（RelationCore
ACCEPTED）；Y/D 列封存不变；负空间全项延续；InformationStore
S1–S6 与 RelationStore R1–R6 契约不变。
