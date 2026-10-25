# G 轮实施任务：多跳跨执行实例增量继续

## 0. 唯一目标

在 F 轮已实现的原生 Swift/MLX + PALACE IS 生产入口上，验证连续两次进程边界下的：

`U1 real compute + signed settlement` → `Process 1 exits` → `fresh ES/process computes U2 using U1 from IS and signs U2` → `Process 2 exits` → `fresh ES/process computes U3 using U2 + recursively verified U1 dependency closure from IS`。

P2 不得重生成 U1；P3 不得重生成 U1 或 U2。普通生产 `continueTask` 自身必须触发 IS 读取、验签、依赖闭包验证和输入构造。Driver 只负责启动子进程、创建合法 fixture 和采集证据，不准直接读取已结算答案来拼接 U2/U3 prompt。

这轮验证的是“多跳、任务级已完成工作复用和跨执行实例恢复”，不是通用安全研究，不增加 F 轮未要求的防回滚或新信任根。

## 1. 现有结论与限制

根据 F 轮交付摘要，当前实现已经报告：原生双世界跨进程 U1→U2；U2 普通生产准入；签名结算；U1 `REUSE` / U2 `COMPUTE`；负对照 N1–N3；N4 隔离扫描；415 测试 0 failures / 5 skipped；guards PASS。请从本机 F 轮运行根和实际源代码独立核验这些记录，但不要改写 F 轮产物。ChatGPT 未独立访问本地源文件，不能把此段当作独立复核结论。

未解决的核心缺口：是否可以把这项能力从单跳推广到依赖闭包中的中间结果——U2 已在新执行实例中计算并结算之后，再由第三个独立执行实例恢复 U2，并在校验其传递依赖 U1 的同时只计算 U3。

## 2. 不可触碰边界

- 不修改、覆盖、删除或重建 F 轮 `$HOME/SimiGo-Agent-Runs/es-is-detached-continuation-20261022f/` 以及 A–E 任何旧运行产物；同样保护 `run-20261022a` 和 G2 冻结批次。
- 不修改 `docs/02-evidence/` 既有文件、冻结治理集、恢复的 SRS-VAL-01 DELIVERY、G3/D1 证据。
- 不执行 `git reset/clean/stash`，不使用 checkout 覆盖本地内容；不触碰与本任务无关的原有 dirty/untracked 文件。不得 stage、commit、push。
- 不改 `carrier_loop` / `execute_demand` 的重算语义；不实现全局 no-recompute。
- 不增加整库 anti-rollback、安全锚重建、硬件/远程信任根、跨 backend 研究。复用 F 轮现有签名机制。
- 不复制模型权重；使用本地 HF snapshot 的规范解析路径，固定并记录模型、权重、tokenizer 身份。
- 证据只写运行根，不在仓库里新增治理/研究报告或其他文档。

## 3. 运行根与前置快照

运行根固定：`$HOME/SimiGo-Agent-Runs/es-is-multihop-continuation-20261022g/`，子目录至少包括 `preflight/`, `source/`, `build/`, `tests/`, `stages/p1-u1/`, `stages/p2-u2/`, `stages/p3-u3/`, `controls/g1-missing-transitive-dependency/`, `logs/`, `manifests/`, `diffs/`, `report/`。

在任何源码修改之前：
1. 快照 `git status --short --branch`、HEAD、branch、staged diff hash、完整 tracked/untracked 清单、已有目标文件差异、Swift/macOS/MLX/模型身份。
2. 使用 `workspace_guard.py snapshot` 写到运行根，绝不能先改代码再补快照。
3. 枚举 `~/SimiGo-Agent-Runs` 实际存在的 A–F 及 `run-20261022a` 历史目录，对这些确实存在的目录调用 `artifact_guard.py snapshot`。不存在的历史目录只在清单标记 absent，不凭猜测创建。
4. 确认 F 轮 `summary.json`、source diff、模型身份与 guard 产物。对 F 轮只读。
5. 审查目前生产代码的调用图：模型/MLX context 和 KV 所有者、普通 `continueTask`、ES 创建/checkpoint、IS resolve/settle、签名验证/签名本次新结果的路径。保留调用图到 run root，不写入仓库。

## 4. 原生实现要求

### 4.1 三个独立 OS 进程 / Execution State

用 Swift 原生 driver 启动三个独立子进程。监督进程可收集 stdout/stderr 与 exit code，但不得拥有任何 U1/U2 模型、engine、context 或 KV 对象。

- **P1 / U1**：从真实运行时 source payload 执行一次模型生成，产出真实 U1 结果，通过现有可信 `settle()` 路径写入 IS 并对 U1 新结算签名。不得 fixture 预填答案。持久化后关闭写事务/连接并退出进程；父 driver 必须 wait 并记录 exit code。
- **P2 / U2**：仅在 P1 已退出后启动。使用新的 `execution_state_id`、空 state 目录、position 0、无旧 checkpoint/prefix/history/KV serialization。通过普通生产 `continueTask` 由 IS 解析和验签 U1，执行一次真实 U2 生成，并将 U2 作为新计算结果结算。U2 的结算必须绑定对 U1 的 dependency ID/hash。P2 可以按现有生产规则签署它自己新产生的 U2 结算，但绝不能重签/改写 U1 或其他依赖结算。
- **P3 / U3**：仅在 P2 已退出后启动。新 `execution_state_id`，另一个空 state 目录，position 0。通过同一个普通生产 `continueTask` 恢复 U2，并递归验证 U2→U1 的完整依赖闭包。只生成 U3 并将其结算。U1、U2 必须均为 `reused`，而不是 `computed`。

身份必须明确分层记录：`logical_lineage_id`；P1/P2/P3 各自的 `execution_state_id`；`process_instance_id`/PID；settlement object ID 与 signature object ID；source/dependency digest。三个 ES state IDs 和三个 PID 均应互不相同。不要从 `executionID` 的固定字符串推断执行实例独立性。

### 4.2 模型与 KV 生命周期

- 每个进程记录模型上下文创建、调用、关闭/销毁和退出时刻。
- 若 MLX/KV 类型公开了真实 owner 释放证据，记录其真实 deinit/release 事件；不得用无实际所有权的 sentinel 代替。
- 如果内部 KV deinit 无法直接观测，结论限定为 `PROCESS_ADDRESS_SPACE_DESTROYED_ONLY`：可以证明旧进程退出使其本地地址空间与进程内资源不可被后续进程引用；不能声称观测到了内部 MLX cache 对象的 deinit。
- P2/P3 各自从空 state position 0 启动，不允许 `reattached`、旧 checkpoint reads、prefix replay、共享进程内模型 context。
- 同一模型/权重/tokenizer identity 跨阶段一致；权重文件不复制。记录模型加载时间/成本，但不要把模型重新加载成本说成零。

### 4.3 任务输入与模型输出

- 沿用 F 轮已验证的可靠 prompt/output contract，并做最小扩展来形成 U1→U2→U3 的依赖关系；避免重新要求模型复制一个长的 32-hex 串。如果当前可靠 fixture 使用 128-bit nonce 与短派生值，应保留运行时随机隔离，只让模型输出已验证可靠的短派生值。模型输出仍必须来自真实模型调用。
- U2 与 U3 的基础模板/COLD seed 不得包含上游结果、nonce、其他阶段的 prompt/completion 或 stage-specific 答案；不同阶段允许有固定任务说明，但模板的依赖值只能由普通生产 `continueTask` 根据经过验签的 IS binding 注入。
- 两个下游阶段的 runner/harness 对 settlement/item 的直接读取次数必须为 0；所有取值经生产准入路径。记录实际 input text/hash/token IDs 与 IS 绑定对象身份、摘要的对应关系。
- 对格式错误不要静默重试；保留原始 token 和输出，标 `OBSERVED_FORMAT_FAILURE` 或 `INVALID_CONDITION`。如果是代码/接线缺陷，保留原 attempt，修复后使用新 attempt ID。

## 5. 最小实验矩阵

### G0 — `CHAIN_3_HOPS`

一次端到端三进程链：P1 真实生成并结算 U1；P1 退出后 P2 从 IS 复用 U1、只生成并结算 U2；P2 退出后 P3 从 IS 复用 U2，并验证其传递依赖 U1，只生成并结算 U3。

必要证据：
- U1/U2/U3 的生成各仅一次（分别在它们自己的 producer stage）；在 P2 中 U1 generation=0；在 P3 中 U1/U2 generation=0。
- P2 `reused_item_ids` 包含 U1、`computed_item_ids` 不含 U1 且包含 U2；P3 `reused_item_ids` 包含 U1/U2（按系统语义若只有直接 reused list，必须另提供完整 verified dependency closure），`computed_item_ids` 仅包含 U3。
- P1 exit 已被 wait 观察到后 P2 才启动；P2 exit 后 P3 才启动。三个开始时 state dir 都为空，position 0；无 prefix replay、旧 checkpoint reads。
- P1/P2/P3 结果摘要与各自 signed settlement 对应；U2 settlement 绑定 U1，U3 settlement 绑定 U2 并能验证传递闭包 U1。
- 对每段保存模型身份、tokenize/generate 计数、输入/输出 text+token IDs+hash、DB object IDs/hashes、数据库事务/结算事件。

### G1 — `MISSING_TRANSITIVE_DEPENDENCY`

从 G0 的数据库/state **副本**构造，原始 G0 不动。在 U2 已结算后、P3 前，只移除/破坏 U2 签名依赖闭包中的 U1 settlement/source binding，使 U2 自身的签名对象仍然存在。尝试以正常 P3 普通 `continueTask` 读 U2。

预期：递归依赖闭包准入失败，错误与实际契约一致；失败发生在任何 tokenize/model generation 前，seed/text tokenize=0、generation=0，DB/state 不发生非预期变化。不得靠 harness direct-read 回退。若系统既有语义允许对缺失结果重算，先观察并报告实际路径；不要为通过实验擅自实现新的 no-recompute 策略。但对本 G1 选定的“签名 U2 依赖闭包不完整”条件，未经完整闭包验证不得把 U2 作为有效已结算结果注入模型。

### N4 — 隔离扫描

扫描 U2/U3 base template、cold seed、argv、environment、空 state 目录、暂存/临时文件、非白名单日志和另一个阶段产物，确认上游结果没有旁路副本。允许出现上游值的位置必须在 manifest 中列明为 source payload、受签名 settlement 或生产准入生成的实际模型输入。记录扫描范围和 exclusions；不得仅报告 `violations=[]` 而不保存扫描输入列表。

条件终态只能是 `OBSERVED`、`INVALID_CONDITION`、`BLOCKED_NOT_RUN`、`OBSERVED_FORMAT_FAILURE`；最终 summary 可另行判定是否满足 acceptance，不要将预期直接写为 observed。

## 6. 证据、计量和验收

每 stage 记录：PID、进程开始/退出时间、exit code、execution_state_id、logical_lineage_id、state 起始/结束位置、空 state manifest、模型 identity、model load、tokenize text/seed、generate 次数、实际 input/output token IDs 与 text、`computed/reused` item IDs、IS admission 调用 ID、settlement/signature object IDs、source/dependency closure digest、DB/state before/after manifest。

跨阶段统一记录：
- P2 启动时间大于 P1 退出时间；P3 启动时间大于 P2 退出时间；三者 PID 和 state IDs 不同。
- P1 实际生成 U1；P2 不生成 U1，只生成 U2；P3 不生成 U1/U2，只生成 U3。
- P2/P3 通过普通生产 `continueTask`，不是 harness 预读和模板拼接。
- U2/U3 结果和它们经过验签的 dependency values/IDs/digests 精确对应。
- `prefix_replay_tokens=0`、old checkpoint reads=0、harness settlement/item direct reads=0。
- G1 负对照在适用的生产准入边界拒绝，0 tokenize/0 generate，无非预期 side effects。
- 三阶段 model/tokenizer identity 一致。明确报告三次模型加载/输入 token 计算成本；禁止声称所有 FLOPs 或所有 token prefill 都避免重复。

运行完生成 `summary.json`、`EVIDENCE_REPORT.md`、逐 stage 原始 stdout/stderr、invocation JSON、数据库/状态摘要、输出 token 文件、模型身份、源代码 diff（必须是可复核非空的实际 patch，untracked 文件通过 pre-snapshot 对比重建时要在 manifest 说明）、构建与测试日志、workspace guard、artifact guard、sha256 manifest。所有证据只在运行根，不能改写历史证据。

C1–C4 必须分开报告：C1 admission，C2 IS 信息来源，C3 当前路径重算/拒绝行为（纯观察且不改策略），C4 受信任结算来源约束。主要研究结论只谈被测链路。单轮 G0 成功支持多跳可行性，不直接证明所有模型/backend/依赖图普遍成立。

## 7. 执行顺序

1. 快照并只读审查本地 F 轮源码和证据，确认单跳执行路径能复用。
2. 设计最小原生 task schema/fixture 扩展，优先复用 F 轮生产代码，不复制另建同功能架构。
3. 添加针对递归 dependency closure 与新 execution state 的 Swift 单元测试。
4. 构建目标和运行聚焦/相关 Swift 测试；保存原始日志。
5. 在无模型成本的 admission/fixture probe 中确认输入模板无上游值、各依赖 ID/摘要正确、签名角色边界正确。
6. 运行 G0 三进程真实模型链，单次尝试；修代码不能覆盖失败 attempt。
7. 从数据库/state 副本运行 G1；执行 N4 leak scan。
8. 跑 workspace guard 与历史 artifact guard；任何被保护路径变化都停止交付，先恢复由本轮错误造成的变化（仅当能精确证明变化由本轮造成且恢复不会覆盖先前修改时），否则明确报告并不擅自回滚。
9. 通过 `validate_g_evidence.py summary.json`；报告缺项不通过时修正证据生成/聚合，不能手工伪造观测值。
10. 不 stage/commit/push。最终回报实际改动、build/tests、每条件状态、run root、核心计数、结论边界和阻塞。

## 8. 结束定义

只有当生产 Swift 代码已修改（或证明所需路径已存在而缺口仅在测试/runner）、构建/测试真实执行、G0 真实三进程模型链至少尝试一次、G1/N4 有真实观测或明确 BLOCKED、运行前后守卫通过、非空源码 diff 与证据 manifest 都可复核，才算完成。不得以 Canvas 或完成报告替代代码与运行证据。
