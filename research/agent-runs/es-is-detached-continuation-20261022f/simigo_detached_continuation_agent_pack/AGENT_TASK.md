# SimiGo：IS 结算结果脱离旧执行上下文并在新 ES 中增量继续 — 本地 Agent 实施任务

## 任务目标（唯一主线）

**实现并实测：U1 的真实模型计算完成并写入 PALACE Information Space 后，旧执行进程及其本地 KV/模型上下文结束；一个全新的 Execution State / OS 进程不继承旧前缀、checkpoint、prompt history 或 KV，只从 IS 恢复已结算的 U1 结果，随后计算 U2，而不重新生成 U1。**

交付目标是原生 Swift/MLX 生产代码与真实模型运行证据，不是另一份计划文档。无人看守推进：检查本地实现 → 编码 → 构建/测试 → 真实运行 → 分析失败 → 修复实现问题 → 重跑受影响测试和独立运行 → 交付证据。不得把预期当成观测，不得静默重试实验条件。

## 现状和研究边界

- C/D 轮报告称：IS 输入准入已进入普通生产 `continueTask`，并在 tokenize/generate 前校验；D 轮双世界结果支持受测路径下的 IS 信息来源。
- E 轮报告称：结算声明已具有生产签名及消费端验签，局部篡改控制可拒绝。签名是本实验的既有前提，不是本轮研究目标。
- 当前最关键的缺口：**旧执行上下文/KV 的实际终止与不可达、新 Execution State 的身份和冷启动、U1 不重新生成、U2 确实通过普通生产入口从 IS 取得已结算值，这四者是否在同一真实运行中同时成立。**
- 不另开整库回滚/远程信任根/F 轮安全工作；不扩建治理文档；不把本轮变成通用 cache 优化研究。
- 结论应区分：任务级已结算结果复用、旧 KV/进程生命周期、模型计算成本；不能从 U1 generation_calls=0 推断所有模型 FLOPs 都没有重复。

## 无人看守执行规则

1. 不向用户请求日常步骤批准；不得完成只读分析后就停下。最小实现、构建、测试、隔离实验属于本任务的必要交付。
2. 如果某项真实运行在当前机器上因模型、MLX、签名工具或设备资源无法执行，仍完成可实施的原生代码、自动化测试和运行器；将该项标为 `BLOCKED_NOT_RUN`，说明精确阻塞，绝不写 PASS。继续完成其余可执行项目。
3. 每个科学实验条件只执行一次。代码/构建错误修复后，可以从全新 run ID 重跑受影响条件；原始失败运行必须保留并标明 `INVALID_CONDITION` 或 `BLOCKED_NOT_RUN`，不能覆盖。
4. 不增加任何未要求的 retry、模型输出格式自动重试、fallback、旁路读取或默认关闭验签。
5. 原生 Swift 应拥有任务编排、ES 生命周期、模型调用计量和 U1/U2 子进程边界。可调用当前已经存在的 PALACE/IS bridge 以读写物理数据库、签名和校验；不得再让 Python harness 自行预读 U1 结算并拼接 U2 prompt。Python 仅可用于外围快照、证据聚合/校验，不得成为此次核心执行路径的权威实现。
6. 先按下方“前置快照”操作；完成前禁止改动源码。

## 不可触碰边界

- 不修改、覆盖、删除、重建 `run-20261022a` 或 A–E 轮任何已有运行产物/证据；先检查实际目录并对其做哈希快照。
- 不修改 G2 冻结批次、`docs/02-evidence/` 现有文件、治理冻结集、恢复的 5 份 SRS-VAL-01 DELIVERY 文件、G3/D1 证据。
- 不 reset/clean/stash/checkout 覆盖/rebase；不覆盖任何现有 dirty/untracked 文件；不 stage、commit、push。
- 不修改 `carrier_loop` / `execute_demand` 的重算语义；不实现全局 no-recompute 策略。
- 不复制模型权重到新长期目录。复用本机 Hugging Face snapshot 的规范解析路径，记录模型 revision、weights manifest、tokenizer digest。
- 不把同一个 `executionID` 字符串当作新 ES 的证据。分别记录 `logical_lineage_id`、`source_execution_state_id`、`new_execution_state_id`、`process_instance_id` 和 PID。
- 不把证据写入仓库中的治理/历史文档。所有本轮运行数据、报告、diff、manifest 均写入仓库外的全新运行根。

## 前置快照与运行根

运行根：

`$HOME/SimiGo-Agent-Runs/es-is-detached-continuation-20261022f/`

建议子目录：`preflight/`, `source/`, `build/`, `tests/`, `world-a/`, `world-b/`, `controls/`, `lifecycle/`, `manifests/`, `logs/`, `report/`。

在任何源码改动前：

1. 记录 `git status --short --branch`、HEAD、分支、staged diff SHA-256、tracked/untracked 清单、目标源码现有 diff、Swift 版本、macOS 版本、MLX/模型/分词器身份。
2. 运行任务包中的 `workspace_guard.py snapshot`，快照位置必须位于运行根，而非仓库。
3. 运行任务包中的 `artifact_guard.py snapshot`，对所有实际存在的历史运行根做递归哈希：`run-20261022a` 以及 A–E 轮的 `SimiGo-Agent-Runs` 运行目录。未知目录先枚举实际内容，不猜路径；对存在的历史根快照文件内容、类型、mode、size 和 symlink target。
4. 先读本地当前工作树中的实际 Swift/MLX/bridge 实现；远端 GitHub、以前对话摘要或旧报告都不能代替本地源代码。
5. 保存实际调用图：模型加载与模型上下文持有者、KV/cache 的真实持有位置、`continueTask` 调用点、ES state/checkpoint 建立处、IS settle/read 路径、签名 key/anchor 的位置。不要凭名称猜 API。

## 原生代码实施要求

### A. 明确区分逻辑谱系、旧 ES、新 ES 与 OS 进程

为真实运行记录或补充明确身份字段：
- `logical_lineage_id`：U1→U2 所属逻辑任务/谱系（若当前 ES 模型有该概念）。
- `source_execution_state_id`：U1 运行所用的旧 Execution State。
- `new_execution_state_id`：U2 使用的全新 Execution State，必须与 source state 不同；不得复制旧 checkpoint、position>0 状态或 token prefix 来伪造冷启动。
- `producer_process_id` / `consumer_process_id`、PID、子进程启动/退出时间与退出码。
- `settlement_object_id` / `settlement_signature_object_id`、result/source/dependency 摘要。

保留 ES 对任务延续的权威语义；IS 保存已结算结果。不要以“新 PID”冒充“新 ES”，也不要以“新 ES ID”冒充旧 KV 已释放。

### B. 原生双进程/双状态执行

建立 Swift 原生 experiment driver（尽量复用当前 package target；如需新增 executable/test target，改动最小并添加对应 Package.swift 测试）。驱动真实模型运行，至少完成：

1. 对 world A 与 world B 分别生成运行时 128-bit 随机 nonce。nonce 不能出现在命令行参数、环境变量、U2 base template/cold seed、无关日志、临时文件或另一个世界；允许出现在该世界 U1 的 source payload 和对应的真实 IS settlement 中。实验结束后做显式 leak scan，允许位置须白名单列明。
2. U1 进程加载既有模型快照，通过真实模型执行 U1，记录真实 token IDs/text 及调用计数，按现有受信任生产结算路径将 U1 结果写入物理 IS 并完成签名。U1 输出必须确实来自这次模型调用，而不是 fixture 直接填答案。
3. 结算持久化并关闭需要关闭的数据库连接/写入事务后，结束 U1 的模型执行上下文并退出该 OS 进程。父进程须 `wait` 到 U1 退出并记录退出码；U2 开始时必须能证明 U1 进程已退出。不得通过长寿命父对象继续持有 U1 的 engine/context/cache。
4. 若现有 cache/context 类型允许可信地观测实际 owner 的释放，加入最小生命周期记录（真实 owner 的 deinit/release、缓存 owner 弱引用/状态，或当前 MLX API 公开的资源释放信号）。不能只给一个无实际资源所有权的“sentinel deinit”就声称 KV 已释放。若可观测性有限，要如实记录 `PROCESS_ADDRESS_SPACE_DESTROYED_ONLY`；OS 进程退出可证明旧进程地址空间/本地资源不可再被新进程引用，但不能声称观测到了某个未暴露的 MLX 内部对象的 deinit。
5. 在 U1 退出后，U2 以独立 OS 进程启动；创建新的空 state 目录和 `new_execution_state_id`，position=0、无旧 checkpoint、无旧 prefix、无 U1 prompt/history/KV 序列化。用同一模型与 tokenizer identity，但不复制权重文件。记录启动前空目录 manifest。
6. U2 只调用**普通生产 `continueTask`**。它应在其函数体内调用 IS `resolveTaskInput`/现有等效生产准入，自行通过已签名结算解析 U1 结果；experiment driver 不得直接 read-settlement/read-item 后插值答案。记录 production admission 调用 ID、IS 实际读取对象、签名对象 ID和结算对象 ID。
7. U2 base template 两世界字节完全一致，且不含 nonce、U1 source payload、U1 prompt、U1 completion；真实送入模型的 U2 input 必须由生产绑定逻辑以有效 IS 结果构造。记录 base-template SHA-256、实际完整 input 的 SHA-256、token IDs、输出 token IDs/text 和输出摘要。
8. 每个 world 的 U1 进程必须在 U2 启动前退出；U2 `execution_state_id` 不等于 U1；U2 生命周期从 created@0 开始，并记录本次实际观察到的推进（期望 created@0 → continued@1）。不要出现旧 state `reattached@1` 或 prefix replay。
9. 一次尝试，无静默重试。若模型输出不符合预期格式，保留原始输出并记录 `OBSERVED_FORMAT_FAILURE`/`INVALID_CONDITION`，不重试直到看起来成功。

### C. 最小实验条件

**正条件**
- `W-A`: U1 生成并结算 nonce A；U1 进程结束；全新 U2 state/进程通过普通 `continueTask` 从同世界 IS 取值，U2 输出与 A 精确对应。
- `W-B`: 独立 nonce B，完整独立 source/settlement/ES；其余 U2 base template 与 W-A 字节相同；U2 输出与 B 对应，不是 A。

**负对照**（从合法世界的数据库/状态副本构造，绝不改正本）：
- `N1 missing-settlement`：移除对应 U1 settlement；普通 `continueTask` 在 tokenize/generate 前拒绝，不从 U1 item/source 或其他副本回退。
- `N2 invalid-signature/byte-tamper`：在隔离副本中局部改写签名覆盖内容/对象字节；消费端验签/摘要校验拒绝。
- `N3 dependency-mismatch`：改变声明依赖或 binding，使当前 item 所需依赖与已签名闭包不一致；在 tokenize/generate 前拒绝。
- `N4 prefix-isolation`：只做自动审计：U2 的 base template、cold seed、state、environment、argv、临时文件及非白名单日志中均找不到 nonce 或 U1 prefix；另一个世界的 nonce 不得出现在当前 world 的输入/状态。
- 不在本轮执行整库 anti-rollback、安全根重建或 T3 场景。E 轮签名能力作为前置机制使用，不扩展威胁模型。

### D. 真实调用与重复工作计量

对每个 world 分别记录：
- U1 阶段：模型加载、真实 generate 次数、输入 token 数/IDs、输出 token 数/IDs、结算和签名提交状态。
- U2 阶段：U1 的 generate 次数必须为 0；U2 generate 恰为 1；`computed_item_ids` 不包含 U1，`reused_item_ids` 包含 U1；实际 U2 input 与被验签 settlement 的 `result.value`/摘要一致。
- tokenize(seed/text)、model continuation/generate、production admission/read 数分别计量。
- `prefix_replay_tokens=0`、old checkpoint reads=0、harness settlement/item direct reads=0；若当前实现无法提供某计数器，先在真实调用点增加计数，不得用固定常量或预填 JSON 冒充观测。
- 记录加载同一模型的成本与模型输入计算，避免把“U1 未重新生成”夸大成“新实例不消耗任何模型计算”。

### E. 结果、证据和判定

所有产物仅写到 run root：原始 Swift stdout/stderr、每进程 invocation JSON、SQLite snapshot/对象摘要、U1/U2 输入输出 token、lifecycle、nonce leak scan、build/test 日志、源码 diff、workspace/artifact before/after manifests、机器/模型/分词器身份及最终 `EVIDENCE_REPORT.md`。仓库内不新增治理/研究报告。

每个 condition 必须有 `terminal_state`，只允许：`OBSERVED`、`INVALID_CONDITION`、`BLOCKED_NOT_RUN`、`OBSERVED_FORMAT_FAILURE`。不要用 `PASS` 作为运行终态；可在事后 acceptance summary 里判定是否满足标准。

**核心验收：**
1. W-A/W-B 的 U1 真实生成并签名结算；U1 进程退出后，新 U2 进程与不同 `new_execution_state_id` 冷启动。
2. U2 通过普通 `continueTask` 完成 IS 准入；harness 的直接 settlement/item reads=0。
3. W-A 输出对应 A、W-B 输出对应 B；U2 base template/cold seed 字节相同、nonce-free；不存在交叉污染/旁路。
4. U2 阶段 U1 generate=0、U2 generate=1、U1 被 reused 而非 computed；没有前缀重放。
5. N1/N2/N3 均在 tokenize 和 generate 前拒绝（两类 tokenize 计数和生成计数为 0），IS DB/state 无非预期副作用。
6. 实际模型 identity 与 U1/U2 一致；复用现有 HF snapshot，不复制权重。
7. 如果旧 KV owner 的 `deinit` 无法直接观测，明确将证据限定为旧 OS 进程完全退出、本地地址空间不可达、无 KV/prefix 持久化/重放；不能宣称未实际观察的内部 deallocation。
8. C1/C2/C3/C4 分开报告；不因签名有效就宣称模型答案语义必然正确。

## 测试与执行顺序

1. 前置快照与源码路径审计。
2. 加纯 Swift/生产入口测试：新 ES 身份与冷 state、不调用 harness read、有效 IS 结果进入模型输入、所有 N1/N2/N3 在 tokenize/generate 前失败、计数和副作用检查。
3. `swift build` 相应生产 target；运行最窄相关 Swift tests，再运行足够覆盖生产输入准入/ES 恢复的测试。
4. 先跑一个独立的有效 U1→新进程 U2 smoke；检查生命周期、nonce 隔离和证据字段是否齐全。
5. 运行 W-A/W-B 与 N1–N4，各条件一次，原始失败不得覆盖。
6. 运行证据校验、workspace guard、historical artifact guard；检查所有历史 A–E run 与冻结路径在本轮前后哈希一致。
7. 生成 run-root 内的 `EVIDENCE_REPORT.md` 与 `summary.json`。报告必须写明 observed fact、inference、claim limit 和 blocked items。
8. 不 stage/commit/push。完成后返回运行根、实际修改文件、build/test 结果、逐条件结果、证据摘要哈希和未解决限制。

## 完成定义

任务只有在原生代码已改、构建/测试已跑、至少尝试真实模型 U1→新进程 U2、正负条件均有真实观测或明确 BLOCKED、工作树/历史证据守卫完成后才算完成。不能用 Canvas、计划文本、mock-only tests 或 Python fixture loop 代替实际实现和实验。
