# SimiGo 代码文件说明（FILES）

**性质**：产品源码文件的逐文件说明（每条一行「这是什么」）。只描述当前快照，不含过程记录或变更建议。
**快照**：origin/main `47beffc`（schema v51）· 2026-11-21。
**口径**：产品源码 191 个 Swift 文件 / 100,616 行（排除 `*Tests*` 与 3 个 Package.swift）；行数按 `wc -l` 实测。按模块分节。
**范围**：`SimiGo/` 与 `Packages/*/Sources`；同包独立导出 target 的 `main.swift` 计入采集模块。


## LOCALBCore（6 文件 / 5,469 行）— 局域网信任域（vendored，swift-crypto 跨平台）

- **LOCALBHostBootstrap.swift**（208）— 局域网主机侧引导：配对所需的本机身份与端点装配入口。
- **LOCALBI0Support.swift**（1,099）— I0 冻结支持层：SRS 表示/信封编解码（RFC 8785 JCS numeric-free 闭模型），自 frozen blob verbatim 提取、测试强制字节 parity，禁重构。
- **LOCALBPairingCoordinator.swift**（1,348）— 配对协议状态机：challenge 防重放（ledger）＋Proof V1/V2＋一次性 secret＋字段/事件编解码＋HTTP 请求帧，24 类型。
- **LOCALBProductionSigner.swift**（919）— 生产签名器：请求签名/证明生成，`#if canImport(Security)` 守卫的跨平台密钥访问。
- **LOCALBRegistryStore.swift**（1,089）— append-only 事件日志：hash 链（headHash/sequence/lineage fail-closed）＋durable append＋loadVerified；含 lstat 根身份复核。
- **LOCALBTransportIdentityStore.swift**（806）— 传输身份存取：Keychain 作用域（scoped query/add/delete）＋isolatedDefault 兼容别名。

## SimiGoCollection（23 文件 / 8,194 行）— 会话采集

- **Adapters/AIStudioSource.swift**（305）— AI Studio 会话目录适配器：定位/解析/判卷（TranscriptSource 实现）。
- **Adapters/ChatGPTSource.swift**（226）— ChatGPT 导出目录适配器。
- **Adapters/DeepSeekSource.swift**（343）— DeepSeek 会话目录适配器。
- **Adapters/FlatMessageExportSource.swift**（305）— 扁平消息导出格式适配器。
- **Adapters/MarkdownSessionSource.swift**（326）— Markdown 会话文件适配器。
- **Adapters/OpenCodeSource.swift**（211）— OpenCode SQLite 库适配器（不 conform TranscriptSource，定位符写死 opencode.db）。
- **Adapters/RolloutSource.swift**（162）— rollout JSONL 会话适配器。
- **CandidateInbox.swift**（262）— 候选入库包装：cursor＋legacy 迁移，委托中立存储。
- **CollectionLease.swift**（133）— 采集租约：目录级 lstat 身份＋持有判定（硬化读）。
- **CollectionRunner.swift**（384）— 采集运行器：DispatchSourceTimer 轮询租约、调度各 adapter 扫描。
- **CollectionTypes.swift**（321）— 采集类型与 operationKey（共享 sortedKeys 规范化）。
- **Core/CollectionCandidateInbox.swift**（1,163）— 源中立候选存储：SQLite＋事务＋digest 校验＋quarantine 两阶段（intent→RENAME_EXCL→unlink，全 `*at()` POSIX＋目录 fsync）＋中断恢复。
- **Core/CollectionTurn.swift**（146）— 采集轮次行类型（CollectionTurn/Dependency）。
- **Core/SnapshotReimport.swift**（389）— 快照重导入：基线对账与重扫入口。
- **Core/SnapshotSupport.swift**（222）— 快照支持：定位符/JSON/timestamp 公共管道（adapter 共享）。
- **Core/TranscriptSource.swift**（120）— 采集协议：identity/grading/diagnostic 共享扩展（CO1 收敛点）。
- **RootFileIdentity.swift**（20）— 硬化文件身份共享 helper（privateRegularFileInfo：S_IFREG+uid+nlink，四处调用点）。
- **Transcript.swift**（182）— 会话/轮次/消息解析类型（ContentBlock 等）。
- **TranscriptClassifier.swift**（154）— 转写行分类器（会话边界判定）。
- **TranscriptSourceAdapter.swift**（82）— 适配器统一入口（源类型→adapter 绑定）。
- **TranscriptTailer.swift**（1,850）— 尾随采集机：TranscriptPathAccess 硬化读（O_NOFOLLOW/openat/inode）＋OversizedScan 大文件窗口＋游标 save-verify。
- **TurnAccumulator.swift**（724）— 增量轮重建：6 项 fail-closed RetentionLimits＋compaction 断链降级。
- **同包独立导出 target 的 `main.swift`**（164）— 复用 TurnAccumulator 事件直出（位于 `Packages/SimiGoCollection/Sources/` 下的独立 target）。

## SimiGoRuntimeContract（26 文件 / 23,161 行）— ES/IS 语义核心（MLX-free，SQLite）

- **ESISDatabase.swift**（11,521）— ES/IS 主库：结算/准入/会话/依赖/摘要/更正/撤销＋迁移 v1-v51（三文件主件）。
- **ESISDatabaseInformationSpace.swift**（2,540）— IS 记录写入扩展：project note/更正回执/撤回/依赖可见性（D1 片二）。
- **ESISDatabaseIndexingAndSearch.swift**（2,056）— 索引与检索扩展：root 扫描/单脊源读（indexOnlySourceData）/searchableFileText/carriedFileContent（D1 片一）。
- **InformationLoop.swift**（1,225）— 检索基座：basis v6 规范化＋流式扫描＋cachedResolution 读端拒绝。
- **SnapshotContract.swift**（918）— 快照契约：requireCovered 去重校验＋settled 对象契约。
- **NativeDeclarativeResultContract.swift**（690）— 原生结果契约：SettlementAuthority 验证＋NativeSHA256（canImport fallback）。
- **ManagedContinuation.swift**（576）— 受管续接：pinAnchor 依赖闭包校验（TOCTOU 收口）＋sourceDependencies 声明。
- **SettlementConsumption.swift**（564）— 零模型消费：currentDemandID 五查＋ownerScope 基串＋sourceOwnershipMismatch。
- **ManagedRefusal.swift**（301）— 失败记录：身份双前缀拒绝分类。
- **ISAdmission.swift**（306）— IS 准入（读端）：ruling ④ 调用方（freshnessGate→Refusal 映射）。
- **TurnDigest.swift**（386）— 轮摘要：prompt/parse/sourceSHA256/staleSource 分类。
- **Bootstrap.swift**（205）— 启动预检：fail-closed 报告＋launchedAt 贯通。
- **DirectoryManifestExport.swift**（253）— 目录清单导出。
- **EngineRecipe.swift**（240）— 引擎配方描述。
- **ModelDiscovery.swift**（192）— 模型目录发现（无缓存，逐次扫）。
- **SettlementIdentityBinding.swift**（186）— 生产者身份绑定（model+tokenizer 内容摘要行）。
- **ExecutionContinuityContract.swift**（165）— 续接契约类型。
- **ISContextLedger.swift**（145）— IS 上下文台账。
- **SettlementKVBinding.swift**（141）— KV 绑定表示：poolKey 单格式（contentDigest 无默认）。
- **SettlementRiskNotice.swift**（77）— 风险通知词汇＋freshness finding（ruling ④）。
- **ManagedPaths.swift**（115）— 受管路径（databaseURL 等）。
- **SettlementSummaryPolicy.swift**（100）— 摘要策略。
- **SettlementAuthority.swift**（89）— 结算权威（payload digest 验证）。
- **ExecutionStateBackendContract.swift**（72）— 执行状态后端契约。
- **RuntimeBackendContract.swift**（67）— 运行时后端契约。
- **ChatRoundText.swift**（31）— 会话轮文本小件。

## SimiGo2Experimental（70 文件 / 21,625 行）— MLX 载体＋证据机器（探针/实验/测量）

- **PrefixSnapshotStore.swift**（752）— 磁盘前缀快照存储：sidecar v4 不可变代次＋rescan 自愈＋单脊源读（production 域）。
- **ExecutionStatePrefixPool.swift**（501）— 前缀池：内容级 ==＋registrationID 登记级双层、performIfCurrent 原子租约、onReplace/onEvict 退休回调。
- **ExecutionBindingRegistry.swift**（218）— 表示绑定登记：RepresentationRef（key 含 contentDigest，无默认）＋绑定量具。
- **ExecutionContinuityCoordinator.swift**（280）— 续接协调器（experimental 侧协调面）。
- **ExecutionResidencyPlanner.swift**（158）— 驻留规划器。
- **ExecutionState.swift**（52）— 执行状态标签（workload label，非 ES handle）。
- **ExecutionStateMaterializationExperiment.swift**（60）— 物化实验入口。
- **MaterializationCoordinator.swift**（119）— 物化协调器（磁盘 artifact 域）。
- **MLXExecutionStateBackend.swift**（130）— MLX 执行状态后端（嵌套 BackendError 为零引用死代码，P1 待授权裁）。
- **MLXExecutionStateCostProfile.swift**（1,179）— MLX 成本画像测量。
- **MLXResidencyBackend.swift**（52）— MLX 驻留后端（RuntimeResidencyBackend 实现）。
- **LLAMAServerExecutionStateBackend.swift**（106）— llama.cpp 执行状态后端。
- **LLAMAServerExecutionStateAdapter.swift**（294）— llama.cpp 适配器。
- **LLAMAServerExecutionStateAB.swift**（215）— llama.cpp A/B 对比实验。
- **LLAMAServerExecutionStateCancellation.swift**（436）— llama.cpp 取消路径。
- **LLAMAServerExecutionStateExecutor.swift**（125）— llama.cpp 执行器。
- **LLAMAServerExecutionStateForkRestore.swift**（298）— llama.cpp fork 恢复。
- **O6ExecutionStateOversized.swift**（949）— 超大上下文执行状态（分段 O6 主实现）。
- **OversizedSegmentedEngine.swift**（906）— 分段引擎（超大上下文推理）。
- **OversizedSegmentMaterializer.swift**（43）— 分段物化器。
- **OversizedTokenLedger.swift**（183）— 超大上下文 token 台账。
- **PerTensorSafetensorsReader.swift**（141）— 逐张量 safetensors 读取。
- **SafetensorsGroupMaterializer.swift**（152）— safetensors 组物化。
- **SafetensorsInventory.swift**（222）— safetensors 清单。
- **UIBranchSessions.swift**（3,228）— UI 分支会话（experimental 侧产品缺口 backlog，14 TODO）。
- **MLXGroupGate.swift**（97）— 组门。
- **MLXGroupInferenceGate.swift**（186）— 组推理门。
- **MLXGroupLifecycleExperiment.swift**（169）— 组生命周期实验。
- **MLXGroupResidencyBenchmark.swift**（449）— 组驻留基准。
- **MLXParameterSwapGate.swift**（113）— 参数交换门。
- **MLXPrefixRecomputeExecutor.swift**（116）— 前缀重算执行器。
- **AsyncLock.swift**（53）— 异步锁原语。
- **UnsafeSendableBox.swift**（8）— Sendable 装箱小件。
- **TaskRunOutcomeClassification.swift**（28）— 任务结果分类（纯函数）。
- **ExperimentSchema.swift**（163）— 实验记录 schema。
- **LayerGroup.swift**（93）— 层分组。
- **LayerPolicy.swift**（78）— 层策略。
- **LayerResidencyEngine.swift**（127）— 层驻留引擎。
- **LayerDemandCSV.swift**（82）— 层需求 CSV 导出。
- **LayerDemandExperimentRunner.swift**（87）— 层需求实验跑器。
- **PlannerBudgetSweep.swift**（143）— 规划预算扫描。
- **StateSequenceSweep.swift**（77）— 状态序列扫描。
- **ResidencyBenchmark.swift**（43）— 驻留基准。
- **ResidencyContractStateMachine.swift**（200）— 驻留契约状态机。
- **ResidencyController.swift**（333）— 驻留控制器。
- **ResidencyPolicyKind.swift**（146）— 驻留策略种类。
- **RepresentationCapture*.swift**（100）— 表示捕获记录。
- **WorkloadTrace.swift**（420）— 工作负载 trace。
- **E5ExecutionStateScenario.swift**（450）— E5 场景实验。
- **L4Identity.swift**（285）— L4 身份实验。
- **L4Reconciliation.swift**（276）— L4 对账实验。
- **NamedSourceConformanceProfile.swift**（266）— 具名源 conformance 画像。
- **ChatTemplateGeneration.swift**（104）— 聊天模板生成。
- **CrossBackendLogitProbe.swift**（457）— 跨后端 logit 探针。
- **CrossBackendMarginProbe.swift**（630）— 跨后端 margin 探针。
- **CrossBackendTokenProbe.swift**（385）— 跨后端 token 探针。
- **O2BaselineProbe.swift**（324）— O2 基线探针。
- **O3CSegmentWiseProbe.swift**（336）— O3C 分段探针。
- **O3CStreamingForward.swift**（366）— O3C 流式前向。
- **O3SkeletonProbe.swift**（275）— O3 骨架探针。
- **O4GenerationProbe.swift**（439）— O4 生成探针。
- **O4OversizedGenerationProbe.swift**（355）— O4 超大生成探针。
- **O6CancellationAB.swift**（433）— O6 取消 A/B。
- **O6FixedPrefixPhaseStudy.swift**（75）— O6 固定前缀相位研究。
- **O6SegmentPhaseProfiler.swift**（169）— O6 分段相位画像。
- **Instrumentation/GroupExecutionTraceProbe.swift**（594）— 组执行 trace 探针。
- **Instrumentation/InstrumentationIdentityProbe.swift**（532）— 仪器身份探针。
- **Instrumentation/MeasuredExecutionTracePilot.swift**（442）— 实测 trace 试点。
- **Instrumentation/MeasuredTraceCollection.swift**（270）— 实测 trace 集合。
- **ModelInventoryReference.swift**（52）— 模型库存引用。

## SimiGo/App（13 文件 / 6,160 行）— macOS UI 壳

- **MenuApp.swift**（382）— 菜单栏 App 入口（NSApplication 装配）。
- **Config.swift**（361）— 配置读写（端口派生、时间导出目录 SourceTimeExport）。
- **Settings.swift**（1,315）— 设置界面（~29 @State；contractBox/informationSpaceBox 分节）。
- **SettingsStatusViews.swift**（111）— 只读状态视图（D7：版本脚注/缺口计数/ownership-retry 三段逐字提取）。
- **StatusBarCoordinator.swift**（351）— 状态栏协调（菜单装配、processLaunchStartedAt 采样）。
- **ExecutionStateGraph.swift**（1,370）— 执行状态图（单 SQLite 权威＋JSON 迁移/投影；fork 经 mutate 权威面）。
- **TurnDigestScheduler.swift**（1,107）— 摘要调度器：repairLoop 共享骨架＋DigestGenerationGate(limit:1)＋durable ledger refill＋重试分类。
- **BootstrapRunner.swift**（70）— 启动引导跑器（loadLegacyGraph 用 lstat 区分 ENOENT 与 I/O 错）。
- **CollectionLifecycle.swift**（198）— 采集生命周期装配。
- **MultiFormatCollection.swift**（295）— 多格式采集入口（codex- 前缀剥离等）。
- **FirstRunWizard.swift**（479）— 首启向导（不自动弹面板、alreadyInstalled 自动收尾）。
- **ExternalTurnSink.swift**（106）— 外部轮次汇入。
- **BackendSelection.swift**（15）— 后端选择小件。

## SimiGo/Headless（3 文件 / 1,690 行）— 无头入口（移植滩头）

- **EnvBootstrapEntry.swift**（143）— 环境引导无头入口。
- **G1G3Entry.swift**（853）— G1G3 实验串跑入口（哈希委托混合：一委托一 raw）。
- **LocalBManagementEntry.swift**（694）— LOCALB 管理无头入口。

## SimiGo/Inference（24 文件 / 11,606 行）— 推理编排

- **NativeMLX.swift**（4,060）— MLX 运行时主件（generate 流/池 admit/export/capture；加载期身份种子教义所在；quiescence/lease 消费方）。
- **NativeMLXSessionOperations.swift**（857）— 会话操作扩展（D5：会话持久化/ES 投影/分支 fork）。
- **NativeMLXPrefixPool.swift**（638）— 前缀池门（admit/bindVerdict/representationRef 单源；namespace 派生）。
- **NativeMLXResidency.swift**（312）— MLX 驻留（驻留后端实现）。
- **NativeMLXObservation.swift**（212）— MLX 观测（observation 结构）。
- **PrefixMemoryPool.swift**（431）— 内存前缀池（boundaryHash 快查＋contentDigest 全验双层）。
- **OversizedRuntime.swift**（392）— 超大上下文运行时（stopGeneration 单调意图＋双 stall 重检）。
- **LifecycleGates.swift**（666）— 生命周期门（quiescence/operation gate/drain 纯函数＋计数）。
- **ToolGovernance.swift**（438）— 工具调用治理（状态机＋retention/hard cap＋事件发射）。
- **RequestBudget.swift**（757）— 请求预算（预算门）。
- **SlotProgressMonitor.swift**（568）— 槽位进度监视。
- **StreamTokenFilter.swift**（208）— 流式 token 过滤（CryptoKit 指纹）。
- **ManagedGGUFRuntime.swift**（287）— GGUF 运行时（settlementConsumption 接线；SlotActivity 扩展）。
- **ManagedGGUFRuntime+SlotActivity.swift**（182）— GGUF 槽位活动扩展。
- **GGUFEngineClient.swift**（279）— GGUF 引擎客户端（llama-server 交互）。
- **ISKVBindAuthority.swift**（108）— KV 绑定权威（register/consume 一次性）。
- **InformationSpaceRuntime.swift**（119）— IS 运行时装配。
- **LOCALBHostRuntime.swift**（222）— LOCALB 宿主运行时（双监听器装配）。
- **LOCALBTransportPolicy.swift**（96）— 传输策略（loopback 明文/LAN TLS 判定）。
- **ExecutionControlling.swift**（143）— 执行控制面。
- **ExecutionPolicy.swift**（312）— 执行策略。
- **ExecutionLineage.swift**（95）— 执行谱系。
- **ExecutionStateProjection.swift**（88）— 执行状态投影。
- **BranchCheckpointRetention.swift**（136）— 分支 checkpoint 留存。

## SimiGo/Lifecycle（2 文件 / 929 行）— 生命周期

- **RuntimeLifecycle.swift**（518）— 运行时生命周期。
- **RuntimeTuning.swift**（411）— 运行时调参常量（含 DEBUG override 门）。

## SimiGo/Model（5 文件 / 1,907 行）— 模型身份/类型

- **GGUFModelIdentity.swift**（512）— GGUF 身份：resolve（stamp 缓存）＋streamingSHA256＋FileIdentityParts。
- **ProducerIdentity.swift**（416）— 生产者身份（weights/tokenizer identity；digest 与 byteCount 同描述符版本）。
- **InferenceNodeCfg.swift**（287）— 节点配置（单端口：listenerPort/apiPort/localCompatibilityPort 恒 nil；isLoopbackBindHost inet_pton）。
- **ModelTypes.swift**（504）— 模型类型（tool-choice schema 校验类型）。
- **TypesBridge.swift**（188）— 类型桥（JSONValue.messageText/argumentsJSON/CFBoolean 守卫）。

## SimiGo/Observability（2 文件 / 330 行）— 观测

- **RuntimeStateReporter.swift**（138）— 运行时状态报告（可判定快照，日志-状态分离）。
- **TraceLogger.swift**（192）— trace 日志（8MB×5 代轮转＋verbose 分档）。

## SimiGo/Protocol（12 文件 / 15,837 行）— HTTP/MCP 传输壳

- **HTTPServer.swift**（3,767）— HTTP 服务器主件（NWListener 双监听器/就绪门/SSE 单发送器/enqueueSend/LOCALB 路由表）。
- **HTTPServerChat.swift**（1,981）— Chat 端点（recordReusedAnswer commit-first 四路）。
- **HTTPServerCompletions.swift**（778）— Completions 端点（复用共享 SSE 发送器）。
- **HTTPServerResponses.swift**（3,805）— Responses 端点（流式/非流式/预检/risk 门）。
- **HTTPServerManagement.swift**（1,320）— 管理端点扩展（D4：env/engine_ledger 等）。
- **HTTPServerMCP.swift**（2,556）— MCP 层（16 工具定义＋runMCPTool＋三入口一扇门 declareReuseContract）。
- **ContinuationAdmission.swift**（81）— 续接准入小件。
- **ContinuationSettlement.swift**（405）— 续接结算（contract 流程）。
- **ManagedContinuationEntry.swift**（680）— 受管续接入口。
- **SettlementConsumptionEntry.swift**（391）— 结算消费入口（allow_recompute 严格 CFBoolean）。
- **BranchLifecycle.swift**（56）— 分支生命周期小件。
- **InformationTurnProducer.swift**（17）— 信息轮生产者小件。

## SimiGo/System（5 文件 / 3,708 行）— 系统集成

- **Service.swift**（1,356）— 服务主件（启动路径/端口/清理）。
- **EnvManager.swift**（1,699）— 环境管理（runProcess 单流式核/bootstrap/安装校验/probeLlamaServerVersion 单探测）。
- **Detector.swift**（340）— 探测器。
- **ProcessRunner.swift**（31）— 进程小件（仅 env/hfEndpoint 存活）。
- **EngineIdentityLedger.swift**（282）— 引擎身份账本（只记不判；probeVersion 单探测；append 无 O_APPEND 为已知 P3）。
