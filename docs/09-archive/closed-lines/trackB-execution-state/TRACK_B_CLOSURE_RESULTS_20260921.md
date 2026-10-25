# Track B Closure Experiment 结果(2026-09-21)

> **终审判定(2026-09-21):PASS / FREEZE——Track B 正式关门。**
>
> 审核按 v4 实际提交内容(acbcb54)三层复审,**语义、可证伪性、结果
> 与语义一致性全部成立**:
>
> 1. **G5 discard 语义闭环**:v3 的 "parent state @P + childNext"
>    非法组合(State(position=P) + Input(position=C) 不构成合法
>    execution state)已真正消失;v4 = parent @P +
>    parentInputBeforeFork,严格满足 discard = child 的执行结果全部
>    丢弃、parent 保持 fork 前状态继续(discard ≠ adopt),且该语义
>    已写入实验记录而非只改代码。
> 2. **parentInputsAgree 是真可证伪条件**:双侧父代 next-input 各自
>    独立产生后再断言相等,使"两个 parent continuation 本就处于同一
>    execution position"成为**可失败的实验条件**,能真实拦下
>    position/input 错位,非装饰性 assert。
> 3. **5/5 由此才有 Closure 意义**:⑤ 验证的不再是"child 做过工作
>    parent 后来也能继续",而是完整 discard lifecycle 语义链
>    (fork → child speculative work → discard → parent state
>    unchanged → parent uses own pre-fork next-input → parent
>    continues → continuation boundary remains correct)。热节流
>    (τ̂=7.8)只影响性能观察;G1/2/3/5 为 correctness/semantic 门,
>    与策略解耦——正确性证据未被污染。
>
> **范围纪律(冻结表述钉死,阻止未来把 5/5 再解释为性能验证):**
>
> Closure v4 proves lifecycle semantic correctness under the tested
> execution position; it does not prove performance superiority,
> estimator robustness, or general residency behavior.
>
> Closure v4 证明的是所测试执行位置下的生命周期语义正确性;不证明
> 性能优越性、不证明估计器鲁棒性,也不证明 Residency 行为。
>
> **冻结状态:**
>
> ```
> Track B — Execution State Lifecycle
> Status: CLOSED / FROZEN
>
> Verified:
>   Fork / COW / Continuation / Multi-branch lifecycle / Reattach /
>   Migration / Migration tax / Adaptive decision /
>   Discard semantics / Parent continuation preservation
>
> Known limitations:
>   τ̂ thermal sensitivity
>   performance variance under thermal throttling
>   estimator robustness not closed
>   Residency not tested
> ```
>
> 其中 **Residency ≠ Closure**。
>
> **审计链(v1→v4,完整史料,不删错)**:v1 cache position 错位 →
> v2 state/position 对照错位 → v3 parent state + child input(adopt
> 混入 discard)→ v4 parent state + parent input(真 discard
> semantics)。审计逐轮逼近的最终模型:**Execution State = KV +
> Execution Identity + Execution Position + Next Input +
> Continuation Semantics**(与 F5-1 mInput 前后呼应)。v4 为 Track B
> 正式终点,不再有 v4.1。
>
> **研究问题正式切换**:从"Execution State 是否成立"(已答:**在已
> 测试边界内,是**)切换到"Execution State 如何跨 Residency 边界而
> 不丢失 Identity / State / Continuation"。下一步定序:① 本冻结 →
> ② #629 技术报告审定 → ③ Residency M1(resident → externalized →
> rehydrated → continue;Track 命名待真源定夺)→ ④ exp06 M1 并行 →
> ⑤ Residency M2–M4 → ⑥ Residency Policy → ⑦ Execution + Residency
> 双 Policy → ⑧ Future 2.0 Architecture。

> **审计响应增补 v4(2026-09-21,已被终审判定取代,史料)**:审核正式接受 v3 的
> G2(迁移单元契约),但推翻 G5——v3 discard 了 child 却把
> `childNext` 喂给父代:"旧 parent state @64K+96 + input 产生自
> @64K+96+64+8" 不是合法 execution state;那是 **adopt 语义**,代码
> 只做了 discard(v1/v2/v3 同一错误族第三种形态;commit message 里
> "continue from their own child's next-input" 一句即自证)。**修复
> (审核最小方案)**:fork 前保存父代自身 next-input
> (`parentInputBeforeFork = inputL` / `twinParentInputBeforeFork =
> pCtrl`),child 的 next-input 只在 child 分支内使用;discard 后双侧
> 父代各自从 **fork 前自身 next-input** 续 4 步;新增可证伪断言两侧
> parent next-input 独立产生且相等。叙事同步修正:discard =
> "parent remains intact",非 commit/adopt。**v4 重跑(acbcb54,已推
> fork):5/5 全过**——①四路 96/96;②KV 逐元素 + 边界输入携带;
> ③decision@8;④预注册门过(regret +2.9% 描述性;本轮重热节流:
> cFresh 125.6ms、观察窗步均 ~1106ms、τ̂=7.8 窗口末触发,正确性与
> 策略解耦);⑤child 门/边界一致/父代 next-input 一致/discard 后从
> 自身 next-input 续跑/offset+4 全绿。**待审核方对 v4 作冻结终判;
> 9a5d91b 保持为审计修复中间版本。**

> **审计响应增补 v3(已被 v4 取代,史料)**:外部审核对 5e39800
> (v2)判定"未最终封口",两处成立——**G2 伪断言**(reattach 不修改
> inputL,`inputL == inputBefore` 为变量自比恒真)与 **G5 对照位置
> 错位**(discard 后 lifecycle@64K+96+64+8 vs twinP@64K+96,且 child
> 门本身 child@232 vs twinQ@136 亦错位)。修复:**A** 迁移做成可测
> 单元 `migrate(caches, state, nextInput)` 三元组整体搬运,边界断言
> 针对迁移单元契约(mInput 丢失 bug 类别的回归拦截),下游消费迁移
> 单元带回的 input;**B** 双分支同位对照——twinP 同形 fork twinChild,
> 双侧 suffix+8→discard→父代从各自 child 的 next-input 续跑,每处
> 对照位置/输入对齐,分支边界输入独立产生并断言相等(可证伪)。
> **v3 重跑(9a5d91b):5/5 通过但 G5 语义错误被 v4 审计揭出**——
> 热节流观察(cFresh 106.7、窗步均 403ms、τ̂=2.78)已并入 v4 的
> τ̂ 热敏感记录(中位数鲁棒窗口 = 后续工作)。

**性质**:2.0 Track B 收官实验——不发现新东西,把已分别验证的机制
串成**一次完整生命周期**(承审核定序:"少做一点",不加新变量)。
**代码**:`Tests/MLXLMTests/TrackBClosure.swift`(通过,463s;
64K@S4、N=96 真实 continuation、observe_k=8、现行 policy 与 reattach、
现行不变式——全部固定)。

## 生命周期叙事(一次串联)

```
Fork(0.028ms, 40 层)
  ↓ COW 继续生成(13 步,观察窗 k=8)
tax 出现(τ̂=0.138)
  ↓ estimate → decision@13
Reattach(73ms,10 attention 层)
  ↓ Continuous 继续生成(83 步)
same continuation(四路 96/96)
  ↓ 迁移后:merged 父代再 fork → 分叉 → discard → 父代续跑
完成
```

## 验收 5 项(审核清单,仅此 5 项)——**全过**

| # | 验收 | 结果 |
|---|---|---|
| ① Correctness | 全程 continuation 一致 | **L==P ✓ L==C ✓ L==R ✓(各 96 token)** |
| ② Identity | 迁移前后 execution identity 保持 | KV 逐元素一致 ✓ + next-input 连续 ✓ |
| ③ Adaptive decision | 实际发生 stay→decision→reattach | decision@13(0<13<96)✓,非强制预迁移 |
| ④ Performance | 总成本 ≤ 两纯策略(+10% 容差) | L 7,169 vs COW 13,722 / R 13,012 → 预注册门 ✓(**见下方诚实性注记**) |
| ⑤ Lifecycle | 迁移后 fork/discard/续跑不破坏语义 | merged(KVCacheSimple)父代再 fork 出 COW 子代 ✓、子代门 ✓、discard 后父代续跑 ✓、offset 精确推进 ✓ |

**v1 失败如实记录**:首跑 gate1/gate5 失败,根因 = P twin 对照跑在
cacheP 上,而 cacheP 已被标定推进 30 步(位置错位)。v2 修正:cacheP
保持纯净 @64K,一切 P 侧对照用 COW fork 副本(O(1)、位置精确;
root-unfreeze 模式的复用)。修正后全过——**failure 本身再次演示了
统一不变式的价值:对照必须在同一 execution identity(位置)上比较**。

## 诚实性注记(④ 的数字不外推)

**regret −44.9% 不得作为性能结论**:closure 按叙事顺序执行(L 先、
C/R 后),本机无风扇,热节流使后跑路径步均 134–143ms vs L 连续段
70.9ms——顺序偏差主导了差距。**④ 的判定有效性 = 预注册门形式
(≤ max+10%)通过;性能的公正数字仍是 F5-3 S2/S3 的交替对照
(regret +0.9%,含双赢操作点 −1.0%)。** closure 的目的是正确性串联,
不是 benchmark。

## 阶段性结论(采用审核批准表述)

> **Track B demonstrates an execution-state representation that can
> be shared, transitioned, and adaptively selected during execution
> while preserving execution identity and continuation.**
>
> **Track B 验证了 execution state 可以在执行生命周期内进行共享、
> 表示迁移与自适应选择,并在表示变化过程中保持 execution identity
> 与 continuation 不变。**

三问闭环:①共享 execution state 能否安全存在(F1–F4:散射写语义、
多级段表、四指标、解冻门、回收复用)✓;②共享表示的性能成本能否
消除(F5-1/2:reattach 全矩阵回 fresh,perf-tax BE 中位 ~4 tok)✓;
③系统能否自主选择表示(F5-3:在线估计 + adaptive,真机 regret
+0.9%,存在优于两极端的操作点)✓。

## 决策

1. **Track B 核心架构命题闭环,探针/实验阶段收官。** 按审核预排
   进入:**归档 → 总结 → RFC/论文式技术报告(#629 follow-up 主体)
   → 开 Track C(Model-State Residency)**。
2. 同构映射(审核已给,正式入档):execution state↔model state、
   COW/continuous↔resident/non-resident、表示税↔传输税、
   reattach↔prefetch/materialize、discard↔evict、在线税估计↔在线
   带宽/延迟估计、adaptive representation↔adaptive residency。
   TurboFieldfare / DeepSpeed / FlexGen 作为 prior art / external
   baseline 进 Track C 框架。
3. 观察项移交 Track C/后续:closure 中连续段步均(70.9)低于 cFresh
   标定(84)的倒挂现象(疑热节流 + 缓冲布局交互)不影响验收,
   留作微架构级好奇项(Instruments 时机由未来需要决定)。
4. 边界重申:全部代码仅在 `exp/execution-state-fork` 实验分支;
   Track B 结论不构成 2.0 发布承诺,迁移生产唯一通道 = Level 门。
