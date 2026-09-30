# ES-R2 Research Design — From Partial Formation to Representation-Independent Reuse

日期：2026-09-30  
状态：`ESR2_RESEARCH_DESIGN_LOCKED / GATE_A_AWAITING_EXECUTION_APPROVAL`  
前序：ES-R1 SEALED（R1-B FINAL：无独立 durable runtime State 可复用）；
ES-D1 SEALED（J-C CONFIRMED：partial formation，gap 定位于 checkpoint
commit boundary）  
研究计划权威：human（本会话）  
性质：研究设计冻结——Gate A 执行待批准；非 schema 设计、非产品实现

## 1. 研究问题（锁定）

> **补足 checkpoint durable boundary 中缺失的 Computational State 形成
> 条件后，是否能够产生真正独立于 Physical Representation 的 Execution
> State Reuse？**

明确：**不是实现一个 State 功能**——首先验证一个因果命题。

## 2. 因果假设（锁定）

```text
ES-D1 已知：checkpoint → partial formation → Representation + History
            → 无独立 State → ES-R1：表示丢失 → cold reconstruction

ES-R2 检验：若 Formation Gap 被最小化补上
  → Durable Computational State 产生
  → Representation 删除
  → State 仍然存在
  → 新 Representation
  → 继续执行
  → 无需完整 History + full cold prefill
```

## 3. Gate 结构（A→B→C→D→Seal；逐门独立裁定；禁止跨门补实现）

### Gate A — Formation Minimality

问题：在 ES-D1 发现的 checkpoint formation boundary 上，需要什么**最小
信息**才能使 partial formation 成为独立 Computational State？
目标 = **Formation Sufficiency Boundary**，而非 `ExecutionState {...}`。

边界与纪律：

```text
✔ 只允许使用 ES-D1 已观察到的信息：identity / position / continuation /
  lineage / history / 已存在 checkpoint lifecycle
✔ 实验 fixture / synthetic carrier 允许（表达「若 boundary 捕获了某个
  已存在的事实会发生什么」）
✔ 不修改生产代码
✘ 不凭空增加完整 State schema
```

### Gate B — State Survival（全课题最重要实验）

复刻 ES-D1 双进程实验，加入**实验性 formation carrier**：

```text
Control    checkpoint → P + History → process death → P loss
           → cold reconstruction
Treatment  checkpoint → P + History + experimental State carrier
           → process death → P loss → inspect State
```

问题：「Representation 消失以后，State 是否仍然**存在**？」——不是
「能不能重新算出来」，而是**有没有东西真正活过了 Representation**。
B 失败 ⇒ ES-R2 立即停止（后续 rematerialization 无科学意义）。

### Gate C — Re-materialization（仅 B 成功进入）

问题：无原始 P 的 Durable Computational State 能否生成新 Representation？
首次真正测试 **S → R'**（ES-R1 已证只有 H → R'）。

严格对照：

| 路径 | 输入 |
|---|---|
| Cold | History |
| State reuse | State |
| Restore | 原 Representation |

**硬禁止**：State reuse 路径不得读取完整 History，不得读取旧
Representation——否则实验失去意义。

### Gate D — Semantic Reuse（仅 C 成功进入）

```text
R1 → State S → R1 删除 → S → R2 → continue
Baseline: R1 → continue → O1
Reuse:    R1 deleted → S → R2 → continue → O2
```

第一目标 = **O1 与 O2 的 continuation semantics 等价**。不是速度、不是
内存、不是 benchmark。

## 4. Formation Minimality 实验边界（Gate A 细化）

```text
输入全集（ES-D1 已观察）= identity / position / continuation / lineage /
                          history / checkpoint lifecycle 事件
载体形态               = fixture 内 synthetic carrier（表达「boundary 若
                          捕获已存在事实」）；不触生产代码
裁定产出               = Formation Sufficiency Boundary（最小信息集 +
                          其充分性证据），逐项标注 derived/duplicate
```

## 5. State Survival 双进程实验（Gate B 细化）

```text
T0 computation → T1 R exists → T2 R released → T3 process restart
→ T4 R absent → T5 candidate queried
防陷阱：「文件还在」≠ State 存在——须证明 durable artifact 是计算状态
的 authority，而非 History 副本或 Representation metadata
```

## 6. S→R' 判定条件（Gate C 硬判据）

```text
full history read       = NO（硬条件）
old Representation used = NO（硬条件）
new Representation made = YES
same ExecutionID        = YES
same logical position   = YES
```

## 7. Semantic equivalence 判据（Gate D）

```text
P1 强证据：确定性环境 O1 == O2（R2n P-N1 已确立贪心确定性先例）
P2 弱证据：非确定环境下 semantic continuation equivalent——判定规则
          须在执行前明确（锚词/指代存活判据沿用 E3 先例）
四项底限：identity SAME / position SAME / lineage 连续 / continuation valid
```

## 8. 预注册结果（六选一，不得事后改标准）

```text
R2-A FORMATION-SUFFICIENT
R2-B STATE-SURVIVES-BUT-NOT-REMATERIALIZABLE
R2-C REPRESENTATION-INDEPENDENT-REMATERIALIZATION
R2-D SEMANTIC-REUSE-CONFIRMED
R2-E FORMATION-INSUFFICIENT
R2-F INCONCLUSIVE
```

## 9. 禁止事项

```text
❌ 修改生产代码 / 创建 State object / schema / 新增持久化 / 新增 API
❌ 为证明 State 存在而人为制造 State
❌ 重开 ES-R1 C-4
❌ 性能实验（1–5 步全部成立后「消除 cold prefill」才成为可定量问题）
❌ backend takeover（ES-R3，研究依赖未满足）
❌ full-history 读取冒充 State reuse / 旧 Representation 复用
❌ 破坏真实 ~/.simigo（全程 fixture）
```

## 10. Seal 条件

```text
Gate D 完成且结果归类（R2-A…R2-F）→ ES-R2 Seal 文档 → 研究链
R1（不可复用之因）→ D1（formation gap）→ R2（formation→reuse 验证）
闭合；性能经济与 ES-R3 backend takeover 另行 gate。
```

## 11. 实验对象与环境

```text
State  = 已验证真实 checkpoint 5401315f（PB1 确定性基线在案；
         baseline fixture 双文件完整、SHA 已验）
环境   = Nail-Qwen3.6-35B-A3B-MLX（HF cache 在位）；隔离配方沿用
         （SIMIGO_PREFIX_POOL=0 TEST_RUNNER_ 转发 + conditionalRestore
         tunable off → 零 durable 写入；真实 ~/.simigo 只读）
进程边界 = 双 xcodebuild invocation（Gate B/C/D 各按需）
```

## 12. Gate 授权节奏

```text
本设计冻结 → Gate A 执行批准（human）→ A 完成 → 停（B 裁定）
→ B 批准 → …逐门推进；每门结果文档 + 预登记对照
```
