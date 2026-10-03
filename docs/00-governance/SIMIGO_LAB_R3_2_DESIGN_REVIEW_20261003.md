# SimiGo-Lab R3-2 Design — Independent Adversarial Review

日期：2026-10-03
状态：**EXECUTED / VERDICT: PASS WITH RECOMMENDATIONS（无 blocker；一项
生效前强制修订）**
授权：human「授权 R3-2 Design 的独立对抗审查」（2026-10-03）。
评审对象：`SIMIGO_LAB_R3_2_DESIGN_20261003.md`（rev.1）。
攻击目标：**实验前的自由度、污染、归因漏洞**——不重新证明 R3-2 值得做。
边界：本评审通过 ≠ 执行开启；R3-2 execution 仍须独立 human 授权。

## 1. Check 1 — Cell validity（含 human 特别聚焦）

**发现 H-A（本次评审核心发现——human 点名的选择偏差问题，生效前强制
修订）**：rev.1 写了「不得改 ES 或 IS₀ 凑数」，但**未锁死 campaign
setup 程序**，以下逃逸路径未被结构性封闭：试 IS₀₁ → t₀ 不满足 → 换
IS₀₂ → …… 直到找到合格 cell（隐性 resampling）。且 rev.1 未回答
human 三问：**Cons 是什么版本、依据什么 Spec、在什么时候判定**。

rev.2 强制补入（campaign setup lock）：

```text
① (ES, IS₀) 选择一次性：按预先登记的选择准则（formation 材料齐备/
   真实形成路径/符号名锚引用）选定一对，选择准则的执行不依赖任何
   t₀ 评估结果；
② t₀ 判定一次性：Cons(ES,IS₀) 按 R2 rev.2 候选定义、依 R3-1 Spec
   rev.2（RATIFIED）程序、在 campaign setup 阶段（任何 ΔIS 存在之前）
   机械评估一次；
③ 结果二值且终局：true ⇒ cell validity 对全战役固定；false ⇒
   setup = INVALID，全部评估记录保全，STOP——**重设新 (ES,IS₀) 属
   新 setup，须新 human authorization，失败 setup 保存为证据**
   （R-C1 attempt 纪律）；
④ per-cell t₀ 重评估 = 仪器一致性复算（同输入必同输出）：任一 cell
   的 t₀ 结果与 setup t₀ 不一致 ⇒ 仪器疑云 ⇒ 整批 INCONCLUSIVE。
```

其余核查：t₀ 无法判定（结构性 NOT-EVALUABLE）⇒ S-1 STOP、明文禁止
换 ES 凑可判定性（rev.1 §7 S-1 已有，rev.2 保留）——**停止而非换数**。✓

## 2. Check 2 — ES fixation

- 工件哈希足否？**发现 H-B**：rev.1 未规定**判定基线的驻留规则**。
  若任何判定基线（formation 摘要/证据声明/前置声明）驻留在 IS 侧，
  ΔIS 即可能触碰基线自身——研究被倒置。rev.2 补入：**全部判定基线
  ES-artifact 驻留**（IS 只含可引用对象与 mutation 记录
  [invalidation/supersession]，永不含判定基线）；ES 工件与 IS 存储
  **物理不相交**，IS 操作永不触碰 ES 存储路径。
- formation 与运输区分：rev.1 有「真实形成（运输非构造 D6）」但未写
  provenance 链。rev.2 补入 O-A：setup 记录含 formation provenance
  （真实系统运行形成 → 工件导出 → 哈希钉定 → 运输入 fixture）；
  **fixture 组装属 campaign setup、非被测 ΔIS**（每 cell 首个被测
  事件是 ΔIS 或 K-0 no-op）。✓（其余：哈希核验每 cell 前后，rev.1
  已有。）

## 3. Check 3 — ΔIS classification（H-1 贯彻核查）

- 构造规则先于结果：✓（§4 规则冻结 + construction record 先于评估 +
  重分类禁令）。
- post-hoc 路径排查：**发现 H-F**——类别指派规则虽冻结，但「按规则
  指派」若为人工执行仍有自由度。rev.2 补入：**类别由冻结规则从操作
  id 机械推导**（非人工指派），adjudication 可复核规则一致性；
  **IS-X 词汇封闭**：X 操作=已冻结单变量目录操作的组合，执行期不得
  引入新操作类型（堵住借 X 扩战役的口子）。

**结论：H-1 完整贯彻且闭合最后自由度。**

## 4. Check 4 — IS₀ isolation

- per-cell 新拷贝 from 钉定 IS₀：✓（IS₁ 永不作下 cell 输入）。
- **发现 H-E**：拷贝机制的正确性依赖「canonical IS₀ 永不被写」——
  rev.1 未设事后核验。rev.2 补入：**每 cell 结束后复验 canonical IS₀
  哈希**（+ES 哈希=双复查）；cell 的 IS₁ 拷贝归档为只读审计工件。
  累积污染被「源头钉定+新拷贝+事后复验」三重阻断。✓

## 5. Check 5 — Spec → observation（人工语义判断排查）

逐签名排查「看起来确定、实际需人工判断」：

**发现 H-C（实质发现——I-UNSTRUCT 二义性）**：rev.1 映射表把
「评估规则引用的 IS 结构不存在」一律导向 I-UNSTRUCT（仪器疑云）。
但在 cell 结构内这是错的：**t₀ 已干净执行 ⇒ 结构当时存在 ⇒ t₁ 缺失
只能是 ΔIS 所致（唯一变量）⇒ 这恰是 I-condition 的定义主体
（「IS 不使其不可判定」被违反）= I BROKEN**，不是仪器疑云。Spec
rev.2 §5.3 的「非 ΔIS 原因」限定词已蕴含此分野，rev.1 映射表把它
压平了。rev.2 修正映射：**in-cell t₁ 结构缺失 ⇒ I BROKEN（签名
I-STRUCT-REMOVED）；setup 阶段结构缺失 ⇒ NOT-EVALUABLE（S-1 路径）；
仪器疑云读法仅适用于 setup 阶段**。零命题变更（恢复 a 子句本义）。

**发现 H-D（fixture 确定性钉定）**：三处残余裁量空间——①引用解析
的「命中」判据未钉死；②C-DECL 声明程序类型开放；③时间类声明条件
的参照时钟未定。rev.2 补入：**引用解析=精确键匹配**（禁模糊/语义
匹配）；**C-DECL 检查类型白名单**（scope-tag 隶属 / 有效期对
setup 钉定时间戳 / 依赖引用解析）；**时间参照=setup 记录冻结的
时间戳**（非评估时墙钟）。✓ 其余签名（摘要比对/记录存在性）本即
机械。✓

## 6. Check 6 — Control integrity

- K-0/K-1 预测先于结果：✓（§4 construction record 机制承载，预测
  随构造记录冻结）。
- **发现（并入 H-B/H-E）**：ES 完整性对照与实验变量的耦合可能性被
  「物理不相交（H-B）+ 事后双复查（H-E）」结构性排除——哈希检查
  本身只读、且不与 IS 共享存储路径。✓

## 7. Check 7 — Failure / INCONCLUSIVE（重叠与逃逸）

四类非成功出口的边界核查：

```text
NOT-EVALUABLE   条件对本 ES 类别结构性不可判定 ⇒ §6.3 出口核算 ⇒
                结构性 ⇒ S-1 STOP（不可继续）
instrument_doubt 观测路径缺陷签名 ⇒ cell INCONCLUSIVE
setup-invalid   campaign 级 t₀ ≠ true ⇒ INVALID + STOP（H-A 锁死后
                不可重试凑数）
不可归因击穿    BROKEN 无签名且无构造解释 ⇒ cell INCONCLUSIVE
```

**「真失败包装成 INCONCLUSIVE 继续」排查**：
- 逃逸尝试一：把定向击穿标成 instrument_doubt？——H-C 修正后，
  t₁ 结构缺失已被正确导回 I BROKEN；A-UNRESOLVABLE 在 t₀ 干净前提下
  **按构造不可能**（引用形式驻留于固定 ES；t₀ 可解析 ⇒ 形式良构；
  t₁ 的差异只能是 A-NF/A-SUB）——其出现即观测路径缺陷的真信号，
  冒用会立即被 setup/复算对照暴露。✓
- 逃逸尝试二：把 BROKEN 降级为 NOT-EVALUABLE？——NOT-EVALUABLE 触发
  §6.3 出口核算且结构性即 S-1 STOP：**包装的代价是停止而非继续**，
  无激励相容漏洞。✓
- 逃逸尝试三：setup-invalid 后换料重试？——H-A 锁死。✓

**结论：无「失败→INCONCLUSIVE→继续」通道。**

## 8. Check 8 — Scope

- 模型推理：§1 显式排除，程序中无任何模型调用点。✓
- R3-4 解释走私：预测=构造时机械推导；all-TRUE⇒NOT SUPPORTED 为
  结果类目（Spec §6.2 已授权），无提前解释。✓
- 战役扩大：IS-X=占位+H-F 词汇封闭；内容寻址变体=显式 defer（§2.5）。
  ✓ **零泄漏。**

## 9. 发现汇总

```text
H-A  强制（生效前）  Campaign setup lock：一次性选对+一次性 t0 判定
                     （版本/Spec/时点钉死）+失败即 INVALID+STOP+保全，
                     重设须新授权；per-cell t0=仪器一致性复算
H-B  强制（生效前）  判定基线 ES-artifact 驻留规则+ES/IS 物理不相交
                     +formation provenance 链与 setup-非-ΔIS 声明
H-C  强制（生效前）  I-UNSTRUCT 二义性修正：in-cell t1 结构缺失⇒
                     I BROKEN（I-STRUCT-REMOVED）；仪器读法仅限 setup
H-D  强制（生效前）  Fixture 确定性钉定：精确键解析/C-DECL 白名单/
                     setup 钉定时间戳
H-E  收紧            canonical IS₀ 事后复验+ES 双复查+IS₁ 只读归档
H-F  收紧            类别机械推导（非人工指派）+IS-X 词汇封闭
```

全部为收紧性/澄清性条款，零命题变更、零研究对象变更。

## 10. 判定与处置

```text
Cell validity       = PASS after H-A（human 特别聚焦问题获结构性回答）
ES fixation         = PASS after H-B
ΔIS classification  = PASS after H-F（H-1 完整贯彻）
IS₀ isolation       = PASS after H-E
Spec→observation    = PASS after H-C/H-D
Control integrity   = PASS
Failure/INCONCLUSIVE= PASS（无逃逸通道）
Scope               = PASS（零泄漏）
────────────────────────────────────────────────
VERDICT = PASS WITH RECOMMENDATIONS（无 blocker）
处置    = rev.2 机械补入 H-A…H-F → R3-2 Design = RATIFIED
          （正式实验设计）；execution 仍须独立 human 授权
```

## 11. 边界声明

- RATIFIED = 设计可作为正式实验设计；**R3-2 execution（fixture 实现+
  cell 运行）须独立 human 授权**。
- O-A（provenance 链）随 rev.2 入档；无遗留观察。
- 全部排除清单维持。
