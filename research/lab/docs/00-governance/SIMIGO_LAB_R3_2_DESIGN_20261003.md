# SimiGo-Lab R3-2 Design — Single-change Boundary Study Design (Design Gate Deliverable)

日期：2026-10-03（rev.2；rev.1 同日）
状态：**RATIFIED / 正式实验设计**（独立对抗审查 PASS WITH
RECOMMENDATIONS 后 rev.2 机械补入六项收紧条款——零命题变更；
**execution 仍须独立 human 授权**）
授权：human「R3-2 = AUTHORIZED FOR DESIGN GATE ONLY」（2026-10-03）——
仅回答八个设计问题；**不跑实验、不写代码、不建 harness、不采数**。
判定规则：R3-1 Judgment Spec rev.2（RATIFIED，引用不修改）。
输入：R3-0 设计（@1c8c463）、Spec rev.2、Spec Review（含 O-1/O-2 两项
登记为本设计门输入）。

**rev.2 修订记录（独立对抗审查 SIMIGO_LAB_R3_2_DESIGN_REVIEW_20261003.md
发现，全部为收紧/澄清条款）**：

```text
H-A  §1a 新增：Campaign setup lock（一次性选对+一次性 t0 判定+失败
     即 INVALID+STOP+保全，重设须新授权；per-cell t0=仪器一致性复算）
H-B  §2a 新增：判定基线 ES-artifact 驻留规则+ES/IS 物理不相交
     +formation provenance 链+setup-非-ΔIS 声明
H-C  §5 映射修正：in-cell t1 结构缺失⇒I BROKEN（I-STRUCT-REMOVED）；
     仪器疑云读法仅限 setup 阶段
H-D  §5a 新增：Fixture 确定性钉定（精确键解析/C-DECL 白名单/setup
     钉定时间戳）
H-E  §6a 新增：canonical IS₀ 事后复验+ES 双复查+IS₁ 只读归档
H-F  §4a 新增：类别机械推导（非人工指派）+IS-X 词汇封闭
```

## 0. 授权边界与八问映射

| # | human 指定问题 | 本文档章节 |
|---|---|---|
| 1 | 最小实验单元是什么 | §1 |
| 2 | ES 如何固定 | §2 |
| 3 | ΔIS 如何构造 | §3 |
| 4 | ΔIS_class 如何在构造时锁定 | §4 |
| 5 | I/A/C 如何从 Spec 转换为可执行观察 | §5 |
| 6 | Control 如何预注册 | §6 |
| 7 | 哪些结果会直接停止 R3 | §7 |
| 8 | 什么情况下仍然只能得到 INCONCLUSIVE | §8 |

全程禁止：实验运行、代码、harness 构建、数据采集、R3-3/R3-4、
P/IPAC/PALACE/MCP/Route/后端适配/产品实现/性能/模型比较。

## 1. 最小实验单元（Q1）

**Cell = 一次受控的 `(ES, IS₀) ─ΔIS→ (ES, IS₁)` 转换及其条件级判定。**

```text
Cell 构成：
  ① 固定 ES 实例（工件级同一，见 §2）
  ② IS₀（钉定初始 Information Space，见 §6.3）
  ③ 一个 ΔIS 操作（取自 §3 冻结目录，类别 §4 锁定）
  ④ t₀ 条件评估（Spec §7 五步，作用于 (ES, IS₀)）
  ⑤ t₁ 条件评估（同程序，作用于 (ES, IS₁)）
  ⑥ per-cell 记录（Spec §6.1 schema）
```

**Cell 有效性前提（构造时披露义务，O-2 落实）**：cell 进入判定要求
`Cons(ES, IS₀) = true`——即 t₀ 评估三条件全 SATISFIED。该前提来自
研究问题本身（测量「从满足到不满足」的转换），属构造要求而非结果
操纵；每个 cell 的 t₀ 评估结果与所选 ES 的 formation 材料清单
（I-EV 声明 / A 锚引用+formation 摘要 / C 前置引用+声明条件）在
构造记录中**先行披露**。若 t₀ 即不满足 ⇒ 该 cell 对转换问题无效，
记 setup-invalid（不参与统计，进 §8/§7 处置，不得改 ES 或 IS₀ 凑数）。

**范围声明（防泄漏）**：R3-2 全程**无模型推理**——判定对象是条件
满足性（R3-0 §5 总纪律），不是延续行为；「条件破坏是否导致延续失败」
属 R2 候选关系 LawfulContinuation⇒Cons 的检验，不在 R3-2 范围。

## 1a. Campaign setup lock（rev.2 H-A——cell validity 的结构性锁）

```text
① (ES, IS₀) 一次性选定：按预先登记的选择准则（§2 formation 材料齐备/
   真实形成路径/符号名锚引用）选定一对；准则执行不依赖任何 t₀ 评估
   结果——选择在判定之前，禁止「试到合格为止」的隐性 resampling；
② t₀ 判定一次性：Cons(ES, IS₀) 按 R2 rev.2 候选定义、依 R3-1 Spec
   rev.2（RATIFIED）§1–§3+§7 程序、在 campaign setup 阶段（任何 ΔIS
   存在之前）机械评估一次——版本、依据、时点三要素钉死于 setup 记录；
③ 结果二值且终局：true ⇒ cell validity 对全战役固定；false ⇒
   setup = INVALID，全部评估记录保全，STOP——重设新 (ES, IS₀) 属
   新 setup，须新 human authorization，失败 setup 保存为证据
   （R-C1 attempt 纪律：不混入、不覆写）；
④ per-cell t₀ 重评估 = 仪器一致性复算（同输入必同输出）：任一 cell
   的 t₀ 结果与 setup t₀ 不一致 ⇒ 仪器疑云 ⇒ 整批 INCONCLUSIVE。
```

## 2. ES 如何固定（Q2）

1. **工件级同一**：单一 ES 工件贯穿全部 cell；每 cell 前后做 ES 工件
   哈希核验，任何漂移 = 仪器疑云（§7 S-3）。
2. **真实形成**：ES 取自系统自身形成路径的真实状态（P4/R-C1 先例：
   运输非构造，D6），禁 research-purpose 伪造 state。
3. **Formation 材料齐备（O-2 落实）**：所选 ES 的 formation 记录必须
   含 Spec 判定所需三类材料——I-EV 身份证据声明（含所在位置）、
   A 锚引用 + formation 时内容摘要、C 前置引用 + 声明式 applicability
   条件。材料清单在构造记录中披露；缺失者该条件 NOT-EVALUABLE
   （触发 §7 S-1），不得事后补造（no construct-then-claim）。
4. **只读**：ES 对一切 cell 只读；ΔIS 只作用于 IS。
5. **引用形式声明**：本设计选定 ES 的锚引用为**符号名引用**——使
   A-SUB（silent substitution）可观测（内容寻址下 A-SUB 结构上不可
   能，Spec §2.4 已定性为表征选择性质）。表征敏感性（内容寻址变体
   下 A 的边界行为）登记为后续边界问题，不在本战役制造。
6. **研究载具声明（bounded claim 纪律）**：ES/IS 的物理载具为 Lab
   仓内 purpose-built 最小研究 fixture（R-B1 SQLite InformationCore +
   external relation store 先例），非产品、非 backend 适配；R3-2 结论
   bounded 于该 fixture 结构类，不外推为产品/普适主张。

## 2a. 基线驻留与 provenance 链（rev.2 H-B / O-A）

1. **判定基线驻留规则**：全部判定基线——formation 摘要、I-EV 证据
   声明、前置声明——**一律驻留于 ES 工件内部**；IS 只含可引用对象与
   mutation 记录（invalidation/supersession），**永不含判定基线**。
   否则 ΔIS 即可能触碰基线自身，研究被倒置。
2. **物理不相交**：ES 工件与 IS 存储为不相交的存储路径；IS 操作
   （含全部 ΔIS 与观察）永不触碰 ES 存储路径——ES 完整性对照与实验
   变量的耦合被结构性排除。
3. **Formation provenance 链（O-A）**：setup 记录登记完整链——真实
   系统运行形成（formation record 随行）→ 工件导出 → 哈希钉定 →
   运输入 fixture（运输非构造，D6）。
4. **Setup 事件非 ΔIS**：fixture 组装（ES 运入 + IS₀ 构造）属
   campaign setup，非被测变更；每 cell 的首个被测事件是该 cell 的
   ΔIS（或 K-0 的 no-op）。

## 3. ΔIS 如何构造（Q3）

**冻结操作目录（design-gate seal 时冻结；执行期不得增删改）**：

```text
IS-I（对象定向：身份证据组）
  I-Δ1  IS 侧模型身份声明变更 M→M′        →预测 I-MISMATCH
  I-Δ2  谱系引用的 IS 目标删除             →预测 I-NF
  I-Δ3  谱系目标复制为内容冲突的多个候选    →预测 I-AMBIG
IS-A（对象定向：锚证据组）
  A-Δ1  锚目标内容删除                     →预测 A-NF
  A-Δ2  锚目标移出当前 IS 边界（内容仍存在于宇宙）→预测 A-NF
  A-Δ3  同址异容（silent substitution）     →预测 A-SUB
IS-C（对象定向：前置证据组）
  C-Δ1  被 ES 前置引用的 settled result 删除→预测 C-REF not-found
  C-Δ2  对该 result 添加 invalidation 记录（本体仍在）→预测 C-INV
  C-Δ3  对该 result 添加 supersession 记录  →预测 C-INV
IS-B（整体边界操作：作用于 IS 边界/访问模式，非单一对象）
  B-Δ1  边界收缩：重划后某区域整体移出当前 IS
  B-Δ2  访问模式变更：区域整体转为不可访问
  （受影响集合由构造时边界划定确定；受影响对象含被引用者⇒按机械推导
   登记预测，仅含未引用者⇒预测 no-break；推导歧义处保留「?」）
K-1（良性对照，Spec §5.1）
  K-1a  纯增量：新增与 ES 无引用关系的信息  →预测 no-break
  K-1b  等价迁移：内容搬家且寻址/可检出性保持→预测 no-break
IS-X（复合）——**目录占位，操作在本战役后段、单变量 cell 完成并确认
可归因之后才实例化**（R3-0 §4.2 顺序纪律；实例化仍走构造时锁定）
K-0（null control）——无 ΔIS，全流程重放
```

**适用性披露义务**：I-Δ1/I-Δ2/I-Δ3 的可执行性取决于所选 ES 的
I-EV 声明结构（如 I 证据完全自足则全部 IS-I 操作记录
not-applicable-to-this-ES，并触发 I-INVARIANT 登记）——适用性判定
只用 formation 材料（构造时知识），不用任何评估结果。

## 4. ΔIS_class 如何在构造时锁定（Q4）

1. **类别指派规则（本设计冻结）**：按操作的**机制与靶**指派——对象
   定向于某证据组 ⇒ IS-I/IS-A/IS-C；整体边界/访问操作 ⇒ IS-B；多
   操作组合 ⇒ IS-X；无操作 ⇒ K-0；无引用关系的加增/迁移 ⇒ K-1。
   规则先于任何 cell 存在，杜绝按结果找类。
2. **构造记录先于评估**：每 cell 的 construction record
   {cell_id, ES 工件哈希, IS₀ 哈希, 操作 id, ΔIS_class, 构造时机械
   推导的预测签名} 在**任何条件评估之前**落盘锁定（Spec §5.4 执行
   化）；评估只向 outcome 文件**追加**，与构造记录物理分离。
3. **重分类禁令**：评估出现意外结果（如 IS-I 未击穿 I）不得改类、
   不得改目录、不得改预测——意外结果本身是数据（R3-N/RQ3-4 素材）。

## 4a. 类别机械推导与 IS-X 词汇封闭（rev.2 H-F）

1. **类别由冻结规则从操作 id 机械推导**（非人工指派）——指派自由度
   归零；adjudication 可机械复核「操作 id ↔ 类别」的规则一致性。
2. **IS-X 词汇封闭**：X 操作 = 已冻结单变量目录操作（§3）的组合，
   执行期**不得引入新操作类型**——战役范围被目录词汇封死，杜绝借
   IS-X 扩张。

## 5. I/A/C 如何从 Spec 转换为可执行观察（Q5）

| Spec 签名 | 可执行观察程序（fixture 上） |
|---|---|
| I-SATISFIED | 读 ES I-EV 声明→自足证据直接通过；IS 引用证据解析唯一命中且模型声明匹配 |
| I-NF / I-AMBIG / I-MISMATCH | 谱系引用解析返回空 / 多冲突命中 / IS 侧模型声明 ≠ ES 声明 |
| I-STRUCT-REMOVED（rev.2 H-C） | **in-cell t₁**：评估规则引用的 IS 结构在 t₀ 存在、t₁ 缺失——唯一变量是 ΔIS ⇒ 这是 I-condition 定义主体（「IS 不使其不可判定」被违反）= **I BROKEN**，非仪器疑云 |
| I-UNSTRUCT（限 setup 阶段） | **setup 阶段**评估规则所依赖结构缺失 ⇒ NOT-EVALUABLE 路径（S-1）；仪器疑云读法仅适用于 setup，不适用于 in-cell t₁ |
| A-SATISFIED | 经 ES 存储引用路径解析成功 ∧ 内容摘要 == formation 摘要 |
| A-NF / A-SUB | 解析空/越界 / 解析成功但摘要 ≠ formation 摘要 |
| C-REF / C-INV / C-DECL | 前置引用 found-notfound / 查 IS invalidation·supersession 索引 / 按 §3.2 H-3 判据核对声明条件 |
| instrument_doubt | A-UNRESOLVABLE（t₀ 干净前提下按构造不可能出现于 t₁——引用形式驻留于固定 ES；其出现即观测路径缺陷真信号）/ setup 阶段 I-UNSTRUCT ⇒ cell 判定 INCONCLUSIVE（Spec §5.3） |
| Cons | I∧A∧C 机械合成，NOT-EVALUABLE 传播 |

- **观察完整性**：IS 写前/写后全域哈希（观察不得变更 IS，Spec §4.1）；
  观察通道与 IS 变更通道分离。
- **仪器化（执行期落实，本设计固定要求）**：run-UUID、append-only
  独立观测文件、单调钟、判读脚本与判读输入分离（Spec §4.3）。
- **O-1 落实**：R3-2 无模型、无输出遥测；未来任何行为层遥测不得进入
  判定通道（R3-0 §5）。

## 5a. Fixture 确定性钉定（rev.2 H-D）

1. **引用解析语义 = 精确键匹配**（IS 索引上的标识符精确匹配；禁模糊
   匹配、禁语义相似度匹配）——「命中/多冲突/未命中」全为确定性输出。
2. **C-DECL 检查类型白名单**：声明条件仅允许三类机械检查——scope-tag
   隶属 / 有效期比对 / 依赖引用解析；白名单外声明 ⇒ C-NOT-EVALUABLE。
3. **时间参照钉定**：时间类声明条件比对 **setup 记录冻结的时间戳**，
   非评估时墙钟（消除 time-of-check 非确定性）。

## 6. Control 如何预注册（Q6）

1. **Control 家族**（Spec §5 三层）全部走与实验 cell 完全相同的流程：
   K-0 至少 1 cell；K-1a/K-1b 各至少 1 cell；预测（no-break / 不变）
   在构造记录中先行登记。
2. **ES 完整性对照（本设计新增常设对照）**：ES 工件哈希跨 cell 恒等，
   任何漂移 ⇒ 整批 INCONCLUSIVE（S-3）。
3. **IS₀ 钉定与 cell 独立**：全战役单一 IS₀ 哈希钉定；每 cell 从 IS₀
   **新拷贝**出发（copy-on-write）——cell N 的 IS₁ 永不成为 cell N+1
   的输入（禁累积污染）。
4. **顺序独立性**：cell 执行顺序登记；保留对子集做换序重跑逐字复现的
   仪器选项（Gate H 先例），是否启用归执行授权。
5. **漂移处置**：K-0 任何条件变化 / ES 漂移 / 观察完整性失败 ⇒ 整批
   INCONCLUSIVE、不进判读（Spec §5.3），先于任何结果解读。
6. **事后双复查（rev.2 H-E）**：每 cell 结束后复验 canonical IS₀ 哈希
   与 ES 工件哈希（源头钉定+新拷贝+事后复验三重阻断累积污染）；cell
   的 IS₁ 拷贝归档为只读审计工件。

## 7. 哪些结果会直接停止 R3（Q7）

```text
S-1  结构性不可判定：所选 ES 类别任一条件 NOT-EVALUABLE（formation
     材料缺失/仅语义声明）⇒ R3-1 出口判据在位失败 ⇒ STOP/修订边界
     （不得换 ES 凑可判定性——换样属边界修订，须回到 human）
S-2  K-0 漂移且仪器审计无法定位原因 ⇒ STOP（可定位⇒修复仪器重跑，
     重跑不混入判读——R-C1 attempt 纪律）
S-3  ES 工件哈希漂移 ⇒ STOP
S-4  系统性不可归因：定向 cell 的击穿/不击穿整体无法归因（签名缺失
     且构造解释缺失）⇒ 战役 INCONCLUSIVE 且继续 IS-X/R3-3 无意义
     ⇒ STOP
S-5  任何门控违反（超目录操作/重分类/评估前移/结果改预测）⇒ 该 cell
     作废并即时上报 human
```

## 8. 什么情况下仍然只能得到 INCONCLUSIVE（Q8）

```text
I-1  K-0 漂移（整批，Spec §5.3）
I-2  instrument_doubt = YES 的 cell（A-UNRESOLVABLE/I-UNSTRUCT）
I-3  不可归因击穿：BROKEN 无签名类别且无构造时解释
I-4  NOT-EVALUABLE 传播（cell 退出四态统计，进 §6.3 出口核算）
I-5  观察完整性失败（观察行为改变了 IS——写前/写后哈希不匹配）
I-6  setup-invalid cell（t₀ 条件即不满足）——不参与转换统计
```

## 9. 预测登记（hypothesis structure，非预期结果）

定向 cell 的预测 = 操作 × ES formation 证据图的**构造时机械推导**
（§3 目录右列），其地位是待验证预测（R3-0 §4.3：矩阵是 hypothesis
structure 不是 expected result declaration）。全部预测随构造记录冻结；
实际结果与预测的偏离按原样记录——包括全 cell no-break（⇒ NOT
SUPPORTED = 实质性有界发现，Spec §6.2，禁改表征/加条件）。

## 10. 出口与下一门

- 本设计已经独立对抗审查
  （SIMIGO_LAB_R3_2_DESIGN_REVIEW_20261003.md，PASS WITH
  RECOMMENDATIONS / 无 blocker），rev.2 补入六项收紧条款后
  **RATIFIED 为正式实验设计**；**R3-2 execution（fixture 实现+cell
  运行）须独立 human 授权**——RATIFIED 不构成任何执行许可。
- R3-3（Counterexample/Non-break）/R3-4（Consistency Synthesis）
  保持 LOCKED。
- 全部排除清单维持（P/IPAC/PALACE/MCP/Route/后端适配/产品实现/性能/
  模型比较/完整恢复系统）。

## 11. 输入清单

- R3-0 设计（GIT SEALED @1c8c463）
- R3-1 Judgment Spec rev.2（RATIFIED——判定规则，引用不修改）
- R3-1 Spec Review（H-1/H-2/H-3 已入 rev.2；O-1/O-2 本设计落实于
  §1/§2/§5）
- R-B1 / R-C1（fixture 与 evidence 纪律先例）；P4/R4 宪法（运输非
  构造、失败有效性、构造时冻结先例）
