# PALACE-1 Framing Registration

日期：2026-09-30  
状态：`REGISTERED / PALACE1_FRAMING_FIXED / LINE_PARKED`  
Registration authority：explicit human ruling（本会话）——「下一刀：Framing
Registration；它只做一件事：把已经被 E0–E3 证明、并经过 Evidence
Consolidation 封装的研究边界，登记成 PALACE-1 的正式 framing。注册完就停。」  
依据工件：Evidence Consolidation（`d408729`，六实验链 CLOSED）

## 1. Registered framing

```text
PALACE-1 framing

Observed:
    系统中存在两种生命周期不同的信息侧：

    A. durable semantic side
       └─ 当前 workload 中观察到的
          continuation-bearing information
          （addressing carrier = caller key
           semantic continuation carrier = conversation history，
           including tool-execution history）

    B. physical acceleration side
       └─ checkpoint / Prefix Pool 等
          可替换 physical representation

Research question:
    这种生命周期差异是否足以支持
    更高层的长期 Personal State Space 抽象？

NOT established:
    ├─ PALACE schema
    ├─ State object
    ├─ universal minimum nucleus
    ├─ storage architecture
    ├─ semantic absence solution
    └─ cross-backend semantic equivalence
```

## 2. Registered research findings

```text
RF-1  Semantic Absence Is Not Self-Evidently Detectable
      = REGISTERED / OPEN RESEARCH
      （现象已实验确立 E3-C-2；解决方案明确不在本登记范围）
RF-2  Restore dependency ≠ Continuation dependency
      = REGISTERED / CLOSED FOR THIS CHAIN
      （E1-R1 + R2-trace/R2n 已完整支撑本链所需）
```

## 3. Evidence chain freeze

```text
E0–E3 实验事实与 fact/inference/unproven 分层（Evidence Consolidation
d408729）自此冻结：后续任何 PALACE 讨论不得反向修改实验事实层；
nucleus 表述 = workload-scoped observed candidate（addressing carrier +
semantic continuation carrier，两 carrier 性质不同不合并；modelId =
外围 compatibility context）——该限定是登记内容的一部分。
```

## 4. Authorization boundary（本登记不做什么）

```text
❌ PALACE schema
❌ State object
❌ Contract 化（framing 不是 Contract；不触发 C-13 drift 语义）
❌ storage / persistence 决策
❌ RF-1 解决机制
❌ 下一实验的选择（NOT YET CHOSEN）
```

## 5. Gate state after registration

```text
PALACE-1 Evidence       = CLOSED（d408729 冻结）
PALACE framing          = REGISTERED（本文）
PALACE schema           = NOT STARTED
PALACE Contract         = NOT STARTED
RF-1                    = REGISTERED / OPEN RESEARCH
RF-2                    = REGISTERED / CLOSED FOR THIS CHAIN
Next experiment         = NOT YET CHOSEN
Current blocker         = none
```

PALACE-1 线至此停车：从「79GB 到底是什么」出发，以「工程中确实观察到
值得抽象的生命周期分离」收束。下一轮研究应寻找**另一个独立的工程问题**
（工程事实 → 问题 → 抽象 → Contract → 验证的路线保持不变）；当且仅当
未来工程事实需要消费本 framing 时，才从显式 gate 重新进入。
