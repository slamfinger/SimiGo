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

## 结果文件

- `results_partial.json` —— 10K 冒烟原始数据
