# ES-T3 Closure Review — T3 已答尽了它所能回答的问题吗

日期：2026-10-01  
状态：`CLOSURE_REVIEW_DELIVERED / T3_FINAL_VERDICT_WITH_HUMAN`  
任务令：human 2026-10-01（Lab `a6ab2d9`：「不写 C、不继续 B′，先做
T3 Closure Review」）  
性质：只读收束审阅——零实验、零代码、零新 State；全部证据来自仓内
已封存文档。必答的一句话：**我们现在缺的到底是一个实验，还是一种
系统本身尚不存在的 Representation 能力？**

## 1. 三层问题表（任务令指定，逐层附证据锚点）

| # | 问题 | 判定 | 证据锚点 |
|---|---|---|---|
| L1 | Representation 中是否存在继续计算所需的内部信息？ | **有证据（ESTABLISHED）** | b0：P restore@17→55 字符 continuation（≡PB1 确定性基线）；B2 反证：摘 attention KV→continuation 摧毁——信息确在 P 内部分量中；R2n：history=continuation-bearing |
| L2 | 哪个分量目前实际参与 continuation？ | **KV 有正向证据** | B-3 终判：B2（KV 摘除→空响应）=必要反证；b3（GDN 零化→四 cell 全恒等，B′-3 观测面）=GDN 无观察贡献；operative carrier 收敛于 attention KV 位置比例分量 |
| L3 | 该分量能否脱离融合载体独立成为未来计算基础？ | **当前不可验证（UNVERIFIABLE-AS-IS）** | C-0 两重边界：融合载体使 H ✗ 在现有入口不可满足；构造 KV-only carrier 把命题降格为 constructibility（构造≠潜藏） |

L1 与 L2 已经回答充分。T3 的边际价值完全取决于 L3 的可实验性——
下节正面判定。

## 2. L3 可实验性判定：现行系统内原则上不可实验

六项 blocker，全部实测/源码在案：

```text
① durable 融合      单文件 save/load，无组件粒度入口（T3-A Q1 / B′-1①）
② restore 三件同行  cache+state+history 强制同进（B′-1③）
③ 结构校验          loader 拒绝组件摘除（B1 实测 non-contiguous indices）
④ vendor 两形态     位置输入仅 history 或 cache+state（T2-A2）；
                    路径 γ 在上游 API 面不存在
⑤ position 碰撞先例 无 history 消费入口实测（ES-R2 Gate C attempt 2）
⑥ 宇宙内无替代物    compressed context carrier 缺席（FSB-2）
```

判定：在「不改变 Representation 载体语义」+「不以构造为证明」双约束
下，L3 在当前系统内**原则上不可实验**——不是实验没设计好，是系统
不提供实现反事实条件的观测/消费入口。

刹车措辞（照例）：限当前系统（Nail/Qwen3-Next + mlx-swift-lm 当前
版本）；不排除 vendor 演化或其他架构给出不同答案。

## 3. 主线回放与两命题分界

```text
Execution State
  ↓
Durable Computational State     ← ES-R1/ES-D1：无独立 durable State；
  ↓                               Formation Gap 在 checkpoint 边界
Representation                  ← E0/T3-A：融合工件，内含两类分量
  ↓
内部计算分量                    ← B-3：attention KV operative；
  ↓                               GDN 无观察贡献（B′ 封存）
Continuation / Reuse            ← restore 即 continuation 成立；
                                  独立复用不成立（L3）
```

**两命题分界（任务令 §3 对应）**：

```text
P-a「Representation 能保存 continuation 所需的信息」      = ESTABLISHED
P-b「Representation 中存在可独立复用的计算分量」          = NOT ESTABLISHED
```

同一证据链同时支持 P-a 与否定 P-b——这就是 **operative ≠ durably
reusable** 的实验内容，构成下一阶段的分界线。

## 4. T2→T3 真正缺口的重述（任务令 §4 对应）

```text
T2：第三种独立 carrier 形态在宇宙内不存在（载体形态缺口，fe35722）
T3：P 内部确有 operative 分量（fa21551），但融合于 P，
    无法证明可独立脱离（本 review L3）
        ↓ 合成
真正缺口 = 「Representation 是否存在可分解、可引用、可重新组合的
            内部计算结构」
```

缺口再分解（对候选实验方向 §5 的关键输入）：

```text
可分解（decomposable）  = 已证——E0 header 普查：两类分量按名可寻址
                          （safetensors 格式层事实）
可引用（referable）     = 缺——组件粒度消费入口不存在（blocker ①②③④）
可重新组合（recombinable）= 未定义——无入口则重组语义无从谈起
```

即：**识别能力已存在（E0 做过），消费引用能力不存在**。这把「过去
的计算怎样成为未来计算的一部分」原始问题精确化到一处断点。

## 5. 一句话问题的正面回答

**缺的不是实验，是一种系统本身尚不存在的 Representation 能力**
——组件粒度的可引用/可消费结构及其入口（「可引用」断点）。

依据：候选实验方向（不改变原始 Representation 语义、识别可独立引用
子结构、不构造先于证明）在当前系统内的可达边界是——

```text
识别（observe/identify）  = E0 已完成，重做只是实验计数
引用（reference→consume） = 无入口，触及即须造 carrier ⇒ 命题降格
独立 continuation          = 依赖「引用」，连带不可达
```

按任务令判据（若缺的是能力，则不应为完成 Gate C 继续做实验）：
**继续在当前系统上追加 T3 实验只会增加实验数量，不会增加解释力。**

## 6. 决策门三岔评估（任务令 §6；推荐，终判归 human）

```text
岔 1「当前问题已经回答充分 → T3 SEALED」
    成立：L1/L2 已答尽；L3 非 T3 内部问题而是能力缺口问题。
岔 2「存在不改变命题的可验证路径 → 新实验设计」
    不成立：在「不构造」条件下，唯一残留在观测面的是 E0 已建立的
    物理可分解性——无现存路径。
岔 3「只能通过制造新 carrier 才能继续 → T3 STOP、缺口转为新研究
    问题」
    与证据一致：继续的唯一方式 = 先造 carrier = 改变命题。
```

**推荐 = 岔 3 形态收束（含岔 1 的封存面向）**：T3 以三层终态关闭
（L1 ESTABLISHED / L2 KV operative / L3 UNVERIFIABLE-AS-IS）；缺口
正式转出为下一阶段研究问题候选。

## 7. 缺口蒸馏（下一阶段研究问题候选，NOT STARTED）

```text
候选问题（措辞待定义门审定）：
  现有 Representation 是否具有——或能否在不改变其语义的前提下
  获得——可分解、可引用、可重新组合的内部计算结构，使得既有
  计算分量能被独立引用并重新进入计算，而不以先构造载体为证明
  前提？
严格条件（任务令原话登记）：
  ❌ 不能为了证明它存在，先把它构造出来
  ❌ 不改变原始 Representation 语义
  ✔ 若条件不可满足 ⇒ 承认当前 Representation 是不可分解的计算
    整体——本身即重要结果
状态：候选 NOT STARTED；RQ 编号经新定义门归 human；不叫 B′-4。
```

## 8. Non-claims

```text
✔ 不宣布「KV 永远无法独立」——缺的是当前系统的能力，非普适不可能
✔ 不把 attention KV operative 升格 Execution State（B 终审禁令延续）
✔ 不把 L3 不可验证表述为「验证失败」——是条件不可实现
✔ 不重开 B′ / Gate C 实验；结论限当前系统+当前 vendor 版本
```
