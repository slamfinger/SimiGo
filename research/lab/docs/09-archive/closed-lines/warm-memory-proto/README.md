# warm-memory-proto（验证型原型，未立项）

决策来源：2026-10-16 架构决策记录（讨论层，未建 ADR、未立项）。
选定方向 (b)「温记忆结构化」验证原型；(a) branch 语义暴露暂缓；
现有 Execution State 路径（checkpoint/恢复/prefix cache）保持不变。

## 架构原则（本原型不可违背）

- KV 是执行优化，不是跨会话记忆的唯一载体。
- 跨 session 连续性由可恢复的工作状态保障；同 session 分支连续性由
  KV 血统复用保障。
- 任何「新窗口零冷启动」结论必须明示：session 边界、历史前缀是否
  一致、实际需重渲的 token 数。温记忆更短/更准 ≠ KV 能跨 session
  继承——两者分别测量。

## 原型只验证三件事

1. **是否更省**：Arm A（客户端压缩摘要，转录 idx 8，1284 字符）vs
   Arm B（结构化温记忆）的 token 数；首次恢复延迟与后续增量缓存
   表现从 SimiGo trace 读（`session=wmra|wmrb/main` 行的
   promptTokens / cacheEff）。
2. **是否记得更准**：`qa_regression.json` 十题固定回归（裁定/状态/
   待办/约束/提交链），关键词组评分 PASS/PARTIAL/FAIL。
3. **是否可追溯、可回退**：provenance 越界剔除（run_regression
   内建）；覆盖率 <80% 或抽查不符 → 回退 Arm A（MEMORY_SCHEMA 回退
   契约）。

## 材料

- Ground truth：`transcript.jsonl`（f21a38 血统，83 消息/186K 字符，
  checkpoint 2026-10-16T09:40:21Z，由 extract_transcript.py 离线提取）。
- 双臂脚本：`gen_structured.py`（Arm B 生成，分窗 ~10 消息）→
  `run_regression.py`（双臂跑批 + 评分 + 报告
  `regression_report.json`）。

## 运行纪律

- 推理调用只在 SimiGo 空闲窗口跑（串行门礼貌；探针 session ≤6 字符
  惯例：wmra/wmrb/wmemg）。
- 服务器为生产实例：不得改配置、不得重启；实验全部经 HTTP 常规请求。
- 原型结论只回答「是否值得立项」，不直接承诺上线。

## 通过后

分别立项决策所需的两份证据：①记忆质量/成本对照表；②「KV 是否跨
session 继承」单独测量（新 session 携带 Arm B 时 pool 是否命中、
重渲 token 数）——两者不许混为一谈。
