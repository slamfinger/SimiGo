# ES-R2 Gate C Results — Re-materialization Attempt (S → R')

日期：2026-09-30  
状态：`GATE_C_COMPLETE / VERDICT = C-2 (STATE SURVIVES, NOT REMATERIALIZABLE) + C-3 IMPLICATION REGISTERED / GATE D LOCKED`  
唯一问题：**脱离 Physical Representation 生命周期并跨进程存活的
Computational State，能否在没有旧 Representation、也没有完整 History
的情况下重新物化出新的 Representation？**  
硬约束核验（实验环境真实缺席，非「不主动读取」）：

```text
C 空间 = { state-carrier.json } 仅此一文件
  ✓ old P 缺席（无 safetensors）
  ✓ full History 缺席（无 meta.json——transcript 只存在于 meta）
  ✓ S = 唯一 computational input（环境常量仅模型权重 + probe 文本）
  ✓ 真实 store 204 项前后核验不变（零 durable 写入）
```

执行：`Palace1ESR2GateCRematerializationTests.swift`（加法式）；19.2s；
TEST SUCCEEDED；观测 `gateC-observations.jsonl`（已落库）。

## 1. 两次物化尝试（实测）

```text
Attempt 1  既有 P→R seam（loadSessionCache 指向 C 空间）
  → FAILED：NSCocoaErrorDomain Code=260「…meta.json…no such file」
  → reading：唯一的 P→R seam 需要 meta+safetensors；carrier 无法替代
    任一输入

Attempt 2  唯一免 history 的会话创建路径（仅 probe 文本可供给）
  → 会话被创建于 position 2（probe+assistant），而非 State 的
    position 17(→18)
  → 模型响应逐字：「请提供具体的上下文或任务指令，以便我继续执行。」
  → reading：无 History/旧 P 时，系统只能创建 position ~1 的新执行——
    State 的 position(17) 与 continuation 无法被 honoring；
    position 17 的 R' 从未形成
```

## 2. R' 存在性核验

```text
C 空间 artifacts after = state-carrier.json + 观测文件——零新表示工件。
「R' 非旧 P 残留」的证明形式 = R' 根本未形成（无任何表示产物产生）。
```

## 3. 裁定

```text
VERDICT = C-2 — Tier-1 State 存活，但无法 S→R'
  （State existence 与 State executability 由运行时实验正式分离：
   同一 carrier，Gate B 证其【存在】（identity/position/anchor 跨边界
   权威存活），Gate C 证其【不可操作】（无物化入口、无上下文承载））

C-3 含义登记（非设计）：S→R' 若要可能，需要一个【compressed context
  carrier】——当前观察宇宙中不存在（唯一的压缩物 = per-token KV 本身
  = P）。这是 FSB-2 预言的实验证实：Tier-1 Formation Sufficiency ≠
  Operative Rematerialization Sufficiency。
```

## 4. 附带观测（诚实记录，不外推）

Attempt 2 的模型响应与 E3-C-2 形成对照：E3-C-2（有 persona 丰富的
system prompt）→ 虚构概述（RF-1）；Gate C attempt 2（无 system、仅
probe）→ 明示要求上下文。两种「语义缺席」场景行为不同——persona 上下
文的存在与否改变失败模式。登记为观察，不外推。

## 5. Non-claims

```text
✔ C-2 限于 Tier-1 carrier + 当前系统 + 单样本
✔ 未把 attempt 2 的「新会话」误认成 State 的 rematerialization
✔ 未扩大 Tier-1 carrier；未加字段/reader/API；C-4 续锁；Gate D 锁定
✔ 零 durable 写入；模型权重 = 环境常量（非旧 P）
```
