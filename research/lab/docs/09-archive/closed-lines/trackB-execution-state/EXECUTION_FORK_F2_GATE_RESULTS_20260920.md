# Execution Fork F2 门结果(2026-09-20)

**性质**:2.0 Track B 第二个实验(探针 → 结果 → 决策,承 F1)
**代码**:`~/Documents/mlx-swift-lm` 分支 `exp/execution-state-fork`
`Tests/MLXLMTests/ExecutionStateForkF2Gate.swift`(E5 + F2b,2 测试全绿)
**运行**:同 F1(xcodebuild,suite 级过滤;~41s 含模型加载)
**模型**:`Cyber-Tiel-Coder-35B-A3B-MLX-oQ4e`(HF 本地缓存,snapshot
b867c9da;qwen3_5_moe,40 层 = 10 attention + 30 GDN,kvHeads=2 ×
headDim=256 fp16 → **20KiB/token 全模型**——F1 假设的 24KiB/token 修正
为此值),加载后 resident ≈ 20,126MiB
**机器**:同 F1(MacBook Air M5 32GB)

---

## 探针(两问)

- **F2b(报告 §5.1 验收指标 4,一票否决)**:真模型 fork → 双分叉 → 逐
  token greedy 一致门;
- **E5(F2a)**:单写者 slack fork(父代缓冲余量内直接续写)能否归零
  F1 发现的 concat decode 税。

## 结果

### F2b 一票否决门:**通过**

设置:公共前缀 2,048 token(chunk 512 prefill)→ fork ×2(40 层)→
X/Y 各自不同后缀 128 token 续跑 → greedy decode 16 步;控制组 A =
同 chunk 边界从零 prefill(prefix+suffix)再 decode。

| 项 | 值 |
|---|---|
| fork ×2(40 层) | **0.061 ms** |
| 正确性门 | **逐 token 一致,16/16 步全对** ✓(fork X == 控制组 A) |
| 分叉真实性 | X 与 Y 后缀不同 → 续跑 token 流完全不同 ✓ |
| 模型级记账 | attention 10 层 page-split(shared 20,480 行 + private used 1,440 行);GDN 30 层引用 fork 零拷贝 |
| 物理增长 | **used 行 = 1.00× 后缀(1,440/1,440)精确**;padded = 1.78×(step-256 对齐,随深度摊销 →1)。(注:测试打印的 17.78 是记账笔误——分母少乘 10 层,真实值如上) |
| shared ratio | 0.889(padded 口径) |
| X 增量内存 | ≈ 10.0 MiB(后缀 144 token × 10 层) |
| 父代冻结 | attention offset 全部保持 2,048 ✓ |
| P prefill 基线 | 2,048 token / 14.8s ≈ 138 tok/s(M5 Air,35B oQ4e——exp06 M1 的一个先行数据点) |

**控制组 B(单发全量 prefill)信息项**:与 fork 漂移 9/16 步——
chunked 与单发 prefill 的归约数值差异,**与 fork 语义无关**。这证明
一致门的正确对照必须是"同 chunk 边界从零"(控制组 A 设计成立);
严格的"单发从零"版本会把 chunking 数值学混进门里,门规应按此理解
(报告 §5.1 指标 4 的可执行化:对照 = 同调度从零)。

**state 线程化**:Qwen35 的 `LMOutput.State`(mrope 位置/锚定元数据)
是 execution state 的组成部分,fork = 直接传递(Swift 字典值语义,
天然 COW)——`可恢复 execution identity` 概念在真模型上落位。

### E5 slack fork:零税 fast path 成立(单写者边界内)

| 路径 | ms/token(深度 65,528,单层) |
|---|---|
| baseline monolithic | 3.055 |
| **slack-fork 子代** | **2.474**(≤ baseline;父代缓冲余量内直写,零 concat 零私有存储) |
| page-split COW(F1 路径) | 3.472(**1.14×**,本次)vs F1 E3 测得 2.36×(post-clearCache 冷分配器) |

- 正确性:slack 子代终视图 == monolithic 同流同深度**逐元素相等** ✓;
  父代 offset 冻结 ✓;
- **COW concat 税的量级随分配器状态浮动(1.1×–2.4× 观测区间)**,
  结构性结论不变:page-split 每 token 付 concat 物化;slack 路径零税;
- slack 边界:余量 = capacity − offset ∈ [0, 256),prefill 对齐 fork
  时余量为 0,decode 至多 256 步后触发一次 O(depth) 增长拼接——与
  baseline 自身的 step-256 增长机制同型,非回归;
- 注:mono 先跑(冷)slack 后跑(热),顺序效应存在;结构性结论
  (slack ≤ baseline < COW)两次运行方向一致。

## 决策

1. **验收指标 4(正确性门,一票否决)通过**——fork 语义在真模型、
   真分叉、含 30 层 GDN 引用共享 + 10 层 page-split 混合构成下,
   逐 token 无损。**报告 §5.1 四项验收指标的探针级证据链闭合:**
   ①Fork Cost 0.061ms(模型级)✓;②Restore Depth 仍缺(下);③Shared
   Ratio 0.889(padded)/精确增长 1.00× ✓;④逐 token 一致门 ✓。
2. **形态定论(三档 fork 策略)**:
   - 单未来、父冻结 → **slack fork**(零税,产品工作流即此形状);
   - 多未来 → page-split(税 ∈ [1.1×, 2.4×],F2 剩余工作 = 消解);
   - 长寿子代跨 step 边界 → 增长拼接与 baseline 同型,可接受。
3. **F3 工作清单**:
   a. COW concat 税消解:视图缓存(私有未变复用)+ 与 #1849 分页直读
      合流评估;
   b. Restore Depth 曲线(A→B→C→D 级联 fork / 父代 LRU 驱逐后从盘恢复);
   c. 长 depth(≥32K)fork 记账 + 模型级 decode 税精确计时
      (本次 greedy 未单独计时);
   d. N>2 fork 树的 shared page accounting。
4. 边界重申:全部代码仅在 `exp/execution-state-fork`,永不进 1.7 路径。

## 与 F1 的增量闭环

| F1 遗留 | F2 裁定 |
|---|---|
| 数组级正确门(单层合成数据) | 真模型逐 token 门 16/16 ✓(含 GDN 30 层) |
| concat 税 2.36×(单点) | 税随分配器状态 1.1–2.4×;slack 路径 0× |
| GDN 引用 fork(kernel 级) | 模型级 30 层零拷贝双向隔离复证 ✓ |
| fork 0.020ms(单层) | 模型级(40 层 ×2)0.061ms ✓ |
