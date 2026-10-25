# SimiGo-Lab R3-3 Design — R3-N Negative / Counterexample Search (Design Gate Deliverable)

日期：2026-10-03（rev.2；rev.1 同日）
状态：**RATIFIED / 正式设计**（独立对抗审查 PASS WITH RECOMMENDATIONS
后 rev.2 机械补入四项收紧条款——零命题变更；**execution 仍须独立
human 授权**）
授权：human「R3-3 opening 授权仍只开 Design Gate」（2026-10-03）——本
设计门只锁四件事：**反证对象 / null expectation / 停止条件 / 与 R3-2
结果的独立性**；**不授权 R3-3 实验**。
上游：R3-0 设计（@1c8c463）、R3-2 结果（SUPPORTED/fixture-slice
bounded，FORMALLY CLOSED）+ second layer AUDIT PASS（16/16）、R3-1
Spec rev.2（RATIFIED 判定规则）。

**rev.2 修订记录（独立对抗审查 SIMIGO_LAB_R3_3_DESIGN_REVIEW_20261003.md
发现，全部为收紧/补全/澄清条款）**：

```text
H-1  §1 SANITY 扩展为逐条件三正控（SANITY-A/I/C）——防单条件正控
     漏检 I/C 评估路径死亡⇒假 NO-COUNTEREXAMPLE
H-2  §3/§5 INCONCLUSIVE 传染规则——NO-COUNTEREXAMPLE 当且仅当零
     INCONCLUSIVE cell（封死「反例洗入 INCONCLUSIVE」吸收路径）
H-3  §5 反例资格三要件（签名可归因+replay 复现+审计未定位仪器缺陷）
     +再分类程序+排除封闭（cell 排除仅经预注册 S/I 码，反例 cell
     永不排除）
H-4  §1 Δ10 谱系等价迁移——referability 子句三引用组全覆盖
O-1/O-2/O-3  范围外 BROKEN 侧预测登记/结构性不可测侧登记/非推导
     声明强化（见 §2/§5）
```

## 0. R3-N 定位与两个合法出口

R3-N = 在 R3-2 同一 fixture slice 内，寻找**按既定规则应当「不产生
相应 Cons 击穿」**的 Information Space 变化，观察差分敏感性是否出现
反例。

**预注册的两种合法出口（均为有效结果，均不外推）**：

```text
无反例  ⇒ NO-COUNTEREXAMPLE：仅在当前 slice 内增强边界证据，
          仍不能升级为普遍规律（不写「规则已证明正确」）；
有反例  ⇒ COUNTEREXAMPLE-FOUND：对当前 taxonomy / condition boundary
          的实质信息（不是「实验失败」），触发边界复审门（human），
          不得在 campaign 内修补预测规则使其转 HOLD。
```

## 1. 反证对象（冻结目录）

N-catalog 的**推导来源（独立性锚，见 §4-inv-2）= 冻结规则条款本身**
（Spec rev.2 §1–§3/§5a + design rev.2 §3/§5a/§6）中**尚未被 R3-2 cell
覆盖的 HOLD 侧**——每条操作注明它攻击的是哪条规则的哪一侧：

| op | 机制 | 攻击的规则条款（未测 HOLD 侧） | 预测 |
|---|---|---|---|
| R32N-Δ1 | 未引用对象删除（unreferenced-1 + 索引项移除） | 判定只依赖 ES 引用键（Spec resolve/C-REF/_referenced_keys） | 全 HOLD |
| R32N-Δ2 | 未引用对象内容改写（同键新内容，无 mutation 记录） | 同上 | 全 HOLD |
| R32N-Δ3 | 死索引项（键→不存在路径） | 精确键解析+存在性过滤（§5a H-D） | 全 HOLD |
| R32N-Δ4 | 被引用键的**同内容**重复候选（lineage-root 二候选、逐字节相同） | 多候选坍缩规则（identical → 收敛为 1；与已测的 I-Δ3 冲突候选相对） | 全 HOLD |
| R32N-Δ5 | 被引用对象**字段保持扩展**（runtime-declaration 增加无关字段，fixture_class 不变） | 字段域比较（I-EV-1 只比对声明字段） | 全 HOLD |
| R32N-Δ6 | 前置等价迁移（I-S0 → store-v2/ + 索引重指向） | 可引用性=解析+边界，非存储地址（K-1b 的对称未测例） | 全 HOLD |
| R32N-Δ7 | invalidation 记录指向**未引用**键 | C-INV 扫描仅核对 ES 引用键目标 | 全 HOLD |
| R32N-Δ8 | manifest scope-tag **增补**（必需 tag 不动） | C-DECL scope-tag 存在性检查的方向性 | 全 HOLD |
| R32N-Δ9 | in_scope 区域**增补**（新区+未引用对象） | 边界隶属是要求侧（对象须在界内；扩界不破坏） | 全 HOLD |
| R32N-Δ10 | **谱系等价迁移**（lineage-root → store-v2/ + 索引重指向）〔rev.2 H-4〕 | referability=解析+边界——I-EV-2 引用组实例（锚=K-1b、前置=Δ6 已覆盖，谱系侧未测） | 全 HOLD |
| R32N-SANITY-A | **正控**：重实例化已冻结的 A-Δ3 | A 评估路径 BROKEN 能力（防判读器死亡） | A BROKEN/A-SUB |
| R32N-SANITY-I | **正控**：重实例化已冻结的 I-Δ1〔rev.2 H-1〕 | I 评估路径 BROKEN 能力 | I BROKEN/I-MISMATCH |
| R32N-SANITY-C | **正控**：重实例化已冻结的 C-Δ2〔rev.2 H-1〕 | C 评估路径 BROKEN 能力 | C BROKEN/C-INV |
| R32-K-0 | null control（同流程重放） | 仪器基线 | 全 HOLD |

**排除的操作形态（预注册）**：
- 「改动后复原」类（t₁ 终态无痕）——判定对象是 t₁ 终态，此类 cell
  空洞无信息，排除；
- 任何触碰被引用内容字节的操作（预测必为 A-SUB/C-REF 类 BROKEN）——
  属 R3-2 已测定向家族，不属反证对象；
- IS-X 组合、内容寻址变体、模型/continuation 通道——维持排除（见 §6）。

**结构性不可测侧（rev.2 O-2，如实登记非遗漏）**：validity-temporal
HOLD 侧在战役时窗内空转；I-EV-3 payload 完整性对 IS 按构造不敏感
（无 IS 敏感 HOLD 侧可探）。**范围外 BROKEN 侧预测（rev.2 O-1）**：
scope-tag 移除⇒C-DECL-FAIL、被引用区域 access-deny⇒A-NF/C-REF-NOT-
FOUND——属定向家族开放预测，不在反证搜索范围。

目录在**本设计门 seal 时冻结**；执行期不得增删改（§4a 词汇封闭沿用）。
**rev.2 后战役规模 = 10 反证 cell + 3 正控 + K-0 = 14 cell**。

## 2. Null expectation（预注册）

```text
R3-N 的 null expectation（rev.2 H-1 后）：
  ① 10 个反证 cell 的 t₁ = I/A/C 全 SATISFIED（逐项等于 setup t₀）；
  ② 三个正控 cell 各自产生预注册 BROKEN 签名
     （SANITY-A→A-SUB / SANITY-I→I-MISMATCH / SANITY-C→C-INV）
     ——逐条件证明评估路径活性；
  ③ K-0 无漂移；完整性（ES/IS₀ 哈希）全净；instrument_doubt 全 NO。

语义（预注册，不得事后改写）：
  - 反例判定 = 任一反证 cell 任一条件 t₁ BROKEN（带可归因签名）；
  - 反例缺席只在该 slice 内增强边界证据——不升格普遍规律；
  - 反例的出现是研究对象本身——campaign 不因反例停止（见 §3）；
  - 「无反例」不得表述为「规则正确性已证明」；
  - 非推导声明（rev.2 O-3）：NO-COUNTEREXAMPLE ≠ 证明一致性——仅
    为本 slice 内被测 HOLD 侧条款经受住反证探针，不验证条件正确性/
    最小性/完备性（RQ3-4 保持开放）；COUNTEREXAMPLE-FOUND ≠ 普遍
    反例、≠ 追溯撤销 R3-2（R3-2 判读关于其自身 cell；反例触发
    taxonomy 边界复审门，是否级联由复审门裁定）。
```

## 3. 停止条件

沿用 R3-2 S-1..S-5，另加 R3-N 特有两条：

```text
S-1  结构性不可判定（setup 阶段）⇒ STOP/修订边界（禁换 ES/IS₀ 凑数）
S-2  K-0 漂移且仪器审计无法定位 ⇒ 整批 INCONCLUSIVE ⇒ STOP
S-3  ES/IS₀ 工件哈希漂移 ⇒ STOP
S-4  系统性不可归因 ⇒ 战役 INCONCLUSIVE 且继续无意义 ⇒ STOP
S-5  门控违反（超目录/重分类/评估前移/结果改预测）⇒ cell 作废+上报
S-N1 反例【不】触发停止——反例是研究对象；campaign 跑完冻结目录，
     反例逐 cell 登记，闭合后进边界复审门（human）
S-N2 任一正控 cell 出现 SATISFIED（判读器死亡信号）⇒ 战役 INCONCLUSIVE
     + STOP（此时全 HOLD 不可解释，禁读为 NO-COUNTEREXAMPLE）
S-N3 不可归因击穿 ⇒ 该 cell INCONCLUSIVE（I-3）+仪器审计；系统性
     不可归因 ⇒ S-4
S-N4 INCONCLUSIVE 传染（rev.2 H-2）：NO-COUNTEREXAMPLE 当且仅当
     零 INCONCLUSIVE cell——任何 cell INCONCLUSIVE ⇒ 战役整体
     INCONCLUSIVE（禁 Partial-NO-COUNTEREXAMPLE 读法，封死「反例
     洗入 INCONCLUSIVE」吸收路径）
```

## 4. 与 R3-2 结果的独立性（五条不变量）

```text
inv-1  判读输入隔离：R3-3 的 harness/判读只读 R3-3 自己 run 目录的
       工件；R3-2 run 产物零读取作判定输入（R-C1 证据纪律沿用）。
inv-2  目录来源隔离：N-catalog 从冻结规则条款推导（本设计 §1 逐条
       注明条款出处），在本设计门 seal 时冻结——R3-2 的 outcome 不是
       目录选择的输入（「R3-2 cell 全 HOLD」只是背景事实；N 目录
       攻击的是规则本身未测的 HOLD 侧，仅凭规则即可枚举）。
inv-3  形成隔离：fresh formation——同一 formation 程序在 R3-3 setup
       重新执行（新 run-UUID、新 setup 记录、哈希重新钉定）；不搭载
       R3-2 的 live 状态或工件。
inv-4  cell 内独立性：per-cell fresh copy / 构造记录先于评估 /
       outcome 追加式 / 双哈希复查 / frozen-op replay 审计——全部沿用。
inv-5  判读语义隔离：R3-N 出口类目为 NO-COUNTEREXAMPLE /
       COUNTEREXAMPLE-FOUND / INCONCLUSIVE——不继承 R3-2 的
       SUPPORTED 语义，不与之合并统计。
```

## 5. 判读规则（预注册）

```text
① 零 INCONCLUSIVE + 全部 10 反证 cell HOLD + 三正控各自预注册
   BROKEN + K-0 无漂移
     ⇒ NO-COUNTEREXAMPLE（slice 内边界证据增强；bounded）
     〔rev.2 H-2：任何 cell INCONCLUSIVE ⇒ 战役整体 INCONCLUSIVE，
     不得宣称 NO-COUNTEREXAMPLE〕
② ≥1 反例（BROKEN 且满足反例资格三要件，rev.2 H-3）：
     (a) 签名可归因至具体条件+机制；
     (b) frozen-op replay 复现该击穿（确定性排除瞬态）；
     (c) 闭合后审计未能定位具体仪器机制缺陷。
     ⇒ COUNTEREXAMPLE-FOUND：逐 cell 登记发现内容
     （条件+签名+操作+被攻击规则条款），闭合后进边界复审门（human）；
     禁止 campaign 内修补预测规则/判定程序/目录使反例消失；
     cell 排除只允许经预注册 S/I 码——反例 cell 永不排除
③ 任一正控 SATISFIED ⇒ INCONCLUSIVE（判读器死亡）+ STOP（S-N2）
④ drift/doubt/unattributable ⇒ INCONCLUSIVE（Spec §5.3 / I-1..I-6 沿用）
⑤ 反例若源于仪器缺陷（审计定位成功）⇒ 改判 INCONCLUSIVE 并记录——
     不得既算反例又算仪器故障（与要件(c)衔接）
```

## 6. 边界重申（独立性表格沿用 human 裁定）

| 边界 | 状态 | 本设计门处置 |
|---|---|---|
| R3-N 反证搜索 | **本设计门对象** | §1–§5 |
| IS-X 复合变化 | 独立、不混入 | 词汇封闭维持，未实例化 |
| 内容寻址表征敏感性 | 独立、不混入 | defer 维持 |
| 条件破坏→continuation failure | R3 外 | 严格隔离维持（R3 全程无模型） |

全部既有排除维持（P/IPAC 冻结/PALACE/MCP/Route A·B·C/后端适配/产品
实现/性能/模型比较/完整恢复系统）。

## 7. 执行剖面（仅供后续授权参考，本门不授权）

- 实现形态：同一 harness 家族扩展（CATALOG 增加 10+3 冻结操作；评估
  程序零改动——r32_lib 判定规则与 R3-2 完全同源，满足 inv-2）；
- campaign = 10 反证 cell + 3 正控 + K-0 = 14 cell（rev.2）；
- cell 纪律、双哈希、replay purity、second layer 审计模式全部沿用；
- **execution 须独立 human 授权**；本设计先行独立对抗审查（同节奏：
  设计→对抗审查→修订→RATIFIED→执行授权）。

## 8. 效力声明

本文档 = R3-3 Design Gate 交付物，DELIVERED / INDEPENDENT REVIEW
PENDING。零实验、零代码、零 harness 改动、零采数。四件锁死事项
（反证对象 §1 / null expectation §2 / 停止条件 §3 / 独立性 §4）经
独立审查通过后即为 R3-N 的正式设计；执行另须授权。

## 9. 输入清单

- R3-0 设计（GIT SEALED @1c8c463）§4.3 R3-N 原始定义
- R3-2 结果（FORMALLY CLOSED）+ second layer AUDIT PASS
- R3-1 Spec rev.2（规则条款出处：§1–§3/§5a）
- R3-2 Design rev.2（§3 冻结目录家族/§4a 词汇封闭/§5a 确定性钉定/
  §6 对照结构）
