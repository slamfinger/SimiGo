# SimiGo-Lab Execution State 证据链收束综合 — 2026-10-01

日期：2026-10-01
状态：`CONSOLIDATION DELIVERED / AWAITING HUMAN REVIEW`
任务令：human 2026-10-01（阶段转向：`P4 replication evidence →
P5 边界/解释 → Execution State 证据链收束`；P5-1 终态 =
protocol-valid INCONCLUSIVE）
性质：**只读综合，零新实验、零新理论**。本文档把当前已在案证据组装
为一条证据链，标注层级与未封口缺口；不产生新命题，不重跑任何实验。

---

## 0. 方向纪律（阶段裁定，约束后续一切工作）

1. **layered loading 只是 Execution State 的辅助证据**——研究重心
   放在 layer 本身会偏离 SimiGo 核心问题；不再堆 layer loading
   实验（与 2026-09-27「小规模是根基」裁定、Research Line Reset
   「Backend 管怎么继续计算、SimiGo 研究从哪里继续计算」一脉相承）。
2. 不回到：继续完善 P4 harness / 再证明一次 fork 是否存在。
3. 收束 = 组装已有证据 + 诚实标注缺口，不是补实验凑结论。

## 1. 证据链总图（按 human 指定三段）

```text
【第一段：Runtime 正确性层（产品工程线）】
  D1 runtime consistency → discard/release atomicity → INV-3 reconcile
  → C_model 校准 → GA-0 Floor policy → Cancellation → Token Ledger
  ⇒ 语义：日常路径的 ES 机制工程事实（真机验证）
        │
        ▼
【第二段：拓扑层（P4 replication evidence）】
  P4 Common Base topology = 机械判读 PASS + 复制 PASS
  ⇒ 语义：「S₀ 可作为多个未来计算分支的共同基点」（拓扑级）
        │
        ▼
【第三段：边界/解释层（P5 boundary/explanation）】
  P5-2-0 Continuation Dependency Map（10 依赖分类 + rebuild 根因路径）
  P5-1 protocol-valid INCONCLUSIVE（anchor-failure→rebuild 边界在
    合格样本 S2′ 复制；S1 定位样本资格问题）
  样本资格条件（新登记）：KV representation 必须能被对应 transcript 解释
  P5-4 L1（原跑）：{I,P,A,C} 独立不可替代；PA-2：Position≠Semantic Anchor
        │
        ▼
【收束对象：Execution State 总体论证】＝ 尚未最终封口
```

## 2. 证据地图逐项登记（human 直录 + 来源分级）

来源分级：**[H]** = human 证据地图直录（本轮未逐条重验）；
**[P]** = 产品仓工程线在案产物；**[R]** = Lab 研究线已登记产物
（带 Lab commit 锚）。

| # | 层级 | 条目 | 状态 | 来源 | 它支持什么 / 不支持什么 |
|---|---|---|---|---|---|
| 1 | Runtime | Runtime consistency / D1 | 已批准并实现 | [H] | 日常路径 ES 语义一致性有工程实现；不支持任何跨 backend 普适宣称 |
| 2 | Runtime | discard / release atomicity | 已修复 | [H][P] | 状态边界缺陷已修（26e9ad1 线）；不支持性能/普适性 |
| 3 | Runtime | INV-3 reconcile | PASS | [H][P]（L4-B 250f683 五模型对账在案） | 契约-实现 reconcile 成立；不构成 State 定义 |
| 4 | Runtime | C_model | 已校准 | [H][P] | 校准常数恒定；不构成行为预测 |
| 5 | Runtime | GA-0 Floor | policy 已明确 | [H][P]（floor>0 停用 b2da1f5/1422328，重设计列 GA） | 政策边界清楚；不构成 ES 证据 |
| 6 | Runtime | Cancellation | E2E PASS | [H] | 真机取消路径可用；不构成 ES 证据 |
| 7 | Runtime | Token Ledger | 95/95 + true-device PASS | [H][P]（07b210d/741da68 时代收束；当时记录为 100/100——**数字分歧已登记待核**） | authority 闭包对账成立；不构成跨 backend 宣称 |
| 8 | 拓扑 | P4 replication | 机械判读 PASS | [R]（Lab 2edc701；J1..J6 两样本；换序 8/8 逐字；S1 输出与原跑逐字同） | 「S₀ 可作为多个未来计算分支的共同基点」拓扑级成立（样本类内）；不涉性能（D8）、不含模型维度（Sample-3 gap） |
| 9 | 拓扑 | P4 human second layer | 保留 | [H] | P4 终判未发出——链条上游仍开放 |
| 10 | 拓扑 | P4 Sample-3 | coverage gap | [H][R] | 模型维度诚实登记，不伪装已覆盖 |
| 11 | 边界 | P5-1 replication | **protocol-valid INCONCLUSIVE**（终态） | [R]（Lab fea3f14；s2′ PASS 0.977-vs-0.000；S1 样本资格问题定位） | anchor 对齐断裂→rebuild 边界在合格样本复制成立；KV=Representation fragment 直接再观测；**不支持**「KV 单独不必要」的普遍否定（attempt-1 即如此限定） |
| 12 | 边界 | 样本资格条件（新概念） | 已登记 | [R] | 对照实验的样本准入条件；本身是方法论产出非 ES 命题 |
| 13 | 边界 | P5-2-0 Dependency Map | 在案 | [R]（10 依赖 D/R/P/O/T 分类 + rebuild 根因路径） | 机制解释层；ES=约束关系集的 backend 级表述 |
| 14 | 边界 | P5-4 L1 / PA-2（原跑） | 在案（未入本轮复制复核） | [R] | {I,P,A,C} 独立不可替代；Position≠Semantic Anchor；证据级=原跑，未复制 |
| 15 | 概念 | P6 FROZEN | Conceptual Boundary | [R] | ES=「minimal relation closure that preserves computational continuity」；冻结名=MLX-based 非 Universal |
| 16 | 总体 | **Execution State 总体论证** | **尚未最终封口** | [H] | ——收束对象本身 |

## 3. 当前证据链实际能说的（三层分离，逐条带非声明）

1. **工程层**：SimiGo 日常路径已有一套经真机验证的 ES 机制
   （一致性/原子性/reconcile/取消/token ledger）——说「机制在运行」，
   不说「机制等价于 Execution State 定义」。
2. **拓扑层**：在两样本类上，「一个已形成的计算状态可作为多个未来
   计算分支的共同基点」拓扑级成立且复制成功——不涉性能、不含模型
   维度、P4 second layer 保留中。
3. **边界层**：ES 不是任何单一对象（KV/history/metadata）；在本
   backend 上 continuation 受 anchor-alignment 约束，KV 是
   Representation fragment；最小关系集候选 {I,P,A,C} 且 Position
   ≠Semantic Anchor——全部为 backend 级/样本级证据，不升格为
   普适定义（普适化 = OP-6-1/6-2 开放）。

## 4. 未封口缺口清单（收束 = 对下列各项逐一裁定，非补实验）

| 缺口 | 性质 | 封口需要什么 |
|---|---|---|
| G-α P4 human second layer | human 终判 | human 对 P4（含复制结果）发终判——保留中 |
| G-β Sample-3 模型维度 | coverage gap | 第二模型可用时按同判据补样本；或明示永久边界（登记即可封） |
| G-γ P5-1 S1 | INCONCLUSIVE 终态 | 无需行动——protocol-valid INCONCLUSIVE 即终态；样本资格条件已登记 |
| G-δ P5-2-C / P5-4 原跑未复制 | 复制计划 Day3-5 未消费 | human 裁定：按收束模式以原跑证据级引用（标注未复制），或择一补复制 |
| G-ε Token Ledger 数字分歧 | 记录核对 | 95/95（human 地图）vs 100/100（0741da68 时代记录）——核对后钉死 |
| G-ζ 总体论证措辞 | 综合定义门 | 把 §3 三层写成一段可引用的「Execution State 证据链论述」，明确「已确立/有界开放/明确不做」三栏——这是封口的最后一笔，属定义/综合门，归 human 授权后执行 |

## 5. Non-claims（本综合不改任何既有边界）

- 不重启 T3/PALACE/oversized/layer-loading；不写 C-0 的 C；
- P4/P5-1 判据零修改；P6 冻结名维持 MLX-based 非 Universal；
- 全部「已确立」表述限定在样本类与 backend 内；性能主张继续缺席
  （D8）；
- [H] 级条目本轮未逐条重验，收束引用时保持来源标注。

## 6. 下一步（归 human）

1. 审阅本综合文档；
2. 对 §4 缺口逐项裁定（G-α/G-δ/G-ζ 为封口主路径；G-γ 无需行动；
   G-β/G-ε 为登记/核对级）；
3. 若授权 G-ζ：进入总体论证措辞的定义/综合门（产出后走外审）。
