# SimiGo-Lab R3-1 Gate Review — Condition Observability Readiness

日期：2026-10-03
状态：**EXECUTED / VERDICT: NO BLOCKER / READY TO OPEN**
授权：human「开启 R3-1 Gate Review」（2026-10-03）——授权对象为**评审本身**，
非 R3-1 实施、非实验、非代码。
评审基础：已封存文档（R3-0 设计 @1c8c463、R2 rev.2 形式化、Boundary
Synthesis 裁定、G-δR role taxonomy）+ 既有封存实验先例。零实验、零实现、
零代码。

## 0. 评审问题（human 原定）

> **I / A / C 三类 condition 是否已经具备独立、可观察、可记录、可判定
> 的操作性定义？**

六项检查：I / A / C / Attribution / Control / Failure。
出口规则（human 预定）：六项全部具备 → 建议 R3-1 AUTHORIZED（授权本身
归 human）；任一不具备 → 停止 / 修订边界。

## 1. Gate I — 是否存在独立且可重复的 I 判据？

**判定：CONDITIONALLY READY（无 blocker；操作性谓词属 R3-1 待产内容）**

已具备：

- Role 分解已成文（G-δR Appendix：I-1 模型绑定 / I-2 谱系绑定 / I-3
  载荷完整性交叉核对）——判据的对象结构明确，无需重新定义（R3-0 §4.1
  已锁定「引用不重定义」）。
- 问题结构已定（R2 rev.2 a 子句）：I-condition = 「ES 的身份/谱系判据在
  当前 IS 语境下仍可评估（IS 不使其不可判定）」——判定对象是**可评估性**
  而非身份真值，天然机械可查。
- 历史可观察签名先例：Gδ-I 的 provenance conflation（identity-stripped
  record 被无差别接受=身份不可判定的实测实例）；P7-1 J-I1/I2 的
  model-binding 比对（`checkpoint.modelIdentity == server.loadedModelIdentity`
  的机械判定先例）；ES-R2 Gate B 的 carrier identity 断言独立读出。

待 R3-1 判定规范产出（非缺口，是工作项）：

- **I-谓词操作化**：枚举「ES 身份/谱系判据」的承载物（ES record 内字段
  vs IS 内容），并定义「不可判定」的可观察签名（解析引用 not-found /
  歧义命中 / 多义命中）。
- 登记一个开放经验问题（非 blocker）：若身份证据完全由 ES record 自身
  承载，则 IS 变化可能永远不触及 I-condition——R3-I cell 可能测出
  「I 恒真」。这不是设计缺陷，恰是 R3-N/边界研究的合法素材；判定规范
  须允许该结果如实登记，不得为产生「破坏」而构造 IS 变化。

## 2. Gate A — 是否存在独立且可重复的 A 判据？

**判定：CONDITIONALLY READY（无 blocker；一项 spec 决策必须先定）**

已具备：

- 三子句结构已定（R2 rev.2 b 子句）：存在 / 可寻址 / 未被静默替换——
  「替换须可检出」已内置于条件定义。
- 历史先例：PA-2（same count different content=silent substitution 的
  实验原型）；Gδ-A（same-I/P/C 不同内容⇒续算分叉=内容绑定区分力实测）；
  ES-R2 Gate B 的 anchor tailSHA256 比对（锚内容摘要判定的机械先例）。

必须先定的 spec 决策（R3-1 强制内容）：

- **A-判定立场**：引用解析必须走 **ES 自身存储的引用路径**（ES→IS 方向）；
  观察者可另持只读哈希作**审计**，但不得作为判定输入——否则判定平凡化
  （观察者永远知道答案）且构成 forbidden channel（观察通道代替状态自身
  解析能力）。
- **比较基线来源**：A-condition 的「未静默替换」判定需要一个内容摘要
  基线。基线必须来自 **formation 时的记录**（状态形成时的 provenance），
  禁止事后补造（no construct-then-claim 精神沿用）。签名=同一地址解析
  内容与 formation 摘要不匹配。

## 3. Gate C — 是否存在独立且可重复的 C 判据？

**判定：CONDITIONALLY READY（无 blocker；一项边界收窄必须先定）**

已具备：

- 结构已定（R2 rev.2 c 子句）：前置语义条件（settled results、
  preconditions）在 IS 中仍成立、未被废弃或取代。
- 机械可查签名的历史先例（最直接）：**R-B1 V-N 的 relation-not-found**
  （前置引用解析失败的机械签名）；R-C1 #4 的 relation artifact
  presence/absence（C-C 臂 relation 存在、C-B 臂 relation 缺席——同为
  证据级机械观察）；R2 IPAC Minimal Semantics Gate 的「applicability
  condition 必须能在不重执行 C 的情况下评估」原则（先于 R3 已裁定）。

必须先定的边界收窄（R3-1 强制内容）：

- **C-判定的机械化边界**：「仍成立」只按**机械可查形态**判定——引用
  解析 found/not-found + invalidation / supersession 记录存在性 + 声明式
  applicability 条件核对。**模型对内容是否「真的」仍成立的语义判断不得
  作为判定输入**——否则输出级观察从后门回流（违反总判定纪律）。
- 若未来需要语义级 C 判定，属边界修订，走 stop/revise 路径，不在 R3-1
  内静默扩展。

## 4. Gate Attribution — 能否把观察归因于 ΔIS 而非其他变量？

**判定：READY（结构完备；一项义务需成文化）**

已具备：

- 归因结构在设计中完备：ES 固定为最小单元前提；单变量 taxonomy
  （IS-I/A/C/B）先于复合 IS-X；Control/Treatment 因果结构；R2 Task 3 的
  归因纪律（不可归因=INCONCLUSIVE）已封存并被 R3-0 继承。
- 历史证据纪律可直接继承：R-C1 四尝试的 deviation 登记与 invalid run
  保全（implementation defect 伪装风险的制度化防御）；物理变更 before/
  after 哈希；隔离 204→204 计数核验；forbidden-channel runtime checks。
- 关键归因优势：R3 判定是**条件级机械观察**，模型行为不是判定输入——
  模型非确定性、资源波动等传统混淆源被结构性排除在判定通道之外
  （输出仅辅助观察）。

需成文化的义务（R3-1 强制内容）：

- **只读观察义务**：观察行为本身不得变更 IS（写前/写后哈希+隔离计数
  先例沿用）；观察通道与 continuation 通道分离。

## 5. Gate Control — 是否有足够的 invariant control？

**判定：READY（三层控制结构充分；一项预注册需补）**

已具备：

- 第一层：null-change Control `(ES,IS₀)→(ES,IS₀)`——同流程、ΔIS=0，
  吸收环境漂移/时间效应/仪器蠕变。
- 第二层：良性变化对照类（R2 Task 3 非破坏类：纯增量 / 不触及 /
  等价迁移）——ΔIS≠0 但预测条件不变，是比 null control 更锐利的
  specificity control。
- 第三层：R3-N 反证方向（non-break 搜索）——防「ΔIS⇒¬Cons」过强结论。

需补的预注册（R3-1 强制内容）：

- **Control 漂移条款**：Control 臂出现任何条件满足性变化 ⇒ 仪器疑云 ⇒
  该批次全部 INCONCLUSIVE（不进入判读；仪器审计先例=P5 audit、b3 异常
  处置）。

## 6. Gate Failure — 是否预先定义 NOT SUPPORTED / INCONCLUSIVE？

**判定：READY（四态出口与失败有效性已在案）**

已具备：

- 四态出口已注册（R3-0 §8）：SUPPORTED / PARTIALLY SUPPORTED / NOT
  SUPPORTED / INCONCLUSIVE；失败有效性条款继承（不得为使路线成立而修改
  判据）。
- RQ3-4 反例价值条款已注册：`IS changed ∧ Cons changed ∧ I=A=C=true`
  直接挑战 R2 候选形式——负结果=有效研究结果，预先登记。
- R3-1 自身的失败定义已在 R3-0 §4.1 写明：三条件若**不可**独立观察/
  记录/判定 ⇒ R3-1 自身 FAIL ⇒ 停止，不得进入 R3-2——本 Gate Review
  的任务正是预先确认这一点可达成（见 §7 总判定）。

## 7. 总判定

```text
Gate I           = CONDITIONALLY READY（谓词操作化为 R3-1 工作项）
Gate A           = CONDITIONALLY READY（A-判定立场 spec 决策为前置）
Gate C           = CONDITIONALLY READY（机械化边界收窄为前置）
Gate Attribution = READY（只读观察义务需成文化）
Gate Control     = READY（Control 漂移条款需预注册）
Gate Failure     = READY
─────────────────────────────────────────────────
VERDICT = NO BLOCKER / READY TO OPEN
```

六项检查**无原则性 blocker**。I/A/C 三项的操作性谓词不是本 Gate 的
缺口——它们正是 R3-1「判定规范」的待产内容；本评审确认其生产**不存在
已知障碍**，且各前置 spec 决策已经可以明确表述。

**R3-1 判定规范的五项强制内容（本评审登记）**：

1. I-谓词操作化：身份判据承载物枚举 +「不可判定」可观察签名；允许
   「I 恒真」结果如实登记；
2. A-判定立场：ES 自身引用路径解析；观察者只读哈希仅审计不作判定输入；
   比较基线=formation 时记录；
3. C-机械化边界：引用解析 + invalidation/supersession 记录 + 声明式
   applicability；模型语义判断禁作判定输入；
4. 只读观察义务：观察不变更 IS；观察通道与 continuation 通道分离；
5. Control 漂移条款：Control 臂任何条件变化 ⇒ 该批次 INCONCLUSIVE。

**边界声明**：本评审零实验、零实现、零代码；评审结论不等于 R3-1
授权——**R3-1 是否开启（进入判定规范生产）归 human 依本评审裁定**；
R3-2…R3-4 保持 LOCKED。
