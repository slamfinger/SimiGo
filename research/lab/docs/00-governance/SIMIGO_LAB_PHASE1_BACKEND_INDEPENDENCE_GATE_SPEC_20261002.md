# Gate Spec — Phase 1: Persistence Replacement / Backend Independence Gate

Date: 2026-10-02  
Status: `GATE OPENED（SPEC 已登记；实现按本 SPEC 执行）`  
Baseline: `5b861c8`（Integration Boundary Gate = PASS）  
核心命题：**数据库是实现选择，而不是架构前提。**

## 1. 目的

证明 SQLite **可以被替换**（不是现在换掉它）：在不修改
Information 语义面、不修改 UpperLayer API 的前提下，第二种
`InformationStore` 实现可以直接接入并通过全链路。通过后形成
架构闭环：

```text
          Semantic Surface
                 │
                 ▼
        ┌─────────────────┐
        │ Information     │
        │ InformationStore│
        └────────┬────────┘
                 │ stable boundary
          ┌──────┴──────┐
          ▼             ▼
     SQLiteStore    Backend-2
          │             │
          ▼             ▼
     Physical       Physical
      Filing         Filing
```

## 2. 输入

已验收/已通过三件套 + Integration harness（`5b861c8` 及之前
全部封存件）；零新语义概念。Backend-2 = **Test/InMemoryStore**
（最小形态，归 harness 侧，不进 InformationCore 生产模块）。

## 3. 允许修改范围

1. 新增 `InMemoryStore.swift`（harness 侧；实现公共协议
   `InformationStore`；自带机制侧 minting——配方属各机制）
2. `main.swift` 扩展 Backend-2 链路（harness 文件，可改）
3. **diff = 0 硬约束**：`Information.swift` / `InformationStore.swift` /
   `UpperLayer.swift` 零改动；`SQLiteStore.swift` 不要求改动
   （实测亦应为 0）
4. Package.swift 零改动（InMemoryStore 入既有 harness target）

## 4. Invariants

| # | 不变量 |
|---|---|
| K1 | `Information.swift` diff = 0 |
| K2 | `InformationStore.swift` diff = 0 |
| K3 | `UpperLayer.swift` diff = 0 |
| K4 | `SQLiteStore.swift` diff = 0（未被要求修改） |
| K5 | Backend-2 实现 `InformationStore`（结构 conformance） |
| K6 | UpperLayer → Backend-2 全链路 PASS（同 UpperLayer 类型、零改动） |
| K7 | 语义 roundtrip PASS（同值相等） |
| K8 | absence = nil 且重复 store 幂等 PASS |
| K9 | SQLite 特有知识 = 0（Backend-2 与 UpperLayer 源码零 SQLite 符号） |
| K10 | 新语义类型 = 0（InMemoryStore 为 mechanism/test backend；Information 零新字段、协议面零新增） |

## 5. 验证方式

1. harness 双链路实跑（Backend-1 SQLite + Backend-2 InMemory，
   同一 UpperLayer 类型零改动驱动）
2. diff 审计（四文件 vs `5b861c8`）
3. 符号审计（Backend-2/UpperLayer 零 SQLite 符号；负空间声明级审计）
4. Build 零警告

## 6. Negative Space

同已封存清单全项禁止；另加：Backend-2 不得引入检索/排序/
删除/taxonomy/filing-入-语义等任何超出 `store + fetch` 的能力；
不预埋「真实持久化以后要用的」接口。

## 7. Pass / Fail

- **PASS** = K1–K10 全过 + Build 零警告 ⇒ 架构命题成立：
  「数据库是实现选择，而非架构前提」获结构证据
- **FAIL** = 任一 K 项需改动被冻结文件/语义才能过 ⇒ 停止、
  重开对应裁定，不静默修改
