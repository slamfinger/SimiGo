# Execution State 论证收束矩阵 — Claim → Evidence → Replication → Boundary

日期：2026-10-01
状态：`MATRIX DELIVERED / AWAITING HUMAN READING（G-δ 是否值得继续由
本矩阵被阅读后裁定，不自动进入）`
任务令：human 2026-10-01（四缺口终验收已给出：G-α CLOSED/G-β
EXECUTED-INCONCLUSIVE/G-δ CRITERIA FROZEN-OPEN/G-ε CLOSED；下一步
「直接起草 Claim→Evidence→Replication→Boundary 收束矩阵，G-δ 暂时
不跑」；要求=真正的论证收束矩阵，非普通总结文档，正式文档不给
评价式分数）
性质：把每一句最终可说的话逐句钉到证据上。零新实验；本矩阵不自动
触发任何后续实验。

---

## 1. 收束矩阵

| Claim | Evidence | Replication | Boundary |
|---|---|---|---|
| **A. KV ≠ ES**（保存 KV cache 不等于保存状态） | P5-1 封存记录（protocol-valid INCONCLUSIVE）+ P5-2-0 rebuild 根因路径（ledger bootstrap 要求 processedTokenCount ≤ rendered prompt tokens） | **P5-1 replication**（Lab fea3f14）：S2′ 对照成立——baseline 消费 KV（cacheHit=1425，cacheEff 0.977/0.979）vs treatment 拒绝（cacheHit=0，cacheEff 0.000）；S1 = INCONCLUSIVE（样本资格问题定位） | MLX backend；对齐条件成立的前提下；**S1 不被当作失败**——它是「transcript 无法解释自身 KV」的样本资格反例，不构成对该命题的反证 |
| **B. 计算连续性依赖关系集**（computational continuity depends on relations，非单一物理载体） | P5-2-C（Backend Dependency Closure VALIDATED）+ P5-4（Minimal Dependency Set L1：{I,P,A,C} 独立不可替代；PA-2：Position≠Semantic Anchor——KV 载计算状态但 rendered history text 决定语义上下文） | **尚未复制**（原复制计划 Day3-5 未消费；证据级=原跑，引用时必须带「未复制」标注） | 当前 MLX；破坏任一关系的后果形态=reject/rebuild/semantic loss/continuation failure（四形态在案）；D7：不归因 KV/内部机制 |
| **C. 候选语义关系闭包 = {I,P,A,C}**（经 G-δ closure revision 修正） | P5-4 L1（破坏性实证，原跑）+ P5-2-C + **G-δ（Lab 659ebf8）：I·A·C necessity evidence（llama.cpp 关系级 leave-one-out）+ P=COMPENSATED 载体依赖**；概念边界=P6 冻结（「minimal relation closure that preserves computational continuity」；冻结名=MLX-based 非 Universal） | **两层定义（human closure revision 2026-10-02）**：ES_semantic={I,P,A,C} 保留；ES_representation(R)=各关系独立编码需求随 R 变化——llama full-prefix：P ∈ Derivable(A,R)；MLX KV：P ∉ Derivable(A,R) [S1] | **minimality 表述上限**：「candidate closure with experimentally supported necessity of each relation」中 I/A/C 成立、P 为 carrier-dependent irreducibility；「从 transcript 全量重算」仍排除于推导空间；数学最小性不可宣称；正式化（G-δR）待 human |
| **D. ES 可跨进程保持未来计算连续性**（ES survives process boundary） | P7-R2-A MLX：真实 checkpoint→进程退出→reload→KV 命中→extend continuation（C1 identity/C2 pos/C3 anchor/C4 prefix_is_extension 全 PASS，cacheHitTokens>0） | P7 证据按原跑（Day5 复制未消费；引用带标注） | MLX 产品运行时路径 validated（**validated 一词限此**）；llama.cpp=P7 harness 真实续算运行（非产品服务器路径、非同等级）——**两 backend 等级差保留**；不含性能表述。〔W-1：Phase-1 Final Audit 词级收紧——「validated」从 llama 侧移除〕 |
| **E. 结果行为可复制**（reproducibility） | P4 原跑（J1..J6 PASS）+ P4 replication（S₁ 输出与原跑**逐位相同**跨日；换序 8/8 逐字）+ S3 第二架构 | P4 replication PASS（Lab 2edc701，second-layer NO-MISREADING 9202142）；S3（Lab bcbc3b5）：承载项 J1..J4+J6 全 PASS，**overall = INCONCLUSIVE（J5 isolation witness），不承担 PASS** | **J4 证据归属精确注记：P4 原 J4 不承担「顺序置换独立性」证据**（F-5：原协议未真正实施换序，其实证的是跨进程重复确定性）；**真顺序置换独立性由 S3 首次承担**（第二架构族上跨独立进程逐字恒等）；一个第二模型≠模型普遍性；拓扑级不涉性能（D8） |
| **F. ES 具有跨 backend 一般性**（backend-independent） | llama contract mapping（Phase C seam audit）+ **P7-1（98dbed7）：五 cell 全 PASS=CONTINUATION_VALIDATED_CROSSBACKEND**（M1 GGUF 全字节哈希身份/J-A1 fork 锚相等/锚定续算/parent 重放逐字） | P7-1 按 9319b40 预注册执行（判据/cell/路由零修改；R0 全 PASS） | **bounded cross-backend claim（human 终验收 2026-10-01）**：「在当前实验条件下，candidate relation closure {I,P,A,C} 已获得 MLX 与 llama.cpp 两个 backend 的实验支持；两者使用不同的 backend-native representation，但均保持预注册的 continuation invariant」——**不推出 backend-independent，不涉及 minimality**；两个 backend ≠ 所有 backend |

## 2. 每行证据锚点索引

- A：`docs/00-governance/SIMIGO_LAB_P51_REPLICATION_RESULTS_20261001.md`（+§8 human second layer + 勘误）；P5-2-0 依赖图在 RESEARCH_STATE.md
- B/C：P5-2-C / P5-4 / P5-5 / P6 各章（RESEARCH_STATE.md，2026-10-01）；工件在产品仓本地对象与 simigo2-experimental/results/（原跑）
- D：P7-R2-A 各章（RESEARCH_STATE.md，2026-10-01）
- E：`SIMIGO_LAB_P4_REPLICATION_RESULTS_20261001.md`（2edc701）+ `SIMIGO_LAB_P4_SECOND_LAYER_JUDGMENT_20261001.md`（9202142，F-1..F-6）+ `SIMIGO_LAB_P4_SAMPLE3_REPLICATION_RESULTS_20261001.md`（bcbc3b5）；工件 `docs/02-evidence/p4-replication-20261001/`、`docs/02-evidence/p4-sample3-20261001/`
- F：Phase C seam audit（afdf30f 登记）+ P7-R2-A 各章

## 3. 证据结构描述（定性；无评分）

```text
A  Carrier 区分      —— 复制层完备（对照实验复制+样本资格条件登记）；
                        边界=单 backend
B  关系依赖          —— 原跑证据成立；复制层空缺（标注在案）
C  候选闭包          —— 破坏性证据有；最小性三判据中 M-1 部分/
                        M-2 零/M-3 零；判据已冻结
D  跨进程存续        —— 运行时级证据在案（真 checkpoint/真进程/
                        真续算）；复制层空缺（标注在案）
E  可复制性          —— 本战役的主成果：同日复制+跨日逐位+
                        第二架构承载项全过；残留=S3 overall
                        INCONCLUSIVE（仪器语义非承载失败）
F  跨 backend        —— 映射级+专用 harness 真实续算；
                        同不变量等价验证未建立
```

结构要点：**越靠近 SimiGo 核心问题（「从哪里继续计算」）的行，复制
层越厚；越靠近 backend 机制与普适性的行，开放越多**——这与研究
地图（Backend 管怎么继续计算、SimiGo 研究从哪里继续计算）和
「layered loading 只是辅助证据」的阶段纪律一致。

## 4. 收束句——「我们现在究竟能对 ES 说到哪一句为止」

**已能说到（本矩阵钉死）：**

> 在 MLX backend 上，Execution State 作为「保证计算连续性的关系
> 闭包」这一抽象已获得运行时级、可复制的实验支持：KV cache 不是
> Execution State（A，已复制）；计算连续性依赖 {I,P,A,C} 关系集而
> 非单一载体（B，原跑证据）；该状态可跨进程存活并恢复未来计算
> （D）；其行为可复制——包括在第二架构族上的承载判据复现与首次
> 真顺序置换独立性（E，S3 承担）。阶段结论已注册（534578e 双语）。

**尚不能越过的线：**

> 不能说 {I,P,A,C} 是最小闭包（M-2/M-3 零证据，G-δ 开放）；不能
> 说跨 backend 一般（F：NOT YET）；不能说模型普遍（S3=一个第二
> 模型）；B/D 的原跑证据在引用时必须带「未复制」标注。

## 5. 与 G-δ 的关系（本矩阵不自动触发）

矩阵被阅读后，human 才裁定 G-δ 实验是否值得继续。本矩阵提供的
判断输入：

- 若收束目标是「MLX 层研究结论」：C 行的现状（候选闭包+破坏性
  证据+判据冻结）已足以支撑注册表述中「minimal relation closure」
  的**假设级**读法（hypothesis supported, minimality pending）——
  G-δ 实验的边际价值=把 C 行从「候选」升到「已审计最小」。
- 若收束目标包含「严格最小性」：M-2（不可推导性）是唯一全新层，
  其推导空间枚举是设计难点（判据文档 §2 已预置判定三分与全量重算
  排除）。
- 两条路都合法；选择归 human。**本矩阵交付后零自动执行。**

## 6. Non-claims

本矩阵不是新证据、不改变任何实验终态、不构成 PASS/FAIL 重判；
S3=INCONCLUSIVE 的登记不变；所有「未复制」标注为引用义务；无任何
性能、普适性、跨 backend 宣称。
