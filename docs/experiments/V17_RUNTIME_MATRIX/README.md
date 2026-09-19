# V1.7-0 Runtime Benchmark Matrix（2026-09-19 开工）

**性质**：V1.7-0 首交付——systematic runner `tools/runtime_matrix.py`
（四路语义：Cold/Warm/Restore/Rebuild × 深度档 10K/40K/80K/120K ×
RAM/KV/Swap）+ 10K 冒烟结果 + 校准发现。

## Harness v0 已验证

- 端到端跑通：构建推深 → warm → restore → rebuild → cold → JSON 落盘
- 位置法完成行捕获（traceKey 短串免疫）、`[EXEC]` 血统行已被
  v1.6 Runtime 点亮（遥测与矩阵同源）

## 10K 冒烟发现（Cyber-Tiel，03:17 窗口）

| 路 | 实测 | 判定 |
|---|---|---|
| WARM（plain user 小 delta） | mode=rebuild，9,120 tok / 10.4s，cacheEff=0.00 | **非 extend**——账本失配触发重渲 |
| RESTORE（tool_calls 尾+小 delta） | mode=cold，18,493 tok / 24.3s，reuse=false | **restore 未触发**——账本已失配，退化为全新会话语义 |
| REBUILD（首消息变异） | mode=cold，18,066 tok / 23.2s | 符合预期（全量重渲基线） |
| COLD（全新 session 重放） | mode=cold，18,062 tok / 23.7s | 符合预期 |

## 根因假设（待校准验证）

**客户端回显形状分歧（cdd0272 类，机制此前已确认）**：harness 把
HTTP 响应的 assistant 消息（tool_calls.function.arguments 为 string）
原样回放，引擎账本存的是结构化 object → isPrefix 在首个带 tool_calls
的 assistant 处失配 → 之后每轮全量重渲。与 execution_bench 首跑
"轮间 assistant 回执入库缺失致全 cold"同族——**回显流的账本形状归一化
是矩阵测量的前置校准项**。

## 校准关闭状态（2026-09-19 晚，全部关闭）

1. ~~回显归一化~~ 关闭（C3 `normalize_assistant`，string→object 对齐账本）
2. ~~RESTORE 触发路径~~ 关闭（C5+C6 双根因修复，见下节）
3. ~~WARM 前置轮~~ 关闭（C1 assistant(normal) 尾制造）
4. ~~swap 采样单位~~ 关闭（正则 M/G 双单位兼容）

## C5/C6：restore 双阻塞根因（全部真机实证）

- **C5 max_tokens 截断**：build 轮默认 16 tok，record_note 调用
  arguments ≈30+ tok，截断的 tool_calls 被引擎整体丢弃（trace:
  `rejectedToolCall reason=incomplete_output`；实测 16→无 tool_calls、
  64→完整）→ 历史零 tool_calls → C2 扫空。rootfix 回归 JSON 的
  `toolCallId=null` 即此因。修复：build 轮 max_tokens=64。
- **C6 时序洗尾**：`rollforwardRisk` 只认账本尾 assistant(tool_calls)
  （ExecutionPolicy），C1 warm_setup 的 normal 尾洗掉风险尾，排在
  warm 之后的 restore 恒退化 cold。真机双向实证（同形状请求）：
  未洗尾 2.1s/617tok/rf=1 命中，洗尾后 26.8s/18616tok 全量。修复：
  restore 测量提前到 warm_setup 之前（C5 后 build 尾恰带完整
  tool_calls，是唯一合法测点）；restore 轮回复提示词不索要工具调用
  （16 tok 下截断 call 自造畸异尾会把 warm_setup 打成全量 rebuild）。
  证据：evidence/c5_c6_restore_hit_20260919.log。

## 第一个真实 restore 数据点（10K 档，results_c5c6_10k.json）

| 路 | wall | prefill tok | reuse | rf |
|---|---|---|---|---|
| warm | 0.9s | 195 | true | - |
| **restore** | **1.7s** | **611** | **true** | **1** |
| rebuild | 29.0s | 18,166 | false | - |
| cold | 25.8s | 18,162 | false | - |

**restore:cold ≈ 1:15（10K 档）**。10K 阶段 restore 真值格首次有值。

## 测量通道缺口（build 3 trim 副作用）→ 已关闭（build 4）

`211aa59`"trim success traces"把成功路径 `[MLX] session=` 完成行整行删除，
HTTP 响应无 usage，位置法捕获在 build 3 上曾退化 prefill 行推导。**build 4
（维护版，纯遥测零行为）恢复该行**：模式声明/赋值/日志三段原样回归
（`cacheReuseMode`/`cacheFork*` 字段源在 vendor pin 内未动），CFBundleVersion
3→4，SimiGoTests 73 tests / 0 failures（72 基线 +1 = tools=null 回归）。

## 正式矩阵（build 4，2026-09-19，results_build4_formal_matrix.json，全行 measured）

| 档（累计处理 tok） | 上下文≈ | warm | restore | rebuild | cold | RAM/swap |
|---|---|---|---|---|---|---|
| 10K | 18K | 0.7s | 1.4s | 24.2s | 25.7s | 22.0G/3.9G |
| 40K | 36K | 1.1s | 3.0s | 109.8s | 103.3s | 20.9G/4.2G |
| 80K | 72K | 2.0s | 6.0s | 310.5s | 306.0s | 20.4G/3.3G |
| 120K | 120K | 2.9s | **20.1s** | 882.6s | 674.5s | 23.6G/2.7G |

四项审核指标读数：

1. **Cold 吞吐拐点**：707 → 351 → 235 → 177 tok/s（18K→36K→72K→120K）。
   2× token 时间比：×4.02 / ×2.96 / ×2.20（幂指数 ~2.0→~1.55；步长阶梯
   2048/1024/512 换档是混杂变量）。**非线性从 36K 档即已确立**。
2. **Restore scaling**：1.4 → 3.0 → 6.0 → 20.1s，**delta 恒为 611 tok**，
   四档全部命中（reuse=true，cacheTokens=全账本 18.5K/36.4K/72.3K/
   119.9K）。restore tps 36.9→27.4→18.7→6.3——fork 拷贝成本随上下文
   上涨，120K 档超线性跳升（swap 压力嫌疑）。restore:cold = 1:18 →
   1:34 → 1:51 → 1:34，**120K 深处 restore 仍省 34×**。
3. **Fork 深度**：restore 的 fork 覆盖**全账本**（120K 处 =119,922 tok）
   ——复用深度=完整上下文，无深度天花板。build r2 的 fork@common 恒
   9,458 = r1 checkpoint 是当时唯一严格前缀（checkpoint 粒度问题，
   非能力上限）。注：日志为单字段 `fork@common=X/Y`，harness 已修为
   双值捕获。
4. **内存压力**：swap 全程有界（2.7–4.9G）；120K 档 footprint 23.6G。
   机制交互一例：rebuild 请求到达时 LRU 以 budget=100K 逐出 119.6K
   warm 会话（MEM 行 evicted=1），rebuild=882.6s vs cold=674.5s 的
   差距部分来自逐出抖动（rebuild 先跑、swap 4.9G；cold 后跑状态较
   新）——warmTokenBudget×深会话是 V1.7-A 的第一个政策实验候选。

附：extend delta 预填同样随上下文变贵（120K build 内 tps 16.7→9.9，
54K→110K context）——超线性是全局形状，不只 cold。

## 步长 A/B：512 vs 1024 @>96K（2026-09-19 晚，results_step1024_120k_ab.json）

动机：120K 冷预填 swap<3G、内存压力中下、曲线平缓波浪——疑似 512 档
护栏冗余，提议砍为两档（2048/1024）。载体：`SIMIGO_PREFILL_STEP_EXP`
环境门（RuntimeTuning >96K 档受控覆盖，默认不设=512 不变），同 harness
同 binary 复跑 120K 档。

| 行 | 512（基线） | 1024（实验） | 判定 |
|---|---|---|---|
| **cold（119,610 tok）** | **674.5s（177 tok/s）** | **1115.4s（107 tok/s）** | **1024 慢 65%** |
| rebuild | 882.6s | 862.1s | 同带 |
| restore | 20.1s | 24.4s | 1024 略慢 |
| warm | 2.9s | 3.0s | 同带 |
| build r10-13 extend | 79.9/86.9/94.5/101.0s | 66.8/125.1/243.3/191.7s | 混杂偏劣 |

**判定：512 档保留，阶梯维持 <64k→2048 / 64-96k→1024 / >96k→512。**
实验侧内存全程干净（swap 2.2–4.1G、零逐出、单会话）——排除内存漂移
混淆，慢就是深段大步长的访问模式代价本身。与 09-18 全档 2048 实验
（深段 ~2× 劣势）同构且单调：步长每上一档，深段付出真吞吐。"swap
绿灯 + 曲线平缓"不足以构成拆护栏的证据——这正是先实验再改 policy
的意义。

### 交错 ×3 复核（外审 P1 闭环，results_step_ab_repeats.json，2026-09-19 深夜）

审核 P1 要求单次观测升级为受控重复：同 120K seed 会话，512↔1024 交错
（step 文件运行中切换，App 无重启），cold/rebuild 各 ×3，逐轮记 swap。

| 场景 | 512 mean (min–max) | 1024 mean (min–max) | ratio | 区间重叠 |
|---|---|---|---|---|
| **cold** | **622.7s (599.4–635.5)** | **1102.3s (1070.8–1123.0)** | **1.77×** | **无** |
| rebuild | 745.3s (630.8–822.8) | 1149.1s (868.8–1341.1) | 1.54× | 无 |

- **cold 侧信号最强**：干净状态 + 交错 + 区间零重叠，512 档优势从
  单次 65% 升级为稳定 ~77%（n=3 全分离）。
- **rebuild 侧高方差但同向**：方差来源已定位——12 轮 swap 轨迹
  2.4→2.5G（cold 侧，平坦）→4.7–5.0G（rebuild 侧，7 个 ~120K 暖会话
  挤压），#1–#3 波动与内存堆积同步。
- **附带裁定（审核第四节猜想证实）**：rebuild 512 #1=630.8s ≈ cold
  mean 622.7s——干净状态下 rebuild≈cold；正式矩阵 rebuild=882.6s vs
  cold=674.5s 的 31% 差距是 LRU 逐出+内存状态污染，**非 rebuild 固有
  成本**。rebuild-vs-cold 不再单列，V1.7-A 记为同族成本。
- 捕获竞态一例（cold 1024 #3 完成行晚于 HTTP 响应落盘）已修
  （wait_completion 3 轮宽限），真值自 trace 回填并标注 corrected。

**最终判定（证据升级后维持）：512 档保留。** 结论适用范围注明：本机
32GB、Cyber-Tiel 35B oQ4e、当前 vendor pin；非普适 MLX 规律。

## Build 4 认证级 10K 行（results_build4_measured_10k.json，全部 measured）

| 路 | wall | promptTime | tok | mode | reuse | ttft |
|---|---|---|---|---|---|---|
| build r1 | 17.3s | 15.9s | 9,447 | cold | false | — |
| build r2 | 25.6s | 24.0s | 18,423 | **fork-no-rewind** | true | — |
| **restore** | **1.8s** | **1.5s** | **611** | (mode 缺省=fragment 族) | **true** | 1.5s |
| warm_setup | 0.9s | 0.7s | 199 | (缺省) | true | 0.8s |
| warm | 0.9s | 0.7s | 195 | (缺省) | true | 0.7s |
| rebuild | 25.1s | 24.7s | 18,166 | cold | false | — |
| cold | 26.7s | 26.3s | 18,162 | cold | false | — |

- **restore:cold ≈ 1:15 在认证字段下复现**（与 C5/C6 降级捕获一致）。
- mode 缺省行的语义注意：引擎在 fragment/plain-extend 路径均不上报
  cacheReuseMode，harness 以 `(fragment)` 标注 mode 缺省行；路语义由
  请求构造（risk 尾）+ reuse=true + 小 promptTime 共同认证。
- build r2 首次拿到真实 mode 名 `fork-no-rewind`（此前只能从 mode 缺省
  推断）；分叉位置字段 fork@common/ledger 已同线恢复，待 40K+ 观测。

## 分相计时验收项（V1.7-0 追加，2026-09-19）

正式矩阵每行除 wall/promptTime/ttft/cacheEff 外，落五相计时：
**tokenization / prefill / KV restore·materialization / MLX
compile-setup / generation**。其中 prefill≈promptTimeS、
generation≈wall−promptTime 可推导，新探针仅前三相。行级
`provenance`（measured / derived-prefill）已落表：降级行的分相计时
一律 not-observed，不伪装实测。

- **前置条件**：上述四项校准先关闭。rootfix 最终回归 restore=24.6s
  实测 mode=cold/reuse=false——restore 未触发时该格只是第四个 cold，
  分相计时跑在失真路径上等于把 cold 精确测四遍。
- **已有数据注脚（10K）**：四条 cold 路 ~710–775 tok/s 线性
  （9.4K tok=13.3s；18K tok=23.7–25.4s），固定成本（tokenize/
  compile-setup）已被压得很小。分相计时的主战场是校准后的 restore
  真值格与 40K–120K 非线性拐点（10K 档 swap 已 3.5G / footprint 22G）。

## V1.7-1 长上下文真实运行实验（results_v17_1_longctx.json，2026-09-20 凌晨收官）

40K/80K/120K × (restore/warm/rebuild/cold) × 3 passes（每 pass 全新会话，
生产阶梯零覆盖，runner `tools/v17_1_longctx.py`，有效性单位
depth+passIdx+attempt）。9/9 pass 完整，全行 measured，meta 证 stepFile/env
均无覆盖，逐行 stepUsed 与生产阶梯逐档吻合（2048/1024/512）。

| 档 | restore | warm | rebuild | cold | rebuild/cold |
|---|---|---|---|---|---|
| 40K | 2.9s [2.0–3.4] | 0.9s | 90.9s [66.5–103.3] | 75.6s [63.9–83.6] | 1.20× |
| 80K | 6.6s [5.6–8.5] | 1.8s | 278.4s [276.6–281.2] | 295.5s [282.7–306.0] | 0.94× |
| 120K | 18.2s [14.0–21.4] | 3.1s | 830.6s [796.4–886.1] | 624.3s [616.0–630.8] | 1.33× |

核心读数：

1. **Restore 9/9 全命中**（reuse=true，delta 恒 611 tok）：2.9/6.6/18.2s，
   对 cold 省比 1:26 → 1:45 → 1:34——复用收益随深度保持，深档无衰减证据。
2. **Cold 曲线（n=3）**：478 → 244 → 192 tok/s，超线性随重复实验复核
   依然成立；80K 档三 pass 冷值 282.7–306.0s 离散 <8%。
3. **rebuild/cold 比值不稳定（1.20×/0.94×/1.33×）**——正式定论：rebuild
   与 cold 是同族全量成本，比值差异由会话/内存状态主导（rebuild 行内
   swap 2.3–4.1G vs cold 行 1.6–2.2G 同 pass 内即可见），不构成独立
   优化目标；交错复核中干净状态两者相等（630.8 vs 622.7s）。
4. **逐出大幅减少**：9 pass 全程仅 5 次 evict（120K cold 三 pass 各
   1、40K cold/rebuild 各 1；首矩阵单次 rebuild 即触发）——每 pass
   全新会话设计天然避免跨档会话堆积；
   warmTokenBudget×深会话交互仍留作 V1.7-A 政策实验（多会话真实负载
   形状）。
5. warm 全谱 0.9/1.8/3.1s：delta-only 路径近乎平坦，复用态续跑成本
   与深度弱相关。

**V1.7-1 结论**：四路成本曲线在受控重复下闭合；restore 收益确证；
rebuild-vs-cold 并案；下一步按序进入 V1.7-2 Concurrency Probe
（先测边界，不改 serializeGeneration）。

## 结果文件

- `results_partial.json` —— 10K 冒烟原始数据
- `results_build4_formal_matrix.json` —— 正式矩阵（10K–120K 单轮）
- `results_step1024_120k_ab.json` —— 步长 A/B 单轮（1024 侧）
- `results_step_ab_repeats.json` —— 步长交错 ×3 复核
- `results_v17_1_longctx.json` —— V1.7-1 长上下文 3 passes 全量
