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

## V1.7-2 Concurrency Probe（2026-09-20，serializeGeneration=true 未动）

生产常量 `RuntimeTuning.serializeGeneration=true`（全局单飞门
`__global_generation__`，排队请求保持 QUEUED，拿到门才 RUNNING）。
探针 runner `tools/v17_2_concurrency.py`：短上下文（~1.5K delta）、低并发
（=2）、8 探针 26 场景；session 一律 ≤6 字符短 id（traceKey 塌缩规则：
`[MLX]` 取末 6 字符、`[LC] s=` 取前 6 字符——长 id 标签塌缩仅碰撞标签，
storageKey 含完整 id 故 KV 隔离无损，V1.7-1 cold cacheTokens=0 反证）。

**结果：28/28 行 pass，0 fail，0 unverified**（26 场景 + P3 修复补跑
attempt-2 ×2 行；runner 首轮两个判据缺陷经存档重算修正，见"判据修正"）。
verdict 三值 pass/fail/unverified，证据缺失不伪装。

| 探针 | 关注点 | 结果 |
|---|---|---|
| P1 顺序隔离 | A build → B build → A delta | A 账本无损：extend 0.4s, cacheEff 覆盖自身历史 |
| P2 交错一致性 | A,B 交替两轮 | 双方 r2 均 reuse=true/extend |
| P3 并发串行化 | 跨 session 并发 ×4 轮（attempt1×2 + 修复后 attempt2×2） | **LC 时间线证串行**：门交接同毫秒（gap=0.000s ×4 轮）；先拿门者非确定（B,B,A,A），queueWait 0.000–2.657s |
| P4 同 session 并发 | 两请求争抢一 session | 先到 extend（1421 tok reuse=true），后到 fork 全量重预填（1508 tok cold）——串行无 crash，fork 语义如 rebuild 同族 |
| P5a decode 中途断连 | 同 session 立即重试 | 重试成功（2.2s）但 **mode=cold**：见"边界发现①" |
| P5b ~30K prefill 中途断连 | 毒 session P0 病灶回归 | **15s 处断连，同 session 立即重试 66.9s 全量预填（25,969 tok cold）成功完成，其后 extend 0.6s 健康**——c81d130 修复实机回归通过 |
| P6 生成期间 /health | 0.5s 轮询可用性 | 24s 生成 48 polls 全 ok（max 13ms, mean 1ms）——服务面与推理完全解耦 |
| P7 失败注入+重试 | 坏 JSON/缺 messages/未知模型 | 4xx 0.0s 快速返回；账本无损（warm extend） |

### 边界发现（本探针新增机制事实）

1. **取消的非空提交 + 盲重试税（P5a）**：decode 中途客户端断连后，
   已生成的部分内容**非空提交入账本**（trace `cancelCommitSkip` 未触发，
   history 含 partial assistant，emitB=359）——39ff354 只拦空提交。
   盲重试重发不含该 partial assistant 的历史 → isPrefix 失配 → cold
   全量。短上下文代价 2.2s；**按 V1.7-1 曲线外推，120K 档同型操作
   ≈ 624s**。客户端重试协议须回填 partial assistant 才能走 extend。
2. **model 字段被忽略（P7）**：未知模型名返回 200 并由已加载模型
   真实生成（非 OpenAI 语义的 404）——失败注入必须走抛弃型 session，
   否则污染目标账本（attempt-1 实证）。
3. **同 session 并发的后到者付全量（P4）**：先到者 extend 后，后到
   请求的账本尾已失配 → fork 全量重预填。serializeGeneration 保证的
   是互斥与不 crash，不保证后到者复用。

### 判据修正（runner 首轮两缺陷，存档重算非数据改造）

- P3 首版判据硬编码"A 先拿门"——实际谁先拿门非确定（attempt1 两轮均
  B 先，attempt2 两轮均 A 先）。修为顺序无关：后跑者 RUNNING ≥ 先跑者
  COMPLETING。
- P4 首版 small/big 阈值误设——fork=全量重预填（与 rebuild 同族
  mode=cold），非"重渲后缀"。修为 mode 集合判据（extend+cold 存档
  重算 pass）。
- P6 attempt-1 提示词太短（<1s EOS，health 窗口无效）→ superseded，
  attempt-2 改计数任务（48 polls）。
- P7 attempt-1 注入污染 probe session（边界发现②）→ superseded，
  attempt-2 改抛弃 session。superseded 数据保留在
  `superseded_runs` 带 note。

### 时间戳精度与范围边界（外审 P1-1/P1-2/P2-1 落实）

- **计时精度**：trace 时间戳格式 `yyyy-MM-dd HH:mm:ss.SSS`（TraceLogger
  单 formatter，`.SSS`=毫秒精度）。runner 首版 `_ts()` 用
  `time.strptime→mktime`，struct_time 无微秒字段导致 **截断到秒级**
  （实测 `14.649 → 14.000`）——已修为 `datetime.strptime().timestamp()`
  保留毫秒。**所有时间差结论以日志精度 1ms 为下限，不宣称更高精度**。
- **存档重算**：P3 attempt-1 与 P4 的 `queueWaitS/gap` 均已从存档原始
  ts 字符串按修复解析器重算（行标 `tsRecomputed`，原始字符串未动）：
  gap 两轮精确 0.000s（A 的 RUNNING 与 B 的 COMPLETING 为同一毫秒
  字符串），queueWait 2.039/2.066s（原截断显示 2.0）。
- **补跑**：P3 以修复后代码实跑 attempt-2 两轮（`--redo` 机制）：
  gap=0.000s ×2、A 先拿门（queueWait 0.001/0.0s vs 2.657/2.212s）——
  门获取顺序非确定、交接同毫秒，两个方向均验证。判据容差 -0.005s
  （容许同毫秒内日志落笔顺序抖动）。
- **时钟同源性**：`[LC]` 与 `[MLX]` 行并非异源——同一进程的
  TraceLogger 在写入时用同一 `DateFormatter` 统一打戳（源码核验），
  跨子系统时间线可比。
- **范围边界**：本探针结论限定为——本机、本模型 pin、并发=2、
  ~1.5K delta、serializeGeneration=true 生产策略下的低并发边界通过；
  不外推到任意并发数、长上下文并发、多客户端压力吞吐、其他 HTTP
  客户端的取消行为。P5a 盲重试税的协议选项（客户端回填 partial
  assistant / 服务端可恢复标记 / 重试携带 execution id / API 文档化
  非空取消提交）留作 V1.7-3 输入，不动 KV/fork 架构。

## V1.7-3 Local Office Prototype（2026-09-20，方向登记 V1.7-C）

规格原文："SimiGo 双翼定位：Runtime + Office。从文件任务起步（多 Excel
分类/提取/汇总：读文件 → 本地模型理解 → 执行脚本 → 生成 → 模型检查 →
输出）——Runtime 第一次承载真实办公生产任务。"

**设计裁决（红线内）**：固定工作流脚本，非 Agent Framework（2 个固定
工具 submit_result/verify，无 Planner/记忆/编排）；**模型出决策、
harness 出确定性执行**（pandas 变换由 runner 执行，不 exec 模型代码
——首版风险裁决，理解→执行→生成→检查→输出闭环语义等价保留）；数据=
固定 seed 合成办公数据，ground truth 同源生成→**结果可精确评分**；
真实用户文件接入留作后续。runner=`tools/v17_3_office.py`，产物落
`office_out/`（xlsx 产物+日报+ground_truth 审计档）。

**任务与评分（temperature=0，attempt 间完全复现）**：

| 任务 | 输入 | 评分 | 结果 |
|---|---|---|---|
| expenses 分类 | 40 行报销流水 → 餐饮/交通/办公/其他 | vs 生成器真值 | **36/40（0.90）**，抽查 3/3 |
| inventory 提取 | 30 行库存 → 数量<20 补货行 | hit/误报 | **10/11，误报 0** |
| invoices 汇总 | 16 行发票 → 未付总额+笔数 | 数值容差 0.01 | **精确命中（89,657.65 / 6 笔）** |
| summary KPI | 跨文件日报 ×3 | vs 上游提交 | **3/3** |

**Runtime 侧指标（19 请求，3 attempts+smoke 另计）**：cold=9（各任务
build）、**fragment/restore 族=10 且 reuse=true 10/10**——每个 tool 尾
后继轮（t2）全部自然命中 Conditional Restore 路径，V1.7-1 确证的复用
收益在真实工作流形状下自发出现；总模型耗时 85.7s（mean 4.5s）；
anomaly=0；eviction=2（LRU 100K 预算内多会话堆积，正常）。

**过程发现（harness 层）**：verify 轮 max_tokens=128 会截断模型的
逐行重算式复核（截在半句、tool call 无法发出）——512 后 verify 全部
正常提交。修复轮提示须按目标工具定制（首版误引导回 submit_result）。
均已在 runner 修复，attempt-1 数据诚实保留。

**结论**：Runtime 第一次端到端承载真实办公生产任务成功——工具循环、
账本镜像、restore 复用、多会话、产物落盘全链可用；35B 本地模型在
结构化提交格式下分类/提取/汇总质量可用（0.90/0.91/精确/3-3）。
V1.7 三阶段（Harness/长上下文/并发/Office 原型）实验收官，
**实验结果定 V1.8 方向**。

## 结果文件

- `results_partial.json` —— 10K 冒烟原始数据
- `results_build4_formal_matrix.json` —— 正式矩阵（10K–120K 单轮）
- `results_step1024_120k_ab.json` —— 步长 A/B 单轮（1024 侧）
- `results_step_ab_repeats.json` —— 步长交错 ×3 复核
- `results_v17_1_longctx.json` —— V1.7-1 长上下文 3 passes 全量
- `results_v17_2_concurrency.json` —— V1.7-2 并发探针 8 探针 26 场景
  （28 verdict 行=P3 修复补跑×2；含 superseded_runs：p6/p7 首轮设计
  缺陷数据带 note 保留）
- `results_v17_3_office.json` —— V1.7-3 办公原型 4 任务 3 attempts
  （`office_out/`=xlsx 产物+日报+ground truth；smoke 另存
  `results_v17_3_office_smoke.json`）
