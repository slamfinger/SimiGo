# Execution Fork F1 探针结果(2026-09-20)

**性质**:2.0 Track B 第一个可运行实验(探针 → 结果 → 决策,承 F0)
**代码**:`~/Documents/mlx-swift-lm` 分支 `exp/execution-state-fork`(基于
8f37dbc 实验室 vendor 检出;**生产 pin dc3ca61 未参与任何工作流**)
`Tests/MLXLMTests/ExecutionStateForkF1Probe.swift`,4 实验全绿(~25s)
**运行**:`xcodebuild test -scheme mlx-swift-lm-Package -destination
'platform=macOS' -skipPackagePluginValidation -only-testing:MLXLMTests/ExecutionStateForkF1Probe`
(`swift test` 在本仓不可用——metallib 加载失败,见 CLAUDE.md)
**机器**:MacBook Air,Apple M5,32GB(mlx-swift 0.31.6 pin)
**形状**:Qwen3.5 35B(oQ4e)单 attention 层 GQA 近似——kvHeads=4,
headDim=128,fp16 → 2KiB/token/层,×12 attention 层 = F0 实测 24KiB/token。
探针在单层测,跨深度换算见各行。

---

## 探针(四问)

- **E1** `copy()` 成本时间线——补 F0 §5"惰性物化未独立计时"欠账
- **E2** 裸引用共享的就地写语义——散射写是否穿透共享缓冲(决定 page-split 是否强制)
- **E3** page-split fork 原型(共享前缀只读 + 私有后缀)——Fork Cost / 物理增长 / 正确性门
- **E4** GDN 递归态(MambaCache)引用 fork——函数式更新是否零拷贝双向隔离

## 结果

### E1 copy() 成本时间线(F0 推断全量证实)

| depth(单层 KV) | copy() 调用 | 子代首次 update+eval | 稳态 update+eval | 首写后 active 增量 |
|---|---|---|---|---|
| 16,384(32MiB) | 0.053 ms | 2.06 ms | 1.59 ms | +34,816 KiB(≈1×KV+后缀) |
| 65,536(128MiB) | 0.046 ms | 4.23 ms | 4.68 ms | +133,120 KiB(≈1×KV) |
| 131,072(256MiB) | 0.095 ms | 19.3 ms | 20.7 ms | +264,192 KiB(≈1×KV) |

- `copy()` 调用 = O(1) 惰性(0.05–0.14ms),**零即时成本、零即时内存**;
- 首次物化成本与稳态同阶(无独立尖峰)——因为**稳态 update+eval 本身就
  每步支付 O(depth)**(返回视图 `keys[..<offset]` 每次新建惰性切片,
  eval 物化;1.6/4.7/20.7ms @16K/65K/131K,线性);
- 常驻 = **2×KV**(+1×来自物化副本),F0"1×KV memcpy + 2×KV 常驻"推断证实;
- 父代永不污染(惰性切片物化到独立缓冲)✓。

### E2 就地写语义(定性钉死)

- **Q1** 子代写 rows[D,…) 后父代 rows[0,D) 完好 ✓(行区间不相交即安全);
- **Q2** 子代写入**出现在父代原始缓冲** rows[D,…) ✓ → **MLX 散射写就地、
  缓冲真共享**(非功能性替换);
- **Q3** 父代随后写同区间,子代后缀被覆盖 ✗ → **双写冲突真实存在**。

**结论**:单写者下裸引用 fork(零拷贝零元数据)语义安全;多未来
(multi-future)下 page-split(后缀私有化)是**强制项**——共享的是缓冲,
不是行区间。

### E3 page-split fork 原型(报告 §5.1 验收指标 1/3 落地)

原型:`COWForkKVCache`(探针内嵌,非生产 API)——共享前缀(父代原始
缓冲只读引用)+ 私有后缀(step-256 自增长,同 KVCacheSimple 策略)+
返回视图 `concatenated(共享前缀, 私有已用行)`。

| 指标 | 值 | 判据 | 判定 |
|---|---|---|---|
| Fork Cost | **0.020 ms** | 亚秒级(基线:磁盘 fork 1.94s @63.6K) | ✓ ~10⁵× 基线 |
| 物理增长 | **1.00 × 后缀**(4,096KiB 私有 vs 4,096KiB 理论后缀 @suffix 2048) | ∝ 分叉后缀,非 ∝ 全深度 | ✓ 精确 |
| Shared Page Ratio | **0.97**(前缀 65,536 / 物理 67,584 行) | 显著高于基线 | ✓ |
| 正确性门(数组级) | fork 终视图 vs monolithic **逐元素相等** | 一票否决 | ✓ |
| 父代完整性 | rows[0,D) 在子代写入后完好 | — | ✓ |

**代价(重要)**:decode 步(update+SDPA+eval,@深度 67,712,单层):
baseline 1.616 ms/token vs COW 3.817 ms/token = **2.36×**。机制:朴素
concat 视图每 token 物化 O(depth+suffix)。**这是实现的税,不是语义的税**
(F2 消解方向:视图节点缓存——私有缓冲未变时复用上次 concat 结果;
或 #1849 式 paged attention 直读页表,免物化)。

### E4 GDN 递归态 fork(报告 §5.1"架构利好"证实)

- fork(引用传递)= **0.0076 ms**,零拷贝零增长;
- 子代续跑(真实 gatedDeltaUpdate kernel)后父代态完好 ✓;
- 父代续跑后子代态完好 ✓ → **双向隔离,fork=纯元数据**;
- 扰动 k 双路续跑 → 终态真实分叉 ✓(注:扰动 q 无效——GDN 状态转移
  只依赖 k/v/a/b,q 仅影响读出;探针踩过此坑)。

GDN 更新是**函数式**的(`state = out[1]` 换新数组),与 attention KV 的
**就地散射写**形成互补对称:前者 fork 天然安全,后者必须 page-split。
qwen3_5_moe 混合布局的两半恰好各自落位。

## 决策

1. **止损条件①解除**:fork 未退化为 O(depth) 全量拷贝——page-split
   原型 Fork Cost O(1)、物理增长精确 ∝ 后缀、数组级正确性门通过。
   **Track B 继续,无止损触发。**
2. **验收指标进度**:指标 1(Fork Cost)与指标 3(Shared Page Ratio)
   探针级达成;指标 2(Restore Depth)与指标 4 终极形态(**逐 token
   greedy decode 一致门**)未测——需真模型集成,列 F2。
3. **F2 工作清单**(按优先级):
   a. 视图物化税消解:concat 视图缓存(私有未变则复用)/ paged
      attention 直读(与 mlx-lm #1849 合流点);
   b. 真模型集成:12 层 attention × page-split + 48 层 GDN 引用 fork,
      **逐 token greedy decode 一致门**(一票否决);
   c. Restore Depth 曲线(A→B→C→D 多级 fork/restore);
   d. 多级 fork 树(shared page accounting 跨 N 代)。
4. **跨轨输入(exp06)**:E1 旁证——稳态 update+eval 每步 O(depth)
   (返回视图物化),单层 1.6ms @16K→20.7ms @131K 线性。若真模型 decode
   路径同机制,则 decode 带宽中存在 **~2× 读放大**(视图物化写 + SDPA 读),
   这是"实测/地板比值"的一个先行机制假设,exp06 Roofline 对账应将其
   列入逐算子归因清单。
5. 边界重申:本探针代码只存在于 `exp/execution-state-fork` 实验分支,
   永不进入 1.7 发布路径;迁回生产唯一通道 = Level 门。

## 与 F0 的对照闭环

| F0 推断/欠账 | F1 裁定 |
|---|---|
| copy() 惰性,首次 eval 物化(未计时) | 证实:O(1) 调用 + 首写物化,物化≈稳态成本,常驻 2×KV |
| 公开面无 sequence identity | 成立(未动公开面;page-split 在子类层实现) |
| 磁盘 fork 1.53GB/1.94s @63.6K | page-split fork 0.020ms @65.5K,~10⁵× |
| "GDN 不可 trim/rewind 不构成 fork 障碍" | 证实:GDN 引用 fork 零拷贝双向隔离 |
| copy() 语义 = independent deep copy | 证实且量化:惰性化不改变 2× 常驻结局 |
