# SimiGo 原生集成与自主引导部署方案

> 交付对象：SimiGo 本地 Agent（实施任务说明）  
> 产品仓：`slamfinger/SimiGo`  
> 任务性质：产品集成与部署工程；不是单纯把 `.app` 复制进应用程序文件夹。  
> 文档状态：基于公开产品仓审查形成的实施基线；本地工作树的真实状态必须由 Agent 在实施开始时复核。

## 0. Agent 执行摘要

请在本地 SimiGo 实际工作树中执行本方案。目标是把原生声明式结果契约集成进 SimiGo 的真实生产路径，并构建一套可重复、可恢复、可验证的首次启动引导流程：创建 `.simigo` 运行数据根、初始化 schema 完整的 SQLite 数据库、注册/索引外部 work 目录与 Agent 会话来源、探测外部本地模型缓存、按锁定清单下载/构建可选引擎二进制、验证环境，然后启动产品。

**不可妥协的语义约束：**

1. SimiGo 是 Execution State + Information Space Runtime，不是 Agent 工作区本身，也不只是模型启动器或 KV 缓存。
2. `work` 是用户已有或明确选择的**外部目录**；绝不默认创建 `~/.simigo/work`，不把工作区内容复制进 `.simigo`。
3. SQLite 保存 ES/IS 状态、结算结果、源文件/目录元数据和 Agent 会话索引及其引用关系；不保存外部文件的第二份完整物理副本，不把模型权重复制进数据库。
4. 不创建 `~/.simigo/models`。本地模型从外部位置加载；默认探测 Hugging Face 缓存 `~/.cache/huggingface`，同时尊重 `HF_HOME`、`HF_HUB_CACHE` 等运行时配置。模型不存在不应阻止无模型的 ES/IS 核心功能初始化。
5. 所有用户路径与构建位置都由运行时路径解析器解析；源码、测试、配置及数据库中不得写入开发者机器的绝对路径。外部根以 `root_id + 相对路径` 表达；本机安全书签等定位信息与可移植数据分开。
6. 外部二进制管理必须是**可扩展引擎配方目录**，不限于 llama.cpp。当前可先实现并验证 llama.cpp 配方；未来引擎可登记、下载、构建及独立审计，但除非 SimiGo 存在并通过对应适配器/conformance 测试，不得宣称已支持该引擎运行。
7. 不覆盖用户数据、不静默覆盖已有数据库、不自动删除原始 work 文件、不拉取未锁定的上游 HEAD、不使用 `curl | bash`、不从未验证的 manifest 执行任意 shell 命令。
8. 不改写历史实验结果，不覆盖冻结的 G2 批次或 H/I/J/K 原始证据目录，不重置或清理脏工作树。除非另有指令，不 commit、不 push、不创建 PR。


## 0.1 研究与工程优先级：原生 MLX + G1–G3 是首要闭环

本节优先级高于后文任何把引擎配方或安装界面提前的安排。SimiGo 当前主要验证硬件是 Apple Silicon 统一内存架构，**第一优先不是扩充外部引擎数量，而是把原生 MLX 下的 ES/IS 核心与 SQLite 物理承载打磨到有多维实际证据的程度**。

本方案把以下 G1–G3 作为产品目标验收门。它们是本实施方案里的验收编号；Agent 必须与 `SimiGo-Lab` 内任何已有同名实验/批次区分，尤其不得把 Lab 的狭义 G1 oracle 结果误述为本方案的整个 G1 已通过。

### G1 — 原生 MLX 的结算、脱离与跨 ES 恢复

- 使用实际适配的本地 MLX 模型执行 U1，验证并结算结果，把可恢复语义结果及来源/版本/依赖/有效性依据写入 IS 数据库。
- 让产生 U1 的旧 ES 结束或彻底失去继续执行的资格；启动新的进程/ES，不能通过旧 ES 内存对象、旧 KV、旧 checkpoint 或旧 prefix cache 取回 U1。
- 新 ES 从 IS 读取并验证 U1，再生成 U2；记录模型输出、结算记录、IS 读取、生成次数、进程/ES 身份和所有允许的载体访问。
- 必须有缺失结算、损坏/篡改结果、依赖版本变化等拒绝或重算对照。不能以“新进程成功输出文本”单独判定通过。

### G2 — SQLite IS 对两类信息源的承载、局部动态更新与验证

- 同一个数据库模式能同时表达外部 work 根里的文件索引，以及可识别 Agent 会话来源中的 session/message 索引；还能把它们与已结算信息对象和依赖边关联起来。
- 数据库不复制外部 work 原文件，不搬迁文件；可保存 IS 语义结果与结算证据，但不把来源会话或外部文件整体再存一份冒充索引。派生全文索引若以后确有需求，应单独声明、可重建并可选择关闭。
- 对 work 文件的新增、修改、删除/移动，以及会话的追加、分支/版本变化进行真实增量实验。验证索引版本、digest、source identity、依赖闭包和有效性状态；只使受影响的依赖闭包失效/重算，无关有效结果应保留。
- 覆盖重复扫描幂等、丢失 watcher event 后的 reconciliation、崩溃中断、事务回滚、root 不可访问/重新映射、symlink 越界、同一文件连续改写和源 session 格式不支持。记录扫描/哈希成本与局部更新比例，避免“索引正确但每次都全量重建”。
- SQLite 的通过条件不只是 `integrity_check=ok`：还包括 schema migration、事务原子性、依赖一致性、局部失效正确性、读回一致性、并发/恢复和数据所有权检查。

### G3 — 新 ES 不依赖旧 ES 的 KV Cache

- 在原生 MLX 路径证明旧 ES 的 KV 状态/对象不再可被新 ES 访问或引用；新 ES 必须建立自己的新 KV Cache，并通过 IS 恢复语义结果继续工作。
- 采用独立进程/ES 的真模型实验，记录旧/新 ES ID、模型与 cache 身份、cache 创建/释放事件、IS 读取、prefix/checkpoint/cache 文件访问和上游重新生成次数。测试条件必须明确排除把旧 KV 快照或 Prefix Pool 命中伪装成“新建 cache”。
- 使用禁用或隔离旧 cache 来源的负向对照；令旧 cache 文件不可达后重复新 ES 续算，结果仍应只依赖有效 IS 信息与新生成的 cache。对 cache read 打点/文件访问审计必须覆盖正式执行路径，而不仅是测试 harness 自己的计数器。
- **“新 ES 不依赖旧 KV”是必须证明的语义/所有权边界；“操作系统是否立即归还底层统一内存物理页”是另一项测量。** MLX/Metal allocator 可能保留可复用内存，因此不能仅靠 RSS/统一内存数值瞬时下降作通过标准；应分别报告对象生命周期、旧 cache 不可访问证据与物理内存观察。也不能宣称全部 Prefill/FLOPs 都被省去。

### 在 G1–G3 通过之前的范围限制

- 先使用原生 MLX 的可验证路径构建核心闭环。模型架构适配按实际需求扩展，但每个模型需要各自的正确性和 cache 生命周期证据。
- LM Studio、Ollama、SGLang 等外部服务/引擎属于下一阶段的跨 Backend conformance 工作；可以提前设计 adapter contract，但不得让它们分散 G1–G3 的工程资源，也不能用 HTTP 接口成功替代 KV 物理/所有权证据。
- 外部二进制 recipe registry 与 Bootstrap UI 仍属于产品交付的一部分，但开发顺序应建立在 SQLite 和原生 MLX G1–G3 已有可重复测试的基础上。
- 各 gate 结果必须各自报告 `PASS / FAIL / BLOCKED / NOT_INSTRUMENTED`，禁止把未打点或不可观测改写成 PASS。每份报告注明模型 revision、后端版本、硬件/OS、commit、run ID、cache/prefix 配置和证据文件摘要。

## 1. 审查基线：公开产品仓现状

本方案已检查公开仓 `https://github.com/slamfinger/SimiGo` 的 `main`、README、部署指南、App/Config、App/Settings、App/ExecutionStateGraph、System/EnvManager、System/ProcessRunner、ModelTypes、Package.swift、构建/打包脚本和相关测试。公开检索到的代码快照引用包括 commit `257d0603b1f9ab6a52507fe85a7930c7f0c92b65`。此快照是**公开仓审查基线，不等同于本地 Agent 当前 checkout**。

### 已有能力可复用

- Swift/SwiftUI 菜单栏 App、设置 UI、运行服务与 MLX Native 路径。
- MLX 与 llama.cpp 两种现有本地运行路径；模型路径当前通过文件选择器选择。
- `Packages/SimiGoRuntime` 本地 Swift package，含 `SimiGoRuntimeContract` 与 `SimiGo2Experimental` 两个产品；MLX package revision 已在 Package.swift 中固定。新结果契约代码应优先评估放入 MLX-free 的 `SimiGoRuntimeContract`，避免使核心契约依赖 MLX。
- `EnvManager` 已承担外部进程依赖和命令控制台职责，可拆解复用其进度/日志能力，但不应继续把任意 shell 命令执行作为正式 bootstrap 的核心实现。
- `ExecutionStateGraphStore` 已实现参考 State Graph 的持久化和 fail-closed 行为，可作为迁移兼容对象，但目前公开代码以 JSON 文件持久化图状态，而不是统一的 SQLite ES/IS 数据库。
- 已存在 `tools/dev_install.sh`、`tools/package_dmg.sh` 和部署指南，可在不破坏原发布路径的前提下扩展。

### 必须修正或收敛的路径/部署问题

- `EnvManager.swift` 当前定义 `.simigo/bin`、`.simigo/models`、`.simigo/logs`，且 `setupEnvironment()` 会创建 `models` 目录；这与本方案“不创建家目录 models 目录”的要求冲突。移除 `modelsDir` 及其创建逻辑。
- 当前 llama.cpp 源码目录与默认二进制位置存在两套约定：`EnvManager` 使用 `.simigo` 路径，`Config.swift` 同时默认到用户主目录的 `llama.cpp` 路径。需要统一为一个通过路径解析器得到的管理根，不保留双重、含糊的默认路径。
- 目前 `setupEnvironment()` 对存在的 `llama.cpp` 执行 `git pull --ff-only`，目标随上游变动；并以 `curl | bash` 安装 HF CLI。这不满足锁定版本、可重现构建和失败封闭要求。新 bootstrap 禁止沿用这两种不受固定版本/校验控制的流程。
- `AppConfig` 使用 `UserDefaults` 保存若干模型绝对路径。需采用可迁移的根标识/相对路径/模型 ID 表达；运行时才解析为 URL。必要的 macOS security-scoped bookmark 只作为本机定位/授权材料，不作为可移植模型身份。
- `ExecutionStateGraphStore.defaultStoreURL()` 当前指向 Application Support 下的 JSON。新 SQLite 存储成为 ES/IS 持久化的权威后，应提供一次性、可重复、事务性的旧 JSON 导入；在确认迁移成功前不能删旧文件或双写两个权威存储。
- `Settings.swift` 当前把外部依赖构建和用户命令放在统一命令控制台里。保留开发控制台并不妨碍新增受控 bootstrap UI，但正式初始化和构建只能走白名单配方、参数数组与结构化状态机。

## 2. 目标运行布局

下面是**逻辑布局**，不是写死的绝对路径。`.simigo` 根由 `FileManager`/系统目录 API 和当前用户 home 动态解析；工作目录与模型目录另行选择/探测。

```text
<user-home>/.simigo/                 # SimiGo 管理的运行数据根（运行时解析）
├── simigo.sqlite3                   # ES/IS 主数据库
├── bin/                             # 经过验证的外部引擎二进制，按引擎/版本隔离
├── sources/                         # 锁定 revision 的第三方源码工作副本
├── build/                           # 独立构建目录/中间产物
├── manifests/                       # 实际安装配方、依赖和完整性收据
├── logs/                            # bootstrap/运行诊断日志
├── staging/                         # 下载与安装暂存目录；成功后可清理已验证临时物
└── locks/                            # 跨进程安装/迁移锁（需要时）

<user-selected-external-work-root>/  # 外部用户目录；不在 .simigo 内，不复制文件
<HF cache root>/                     # 外部模型缓存；默认探测 ~/.cache/huggingface
<other model root(s)>/               # 用户可通过选择器注册的外部模型目录
```

### 路径要求

- 不在应用代码中使用 `/Users/...`、`/Applications/...`、开发者用户名、固定 home 字符串或构建机绝对路径。
- `~/.simigo`、`~/.cache/huggingface` 是**用户可理解的约定**；代码中使用系统 API 解析 home 并组合路径，不要把 `~` 当成 POSIX 自动展开的路径，也不要把解析后的绝对字符串写入 portable config。
- 打包与开发脚本用脚本自身位置求 repo root，构建输出相对 repo root 放入可忽略的 `build/`；App 内资源从 `Bundle` 解析，不从 cwd/项目绝对路径解析。
- 外部目录索引保存 `root_id` 和规范化的 `relative_path`。本地访问时通过 root locator/bookmark 重新解析。导出/迁移时允许用户重新映射 root，而不是依赖另一台机器上相同的绝对路径。
- 路径内的 `..`、越根相对路径、符号链接逃逸与路径大小写/Unicode 归一化必须有守卫。

## 3. 数据所有权与 SQLite 设计

SQLite 是 ES/IS 的**元数据与已结算语义结果权威**；它不是外部文件存储，也不是模型仓库。建议采用一个主数据库文件和显式 schema migrations。是否继续使用现有独立 prefix/checkpoint 文件载体应按原有 Representation/Residency 契约决定，不能在本任务中把所有 KV/representation 文件盲目塞入 SQLite。

### 最小 schema 逻辑

Agent 先根据本地代码建模并确定最终 schema；以下是最低要求，不强制逐字照搬表名。

- `schema_migrations`: schema 版本、迁移时间、迁移校验/版本。
- `roots`: 外部工作区、Agent 会话来源、模型根等外部 root 的稳定 ID、类别、显示名、定位类型、状态、创建/扫描时间。可移植数据不依赖绝对路径。
- `external_files`: `file_id, root_id, relative_path, kind, size, modified_at, mtime_ns/resource_id, content_digest, indexed_at, last_seen_at, status` 等索引信息。**不得保存完整文件 payload**；文件仍留在原始目录。
- `agent_sessions`: 来源适配器 ID、源会话 ID、root ID/相对定位、父/分支关系（能可靠获得时）、时间戳、扫描游标、元数据摘要与同步状态。
- `agent_messages` 或同等索引表：外部消息/事件稳定 ID、顺序、父子关系、来源引用、digest 和少量索引字段。默认仅索引，不把来源会话日志完整复制一份进 DB；来源数据不可访问时要标记为 unavailable，而非臆造。
- `execution_states`: ES identity、lineage、position、continuation/lifecycle、model/backend identity、representation binding 和版本字段。
- `information_objects` / `settlements`: 已结算、可恢复的语义结果及其 canonical payload/digest、来源、签名/验证材料、结算时间、契约版本、有效性依据。
- `dependency_edges` / `bindings`: 信息对象依赖、输入绑定、引用的外部文件/会话/上游 settlement、版本或 digest。
- `bootstrap_runs` / `install_receipts`: 每次设置流程的 step 状态、配方 ID/revision、下载/构建收据、输出 hash、开始/结束时间和错误分类。
- `migration_receipts`: 旧 JSON/旧设置迁移源、摘要、结果和完成状态，保证重跑幂等。

### 数据规则

1. DB 可以保存**语义结果**与结算证据，这是 IS 的内容；它不可以再保存 work 源文件、模型权重或 agent transcript 的完整第二份物理拷贝。
2. 外部文件索引可以含路径相对引用、元数据、hash、MIME/类型、扫描状态，以及可重算的索引结构；默认不写整份 extracted text/body。若未来需要全文索引，应将其明确设计为派生索引并可重建、可关闭，不应伪装成原文件副本。
3. `external_files` 的 path 字段只保存 root-relative path；绝对路径可以作为运行时解析出的 URL 临时存在内存中，不得作为可移植 ID 或持久配置主键。
4. 所有 schema 建立与迁移必须在事务中。设置 SQLite `foreign_keys=ON`、明确的 busy timeout、合理 WAL/同步策略；完成后运行 `PRAGMA integrity_check` 与 schema 版本检查。
5. 对既有 JSON Graph 迁移采用“读取旧源 → 校验 contract/version → 单事务写入 DB → 读回逐字段比较 → 写 migration receipt”的流程。失败时旧源不删除、不覆盖 DB 中已确认数据，应用显示可诊断错误并 fail closed。
6. 不要把 `ExecutionStateGraph` 的 `R_Reference_v1` 参考 carrier 等同于 MLX/KV/本地模型执行证据。数据库集成和原生契约通过本身不构成 backend conformance 证明。

## 4. 原生契约集成

最近的独立原生增量已在会话环境中实现并通过 Swift Debug/Release 21/21 测试，增加 `digest_equals_binding` 的 canonical JSON SHA-256 计算和 fail-closed 检查。但它**尚未被证明已整合到本地 Mac 产品生产调用链**，也没有在本地 MLX 环境重新构建验收。

本地 Agent 应：

1. 首先检查本地实际工作树、分支和未提交改动；本地 K 轮代码/证据比公开 `main` 新时，以本地实际代码为集成依据，不能以公开 `main` 覆盖它。
2. 对照当前 Python bridge 的精确 `digest_equals_binding` 语义，包括 canonical JSON、Unicode、布尔/数字/null、嵌套对象、数组、错误分类和字符串绑定值。不能只凭名字判断语言相同。
3. 将 Swift 原生 validator 放在生产契约层的正确目标中。若仍为 Foundation/CryptoKit-only，应优先考虑 `SimiGoRuntimeContract`；若有真实 MLX 依赖才放 `SimiGo2Experimental`。保持它不依赖 Python 才能成为最终权威。
4. 在生成值进入 settlement/signature/持久化桥之前调用 native gate。原生不认识的约束、缺失绑定、canonicalization 错误或 digest 不一致均拒绝；禁止 fallback 到 Python 的宽松接受路径。
5. K 轮曾以 `digest_equals_binding` 作为 native unknown-constraint 反事实；该约束加入 native 支持后，N2 应改为真正未知的 constraint kind，保持未知约束的 fail-closed 测试意义。不要把“模型已生成，结算前被拒绝”误记为“生成前拒绝”。
6. 不注册尚未正式验收的 provider trust，不触发新的真实模型/签名/信任注册实验，除非当前项目授权与测试计划允许；本任务无需改 G2 冻结批次。

验收：Swift Debug/Release 测试通过；native/Python 32-case parity suite 通过（允许 native 更严格，不允许 native 更宽松）；H/I/J 回归通过；生产入口测试证明 mismatch/unknown constraint 在结算前被 native 拒绝；真实 Mac `xcodebuild` 和可用的授权 MLX 验证报告必须由本地 Agent 实际运行与记录。

## 5. 自主引导流程

实现一个共享的 `BootstrapCoordinator`（名称可随项目约定调整），使用显式状态机，App UI 与 CLI/测试使用同一核心逻辑。若成本允许，提供 CLI 入口（例如 `simigo setup`）用于可重复部署与诊断；不要同时实现两套初始化逻辑。

### 状态步骤

1. `preflight`: 检查 macOS、CPU 架构、磁盘空间、Swift/Xcode command line tools、git/cmake/ninja 等配方所需工具。缺项要按需提示安装/引导；不提前把所有可选引擎依赖都判定为必需。
2. `resolve_paths`: 用路径服务解析 `.simigo` 管理根、数据库位置、外部 work root 与 HF cache；展示解析结果的易读路径，但持久配置用 root IDs/相对引用。
3. `create_runtime_dirs`: 幂等创建 `.simigo/bin`, `sources`, `build`, `manifests`, `logs`, `staging` 和所需锁目录。**不得创建 `work/` 或 `models/` 子目录。** 创建失败需返回路径/权限错误。
4. `database_init`: 创建或打开 SQLite；新 DB 使用当前 schema 初始化而不是创建零字节文件；已有 DB 校验 schema 与 integrity；失败时不重建、不覆盖、不清空。
5. `migrate_legacy`: 发现旧 JSON Execution State Graph/设置时按版本导入；成功后写 receipt。旧文件保留作为迁移源/备份直到用户可验证，不能默认自动删除。
6. `select_or_import_work_root`: 使用目录选择器或已注册 root。对源目录只读扫描并建立索引；不复制、不移动、不改名、不删源文件。未选 work root 时可完成 runtime 初始化但报告 `work_import=pending`，不要偷偷创建默认目录。
7. `index_external_files`: 记录 root-relative paths、metadata、digest policy、dependency relations; 默认不跟随指向 root 外部的 symlink；大文件 hash 可分阶段或按策略执行，清晰标记 partial/indexing 状态。
8. `index_agent_sessions`: 使用 `SessionSourceAdapter` 接口导入已确认来源的 session/message 索引。每个 adapter 只读；先识别来源格式/版本，记录 cursor 和 stable IDs，以增量方式更新。未识别格式标 `unsupported`，不猜目录、不破坏源数据。
9. `discover_models`: 按运行时 env 配置探测 HF cache，默认由 home API 解析 `.cache/huggingface/hub`; 枚举 snapshots、repo IDs、revision、模型配置和文件清单。只注册外部路径，不复制权重，不创建 `.simigo/models`。手动选择的外部目录也可以登记。未找到模型不阻塞 DB/ES/IS。
10. `resolve_engine_plan`: 根据用户选择与系统能力，读取受信任、锁定版本的引擎 recipe manifest；显示将下载/构建的对象、许可证、来源、revision、磁盘需求和输出位置。未适配的引擎可以构建/登记，但运行状态必须是 `built_not_adapted`。
11. `download_verify`: 下载到 staging；验证来源、版本、sha256，适用时验证签名；仅在全部校验成功后原子提升到 sources/bin 缓存。失败时留诊断证据，不启动产物。
12. `build_verify`: 对源代码仅 checkout manifest 指定的精确 commit/tag；按参数数组调用 git/cmake/编译器，不执行任意 shell 字符串。构建日志、架构、产物 hash、license 和 recipe revision 写入 receipt。已有同 revision 且 hash 验证通过的产物可复用。
13. `runtime_smoke_test`: 分层验证二进制存在、架构/权限正确、`--version`/健康检查等最小探针可执行。适配器 conformance 单独测试；“已构建”不等于“已适配/受支持”。
14. `final_audit`: 检查 DB integrity、schema version、所有登记 root 可解析或正确标记 unavailable、work 文件数与索引状态、模型未被复制、`~/.simigo/models` 不存在/未创建、配方完整性和依赖状态。
15. `ready_report`: 输出 JSON + 人类可读报告，明确 `ready_core`, `work_import`, `model_discovery`, `engine_build`, `backend_adapter`, `needs_attention` 等独立结果，不将部分完成归为整体成功。

### 幂等与恢复

- 每步都要有稳定 step ID、输入 fingerprint 和可验证输出。
- 同一配置重复执行不应重复导入、重复克隆/构建、重写 root ID 或篡改用户数据。
- 支持锁与并发启动防护；处理中断时读取上次 receipt 续跑。下载和构建先 staging、验证后原子切换。
- 允许失败恢复：重新执行只重试失败/失效步骤，已验证步骤复用；输入或 recipe 版本变化则只使相应步骤过期。
- 失败需分类为 `missing_tool`, `network_error`, `hash_mismatch`, `build_failed`, `schema_mismatch`, `root_unavailable`, `unsupported_source`, `permission_denied` 等，而不是仅返回字符串。

## 6. 外部引擎构建注册表

新增可扩展的 recipe manifest / Swift model。字段至少包含：

- `engine_id`, `display_name`, `version`, `source_url`, `revision`（精确 commit 或不可变发布版本）
- 支持平台/架构、license ID/URL、上游说明
- 获取方式：固定发布资产或固定源代码 revision
- SHA-256 / 签名验证要求
- 构建工具及其最低版本、构建参数数组、输出 artifacts 相对于受管 build root 的路径
- smoke test 参数、成功条件、运行时 adapter 状态 (`not_adapted`, `experimental`, `verified`)
- recipe schema version、维护状态及可复现性说明

### 第一批落地范围

- `llama.cpp`：把现有 clone/build 流程移入配方系统；固定到明确 revision，不再 `git pull` 最新 HEAD；输出放在 `.simigo/bin`/`.simigo/sources`/`.simigo/build` 解析后的受管目录中，不能安装到全局 `~/.local/bin`，除非用户在单独的可选操作中明确要求。
- `MLX`：当前为进程内 Swift package/运行时依赖，不把它误当作必须下载的外部 server binary。沿用 Package.resolved / 固定依赖版本；应用可以独立启动不加载模型。
- 其他 macOS 可构建引擎：先通过 schema、兼容性和模拟 recipe 测试证明 registry 可扩展，再按有明确版本、许可证和构建/校验方式的条目逐一添加。不要为了“支持多个引擎”一口气加入未验证的任意第三方脚本。
- 后续接入某引擎前必须同时有适配器、输入/输出协议映射、取消/生命周期语义声明、资源能力声明和对应 conformance tests；仅构建该 binary 只能报告 `built_not_adapted`。

### 外部命令执行安全

- 尽量用 Foundation `Process`，将 executable URL 与 `[String]` arguments 分离，禁止用 `/bin/zsh -c` 拼接仓库名、路径或用户输入。
- `git`, `cmake`, `ninja`, `swift`, `hf` 等从 PATH / Command Line Tools / Homebrew 常见位置动态探测；不在源码硬写个人机器路径。显示探测来源，用户可覆盖路径，但持久化配置应做 root/locator 抽象。
- 不信任下载下来的 manifest 来执行脚本；manifest 只声明受控的参数/输出， recipe executor 按 schema + allowlist 解释。
- 依赖获取源应固定到允许列表；网络失败、hash 不匹配、签名失败或未知 license 状态必须 fail closed。

## 7. UI / 产品交互

在现有 Settings/首次启动路径加入一个“初始化与数据来源”页面或向导，复用统一 BootstrapCoordinator：

- 显示 `.simigo` 数据根与 DB 状态（可打开目录，但不暴露开发者绝对路径为配置）。
- 选择/注册外部 work root，显示只读扫描数量、索引状态和“不会复制原始文件”的说明。
- 显示识别到的 Agent session providers/source roots；用户能选择来源，adapter 只读索引。
- 显示 Hugging Face cache 发现的模型、revision 和所在 root；默认不自动下载大型模型、不移动/复制权重。
- 显示引擎配方、许可证、固定版本、预计下载/构建内容和结果；用户确认后执行受控下载/构建。
- 每项显示 `not_started / running / succeeded / skipped / failed / needs_attention`，支持重试失败步骤和导出诊断报告。
- State Graph 和数据库初始化可以在无模型、无外部后端的条件下工作；模型引擎状态与 ES/IS 核心 ready 状态分开。

## 8. 实施分阶段与交付物（按 G1–G3 优先重排）

### Phase 0 — 本地工作树审计与原生契约合并

- 输出 `git status --short`、branch/HEAD、相关 diff 与冻结资源清单。
- 对照本地 K2、`production_runtime_bridge.py`、Native contract 和 `SimiGoTaskRun.continueTask`，以本地最新源码为准，保留所有既有差异。
- 验证 digest canonicalization、36-case 或更新后的现有 parity suite、H/I/J 回归；未知约束测试保留真实的 native/Python 差异。

交付：原生集成代码、测试日志、受影响文件清单；不 commit/push。

### Phase 1 — PathResolver 与 SQLite ES/IS 权威持久层

- 统一路径解析；移除 `.simigo/models` 创建逻辑。
- 建立 schema/migration/repository，事务承载 ES、settlements、information objects、bindings、dependencies 与 source roots。
- 对旧 JSON State Graph 做事务迁移与逐字段读回；旧文件保留至验证通过。
- 证明新数据库创建、二次启动、迁移、崩溃回滚与 corruption fail-closed。

交付：可测试 SQLite 模块、schema/migrations、旧数据迁移收据。

### Phase 2 — G1：原生 MLX 真实模型结算与跨 ES 恢复

- 在 native gate/数据库接通后，用本机 MLX 兼容模型执行 U1 并结算；旧进程/ES 结束后，在新进程/ES 从 IS 恢复 U1、增量生成 U2。
- 确认新 ES 无旧 KV/旧 checkpoint/旧 prefix 访问；所有 IS 结果都能追溯到 settlement、来源和依赖。
- 加缺失、篡改、版本不符、依赖变化等拒绝/重算对照。

交付：真实模型多进程证据包、阶段记录、独立 validator 与明确的 claim boundary。

### Phase 3 — G2 + G3：双源 IS 局部更新与 KV 生命周期隔离

- 建立 work root registry 与只读文件索引；建立真实可识别的 Agent SessionSourceAdapter 与 session/message 索引。
- 验证文件/会话的局部变更、dependency closure 失效、无关信息复用、故障恢复和重复扫描幂等。
- 在原生 MLX 真模型场景打通旧 KV 释放/失去可达性、新 ES 建立新 KV、通过 IS 恢复结算值；启用 cache/prefix 文件访问审计和负向对照。
- 如果本地 MLX API 无法直接暴露某个生命周期指标，应增加窄的运行时 instrumentation；无法打点的项目报告 `NOT_INSTRUMENTED`，不能以推测补齐。

交付：G2 增量更新报告、G3 生命周期报告、跨源依赖闭包样例、失败/恢复证据。

### Phase 4 — 原生 MLX 新模型适配与 conformance 流程

- 整理模型发现、架构/配置/tokenizer/权重兼容性探测与适配注册流程，默认从外部 HF cache 引用权重。
- 对现有可适配模型与至少一个新增模型执行模型加载、正确生成、结算/IS 恢复、KV 重建和负向测试。
- 对暂未支持的模型明确返回 unsupported/unverified；不得仅因 snapshot 存在就显示支持。

交付：模型适配矩阵、版本锁定信息、每模型的真实测试证据与未支持原因。

### Phase 5 — 外部引擎 recipe registry 与 Backend conformance（G1–G3 后扩展）

- 将 llama.cpp 构建移入版本锁定 recipe；保持 Native MLX 作为首要且无需外置 server binary 的路径。
- recipe registry 通过 fixture/mock 测试后，再增加第二个真实可构建的 macOS binary recipe。
- LM Studio、Ollama、SGLang 适配器按各自可观测性和 cache ownership 能力分开登记；运行协议可用与 ES/IS conformance 通过是不同状态。
- 对无法控制/观测服务内部 KV 的 Backend，只声明已证明的 ES/IS 层连续性，不宣称证明其内部 KV 已物理释放。

交付：recipe schema、锁定 manifest、download/build receipts、逐 Backend conformance 与可观测性矩阵。

### Phase 6 — First-run Bootstrap UI / CLI

- UI 与可选 CLI 共用同一个 coordinator/state machine。
- 顺序为环境预检 → `.simigo` 必需目录 → SQLite 检查/初始化/迁移 → 选择外部 work root → 索引文件与 session sources → 发现 HF 模型 → 可选外部引擎获取/构建 → smoke tests → JSON/人类可读报告。
- 无模型、未选 work root、没有可选外部引擎时，核心 ES/IS 仍可初始化；UI 明确呈现部分就绪状态。

交付：向导、幂等/恢复演练、初始化 JSON report。

### Phase 7 — 产品打包与首次部署验收

- 基于本地真实工作树做 Debug/Release build/test、open-source audit、数据库检查、bootstrap dry run/实跑与第二次幂等启动。
- 干净用户目录验证 app launch → SQLite init → work/session index → HF model discovery → Native MLX G1–G3 → 选配外部引擎配方。
- 保留已有用户数据；不自动清理、覆盖或移动用户指定目录。

交付：release candidate、实际测试日志、安装/初始化报告、数据迁移凭证与残余风险清单。

## 9. 验收矩阵

### 原生契约

- Swift Debug 测试必须全通过；运行相关 Release 测试与 Release build。若全量 Release test target 被既有、无关的 `#if DEBUG` fixture 编译问题阻断，应准确报告为 `BLOCKED` 并给出复现日志；不可将其描述为通过，也不得借本任务清理无关文件。
- Python/native 当前扩展 parity suite 通过（K2 基线为 36 cases；若 fixture 增加，报告实际 cases/hash），并通过 H/I/J 回归；native 不得比 Python 更宽松。
- 未知约束、缺失 binding、digest mismatch 必须在结算/签名前拒绝；不得 silent fallback。
- 在本地实际生产入口调用原生 authority；不能只提交独立 library 或 fixture wrapper。

### G1–G3 核心研究验收门（必须各自有独立证据）

- **G1 / Native MLX ES→IS→新 ES：** 真模型 U1 已结算且可从 IS 校验恢复；旧执行进程/ES 不再提供连续性；新 ES 生成 U2；无上游重生成；缺失/篡改/依赖变化按声明拒绝或重算。
- **G2 / 双信息源局部动态更新：** 同一 SQLite IS 同时索引外部 work 与 Agent session 来源；对新增/修改/删除/追加/分支事件只更新所需记录与依赖闭包；受影响结果失效，无关有效结果保持可用；重复扫描幂等；故障后可恢复。
- **G3 / KV 生命周期隔离：** 旧 ES 的 KV 不被新 ES 读取、借用或通过 checkpoint/prefix pool 间接复用；新 ES 的 cache identity/创建事件有记录，IS settlement 被恢复；在旧 cache 不可达的对照下依旧通过。另行报告 allocator/统一内存指标，不以 RSS 是否立即下降单独裁定。
- G1–G3 每一门至少包括真实 Native MLX 路径、独立进程边界、运行时日志/访问审计、负向对照、独立验证器与可复核证据目录；fixture-only 或 `NOT_INSTRUMENTED` 不算通过。
- G1–G3 通过前不得将外部服务适配扩展作为主线验收，也不得声称多 Backend 通用性。

### 数据库与文件所有权

- 首次启动创建 schema 完整、可打开的数据库；`integrity_check=ok`。
- 重跑初始化保持 DB ID、root IDs、已结算 ES/IS 内容稳定；schema migration 不重复导入。
- work 目录的文件字节、文件数量、修改时间和位置不因导入改变；数据库没有完整原文件 payload 或模型权重副本。
- 数据库索引只使用 root ID + relative path；根路径丢失时标记 unavailable 并允许重映射，不崩溃、不猜测。
- 旧 State Graph JSON 导入前后逐字段一致；失败时旧数据留存且 DB 无半写入。
- `.simigo` 下**不存在新建的 `work/` 或 `models/`**；HF cache 保持外部路径引用。

### 引导部署与外部引擎

- 路径解析器测试覆盖不同 home、带空格/Unicode 的目录、外部卷、相对路径越根、symlink。
- 没有开发者绝对路径、个人用户名、固定签名身份或机器专属路径进入 tracked code/config/report fixtures。
- 配方仅从固定版本下载/checkout；hash/signature 失败时二进制不提升到 installed 状态。
- 构建中断可续跑；重复运行复用验证过的产物；未知配方不运行。
- `built_not_adapted` 不会被 UI/API 显示成已支持 backend。
- 无模型/no work root/no optional engine 下，核心 ES/IS 可初始化；报告具体缺项，不假报全绿。

### 工程回归

- 跑 `tools/open_source_audit.sh`、Xcode Debug tests、Release build 和所需 E2E。
- 运行原生实际代码所需的测试；记录执行环境和准确结果，不能以远程公开仓源码测试代替本地更近的工作树验证。
- `git diff --check` 通过；工作树中已有无关改动保持不变；未授权时不 commit/push。

## 10. 本地 Agent 开始前的保护协议

实施第一步必须执行并保存输出：

```text
git status --short
git branch --show-current
git rev-parse HEAD
git diff --stat
git diff --name-only
```

然后建立本地保护清单：

- 记录 K/native-contract bridge、`SimiGoTaskRun.continueTask` 和 Python bridge 的实际路径与 hash。
- 列出冻结 G2、H/I/J/K 运行目录/证据文件；任何这些路径都不能被清理、重写、重新生成或纳入新导入目录。
- 对每个计划修改文件先读现状，确认不覆盖先前 Agent 留下的改动。不要 `git reset --hard`、`git clean`、大范围格式化或通过从公开 `main` 拷贝文件替换本地版本。
- 新实验和部署报告使用全新的 run ID/目录。不要触碰历史证据以“修复”结果。
- 不在代码、配置、测试或报告中保存模型绝对路径、用户名、私人签名信息/API keys、私人日志原文或机器标识。

## 11. 推荐执行顺序与风险控制

优先级按下列次序执行，不得被 UI/外部引擎的可见成果倒置：

1. **保护工作树并接入原生 gate**：确立实际本地代码基线，不覆盖 K2 与历史证据。
2. **先磨合 SQLite ES/IS 权威存储与 PathResolver**：这决定文件/会话双源索引、依赖校验和模型路径移植性的正确基础。
3. **原生 MLX 完成 G1**：证明真实结算结果能在新进程/ES 从 IS 恢复。
4. **完成 G2 + G3**：数据库双源局部更新/依赖失效正确，以及新 ES 不依赖旧 ES 的 KV。三者均作为基本门，不互相代替。
5. **持续扩展原生 MLX 模型适配**：新模型逐一经过 loading/generation/settlement/IS restore/KV lifecycle conformance。
6. **之后扩展 LM Studio、Ollama、SGLang 等外部后端和二进制 recipe**；根据可观测能力限定 claim。
7. **最后让 Bootstrap UI/CLI 与打包流程编排已验证能力**，并实测首次安装、重复启动和故障恢复。

如范围需要分里程碑，第一里程碑至少包括 Phase 0–3，并以原生 MLX 下 G1、G2、G3 全部通过为 exit criteria；第二里程碑推进 Phase 4 的新模型适配；第三里程碑推进 Phase 5 的外部 Backend/recipe；最后完善 Bootstrap 与打包。不能为了交付界面而把尚未完成的 G1–G3 显示成“系统 Ready”。

## 12. 源码参考

- [公开产品 README](https://github.com/slamfinger/SimiGo/blob/main/README.md)
- [部署指南](https://github.com/slamfinger/SimiGo/blob/main/%E9%83%A8%E7%BD%B2%E6%8C%87%E5%8D%97.md)
- [EnvManager.swift](https://github.com/slamfinger/SimiGo/blob/257d0603b1f9ab6a52507fe85a7930c7f0c92b65/SimiGo/System/EnvManager.swift)
- [Config.swift](https://github.com/slamfinger/SimiGo/blob/257d0603b1f9ab6a52507fe85a7930c7f0c92b65/SimiGo/App/Config.swift)
- [Settings.swift](https://github.com/slamfinger/SimiGo/blob/257d0603b1f9ab6a52507fe85a7930c7f0c92b65/SimiGo/App/Settings.swift)
- [ExecutionStateGraph.swift](https://github.com/slamfinger/SimiGo/blob/257d0603b1f9ab6a52507fe85a7930c7f0c92b65/SimiGo/App/ExecutionStateGraph.swift)
- [SimiGoRuntime Package.swift](https://github.com/slamfinger/SimiGo/blob/257d0603b1f9ab6a52507fe85a7930c7f0c92b65/Packages/SimiGoRuntime/Package.swift)
- [ProcessRunner.swift](https://github.com/slamfinger/SimiGo/blob/257d0603b1f9ab6a52507fe85a7930c7f0c92b65/SimiGo/System/ProcessRunner.swift)
- [dev_install.sh](https://github.com/slamfinger/SimiGo/blob/257d0603b1f9ab6a52507fe85a7930c7f0c92b65/tools/dev_install.sh)
- [package_dmg.sh](https://github.com/slamfinger/SimiGo/blob/257d0603b1f9ab6a52507fe85a7930c7f0c92b65/tools/package_dmg.sh)

---

## 给本地 Agent 的直接执行指令

你负责把本文件从方案落实成代码和证据。不要只改文档或输出更多计划。先盘点当前本地仓与工作树，保全所有现有差异；随后按 Phase 0 → 7 推进；首先在原生 MLX 上完成 G1–G3 基本验收，再扩展模型与外部 Backend。每个 phase 完成后立即运行对应测试、写报告和继续下一阶段，不要等待用户逐步批准常规、可逆的工程动作。

必须把以下行为作为实现不变量：外部 work root 不移动、不复制；DB 为 ES/IS 语义状态与外部源索引的权威；模型权重留在 Hugging Face/用户指定外部目录；无 `~/.simigo/models`；不硬编码开发机器绝对路径；外部 binary 只从锁定、可验证配方下载/构建；引擎构建成功不等于 runtime adapter 已支持；原生契约校验在结算前拥有最终拒绝权；不覆盖冻结/历史实验或工作树中的无关差异。

实际无法执行的步骤（比如需要未装工具、额外网络授权或不存在可识别的 Agent session 源格式）要记录为明确的阻塞与复现命令；其余部分继续实现。不要把未执行或 fixture-only 测试写成真实 Mac/模型验收。最后交付：代码 diff 文件清单、每阶段报告、Debug/Release 测试日志、数据库 schema/migration、bootstrap JSON report、配方清单、残留风险，以及 `git status --short`。未经明确要求不 commit、不 push。
