# Research Dependency Map

**Purpose:** 明确“哪些研究依赖哪些前置问题/知识”，防止关闭一个问题后自动推导出另一个问题已被回答。

## 1. Main research chain

```
Execution State (Track B)
        ↓
Residency / policy
        ↓
P3
        ↓
H-P1
        ↓
nodes-out
        ↓
Track E CLOSED
        ↓
P4 (independent future question)
```

该链表达历史研究顺序与知识承接，不表示下游问题自动继承上游结论。

## 2. Current definition chain

```
Research Object
   ↓
Research Question
   ↓
Independence
   ↓
Estimand
   ↓
Existence Criterion
   ↓
Insufficiency / Negative Criterion
   ↓
Discriminating Power
   ↓
Information Value / Cost
   ↓
Path / Harness / Experiment
```

当前已通过 STEP④；STEP⑤尚未开始。

## 3. Independent branches

```
Track A  Kernel/Bandwidth
   └── exp06 roofline gate

Track D  Adaptive Memory
   └── independent definition / validation

Track C  Multi-device
   └── hardware + independent definition

Source/Runtime
   └── current Definition / Opening gate
```

这些分支不能因为共享硬件、模型、工具或历史结果而自动合并。

## 4. Agent rule

当 Agent 发现一个“看起来已经被以前研究回答”的问题时，必须先检查：

- 是否为同一个 RQ；
- 是否使用同一 estimand；
- 是否处于同一 observation domain；
- 是否有合法 provenance；
- 是否存在 endpoint 对下游引用的明确授权。

否则按“相关历史证据”处理，而不是“当前问题已回答”。
