# SimiGo 产品仓集成与自主引导部署 — 实施证据报告

生成时间：2026-10-23　执行人：本地 Qoder Agent（无人值守续跑）
交付边界：产品仓 `slamfinger/SimiGo`（本地路径 `/Users/mr.simi/Documents/SimiGo`，分支 `localb-b3-closure-20261016`，HEAD `de362ef` 未变）
Git：本轮**未 commit、未 push、暂存区为空**；公开主线未被覆盖；Lab 冻结证据未触碰。

## 三层验收证据（严格分列，不得合并）

### Layer 1 — Lab 原生契约研究证据（前置，继承 K2）
- 原生摘要契约 `SHA256(canonicalJSON(field)) == verifiedBindings[binding]` 方向已对齐 Python（K2）。
- 已验证向量随**逐字节复制**进入产品包：
  - `2b1a5d9f…c334a8`（"NORTH>EAST"）
  - `09ad9fd2…301cc6`（`{"a":1,"b":"é"}`）
- Lab 引擎源 `NativeDeclarativeResultContract.swift` 以 `cp` byte-exact 复制进 `Sources/SimiGoRuntimeContract/`。

### Layer 2 — 产品仓实际集成证据（本轮，本 Mac 实跑）
1. 原生契约入**真实生产结算路径**：`ExecutionStateGraphStore.settleValidatedResult` 先跑
   `SimiGoSettlementAuthority.authorize`（native、MLX-free、无 Python 回退、拒绝即抛），通过后才落库。
2. SQLite 为 ES/IS 与结算的**权威写入**：`settleValidatedResult` 于 `mutate` 后调用
   `ensureESIS()` → `recordExecutionState` + `recordNativeSettlement`；DB 打开 `SimiGoPaths.databaseURL`，
   corrupt/unwritable fail-closed（记 `persistError`，绝不静默覆盖）。
3. 旧 JSON **事务性迁移**：`importLegacyGraph` 单事务导入 + 逐字段 read-back 校验 + migration_receipt，
   失败回滚；bootstrap 仅在 `execution_states==0` 时导入一次（可重复、不重复导入）。**（本轮已推进见 Layer2 续：SQLite 现为读+写权威，JSON 退役。）**
4. 模型发现：`SimiGoModelDiscovery` 从运行时解析的 HF 缓存位置（HF_HUB_CACHE→HF_HOME/hub→~/.cache/huggingface/hub）
   以 (root_id + 相对路径) 发现，**不复制进 `.simigo`**。
5. 外部索引：`external_files` / `agent_sessions` / `roots` 存索引+元数据，无第二份物理文件。
6. 外部引擎配方 registry（不写死 llama）：`SimiGoEngineRecipe`/`SimiGoEngineRegistry`；
   downloaded/built/adapted **三态独立**；`git pull` → 锁定 `checkout --detach <pinnedRef>`；
   无 checksum 时自动下载 **fail-closed**（不伪造哈希）；构建后删 sources/build/staging 仅留 binDir 二进制；
   ollama / LM Studio / SGLang 为 externalServer，SimiGo 只采用不构建。安装页 `Settings.swift` 加引擎选择 Picker + 三态显示。
7. 内存黄色缓解：`NativeMLX` 三处卸载点（stop/suspend/evict）在 `Memory.clearCache()` 后
   **强制** `malloc_zone_pressure_relief(nil, 0)`，settle 观测间隔 500ms→250ms 且每稳定轮再 relief；
   **本轮续跑**再缩短空闲驻留：`adaptiveIdleTimeout` 由 `max(600, tok/150+60)`（121k→~14.5 分钟）
   改为 `min(cap=360, max(floor=240, …))`（RuntimeTuning.idleResidencyFloor/CapSeconds），大会话最长窗口→≤6 分钟、小会话 600→240s。
8. 移除：`.simigo/models` 创建、`curl | bash`、floating `git pull`（实际代码路径已无；仅剩注释/日志字符串说明其被禁止；真实命令为锁定 `fetch`+`checkout --detach`）。
9. 自主 Bootstrap：`SimiGoBootstrap` 幂等/可恢复状态机，产出机器可读 `bootstrap-report.json`；
   `SimiGoBootstrapRunner.launchIfNeeded()` 在 `applicationDidFinishLaunching` 后台任务调用（每次启动安全）。

- 包测试：`swift test` **60/60**（21 契约 + 5 授权 + 7 路径 + 9 SQLite DB[含 ES 往返] + 8 引擎配方 + 4 bootstrap + 6 便携模型引用解析）。schema v1→**v2**（纯增量）。
- App 编译：`xcodebuild -scheme SimiGo -configuration Debug`（含 MLX）**BUILD SUCCEEDED**（日志 `phase2/xcodebuild_app_ui.log`），0 编译错误。

### Layer 3 — 首次安装与初始化的部署证据
**部分产出（PARTIAL_PASS）。** 本轮已用**产品仓外的临时驱动包**（`SimiGo-Agent-Runs/.../l3-driver`，按路径依赖 `SimiGoRuntime`，不进产品 git）在真机实测首次自主引导：
- RUN1 全新：`issueCount=0`、`schemaVersion=2`、真实发现 `modelsDiscovered=20`（真 `~/.cache/huggingface`）、`roots=1`、`external_files=20`、`integrity=true`，报告落 `first-install-v2/.simigo/manifests/bootstrap-report.json`；
- RUN2 复跑幂等：计数**不翻倍**、`import-legacy` 仍 skipped；
- 禁建目录核验：`.simigo` 仅 bin/build/locks/logs/manifests/sources/staging，**无 work/ 或 models/**。

仍未产出（PENDING），需在打包后全新安装环境实测：
- Activity Monitor 实测推理结束后内存压力黄色窗口是否缩短（relief 生效性）；
- 真实用户机 `~/.cache/huggingface` 模型发现结果 + bootstrap 报告落地；
- llama.cpp 锁定版本实构建（需操作者清单先 pinnedRef + checksum）；
- .app/.dmg 打包 + 签名/公证 + 首启动验收。

> 结论：Layer1 ✓、Layer2 ✓；Layer3 未过。三者未全部通过，**不得**称"原生集成与自主引导部署已落地"。

## 诚实边界
- Native 支持约束族窄于 Python（`equals_binding_segment` 等命中 default → CONTRACT_UNKNOWN_CONSTRAINT fail-closed）。
- 便携引用 `ModelReference` 已入 `Config`/`Service`（持久身份=root_id+相对，绝对仅作运行时定位）；但旧的 modelPath/mlxModelPath/llamaModelPath 绝对键仍保留以兼容 llama/MLX 启动定位，彻底移除 deferred。
- 引擎自动下载 fail-closed：llama 首构建现要求操作者清单锁定版本——符合"版本锁定"但改变了开箱行为。
- 内存 relief 仅回收进程自身空闲页；空闲驻留窗口本轮已封顶 360s/floor 240s（代码/编译验证），但黄色窗口的真实收敛仍需 GUI + 活动监视器实测（环境受限）。
- JSON 退役已实现为可证覆盖后的重命名 sidecar；但 App 层 C 接线仅经编译 + DB 往返测试证明，无 app-target 集成测试、未跑 GUI 运行时。

## 本轮续跑增补（Turn 2：读权威 + 便携模型引用 + schema v2）

### C — SQLite 成为 ES 读+写权威，JSON 校验后退役
- **v2 增量 schema**：`execution_states` 加 `next_input/prefix_json/checkpoint_ids_json`；新增 `checkpoints` 表（state_id 无 FK，故不会级联删到 settlements/IS）。
- **DB 往返**：`writeGraph(states:checkpoints:)` 单事务 upsert + 仅删未被结算引用的移除态（保护 IS）；`readGraph()` / `readSettlementReceipts()` 重建全量图。3 个 DB 测试覆盖往返/幂等/IS 保护。
- **App 接线**（`ExecutionStateGraph.swift`）：`init` 改为**从 SQLite 读**重建 `document`；`persist` 改为**写 SQLite**（settlements 仍由 gate 单独写，不入此图写）；DB 不可用时 fail-closed 回退读/写 JSON 不丢数据。
- **退役**：`retireLegacyJSONIfNeeded` 仅当 JSON 已被权威库可证覆盖（本轮导入 / 无活态 / 状态 id 全在库中）时把 JSON **重命名**为 `.migrated-<时间戳>` sidecar——保留字节，**绝不删除或就地覆盖**。

### B — 便携模型引用（root_id + 相对），绝对路径仅作本机定位
- 包内新增 `ModelReference{rootID,relativePath}` + `SimiGoModelDiscovery.resolve(_:)`（从外部 HF 缓存候选根解析；缺失/越权/未知根一律 **fail-closed 返 nil，绝不伪造路径、绝不做 `.simigo/models`**）+ `reference(forAbsolutePath:)`（把遗留绝对路径归一为相对引用，非缓存根内则 nil）。6 个测试。
- `Config.swift`：新增 `selectedModelReference`（持久化 root_id+相对）、`resolvedSelectedModelURL`（运行时解析）、`persistReference(forAbsolutePath:)`。
- `Service.swift`：`selectModel` 额外持久化便携引用；`init` 优先用可解析的引用刷新本机定位（抗缓存迁移），绝对路径降级为运行时定位器。

### 核验
- `swift build --target SimiGoRuntimeContract` ✓；`swift test` **60/60** ✓；App `xcodebuild -scheme SimiGo Debug`（含 MLX）**BUILD SUCCEEDED** ✓（0 error）。
- L3 首装驱动 RUN1/RUN2 见上。产品包保持干净：临时 `simigo-bootstrap` 可执行 target 已从 `Package.swift` 移除、`Sources/simigo-bootstrap/` 已删除；L3 驱动在**产品仓之外**。

## 变更文件
Diff：Package.swift +10、Config.swift +3、ExecutionStateGraph.swift +123、Settings.swift +32、StatusBarCoordinator.swift +4、NativeMLX.swift +22、EnvManager.swift +115（合计 +276 / -33）。
新增：SimiGoRuntimeContract{NativeDeclarativeResultContract,SimiGoSettlementAuthority,SimiGoPaths,SimiGoESISDatabase,SimiGoEngineRecipe,SimiGoModelDiscovery,SimiGoBootstrap}.swift + 对应 5 个测试文件 + SimiGoBootstrapRunner.swift + Package.resolved。

## 本轮续跑增补（Turn 3：C 迁移无损化闭合）

### 识别并修复的正确性缺口
Turn 2 的 `importLegacyGraph` 仅写旧 8 列，checkpoint 只落 `settlements(MIGRATED_LEGACY)`，未写 v2 的 `next_input/prefix_json/checkpoint_ids_json` 与 `checkpoints` 表——因此**校验后退役 JSON、再从 SQLite 重读会丢 prefix/nextInput/checkpoint 链接**，违背"事务性迁移 + 校验后才能无损退役"的硬约束。

### 修复（`SimiGoESISDatabase.swift`）
- states `INSERT` 扩为 11 列：补齐 `next_input`、`prefix_json`、`checkpoint_ids_json`，编码与 `writeGraph` 完全一致（同一 `JSONEncoder` 的 `[String]` / uuidString 数组）。
- checkpoints 循环**额外**写入 ES 自有 `checkpoints` 表（与 `writeGraph` 同列），并保留原 `settlements(MIGRATED_LEGACY)` 收据写法不破既有校验。
- `verifyReadBack` 在同一事务内逐字段证明无损：state 读回校验 `next_input/prefix/checkpointIDs`，并新增 checkpoints 表读回校验 `checksum/state_id/prefix`——只有全部通过才写 migration receipt，任一漂移即回滚、源 JSON 不动。

### 证据
- 新增 `testLegacyImportIsLosslessForGraphRebuild`：`importLegacyGraph` 后 `readGraph()` 精确复现 `prefix=["hello"] / nextInput="hello" / checkpointIDs / checkpoint checksum`，`checkpoints` 计数=1，`integrityCheck=true`。
- `swift test` **61/61** ✓；App `xcodebuild -scheme SimiGo Debug`（含 MLX）**BUILD SUCCEEDED** ✓。
- L3 首装驱动 v3 复跑（无损改动后回归）：RUN1 schema=2 / issueCount=0 / models=20 / roots=1 / external_files=20 / integrity=true；RUN2 幂等（计数不翻倍、import-legacy skipped）；托管根内**无 work/models**。

### C 的剩余边界（如实）
迁移逻辑本身已无损且有单测证明；仍开放的是 **app-target 集成测试的执行**——本机 `xcodebuild test` 因 CoreSimulator 框架版本不匹配（1171.7.0 < 1174.9.2）无法执行（环境工具链限制，非代码缺陷）；`build-for-testing` 链接已可过。包级 `swift test` 不受影响。

### 需求③「构建完成后删除缓存只保留二进制」— 从声明升级为强制
- 旧状：`EngineRecipe.cachePathsToRemoveAfterBuild` 仅为声明；EnvManager 硬编码删 sources/build/staging，存在“声明 vs 执行漂移”风险（配方若声明别的缓存集不会被遵守）。
- 现：EnvManager 构建产物拷入 binDir 后，**遍历配方声明的 `cachePathsToRemoveAfterBuild`**（经 `SimiGoPaths.managedRoot()` 解析，含相对/越界 precondition），bin/ 永不在集内故二进制永不被删；并新增可复用 `EngineRecipe.pruneCacheKeepingBinary(engineRoot:fm:)`——先把产物二进制搬到 `bin/<id>/` 再删缓存，二进制未产出时**什么都不删（fail-safe）**。
- 测试 `testPruneCacheKeepingBinaryRunsAndIsFailSafe`：断言搬移后字节保留、三缓存删除、原地产物路径消失、未完成构建不删任何东西。`swift test` **62/62**；App `xcodebuild Debug` **BUILD SUCCEEDED**。

## 本轮续跑增补（Turn 4：内存驻留端到端核验 + Phase6 本地打包实测）

### 需求①内存黄色：从证据核验实现确实生效
- 卸载/挂起两条热路径均在**释放权重之后**再回收：`suspendIfIdle` 置 `modelContainer=nil`+`sessions.removeAll()` → `Memory.clearCache()` → `malloc_zone_pressure_relief(nil,0)`；`stop` 同理并带 settle 观测循环。
- 驱动确为周期：`Service` 健康循环每 30s 对 mlx 后端调用 `suspendIfIdle()`，故缩短后的自适应超时真正触发。自适应超时 `min(cap=360,max(floor=240,重建估算+60))`：大会话驻留由 ≈14.5 分钟收敛到 **≤6 分钟（含 30s 扫描 ≤6.5 分钟）**。
- 修正两处**过时注释**（旧 `max(600s 基线)`/`保留 600s 下限`），使代码与注释一致，避免误导后续审阅。

### Phase6 本地打包实测（不依赖凭证的部分）
- `xcodebuild -configuration Release`（`CODE_SIGNING_ALLOWED=NO`）**BUILD SUCCEEDED** → `SimiGo.app` v2.1.15（`SwiftUI.SimiGo`），Mach-O **universal（x86_64+arm64）**。
- ad-hoc 深签名 `codesign --sign -` → `Signature=adhoc`，`--verify --deep --strict` **OK**。
- `hdiutil create` 生成 `SimiGo-2.1.15-unsigned-adhoc.dmg`（63,132,068 B），`hdiutil verify` **CRC32 VALID**；挂载后含 `SimiGo.app` + `/Applications` 拖拽安装符号链接。SHA256 `e8c68526…6f2ab`。产物存 `phase6-package/`。
- **如实边界**：`spctl -a` → `rejected`、无 staple 票据 —— 符合预期：Developer ID 签名、公证（notarize）、staple 需 Apple 凭证与网络，超出无人值守范围；此 ad-hoc dmg 在未授权机器上会被 Gatekeeper 拦截，直到完成公证。

## 本轮续跑增补（Turn 5：补齐"外部 work 索引"与"中途失败可恢复"证据 + 修正伪断言）

审阅既有 bootstrap 测试发现两处**证据强度不足**并修正（纯测试改动，未动 app 源码）：
- **伪断言**：原 `testBootstrapProducesMachineReadableReportAndIsIdempotent` 里 `XCTAssertEqual(count, count)` 把自己和自己比，恒真，从未真正证明 work 行跨重跑不翻倍 → 改为比较第二次运行后 `listExternalFiles(rootID:"work-1").count == 第一次的 workFilesIndexed`。
- **"导入外部 work 索引 / 不复制第二份物理文件"缺专门证明** → 新增 `testWorkFilesAreIndexedByRootRelativeAndNeverCopied`：3 个含子目录的工作文件以 `(root_id, relative_path)` 行入库（相对、非绝对、status=present），**托管根内无任何物理副本**、无 `work` 目录，重跑仍为 3 行不翻倍。
- **"中途失败可恢复"此前只覆盖 legacy-import 跳过路径，没有真正的失败-恢复证明** → 新增 `testBootstrapRecordsFailureThenRecoversOnReRun`：把托管根设为文件使 ensure-dirs 失败，断言 `issueCount>0` 且该步 `.failed`（失败绝不被吞）；移除障碍后**同一根重跑恢复** `issueCount=0`、ensure-dirs `.ok`、`integrityCheck=true`（失败步骤不损坏权威库）。
- `swift test` **64/64** ✓（app 源码本轮未改，前轮 Release/Debug BUILD 仍有效）。

## Turn 6 — L2 item1 audit: native settlement gate was an ORPHAN, now wired into the production call chain

Evidence-based audit (grep): `ExecutionStateGraphStore.settleValidatedResult` had ZERO callers
in shipped app code. `SimiGoSettlementAuthority.authorize` and `recordNativeSettlement` were
reached only from that orphan and its private helper `commitSettlementToAuthoritativeStore`,
plus unit tests. The real inference path (Service / NativeMLX / HTTP) carries no result-contract
concept at all. So the earlier `phase0 PASS` / `L2 PASS` overstated the objective's explicit rule:
"原生契约先进入真实生产调用链" was NOT actually satisfied — exactly the "原生实现完成 ≠ 进入产品应用"
distinction.

Remediation (all in the SimiGo product repo; SimiGo-Lab untouched):
- `ExecutionStateGraphStore.settleProducerResult(generatedText:boundToState:)` — the first real
  production caller. Builds `referenceResultContractJSON` (field `content` <- `^RESULT=(.+)$`,
  `equals_binding` -> `next_input`), sources the IS binding from the state's persisted `nextInput`
  (commit-to-already-settled semantic, native-only constraint family, no Python fallback), then
  delegates to the existing fail-closed `settleValidatedResult` -> native gate -> SQLite IS commit.
- `ExecutionStateGraphView` reference inspector gains a "Settle (Native Gate)" section: producer
  text field, "Fill from IS", "Settle via Native Gate" button, and a live settled-receipt count, so
  the gate is genuinely app-reachable rather than an orphan API.

Verification (real runs):
- `swift test` = 65/65, including new runnable package test
  `testSettlementGateCommitsToAuthorityAndFailsClosedOnReadBack` — proves native gate ->
  `recordNativeSettlement` -> `readSettlementReceipts` round-trip, digest match, and that a
  non-committing producer refuses (PRODUCER_RESULT_BINDING_MISMATCH) writing NOTHING (settlements
  count stays 0).
- `xcodebuild ... Debug build` = BUILD SUCCEEDED (UI + helper compile into the app).
- `xcodebuild ... build-for-testing -enableCodeCoverage NO` = TEST BUILD SUCCEEDED (the new
  app-target integration test `testSettleProducerResultCommitsThroughNativeGateAndFailsClosed`,
  which injects a temp dbURL, compiles into SimiGoTests).
- App-test EXECUTION is blocked by the environment, not the code: CoreSimulator 1171.7.0 < Xcode
  build 1174.9.2 aborts the test plan before the macOS target; the C dependency yyjson also fails to
  link under coverage with an undefined ___llvm_profile_runtime_user. Honest boundary: production
  wiring is proven by shipped UI code + app-test compile + the runnable package pipeline test.

Git invariants preserved: HEAD de362ef unchanged, staged 0, no commit/push, no public-main overwrite;
forbidden behaviors still absent (only negative-guard comments reference git pull / curl|bash /
.simigo/models). L3 remains credential/network/GUI-gated (notary/Developer ID, real llama build,
in-GUI memory-under-load). Goal stays active.

## Turn 7 — Runtime product evidence: the wired gate renders in the launched SimiGo app

Advanced item1 from "compiles + package-test-proven" to "confirmed present in the RUNNING shipped app".

- Confirmed the store is a genuine app-lifetime object: `StatusBarCoordinator` holds
  `private let stateGraph = ExecutionStateGraphStore()` (default dbURL = SimiGoPaths.databaseURL)
  and `openStateGraphWindow()` injects it via `.environmentObject(stateGraph)` into
  `ExecutionStateGraphView` — so the Settle path is a real product call chain, not test-only.
- Launched the freshly-built Debug app (binary mtime Oct 23 05:34, includes the wiring) via `open`;
  process came up alive (PID 92739) against the real ~/.simigo managed root, then quit cleanly.
- A ComputerUse Accessibility-tree inspection of the live "Execution State" window, switched to the
  "契约参考图" tab, read back verbatim the wired section: "Settle (Native Gate)", the hint
  "Producer result must commit to this State's IS next-input", the RESULT= text field, the
  "Fill from IS" and "Settle via Native Gate" buttons, and the "no settlement" status. This proves
  the native-gate settlement UI is actually present in the running product.
- Live fail-closed guard observed: the fresh root S-0001 has an EMPTY next-input, so both Settle
  buttons render enabled=false exactly as authored (.disabled(state.nextInput.isEmpty || ...)). To
  settle at runtime an operator first uses "Continue this State" to set a non-empty next-input.
- Honest limit: a PIXEL screenshot could not be captured — macOS Screen-Recording TCC requires an
  interactive grant that was not forced in an unattended run. The Accessibility-tree readback is the
  runtime proof instead. A pre-existing /Applications/SimiGo.app instance (from the Turn-6 dmg) was
  left untouched.

Net: L2 item1 is now backed by runtime evidence (feature renders + guard is live in the product).
Remaining true gaps are all external-resource-gated L3: notarization/Developer ID (Apple credentials),
real llama.cpp engine build (network + authorized pinned ref), and in-GUI memory-under-real-model
measurement (running a multi-GB model). HEAD/staged invariants and forbidden-behavior guarantees still
hold; SimiGo-Lab untouched. Goal stays active.

## Turn 8 — First-install proven by the SHIPPED product on the real machine

Previously L3 first-install evidence came from a driver run under a SIMIGO_HOME override. This turn
confirmed the ACTUAL product performs it against the real ~/.simigo:

- AppDelegate.applicationDidFinishLaunching dispatches SimiGoBootstrapRunner.launchIfNeeded() on every
  launch; the Debug .app is NOT sandboxed (no container/entitlements), so it writes the real home.
- The Turn-7 launch's own bootstrap produced: ~/.simigo/simigo.sqlite3 (schema v2; roots=1 HF cache,
  external_files=20 discovered models indexed as references — no second physical copy; no .simigo/work)
  and ~/.simigo/manifests/bootstrap-report.json (issueCount=0, schemaVersion=2, modelsDiscovered=20,
  workFilesIndexed=0). File mtimes (10:38:51 CST) match the product launch; report finishedAt is
  2026-10-23T02:38:51Z. => real-machine, product-emitted, machine-readable first-install report.
- Requirement check: no ~/.simigo/work created. The stale empty ~/.simigo/models (Aug-15, pre-remediation)
  was NOT created/touched by the current bootstrap (its mtime is unchanged) — confirms the fix holds. Left
  in place (not deleting a user-home dir unattended; command-deletion disallowed).
- Honest caveat: two relaunches kept roots=1/external_files=20 stable but the report timestamp did not
  advance in the observed window, so real-home repeat-idempotency is NOT claimed from this run; it stays
  proven at the package-test + l3-driver RUN1/RUN2 level.

Remaining L3 gaps unchanged and genuinely external: notarization/Developer ID (Apple credentials), real
llama.cpp build (network + authorized pinned ref, and download-build is outside agent constraints), and
in-GUI memory-under-real-model measurement. HEAD de362ef / staged 0 preserved; SimiGo-Lab untouched.

### Correction to the Turn 8 claim (self-audit)

My Turn-8 statement that "the SHIPPED product's launch performed first-install on the real ~/.simigo"
is NOT adequately supported. Follow-up tests: across several Debug launches (longest 36s) the report's
finishedAt stayed frozen at 2026-10-23T02:38:51Z and `log show --predicate 'eventMessage CONTAINS "SimiGo
bootstrap"'` produced NO output, even though SimiGoBootstrap.run has no run-once guard and would rewrite
the report each time it executes. StatusBarCoordinator.start() DID run in Turn 7 (AX confirmed the window),
so the app delegate fires — but I could not observe the detached bootstrap actually running.

Honest conclusion:
- Real ~/.simigo DOES contain valid, product-shaped first-install artifacts (db schema v2; roots=1; 20 models
  indexed as references; no .simigo/work; machine-readable report issueCount=0). Those artifacts exist.
- Their provenance is UNCONFIRMED for THIS session (earlier successful run vs. a driver/manual invocation).
- The bootstrap CODE PATH (emit report, idempotency, failure recovery) is proven by package tests + the
  l3-driver; the app's launch-time CALL is code-wired; but the runtime hookup firing on launch is NOT
  verified here. Candidate causes: the detached utility task not executing under `open` in this session,
  NSLog not surfacing, or launchIfNeeded failing-closed on a DB open/lock (the /Applications/SimiGo.app
  copy PID 97833 runs concurrently). Flagged for follow-up rather than claimed.

This correction does not change L2 (item1 runtime UI evidence stands) and keeps L3 at PARTIAL_PASS.

### Turn 8 FINAL (runtime verification resolves the mid-turn uncertainty)

Ran the shipped Debug binary DIRECTLY with SIMIGO_HOME pointing at a fresh temp home (zero contention,
no real-home mutation):
- Launch executed applicationDidFinishLaunching -> SimiGoBootstrapRunner.launchIfNeeded -> SimiGoBootstrap.run.
  bootstrap-report.json appeared at t+3s (schemaVersion=2, issueCount=0, modelsDiscovered=20 from the real
  ~/.cache/huggingface/hub, workFilesIndexed=0) and the process NSLog fired: "SimiGo bootstrap: issueCount=0
  models=20 work=0 legacyMigrated=false". Only permitted runtime dirs were created; NO .simigo/work, NO
  .simigo/models; the 20 models are indexed by root_id+relative reference (external_files=20), no second copy.
- Repeatability/idempotency at PRODUCT RUNTIME: two launches against the SAME home gave roots=1,
  external_files=20 both times (not doubled) and the report regenerated (finishedAt advanced, issueCount=0).
  => "首次初始化可重复执行" is now verified by the actual product, not only by package/driver tests.
- Explanation for the earlier `open` anomaly: LaunchServices reactivated the already-running
  /Applications/SimiGo.app (same bundle id) rather than my fresh Debug bundle, so the real-home report didn't
  advance via `open`. Direct binary launch is a valid product launch and demonstrably runs bootstrap.

Discovered (out of scope, flagged): duplicate-class linkage warnings at launch — SimiGoESISDatabase (and
Tokenizers/Crypto Hub actors) are present in both SimiGo2Experimental's PackageFramework and SimiGo.debug.dylib
("one of the duplicates must be removed or renamed; may cause spurious casting failures/crashes"). A pre-existing
packaging concern, not introduced by the integration work; noted for follow-up.

Net L3: first-install + repeatable/idempotent now RUNTIME-VERIFIED on the shipped product. Still open and
genuinely external: notarization/Developer ID (credentials), real llama.cpp build (network + authorized pinned
ref; also outside agent download/build constraints), in-GUI memory-under-real-model measurement, app-test
EXECUTION (CoreSimulator env). HEAD de362ef / staged 0 preserved; SimiGo-Lab untouched. Goal stays active.

---

## Turn 9 — 产品运行时“中途失败可恢复”实证（2026-10-23）

**基线复验**：`swift test`（SimiGoRuntime 包）= 65/65 通过，arm64e-apple-macos14.0。

**代码核验（非新主张，复核既有 L2 集成证据）**：
- `EnvManager.swift`：审查发现的三处禁用行为均已移除并注明——不创建 `.simigo/models`（27/258）、无 floating `git pull`（269，锁定 ref 缺失即 fail-closed 拒绝构建 277）、无 `curl | bash`（365/371）。构建走 `SimiGoEngineRegistry` 配方，构建后按 `recipe.cachePathsToRemoveAfterBuild` 清理缓存只保留二进制（352-363，单一事实源，仅删配方声明的相对且受含路径）。
- `Settings.swift` 第 132-146 行：安装页“外部引擎 · 安装选择”Picker 绑定 `envMgr.availableEngines`/`selectedEngineID`，实时显示三态（下载/构建/适配）标签，并说明外部服务端（Ollama/LM Studio/SGLang）为“采用非构建”。需求②③④ 在产品源码层已接线。

**产品运行时恢复实验**（`recovery_runtime_driver.sh`，SIMIGO_HOME 隔离，直接运行出货的 Debug 产品二进制，走真实 `SimiGoBootstrapRunner`，非包级 harness）：
- RUN1（把 `bin` 预置为普通文件制造障碍）：`bootstrap-report.json` → `ensure-dirs: failed`（NSCocoaError 516），`migrate-schema: ok`、`discover-models: ok (20)`、`index-work: skipped`、`write-report: ok`，`issueCount=1`；NSLog `SimiGo bootstrap: issueCount=1 models=20`。**失败非致命**：其余步骤继续，报告机器可读且如实暴露失败步骤。
- RUN2（删除障碍文件，同一 managed root 复跑）：`ensure-dirs: ok`，全部步骤 ok，`issueCount=0`，模型仍 20（不翻倍）。先前失败步骤被重试并自愈。
- 布局：`bin/build/locks/logs/manifests/sources/staging + simigo.sqlite3`；**无 `work/` 无 `models/`**。进程已清理无残留。

**结论分层（严格不合并）**：objective 的“首次初始化可重复 + 中途失败可恢复”现已在**产品运行时层**取证（此前仅包级）。L1 PASS / L2 PASS / L3 仍 PARTIAL——未完成项均为外部资源硬门控：公证/Developer ID（Apple 凭证）、实 llama.cpp 构建（网络+授权 pinned ref，且下载/构建超出 Agent 操作约束）、GUI 内真实大模型负载内存实测、app 测试执行（CoreSimulator 环境）。git：HEAD de362ef 未变、staged 0、未 commit/push；本轮未改任何产品源码（纯运行时取证+证据文档）。

---

## Turn 10 — 重复符号链接风险审计：判为“良性复制，非正确性阻断”（2026-10-23）

承接 Turn 8 遗留的“可能崩溃”疑虑，本轮以二进制+源码证据定性：

- **现象**：产品包内无独立的 `SimiGoRuntimeContract` framework；契约代码被**静态嵌入两处**——`SimiGo.debug.dylib` 与 `SimiGo2Experimental_…PackageProduct.framework`（`nm` 各含 3 个 `SimiGoESISDatabase` 符号）。app target 同时链接两个 package product（pbxproj C1632B13/B14），且 `SimiGo2Experimental` 依赖 `SimiGoRuntimeContract`（Package.swift:38）。
- **跨边界核验（决定性）**：仅 3 个 app 文件用 `SimiGo2Experimental`（NativeMLX/NativeMLXPrefixPool/OversizedRuntime），它们**只 import SimiGo2Experimental、从不 import SimiGoRuntimeContract**，且不引用任何契约类型；边界类型 `OversizedSessionInfo`（定义于 SimiGo2Experimental）与 `EngineExecutionStateSnapshot`（定义于 app）均非契约类型。app↔experimental 只通过 experimental 本地类型与 Foundation 值（String/URL 路径）交换。
- **结论**：没有任何 `SimiGoRuntimeContract` 实例“在一张镜像创建、被另一张消费”，两份复制各自自洽，经当前调用图不可达 Swift 类型身份错配——与 Turn 8/9 干净 bootstrap（issueCount=0）实测一致。**判为良性静态复制，非正确性阻断。**
- **残留（打包卫生）**：重复静态链接增大体积，若未来把契约类型暴露进 SimiGo2Experimental 公共 API 会变脆。**建议后续**（无人值守约束下不强行动刀、避免重构已可用构建）：把 SimiGoRuntimeContract 发布为单一动态 product 使全进程只加载一份，或不再把它静态嵌入 SimiGo2Experimental。不属于“落地”的正确性阻断项。

git：HEAD de362ef 未变、staged 0、未 commit/push；本轮未改产品源码（纯审计取证）。L1 PASS / L2 PASS / L3 仍 PARTIAL（未完成项均为外部资源硬门控：公证/Developer ID、实 llama 构建、GUI 真实负载内存实测、app 测试执行）。

---

## Turn 11 — 纠正“app 测试无法执行”的虚假障碍，并发现+修复一处真实回归（2026-10-23）

**纠正虚假障碍**：此前多轮认定 app-target 测试“受 CoreSimulator 环境门控、无法执行”。本轮查明真因是 `xcodebuild test` 自动选中了 iPhone run destination。SimiGoTests 实为 macOS 托管单元测试包（SDKROOT=macosx，TEST_HOST=产品可执行文件）。改用 `-destination 'platform=macOS,arch=arm64'` 即可**原生执行**，无需模拟器。

**执行结果**：`SimiGoTests/ExecutionStateGraphTests` 5/5 在真实宿主进程内**执行通过**（含原生门→SQLite IS 提交+fail-closed 的 settleProducerResult 测）。`swift test` 仍 65/65。

**发现真实回归（诚实：由我的 Phase-2 改动引入）**：一旦能执行，`testDurableGraphPersistsAcrossStoreInstances` 失败——内存态 store 的 `document` 与“从权威库重建的 store”不相等，尽管两者打印完全一致。根因二分：
- 表层：`created_at` 用整秒 ISO8601 绑定，丢失亚秒精度；store 现从 `readGraph()` 重建 document（不再读 JSON），故内存态与回读态在 `Date` 上漂移。
- 深层（关键）：即使改用 17 位 `timeIntervalSince1970` 仍不相等——因为 Foundation `Date.==` 比较的是 `timeIntervalSinceReferenceDate`，而 ±978307200 的纪元偏置对 ~1.7e9 量级并非位精确；`timeIntervalSince1970.bitPattern` 相等但 `Date ==` 仍失败。

**修复**：SimiGoESISDatabase 时间戳 codec 改为持久化 `timeIntervalSinceReferenceDate`（即 `Date.==` 实际比较值）17 位字符串，重建用 `Date(timeIntervalSinceReferenceDate:)`，位精确回读；`parseISO8601` 先试 Double、否则回落旧 ISO 行（兼容既有数据库）。`verifyReadBack` 不比较日期，不受影响。另修既有测试非隔离缺陷：它们注入 temp storeURL 但不注入 dbURL，导致多实例共享全局 `~/.simigo` 权威库互相污染——现 setUp 注入隔离 dbURL（生产仍单一共享 store，语义不变）。

**验证**：`swift test` 65/65 + app `ExecutionStateGraphTests` 5/5 执行通过。

git：本轮改了产品源码（SimiGoESISDatabase.swift 时间戳 codec，属既有未跟踪新文件之一；ExecutionStateGraphTests.swift 属既有已改跟踪文件）；HEAD de362ef 未变、staged 0、未 commit/push。L1 PASS / L2 PASS（app 测执行绿+回归修复）/ L3 仍 PARTIAL（外部资源硬门控项：公证、实引擎构建、GUI 内存实测）。

## Turn 12 — 全量 app-target 套件执行 + codec 源码改动复验（2026-10-23）

动手前按证据核验：分支 localb-b3-closure-20261016、HEAD de362ef 未变、暂存区 0、tracked-modified 仍 10。Turn 11 改了产品源码（SimiGoESISDatabase 时间戳 codec），但当时只跑了 test，未跑干净 build —— 本轮补上并扩到整套 app-target。

**复验（codec 源码改动后）：**
- `swift test`（SimiGoRuntimeContract）：65/65 绿。
- app Debug `xcodebuild build`：`** BUILD SUCCEEDED **`。
- 磁盘核验：codec 用 `timeIntervalSinceReferenceDate`（stamp + parse 先 Double 后回落旧 ISO），无残留 `ISO8601DateFormatter().string(from:` bind。

**新证据 —— 完整 SimiGoTests app-target 原生执行（此前只跑过 ExecutionStateGraphTests 单类）：**
- `xcodebuild test -destination platform=macOS,arch=arm64`（整 target）：**197 executed / 13 skipped / 1 failure**。
- 13 skipped 全部是既有环境/权重/开关门控（BranchFork 需 `SIMIGO_FORK_EXP=1`+本机权重、"daily model not present"、Oversized E2E 等），与本轮集成无关。
- 唯一 failure：`HTTPRequestBoundaryTests/testDoubledSpaceRequestLineRejectedOnTheWire` → `NWError 48 Address already in use`：该 wire 测试用 `randomPort()` 且不做可用性检查/重试，整套并发跑时端口撞车 → `XCTUnwrap(statusLine)` 为 nil。
- 判定为瞬态 flake、非集成回归，三条硬证据：① 同一请求行规则的纯解析姊妹测试 `testRequestLineWithNonCanonicalWhitespaceIsRejected` 在同一次运行中 PASSED；② 单跑 HTTPRequestBoundaryTests 32/32 TEST SUCCEEDED、无 Address-already-in-use；③ 失败点在 HTTPServer socket 绑定子系统，本轮产品源码改动（时间戳 codec + 测试隔离）不触碰 socket 绑定。

**结论（严格分列，不合并）：** 完整既有 197 测产品 app 套件在集成就位下运行，无集成引入的回归 —— L2 产品集成证据由"单类 app 测执行绿"升级为"整套 app-target 执行绿（唯一失败为已证实的外部端口 flake）"。L1 PASS / L2 PASS / L3 PARTIAL_PASS 不变；L3 中过时的"app-test 受 CoreSimulator 无法执行"措辞已在矩阵中标记为 Turn 11 纠正的虚假障碍。

**仍硬门控（外部资源）：** 公证/Developer ID（Apple 凭证）、实 llama.cpp 引擎构建（网络+授权 pinned ref，且下载/构建超出 Agent 约束）、GUI 内真实大模型负载内存实测。目标保持 active：本轮有实质推进（不标 blocked），三层未全满足（不标 complete）。git 不变量保持，未 commit/push，Lab 未改。

## Turn 13 — 需求①内存黄色：卸载-relief-周期驱动全链核验 + 陈旧注释修正（2026-10-23）

按证据核验内存缓解是否真正接进产品运行时（而非只改常量）：
- **两处卸载点都强制 relief**：`NativeMLX.suspendIfIdle()` 空闲挂起路径（723-725 `Memory.clearCache()` + `malloc_zone_pressure_relief(nil,0)`，日志 `[LIFECYCLE] suspend_done`）与完整 `stop()` 路径（561-581 clearCache + relief + footprint settle 观测循环，稳定 4 轮或 10s 上限，日志 `settled`）。非死代码。
- **周期驱动确认**：`Service.swift` 健康循环（1172-1193）每 ~10s 调 `nativeMLX.suspendIfIdle()`，故缩短后的驻留窗口无需用户动作即会触发。
- **窗口**：`adaptiveIdleTimeout()` = min(cap=360, max(floor=240, est+60))，大会话不再滞留 ~14.5 分钟，最长约 6 分钟。
- **可观测**：`footprintBytes()`（phys_footprint）+ `swapUsedBytes()` + logMemory 相位 beforeLoad/afterLoad/beforeUnload/settled/afterEvict。

**发现并修正一处陈旧注释**：`Service.swift:1189` 原把**当前**超时描述为 `max(600s, …)`——正是用户要求消除的"长时间黄色"旧语义，与实际 `[240,360]` 收敛窗口矛盾。改为准确描述 + 日期注记。编辑后 app Debug `xcodebuild build` **BUILD SUCCEEDED**。（其余 14.5/600 命中均为正确的历史注记或无关的冷预填重试上下文，保留不动。）

**诚实边界**：机制/接线/驱动/可观测均在代码+构建层核验通过；系统级内存压力滑块在真实持续大模型负载下更快回绿，本质属交互式 GUI/真实负载观测，仍归硬件/交互门控的 L3 集合，未伪造。

git 不变量：本轮改了产品源码 `SimiGo/System/Service.swift`（已在 tracked-modified 集内，无新增文件），HEAD de362ef 未变、暂存区 0。L1 PASS / L2 PASS / L3 PARTIAL_PASS 不变；三层严格分列不合并。目标保持 active。

## Turn 14 — 需求②外部服务端：从装饰性选择 → 功能性采用接线（2026-10-23）

审计发现真实功能缺口：安装页引擎选择器此前只记录 `selectedEngineID` + 显示三态，选中 ollama/LM Studio 后 `EnvManager.setupEnvironment()` 仅记 "SimiGo 只采用不构建"，**从不把推理路由到该服务端**——需求②只被装饰性满足（正是 fidelity 规则警示的"更窄/更容易通过的兼容版"）。

**修复（复用既有、已测的 OpenAI 兼容 `RemoteOpenAIRuntime`，而非新造运行时）：**
- `EngineRecipe` 增可选 `endpointBaseURL` / `defaultModel`（Codable，可选键 → 旧清单仍可解码）。
- `SimiGoEngineRegistry.adoptedEndpoint(for:)` 纯解析器：仅 `.externalServer` 且声明了端点才返回具体 URL；`sourceBuild`（llama.cpp）与 `nativeRuntime`（mlx）返回 nil（绝不误路由）；无端点的 `.externalServer`（SGLang）fail-closed 返回 nil。
- 默认清单：ollama→`http://127.0.0.1:11434/v1`(+默认模型)、lm-studio→`http://127.0.0.1:1234/v1`、slang→无（待算子清单）。
- `EnvManager.adoptedEndpoint(for:)` helper；Settings 选择器新增"采用此外部服务端"动作，把解析到的端点/模型写入 `svc.cloudBaseURL`/`svc.cloudModel` 并置 `svc.backendSelection = .cloud`，接上既有云端启动路径；无端点时显示 fail-closed 提示（不臆造 URL）。

**验证：**
- 包测 **70/70**（新增 5 测：外部服务端解析具体端点 / source-build&native 绝不端点采用 / 无端点 fail-closed / 清单补端点可采用 / 无新键向后兼容解码）。
- app Debug `xcodebuild build` **BUILD SUCCEEDED**（EnvManager + Settings 接线编译绿）。

**诚实边界：** 经由**真实运行中的**外部服务端（实际装好的 ollama/LM Studio）跑通推理，属网络/安装门控，本环境未执行、不伪造；本证据只证明"选择解析出正确端点并驱动既有 OpenAI 兼容运行时配置"。三态（downloaded/built/adapted）与"采用不构建"语义保持不变，未被合并。

git：改了产品源码 EnvManager.swift / Settings.swift（均在既有 tracked-modified 集内，无新增跟踪文件）+ 未跟踪包内 SimiGoEngineRecipe.swift / 其测试。HEAD de362ef 未变、暂存区 0。L1 PASS / L2 PASS / L3 PARTIAL_PASS。目标保持 active，三层严格分列不合并。

## Turn 15 — 需求②功能性采用：抽出可测方法 + app-target 原生执行 3/3（2026-10-23）

承接 Turn 14 的功能性采用，本轮把内联在 SwiftUI 按钮里的 3 行赋值**抽取为 `EnvManager.applyExternalAdoption(of:to:)`**（业务逻辑离开视图、单一真相源、可直接测），按钮只调用它；并新增**产品 app-target 集成测试** `SimiGoTests/ExternalServerAdoptionTests`，在 macOS destination 下**宿主进程内原生执行 3/3 GREEN**：
1. 采用 ollama → `Service.backendSelection == .cloud` 且 `cloudBaseURL == 解析端点` 且 `cloudModel == 服务端默认模型`（证明"选择"真正驱动既有 OpenAI 兼容运行时配置，而非装饰）。
2. llama.cpp / mlx-native / slang → 返回 nil、`Service` 原状不动（fail-closed，不误路由）。
3. 未知引擎 id → nil。
- 测试 setUp/tearDown 快照并还原 `AppConfig`（backendSelection/cloudBaseURL/cloudModel 三键经 `didSet` 持久化），确保不把用户真实配置改脏——hermetic。
- 新增文件经 `SimiGoTests` 的 `PBXFileSystemSynchronizedRootGroup` 自动纳入目标（无需改 pbxproj）。

**验证链：** 包测 70/70（端点解析器，Turn14）+ app 编译 + app-target 新测 3/3 原生执行绿。
**诚实边界：** 仍未对**真实运行中**的 ollama/LM Studio 端到端跑推理（网络/安装门控）；本轮坐实的是"解析端点确实经宿主执行把 Service 切到云端远端配置 + fail-closed"这一功能性路径本身。

git：改了产品源码 EnvManager.swift / Settings.swift（均在既有 tracked-modified 集内）、新增未跟踪 `SimiGoTests/ExternalServerAdoptionTests.swift`。HEAD de362ef 未变、暂存区 0、tracked-modified 仍 10、未 commit/push、Lab 未改。L1 PASS / L2 PASS / L3 PARTIAL_PASS；三层严格分列不合并；目标保持 active。

## Turn 16 — L3 首次安装/可恢复 用当前构建复验（2026-10-23）

动机（完成审计要求"以当前状态为证据，不靠记忆"）：Turn 9 的 L3 首装/恢复证据早于 Turn 11 的 SQLite 时间戳 codec 与 Turn 14/15 的引擎配方/EnvManager/Settings 改动。用当前构建重跑产品二进制复核。

在当前 Debug 二进制（构建于 12:56，晚于全部源码改动）上，以隔离 `SIMIGO_HOME`（绝不触碰用户真实 `~/.simigo`）跑真实产品启动：
- **RUN1 首装**：`bootstrap-report.json` issueCount=0、schemaVersion=2；步骤 ensure-dirs ok / migrate-schema ok(v2) / import-legacy skipped / discover-models ok(20) / index-work skipped(0)；**无 work/ 无 models/**（禁止目录未建）；DB roots=1、external_files=20（模型按引用索引，未复制物理文件）。
- **RUN2 幂等**：同根复跑 roots=1、external_files=20 **不翻倍**，issueCount 仍 0。
- **中途失败可恢复**：把 `bin` 预置为文件 → RUN-A `ensure-dirs failed`（NSCocoaError 516 File exists）、**issueCount=1 且在机器可读报告中 surfacing**、其余步骤仍继续（非致命）；移除障碍同根复跑 → RUN-B issueCount=0、schema 2、models 20。

结论：L3 的首次安装、可重复/幂等、中途失败可恢复、机器可读部署报告**全部用当前构建复验通过**。L3 整体仍 PARTIAL_PASS，仅因公证/Developer ID（Apple 凭证）、实 llama.cpp 外部构建（网络+授权 pinned ref）、GUI 真实负载内存实测仍属外部资源硬门控——未伪造。

git：本轮只写证据目录，未改任何产品/Lab 源码。HEAD de362ef 未变、暂存区 0、tracked-modified 仍 10。三层严格分列不合并；目标保持 active。

## Turn 17 — 完整 app-target 套件复验（引擎采用改动后无回归）

**事实**：Turn 14/15 修改 EnvManager/Settings/SimiGoEngineRecipe 之后，此前只跑过
单类 app 测（ExternalServerAdoptionTests 3/3）；Turn 12 的整套 197 测执行发生在这些
改动之前。本轮用当前构建整套执行：

- `xcodebuild test -only-testing:SimiGoTests -destination 'platform=macOS,arch=arm64'`
- **Executed 200 tests, 13 skipped, 0 failures — \*\* TEST SUCCEEDED \*\***（715.5s）
- 新增 ExternalServerAdoptionTests 首次随整套执行 3/3 passed
- HTTPRequestBoundaryTests 本次 32/32 passed——Turn 12 那次 randomPort EADDRINUSE
  失败未复现，佐证当时为瞬态端口冲突 flake、非集成回归（该弱点仍未擅改，留待授权）
- 13 skip 与既有基线同类（BranchFork/GenerationLifecycleRace/LifecycleRace/
  OversizedE2E/RollForward 门控项），非新增 skip
- 日志归档 `full-app-suite-turn17/`，sha256 d7b798cc…；xcresult 路径已记录

**结论**：L2 证据补齐——需求② 功能性采用（Turn 14/15）对既有产品行为零回归，
且本次是 200 测全集（含新测）在 macOS destination 原生执行全绿。

**git 不变量**：HEAD de362ef 未变、暂存区 0、tracked-modified 10、新测文件 untracked；
本轮仅写证据目录。

## Turn 18 — 需求② 端到端派发测（本地可核验层解锁）+ 卫生修正

**事实**：
- 本机勘察：ollama/LM Studio 均未安装，11434/1234 端口 closed → 真实第三方
  provider 进程端到端仍外部资源门控（不伪造）。
- 新增 app-target 测 `ExternalAdoptionInferenceE2ETests`（SimiGoTests 同步组自动纳入）：
  用 ollama 形状采用端点（`http://127.0.0.1:<port>/v1` + defaultModel）构造与生产
  `internalStartCloud` 相同的 `RemoteOpenAIRuntime.startWithLOCALB`（真实 LOCALB
  激活主机 + 配对客户端 + 签名 P-INFERENCE 请求），经 `HTTPServer.forwardToRemote`
  到本地 OpenAI 兼容桩 provider。断言全过：
  ① 客户端收到桩生成内容（派发真实发生）；② 上游请求行 `POST /v1/chat/completions`
  （/v1 base 路径映射无重复）；③ `Authorization: Bearer` 由采用配置注入；
  ④ 请求体 model 由采用配置覆盖（client-alias→qwen2.5-coder:7b）。
- 调试过程记录两个真实发现：裸 legacyPlaintextCompat 直连在 LOCALB B3 保护门
  fail-closed（**正确产品行为**，测试须走激活主机夹具）；桩须按 Content-Length
  累积收满请求体（URLSession 将头部与体拆入不同 TCP 段）。
- 单类执行 **TEST SUCCEEDED**（0.68s）；整套 SimiGoTests **201 executed / 13 skipped /
  0 failures TEST SUCCEEDED**（94.7s，含新旧采用测）。包测复跑 70/70。
- 卫生修正：发现并删除 Turn 16 障碣注入残渣 `Packages/SimiGoRuntime/ensure-dirs`
  （8 字节 "obstacle"，注入命令 CWD 错位产物，非产品源文件）；审查确认 bootstrap
  代码不在 CWD 创建任何文件（全部落 effectiveRoot）。tracked-modified 恢复 10。

**结论**：需求② 的证据从"配置写入 Service"（Turn 15）深化为"采用配置确实驱动
生产派发路径把推理送到 OpenAI 兼容服务端并完成协议封装"。真实 ollama/LM Studio
进程本身、GUI 人机内存实测、公证仍为外部资源门控边界。

**git 不变量**：HEAD de362ef、暂存区 0、tracked-modified 10、新测 untracked。

## Turn 19 — 需求① 真实权重内存释放端到端实测（分页假设检验）

**事实**：
- 新门控 app-target 测 `MemoryReliefRealModelTests.testSuspendReleasesResidentModelMemory`：
  真实权重 `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit`（HF 缓存 snapshot，16GB）。
- 机器可读实测（宿主执行 TEST SUCCEEDED，15.25s）：
  `baseline=25MiB → loaded=16604MiB → afterSuspend=122MiB (released=16482MiB≈99.3%)`；
  挂起后新请求自动恢复生成成功；`afterStop=169MiB` 回落至基线。
  **→ 内存黄色不是换页拖尾：挂起直接释放全部驻留，窗口收紧（Turn13 [240,360]s）
  后黄色持续时间受该上限约束。**（原假设"疑为换页"检验为：机制上主要是驻留未释放。）
- 整套回归：**202 executed / 13 skipped / 0 failures TEST SUCCEEDED**（112.4s）。
- 工程发现（记录）：
  ① `xcodebuild test` 不支持向测试宿主注入 env（无 `-testEnvironment`/
  `-testConfiguration` 选项）；
  ② `build-for-testing` 在本产品受无关 SPM/yyjson 动态库链接缺陷阻断（既有边界）；
  ③ 因此新测门控 = 既有 `SIMIGO_LIFECYCLE_RACE=1+SIMIGO_FORK_MODEL` 环境变量约定
  （主）+ `~/.simigo/memory-relief-run.json`（备用，证据运行后已删除，恢复常规
  跑缺省 XCTSkip）；
  ④ 本机真实 LOCALB 主机默认启动路径呈 `transportIdentityMismatch` fail-closed
  （正确产品行为），测试改用 `startWithLOCALB` 显式注入一次性隔离传输身份，
  Keychain 临时项随 teardown `deleteAll` 清理。

**结论**：需求① 的证据链从"代码全接线核验"（Turn 13）升级为"真实大模型权重下
驻留释放的可观测数值实测"。GUI 真人负载下内存压力面板的时间曲线仍为交互门控边界。

**git 不变量**：HEAD de362ef、暂存区 0、tracked-modified 10、两个新测+本测 untracked。

## Turn 21 (2026-10-23) — 修订任务书：原生 MLX 优先 + SQLite IS 行为打磨（G2）

来源：`~/Downloads/SimiGo_Native_Integration_Bootstrap_Handoff-2.zip`（修订版方案 + Agent 指令）。收紧顺序为 **原生 MLX 优先 → SQLite 信息空间优先打磨 → G1–G3 基本门 → 外部 Backend 后置**；明确"方案修订≠已改产品代码"，须从真实工作树继续。

本轮从当前真实工作树出发，落实修订顺序中可先行、可快验、低资源风险的 **G2（SQLite IS 行为实验）**（非仅结构 integrity）：

- **发现缺口**：`SimiGoESISDatabase` 已有 v1/v2（roots/external_files/agent_sessions/execution_states/settlements/settlement_bindings/dependency_edges），但 `dependency_edges` 与 `settlement_bindings.source_*` **无写 API、无有效性传播、无行为测试** —— 正是 G2 核心未实现层。
- **实现**：纯追加 v3 迁移（`settlements.validity DEFAULT 'valid'` + `invalidated_at` + 索引，向后兼容）；新增 `reindexExternalFile`（digest 变更探测，保局部更新比例）、`linkSettlementToExternalFile`、`addDependency`、`invalidateSourceFile`（`WITH RECURSIVE` 依赖闭包）、`invalidateSettlement`/`transitiveDependents`（会话版本变更路径）、`reconcileRoot`（丢 watcher 事件对账）、`settlementValidity`/`validSettlementCount`、`tableHasBlobColumn`（所有权内省）。
- **行为测 7 项全绿**（包测由 70→**77/77**）：双源共存、局部失效仅影响闭包且保留无关有效结果、传递依赖闭包失效、重复扫描幂等（无伪失效/无行增长）、丢事件对账（missing→闭包失效）、事务原子性（注入失败回滚不留半写）、数据所有权（external_files 无 BLOB，只存 digest+元数据）。
- **复验**：`swift test` 77/77；app `xcodebuild build` **BUILD SUCCEEDED**（共享 DB 改动不破坏 app）；既有 `schemaVersion` 断言同步 2→3。日志 sha256 `b730b950…463a`（g2-behavioral-turn21/）。
- **git 不变量**：HEAD `de362ef` 未变、暂存区 0、tracked-modified 10（`SimiGoESISDatabase.swift` 与 G2 测均为本集成工作 untracked 新文件，不计入）。不 commit/push。

**边界（如实标注，非 PASS）**：
- 本 G2 是产品验收门的行为实验，**不等同 Lab 同名狭义 G2**。
- **G1/G3 仍未做**：二者需**真模型、独立进程、访问审计、负向对照**（旧 KV 逻辑不可访问为 G3 必证项；统一内存物理页归还单列测量，不以 RSS 瞬降代替）。产品仓无可执行目标承载多进程真 MLX（revertcli 已移除临时 exe），故 G1/G3 属后续跨会话工程，本轮不以结构测冒充其通过。
- 修订指令第 4 条要求"每门运行真实 MLX、多进程、访问审计与负向对照" —— G2 之外的门尚未满足该要求。

## Turn 24 (2026-10-23) — G1/G3 落地：里程碑 M1 完成（受控无头生产入口，代码优先）
按授权任务包 A｜V1 直接实施原生代码，非文档阶段。
- **新增** `SimiGo/Headless/SimiGoG1G3Entry.swift`：env 门控 produce/consume 编排，**只复用**生产 API（`NativeMLX.start/generate`、`ExecutionStateGraphStore.settleProducerResult`→原生 gate→authority→SQLite IS、`ModelInfo(.mlx)`、`SimiGoPaths.databaseURL`）；含 `SimiGoRuntimeCachePaths` 可注入 KV 根。生成路径直调 `NativeMLX.generate`，明确标注 `restricted_production_path`（绕过 HTTPServer 请求解析 + LOCALB 线上鉴权；模型加载/KV/结算 gate/digest/SQLite 提交均复用）。
- **增量** `NativeMLX`：加语义 `cacheIdentity`（实例级，非内存地址）；branch-checkpoints 根改走解析器。`NativeMLXPrefixPool`：prefix-pool 根改走解析器。**关键隔离修复**：两者原硬编码真实 `~/.simigo`，现遵 `SIMIGO_HOME`（默认行为不变），使实验根能真正隔离 KV。
- **门控** `AppDelegate.applicationDidFinishLaunching`：`SIMIGO_HEADLESS_ROLE` 缺省→GUI 路径完全不变；非法角色/缺参→fail-closed `exit(2)`，模型工作前拒绝。
- **回归**：App Debug `BUILD SUCCEEDED`（新代码零告警）；新增 5 项入口门控单测 `** TEST SUCCEEDED **`（执行中捕获并修复“缺参仍返回 role”的真实缺陷）；包测维持 **77/77**；工程对 `SimiGo/` 用同步根组，新文件自动纳入编译，未改 pbxproj。
- **工作树**：HEAD `de362ef` 未变、staged 0、tracked-modified 10→11、`diff --check` 干净；未 commit/push；G2 冻结批次/既有边界未触碰。
- **门判定**：M1/M2 通过≠G1/G3 通过。**G1/G3/物理内存回收仍 NOT VERIFIED**（真实双进程 30B 实验未跑）。下一步 M2（父驱动 + validate_g1_g3.py + 负向对照）→ M3（真模型 ES1→退出→ES2 续算 + 旧 KV 不可达 + 三层内存分列）。

## Turn 25 — M3 real ES1→exit→ES2 MLX experiment (r6) — evidence-driven

Vehicle: A|V1 controlled headless entry, run as a distinct-CFBundleIdentifier copy of
the built app under a pty in-process runner. Model: mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit.

Root-cause fixes this turn (all verified against real runs):
1. NativeMLX.generate threw CancellationError when called directly. Cause: the
   production lifecycle protocol requires RuntimeLifecycleCoordinator.register
   (CREATED) before generate, which then transitions RUNNING; RESEARCH_STATE:15080
   records this. Fix: register/finish around generate in both produce and consume
   (this IS the HTTP-server client protocol, not a bypass).
2. A GUI app launched with stdout on a pipe/file DETACHES via LaunchServices and
   loses the SIMIGO_HEADLESS_* env (silent exit 0). Fix: pty_run.py gives the app a
   controlling tty so it runs in-process and inherits env; bogus-role sanity = rc 2.
3. A running /Applications/SimiGo.app collides by bundle id. Fix: copy of built app
   with CFBundleIdentifier com.simigo.g1g3.headless.<run>.

ES1 produce (pid 40447, rc 0): real generation "RESULT=hello" (prompt 19 / gen 3),
settled via existing gate (digest 20b2dda9…4a8e), IS readback true, then process exited
before ES2 launched.

ES2 consume (rc 0): fresh process, fresh cache identity (differs from ES1), recovered
U1 from the SAME IS, production digest re-verify + validity check passed, real
continuation "RESULT=hello-U2" (u2 gen 5), settled via gate (digest bccf6ef6…).

Negative controls — all fail-closed BEFORE any model call (generation_call_count 0):
NC1 missing settlement rc6; NC2 payload/digest tamper rc6; NC3 dependency invalidated
rc6 (each against an ISOLATED copy of the experiment DB; the real/sealed DB untouched);
NC4 invalid role rc2; NC5 missing param rc2.

G1/G3 verdicts (reported separately, no blended PASS) in g1_report.json / g3_report.json:
G1: is_settlement_restored PASS, result_reuse_via_IS PASS, real_model_continuation PASS,
    u1_reprefill_observed NOT_INSTRUMENTED.
G3: old_kv_unreachable PASS (BOUNDED to in-process KV; on-disk prefix-pool/branch-checkpoints
    were shared, so on-disk cross-process reuse NOT excluded this run),
    cache_reference_release NOT_INSTRUMENTED, resource_reclaim NOT_INSTRUMENTED,
    physical_page_return BLOCKED.

Invariants held: branch localb-b3-closure-20261016, HEAD de362ef unchanged, staged 0,
tracked-modified 11, nothing committed/pushed, G2 sealed evidence untouched.

SHA-256: produce 7cafd80d…, consume ea547429…, g1_report f58cbc4c…, g3_report abf66956…,
driver 2a264136…, validator 24ecfe67….

---

## Turn 26 — §5 observation instrumentation + §4 disk KV isolation, r7 real-model run (2026-10-23)

### Code changes (product repo, HEAD de362ef, staged 0, not committed)
- **NativeMLXObservation.swift** (untracked, extended): read-only recorder with
  ENGINE_RUNTIME token observables (prefill_tokens_observed, cache_hit_tokens,
  generation_tokens, cache_reuse_mode), LIFECYCLE_EVENT counters (reuse_miss,
  prefix_mismatch, pool_bind_hit, pool_bind_failed, cache_save, checkpoint_failed,
  cold_rebuild, lifecycle_resume/suspend, generate_passes) and memory-tier
  observables (reference_release + sessions_released, resource_reclaim). All note*/
  snapshot methods `nonisolated` (NSLock-guarded). Every field carries
  definition + LEVEL + SOURCE; forward_calls and physical_page_return are explicitly
  NOT_INSTRUMENTED, never faked.
- **NativeMLX.swift** (tracked-modified): added `public let observation`; 12 read-only
  instrumentation hooks placed beside existing trace/engine values — prefill.progress
  total, reuseMiss, prefixMismatch, poolBind/poolBindFailed, cold-rebuild,
  performSave success, checkpointFailed, engine-token report, resume_done, suspend_done,
  suspend reference-release + Memory.clearCache. No cache-hit decision or lifecycle
  branch was changed.
- **SimiGoG1G3Entry.swift** (untracked): `SimiGoRuntimeCachePaths` now prefers
  `SIMIGO_CACHE_ROOT` (falls back to SIMIGO_HOME, then ~/.simigo) so the IS DB can be
  SHARED while prefix-pool / branch-checkpoints point at a DISTINCT, empty root —
  the disk-level basis for old_kv_unreachable. produce/consume evidence now embed
  `runtime.observation.snapshot()`.
- **run_g1g3.sh** (agent-runs): ES1 uses SIMIGO_CACHE_ROOT=cache_es1; ES2 uses a
  freshly-emptied SIMIGO_CACHE_ROOT=cache_es2 while sharing SIMIGO_HOME (IS DB).
- **validate_g1_g3.py** (agent-runs): added observation + filesystem checks; u1_reprefill
  and old_kv_unreachable now derived from real evidence; forward_calls recorded as an
  informational NOT_INSTRUMENTED non-check.

### Build + regression
- App Debug `** BUILD SUCCEEDED **`; Swift package tests **77/77**; headless-entry
  tests **5/5** (absent/empty role => GUI default untouched; unknown role / missing
  param / IS-verify fail => fail-closed before model); `git diff --check` clean.

### r7 real-model experiment (Qwen3-Coder-30B-A3B-Instruct-4bit)
- ES1 produce pid 89428 rc=0: generated `RESULT=hello`; observation snapshot shows
  prefill_tokens_observed=19, prompt_tokens=19, cache_reuse_mode=cold, cold_rebuild=1,
  cache_save_checkpoint=1, generate_passes=1. Settled via production gate, read back
  from IS, process exited before ES2.
- ES2 consume pid 89546 rc=0 (new process, new cache identity): recovered U1 `hello`
  from the SHARED IS, verified digest (production authority) + validity BEFORE any
  model call; generated `RESULT=hello-U2`; observation snapshot shows
  prefill_tokens_observed=27, cache_reuse_mode=cold, cold_rebuild=1,
  pool_bind_hit=0, cache_hit_tokens=0 => U1 prefill was RE-EXECUTED (not avoided),
  and ES2 never touched ES1's KV.
- Disk isolation confirmed: cache_es1 and cache_es2 have distinct prefix-pool +
  branch-checkpoint artifacts; ES2 root held only its own es2-* files at verify time;
  both point at the same home/simigo.sqlite3.
- Negative controls: NC1-missing / NC2-tamper / NC3-invalidate rc=6, generation_call_count=0
  (fail-closed before NativeMLX created); NC4-badrole / NC5-missingparam rc=2.

### Verdicts (G1/G3 reported SEPARATELY — no blended PASS)
- G1: is_settlement_restored **PASS**, result_reuse_via_IS **PASS**,
  real_model_continuation **PASS**, u1_reprefill_observed **PASS** (now observed: ES2
  cold re-prefill of U1 text). forward_calls stays NOT_INSTRUMENTED (labelled proxy =
  generation_tokens).
- G3: old_kv_unreachable **PASS** at DISK+PROCESS level (distinct cache roots, shared
  IS, ES2 cold rebuild, no foreign ES1 files). cache_reference_release /
  resource_reclaim **NOT_INSTRUMENTED** — hooks are now compiled in at the suspend
  ref-release and Memory.clearCache points, but the headless process settles and exits
  without an idle suspend, so no runtime release EVENT was captured this run.
  physical_page_return **BLOCKED** — malloc_zone_pressure_relief is only an allocator
  hint; the gate definition excludes RSS/footprint/exit, and no independent physical
  page-reclaim evidence exists.

### Honest remaining work
- To turn cache_reference_release / resource_reclaim from NOT_INSTRUMENTED into
  evidenced requires a dedicated suspend-trigger experiment (force/wait the idle
  lifecycle suspend, then read observation.reference_release / resource_reclaim before
  exit). physical_page_return cannot PASS under the stated evidence bar without an
  independent OS-level reclaim source; it is reported BLOCKED rather than faked.

---

## Turn 27 — G3 memory-tier evidence via memprobe lifecycle experiment (2026-10-23)

To move cache_reference_release / resource_reclaim off NOT_INSTRUMENTED without faking
anything, a `memprobe` headless role was added that drives the REAL production
lifecycle: generate -> `suspendIfIdle()` -> resume-by-generate, observing the new
NativeMLXObservation memory-tier counters plus a Mach phys_footprint read.

### Mechanism (production path reuse, no re-implementation)
- Reuses `NativeMLX.generate`, `RuntimeLifecycleCoordinator.register/finish`,
  `ModelContainer` load/unload, `Memory.clearCache`, `malloc_zone_pressure_relief`,
  and `NativeMLX.suspendIfIdle()` exactly as the idle lifecycle does.
- The idle threshold is forced to 0 ONLY via the existing `#if DEBUG` test seam
  `RuntimeTuning.suspendIdleTimeoutOverrideSeconds` (Release build has no such symbol,
  so production semantics are untouched).
- NativeMLX.swift suspend path now records `reference_release` (sessions dropped +
  ModelContainer ref set nil) and `resource_reclaim` (Memory.clearCache invoked);
  NativeMLXObservation exposes them with definition + LEVEL + SOURCE.

### mp1 run (pid 37862, rc=0, real MLX Qwen3-Coder-30B-A3B-4bit)
- warm generate `RESULT=hello`; footprint_pre = 17,418,204,288 B.
- suspendIfIdle() returned TRUE; observation shows lifecycle_suspend=1,
  reference_release=1 (sessions_released_at_release=1, model_container_ref_dropped=true),
  resource_reclaim=1; footprint_post = 12,948,876,328 B (delta ~4.47 GB).
- Resume-by-generate reloaded the container and produced `RESULT=hello` again;
  observation shows lifecycle_resume=1, cold_rebuild=2, generate passes=2.

### Verdict impact (G1/G3 still reported separately)
- G1: unchanged — is_settlement_restored / result_reuse_via_IS / real_model_continuation /
  u1_reprefill_observed all PASS.
- G3: old_kv_unreachable PASS, cache_reference_release PASS (LOGICAL tier, evidenced),
  resource_reclaim PASS (LOGICAL tier, evidenced), physical_page_return BLOCKED.

### Why physical_page_return stays BLOCKED (honest)
The task's gate definition states RSS/footprint transient drop or process exit alone
cannot make physical_page_return pass. The memprobe records a ~4.47 GB footprint drop
and a full suspend->resume reload cycle, but those are footprint-based and therefore
EXCLUDED as sole proof. `malloc_zone_pressure_relief` is only an allocator hint; no
independent OS-level physical page-reclaim source was obtained. Reported BLOCKED rather
than marked PASS.

### Regression
- App Debug BUILD SUCCEEDED after the memprobe additions.
- NativeMLX edits are confined to the app target (not SimiGoRuntime), so the package
  suite remains the 77/77 baseline; headless-entry tests 5/5 cover role dispatch.
- git invariants: HEAD de362ef, staged 0, not committed/pushed; G2 sealed batches untouched.

## Turn 28 — §2 HTTPServer-dispatch infeasibility proof + §5 model/tokenizer identity (r8) + full App suite (2026-10-23)

### 1. §2 closed at code level: why the headless path cannot go through HTTPServer
Read-only verification against the product tree (no code changed for this item):

- `SimiGo/Protocol/HTTPServer.swift:1174-1214` — `localbRoutePolicy(forMethod:routePath:)`
  maps `POST /v1/chat/completions` (and `/chat/completions`, `/v1/completions`,
  `/completions`, `/v1/responses`) to `.protected(permission: .inference)`.
- `HTTPServer.swift:1320-1334` — `verifyLOCALBProtectedRequest(...)` then fails closed,
  in this order:
  1. `guard context.transportSecurity.eligibleForLOCALBPairingBinding` (`== isTLS`, line 213)
     else `.localbTransportNotTrusted` -> **HTTP 403** "Protected requests require a
     LOCALB TLS connection".
  2. `guard let authorization = localbRequestAuthorization` else
     `.localbAuthorizationUnavailable` -> **HTTP 503** "LOCALB request authorization is
     not configured".
  3. Requires `x-simigo-localb-client-key-id` + 32-byte `x-simigo-localb-challenge`
     + 64-byte `x-simigo-localb-proof-v2`, else `.localbRequestRejected` -> **HTTP 401**
     `LOCALB_CLIENT_PROOF_MISSING`.
  4. Then `authorization.coordinator.authorizeProtectedRequest(..., checkpoint:)` must
     accept the proof against a **paired client key** and trusted checkpoint; the route
     must still resolve to the same `.protected` permission.
- `NativeMLX.swift:422-480` wires the real `generateHandler` into the `HTTPServer`, but
  `NativeMLX.startWithLOCALB(..., localbRequestAuthorization: nil)` (`NativeMLX.swift:487-502`)
  only calls `server.configureLOCALBTransport(identity:)` and never
  `configureLOCALBRequestAuthorization(...)`.

Conclusion: from a standalone headless process the `generateHandler` is unreachable over
the wire — reaching it needs a LOCALB **TLS-paired client key plus a per-request
signature**, i.e. a second product surface running outside the process under test. The
`restricted_production_path` classification is therefore justified by code, not by
preference. Bypassed: HTTP request parsing + OpenAI-schema response encoding, and on-wire
LOCALB request authorization. NOT bypassed: LLMModelFactory model loading, KV /
prefix-pool / checkpoint lifecycle, the native settlement gate +
`SimiGoSettlementAuthority` digest, SQLite IS commit, and
`RuntimeLifecycleCoordinator` register/transition/finish.

Correction of an earlier draft: it described the missing-authorization response as 401.
The code maps `localbAuthorizationUnavailable` to **503**; 401 is only reached after
authorization is configured and the client proof headers are missing or malformed.

### 2. §5 model revision + tokenizer identity (content-addressed)
- `SimiGoSettlementAuthority` gained a public `payloadDigest(_ payload: Data) -> String`
  that reuses the same internal `NativeSHA256` as settlement sealing — no second hash
  implementation.
- `produce` / `consume` / `memprobe` evidence now carries:
  - `model_identity` from production `SimiGoModelDiscovery.discover()`: `model_repo_id`,
    `model_revision` (snapshot hash), `model_root_id`, `model_path` — the durable
    (rootID + relativePath) authority, not a bare absolute path;
  - `tokenizer_identity`: content SHA-256 per tokenizer file.
- r8 values:
  - repo_id `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit`,
    revision `6e302ea604ad9ab206367e2c501d1571023e7b6d`, root `huggingface-cache`;
  - `tokenizer.json` `aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4`;
  - `tokenizer_config.json` `05a2d456eb807c8368fe6b60101b1d1160d6889071a751ed08576b96e77e01cd`;
  - `vocab.json` `ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910`;
  - ES1 and ES2 report the identical repo/revision/tokenizer digests and different
    runtime cache identities.

### 3. r8 real-model run (ES1 -> exit -> ES2)
- ES1 (produce) pid **69396**, start 2026-10-23T16:50:34, rc=0, `RESULT=hello`;
  observation: prefill_tokens 19, cache_reuse_mode `cold`, cold_rebuild 1, cache_save 1,
  cache_identity `cache-d8d011c4-0b17-4c4d-89c0-4493ac85644e`.
- ES2 (consume) pid **69422**, start 2026-10-23T16:50:43, rc=0; recovered `hello` from
  the shared IS DB, generated `RESULT=hello-U2`; observation: prefill_tokens 27,
  cache_reuse_mode `cold`, cold_rebuild 1, pool_bind_hit 0, cache_hit 0, cache_identity
  `cache-d3f07fa2-08a3-44a3-84d1-d29fa0aac2ca` (differs from ES1).
- Shared IS DB `home/simigo.sqlite3`; cache roots `cache_es1` / fresh `cache_es2`;
  ES1 confirmed exited by the parent driver before ES2 launched.
- Negative controls unchanged: NC1 missing / NC2 tamper / NC3 invalidated -> rc=6 with
  generation_call_count 0; NC4 bad role / NC5 missing param -> rc=2. Tampering only on
  isolated SQLite copies.
- Verifier `validate_g1_g3.py` on r8 + mp1: 29 checks, `checks_failed: []`.
  Evidence SHA-256: produce `94125616...ab7`, consume `044e6452...ceaf`,
  g1_report `fc054fe6...b5e6`, g3_report `18c224af...9296`, memprobe `fb8c85ca...437d`.

### 4. Full App target suite (the gap left open in Turn 27)
- Command: `xcodebuild test -project SimiGo.xcodeproj -scheme SimiGo -configuration Debug
  -destination 'platform=macOS,arch=arm64' -enableCodeCoverage NO
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=''`.
- Result: **Executed 207 tests, with 14 tests skipped and 0 failures (0 unexpected) in
  100.367 s — `** TEST SUCCEEDED **`**. Log
  `apptarget_fullrun_turn28_20261023.log`, SHA-256
  `a34f49917d5efd809b073d5f5a8aa897f1326132c6a6d86a753c136e1b519e9e`.
- Baseline discipline: earlier same-batch full run = 197 executed / 13 skipped /
  1 failure (a port-collision flake in `HTTPRequestBoundaryTests`). Test-case-name set
  diff: **10 only-in-new, 0 only-in-old** — a strict superset. The previously flaky
  `testDoubledSpaceRequestLineRejectedOnTheWire` passed this run (0.003 s). The +10 are
  tests added earlier in this batch (ExternalServerAdoptionTests x3,
  ExternalAdoptionInferenceE2ETests x1, MemoryReliefRealModelTests x1 [still skipped],
  SimiGoG1G3HeadlessEntryTests x5 [all passed]).
- All 14 skips are pre-existing env/model/flag gates (BranchForkTests x6,
  GenerationLifecycleRaceTests x3, LifecycleRaceTests x1, MemoryReliefRealModelTests x1,
  OversizedRuntimeE2ETests x2, RollForwardExperimentTests x1).
- Real-model work inside the plain suite: `PrefixPoolDailyPathE2ETests.testF3DeviceAcceptanceBattery`
  passed in 40.525 s against a live `127.0.0.1` HTTPServer + real `chat.completions` dispatch.
- GUI path unchanged: `testAbsentRoleDoesNotEngageHeadless` and
  `testEmptyRoleStringDoesNotEngage` pass inside the host app, i.e. the env gate engages
  nothing without an explicit role.

### 5. Self-audit corrections found while closing this turn
- `acceptance_matrix.json` had `processes.es1.pid` and `processes.es2.pid` both filled with
  **69297**, which was the driver shell's pid, not the experiment processes. Re-read from
  `produce_r8.json` / `consume_r8.json` / `es1_start.txt` / `es2_start.txt`:
  **ES1 = 69396 @ 16:50:34, ES2 = 69422 @ 16:50:43**. Matrix corrected (the note field
  records the mistake explicitly).
- The 401 -> 503 path-class evidence correction described in §1.

### 6. Status (unchanged in substance)
- G1: `is_settlement_restored` PASS, `result_reuse_via_IS` PASS,
  `real_model_continuation` PASS, `u1_reprefill_observed` PASS (ES2 re-prefilled 27 tokens,
  so no claim of avoiding recomputation).
- G3: `old_kv_unreachable` PASS (process + disk), `cache_reference_release` PASS (logical
  tier), `resource_reclaim` PASS (logical tier), `physical_page_return` **BLOCKED** by the
  gate's own evidence rule (footprint/RSS/exit excluded; `malloc_zone_pressure_relief` is
  an allocator hint, not independent OS proof).
- `forward_calls` (per-layer) remains **NOT_INSTRUMENTED**, recorded as informational
  rather than as a passing check.
- Git invariants: HEAD `de362ef46118402b40356c8c9e3633395a151717`, branch
  `localb-b3-closure-20261016`, staged 0, nothing committed or pushed, G2 sealed batches
  untouched, `git diff --check` clean.

### 7. Evidence manifest (§6)
`g1g3-run/MANIFEST_SHA256_turn28.txt` lists SHA-256 + byte size for every artifact the
G1/G3 claim rests on: the r8 raw JSON/logs/RC files, both cache roots' KV artifacts, the
memprobe run, the negative-control runs, the driver scripts (`run_g1g3.sh`,
`validate_g1_g3.py`, `pty_run.py`), the full App suite log, and the headless app binaries
that actually executed. The file is generated from disk (not hand-written) and excludes
only itself, since a file cannot contain its own digest.

## Turn 29 — 三项证据审计：U2 因果来源 / 三层隔离强度 / 可复现证据链（2026-10-23）

**判定口径未变**：G1 四项 PASS；G3 三项 PASS + `physical_page_return` **BLOCKED**；`forward_calls`
NOT_INSTRUMENTED；路径类别 `restricted_production_path`。本轮不扩大实现范围，只审计证据强度。

本轮新增一个**只读**审计脚本 `g1g3-run/driver/audit_turn29.py`，对 r14/r15/mp3 的原始证据做后验复核，
输出 `g1g3-run/AUDIT_TURN29.json`（38 checks / 0 failed：审计1 24 项、审计2 8 项、审计3 6 项）。
它不重写任何运行期记录（`g1_report.json` / `g3_report.json` / `consume_*.json` 的摘要保持不变），
因此运行期报告仍是 45 checks 的原始版本，38 项是附加的后验审计，两者不混算。

### 1. 审计 1 — U2 的因果来源（结论：SUPPORTED，含明确边界）

**方法**：受控差异实验。同一代码镜像、同一驱动，只改变 ES1 产出的值（r14 `hello` / r15 `world`）；
ES2 只从 `produce_handoff_<RID>.json` 取 `state_id`，不接收值。

| 环节 | 实测证据 | 说明 |
|---|---|---|
| 恢复对象来源 | ES2 `u1_payload_digest_from_is` == ES1 `settlement_payload_digest`（r14 `20b2dda9…`、r15 `97359fe1…`） | 经 `payloadDigestMatches` + `settlementValidity` 复核后才进入内存 |
| 恢复值本身 | ES2 `u1_recovered_value` = `hello` / `world`，等于本跑 ES1 的 `target_value` | 不是另一跑的值 |
| 生成请求输入 | `u2_prompt_text` = `Recovered prior result: <u1>. Output exactly one line and nothing else: RESULT=<u1>-U2` | 请求文本含恢复值 |
| 生成输出 | `generated_text_u2` = `RESULT=hello-U2` / `RESULT=world-U2` | 输出级关联，不只是 prompt |
| 进程身份 | r14 PID 51053/51094；r15 PID 51847/52044；ES2 cache 启动前 0 文件 | 无跨进程残留 |
| 状态 id 追溯 | handoff `S-0001` → ES1 `state_id` → ES2 `reading_state_id` 三者相同；两跑各自独立 DB | 定位到 ES1 创建的那一行 |
| 非硬编码 id | NC1 以 `S-9999` 请求 → rc=6、`stage=is_verify_u1`、`generation_call_count=0` | 若硬编码 `S-0001` 会命中并继续，故排除 |
| 同一 IS 文件 | ES1/ES2 的 `is_database_url` 完全相同（各跑独立目录内的 `home/simigo.sqlite3`） | 唯一跨进程通道是同一文件中的那一条 IS 行 |

**旁路通道逐项审查**（本轮补上此前未登记的 `SIMIGO_COUNTERFACTUAL_BASELINE_VALUE`）：

| 通道 | 状态 | 证据 / 处理 |
|---|---|---|
| `produce_handoff_<RID>.json` | 无值 | keys = `cache_identity_es1, payload_digest, run_id, state_id`；全文 207 B，不含产出值 |
| `SIMIGO_HEADLESS_TARGET_VALUE` | 不存在 | 门在 consume 入口拦截（rc=7）；NC6 证明门是活的 |
| `SIMIGO_EXPERIMENT_TARGET` | 不存在 | 同上；NC7 证明门是活的 |
| `SIMIGO_COUNTERFACTUAL_BASELINE_VALUE` | **存在且携带值** | 携带的是"另一跑"的值：r14 baseline=`world`（恢复 `hello`）、r15 baseline=`hello`（恢复 `world`）；两跑 prompt/output 均**不含** baseline；代码 `SimiGoG1G3Entry.swift:346-349` 仅写入证据字段，不参与 prompt |
| `SIMIGO_HEADLESS_ES1_CACHE_IDENTITY` | 存在，无值语义 | 在 prompt 构造之后读取（`:376`），只用于 cache 身份比较 |
| 入口常量 | 无 | `consume()` 无字面值；`u1value` 唯一赋值点在 `:336`，`u2Prompt` 在 `:340` 由它构造，全文无二次赋值 |
| 进程间残留 | 已排除 | 不同 PID、ES2 独立空 cache 根（见审计 2 tier A） |

**差异对照**（`AUDIT1_DIFFERENTIAL.json`）：11 项 invariant 全为 true（同代码镜像、同源码摘要、
不同产出值、prompt/output 各自携带本跑恢复值、无值 env 通道、每跑进程互异）。两跑唯一变化是产出值，
输出随之改变 —— 这是"跟随变化量"的判据，不是"存在相关性"的判据。

**审计过程中被自己抓出的反例（保留，不删）**：
- r10：ES2 继承了 `SIMIGO_EXPERIMENT_TARGET=world`。consume 从不读它，但"无值通道"这一主张当时为假。
  修法：`env -u` 洗环境 + 门扩展到两个变量 + NC7 证明门有效。
- r11：洗了正路径但 NC1–NC3 未洗，控制组被新门提前拦成 rc=7，测的是门的层级而不是 IS 校验层级。
  修法：控制组同样洗环境，重跑为 r12。

**边界（不证明）**：
1. 结算契约 `referenceResultContractJSON` 强制 `content`（`^RESULT=(.+)$` 捕获）`equals_binding` 到 `next_input`，
   所以本任务族里"传递模型输出"与"传递期望值"在语义上不可区分。因果结论只能落在
   "U2 的请求输入与生成输出跟随 IS 恢复值"，不能主张"模型独立推导出了该值"。
2. 单模型快照、贪心解码、单任务族：不能证明换 prompt/换模型时不会给出同一字符串。
3. 无独立 IS 写监视器：digest 只证明"读到的行 == ES1 写的行"，不证明 ES1→ES2 之间没有其他写者。
4. `u1_reprefill_observed` 同时记录反向事实：ES2 `prefill_tokens_observed=27`、`cache_reuse_mode=cold`，
   即 U1 的 prefill **被重新计算**，本实验不主张"省掉了这部分算力"。

### 2. 审计 2 — 三层资源状态（结论：三层分别成立，物理页仍 BLOCKED）

| 层级 | 观测点 | 实测值 | 判定依据 | 证明 | 不证明 |
|---|---|---|---|---|---|
| A. ES2 无法访问 ES1 的载体 | 磁盘根 + 引擎计数器 | 独立 `cache_es1`/`cache_es2` 根；ES2 启动前 0 文件；`cold_rebuild=1`、`cache_hit_tokens=0`、`pool_bind_hit=0`、`lifecycle_resume=0`、`reuse_mode=cold`、prefill=27；ES1 载体 4 文件前后摘要同为 `8da367ec…`；ES2 根内无 es1 命名产物 | 四者同时成立 | ES2 的 KV 是本进程从零算的，没有加载任何既有 KV | 计数器未覆盖的加载路径不可见 |
| A'（纵深防御） | chmod 000 窗口 | 驱动记录"ES2 启动前 chmod 000、结束后恢复"；同机同 uid（501，非 root）机制复验：读→EACCES(13)、list→EACCES | 机制 + 驱动自述 | 该权限状态在本机确实阻断读取 | **窗口内未实测 EACCES**；这是机制验证，不是运行期观测 |
| B. ES1 缓存/模型引用已释放 | `NativeMLX.swift` suspend 路径，`state.withLock` 内前后读状态 | `present_before=true`、`absent_after=true`、`sessions_released=1`、`sessions_after_release=0`；事件 seq 严格递增 `cold_rebuild(1)→cache_save(2)→reference_release(3)→resource_reclaim(4)→lifecycle_suspend(5)` | 值由调用方从运行时状态读出，recorder 不断言 | 进程内**逻辑引用**已释放，容器引用由有变无 | ARC 是否已 dealloc；更不证明字节归还 OS |
| C. 运行时资源已回收 | 生产 suspend 路径 | `resource_reclaim_observed=true`；`resource_reclaim_level="OPERATION_INVOKED (not bytes; not physical pages)"` | 操作被调用 | `Memory.clearCache()` 在该路径执行且晚于引用释放 | 回收了多少字节 |
| D. 物理内存页归还 | 无可接受来源 | footprint 17,416,664,168 → 12,801,403,728（Δ=4,615,260,440 B ≈ 4.6 GB） | 门定义排除 footprint/RSS/exit | 无 | **BLOCKED**：`malloc_zone_pressure_relief` 只是 allocator hint，没有独立的 OS 级页回收证据 |

memprobe 修正：`lifecycle_resume_delta` 原先恒为 0，原因是 `preRes2` 取自 `snapEnd`（自己跟自己比）。
改为取 `snapPre` 后重建、重跑 mp3，得 `suspend_delta=1`、`resume_delta=1`。这是本轮"证据自身被审计改写"
的第二个实例：修复前那个 0 会被误读成"resume 未发生"。

### 3. 审计 3 — 可复现证据链（结论：PASS）

- **单一实验标识**：`g1g3-turn29-2e0fb21f-20261023`，覆盖 r14 / r15 / mp3（`RUN_BINDING.json`）。
- **代码身份**：src `SimiGo.debug.dylib` = `e6c50c63…` → ISO 副本 = `2e0fb21f…`。
  `codesign --force --deep` 会改变字节，但 `LC_UUID = 1304120F-AE4B-30CA-91F2-A7165A710719` 两侧一致，
  证明是同一链接产物而非重新编译。三个跑（r14/r15/mp3）的运行时镜像摘要与 UUID 全部相同。
- **文件未变**：`RUN_BINDING.json` 列出的 33 个证据文件全部重新哈希，0 mismatch。
- **源码未变**：工作树中 `NativeMLX.swift` / `NativeMLXObservation.swift` / `SimiGoG1G3Entry.swift`
  今日重新哈希 == r14 记录的 `source_digests_r14.txt`（逐字节一致）。
- **模型/分词器**：repo `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit`，revision
  `6e302ea604ad9ab206367e2c501d1571023e7b6d`；tokenizer 文件（name + SHA-256）两侧一致。
- **隔离目录**：`r14/home`（共享 IS `simigo.sqlite3`，仅 3 个文件：db/wal/shm）、`cache_es1`、
  `cache_es2`，全部在实验目录内，未触碰真实 home 或封存批次。
- **源码变更**：`SOURCE_CHANGES_turn29.txt`（HEAD/branch/staged、11 个已跟踪修改 + 16 个未跟踪项，
  逐文件 SHA-256 + 字节数）与 `SOURCE_TRACKED_DIFF_turn29.patch`（67,266 B，`214a1736…`）。
  显式边界：未跟踪文件（含 `SimiGo/Headless/`、`NativeMLXObservation.swift`、新契约文件）不会出现在
  git patch 中，其内容身份只能由逐文件摘要承载 —— 这是记录方式的局限，不是"已覆盖全部变更"的声明。
- **绑定文件自描述（`RUN_BINDING.json` 现有 13 个顶层字段）**：除 runs/memprobe/差异报告外，本轮显式收录
  - `regression`：两套件日志名 + SHA-256 + 结果，并写明 `same_binary_as_experiment: false`、`same_sources: true`、
    实验镜像与测试镜像的 SHA-256/UUID，指向 `BUILD_IDENTITY_NOTE_turn29.txt`；
  - `source_changes`：`SOURCE_CHANGES_turn29.txt` 与 `SOURCE_TRACKED_DIFF_turn29.patch` 的摘要 + 未跟踪项局限；
  - `post_hoc_audit`：审计脚本路径 + SHA-256 + 输出名，并注明**不存审计输出自身的摘要**（否则与 `inputs_sha256` 成环）。
- **外层清单**：`MANIFEST_SHA256_turn29.txt` = 213 个文件，逐条重哈希 0 mismatch（总字节见清单末行，不在此处转抄，避免重生成后漂移）。
  它包含 `RUN_BINDING.json` 与 `AUDIT_TURN29.json`，自身不进清单 —— 摘要链方向单一：manifest → binding → 审计输入。
- **SHA-256 的边界（写在绑定文件里，不只是口头）**：
  - proves: *"The named file is byte-identical to what was hashed at binding time."*
  - does not prove: *"That the events described inside the file occurred."*
  事件的成立依赖运行期记录：PID、rc、带摘要校验的 IS 读、`NativeMLXObservation` 快照。

### 4. 回归（同一工作树源码；**不是**同一个二进制，见 4.1）

| 套件 | 结果 | 日志 SHA-256 |
|---|---|---|
| App target 全量 | 207 executed / 14 skipped / **0 failures**，95.528 s，`** TEST SUCCEEDED **` | `d4891af1ac17e71059cfd368cfa13d8f4594571870f2edfe6318f9ca193908e9` |
| 包测 `swift test` | **77/77**，0 failures | `583c165848bff5700bceac4b509d014f66d07eef349e9d94261e637b31a096d8` |

负控层级：NC1 missing / NC2 tamper / NC3 invalidated → rc=6；NC4 bad role / NC5 missing param → rc=2；
NC6/NC7 泄漏值通道 → rc=7。正路径 ES2 rc=0。

**4.1 构建身份差异（本轮审计 3 抓出的证据缺陷，已登记）**

`xcodebuild test` 在 18:02 重新链接了 App，而实验镜像在 17:57 就已被复制出：

|  | 实验（r14/r15/mp3） | App 回归套件 |
|---|---|---|
| `SimiGo.debug.dylib` SHA-256 | `2e0fb21f…`（ISO）/ `e6c50c63…`（src） | `a2f0e8db…` |
| `LC_UUID` | `1304120F-AE4B-30CA-91F2-A7165A710719` | `90C97A3E-B977-33E0-B3F6-3B5512C3E33F` |
| 字节数 | 161,696,832 | 28,436,352 |
| mtime | 17:57:30 | 18:02:30 |

源码 mtime 全部早于 17:57（`SimiGoG1G3Entry.swift` 17:54:00、`NativeMLX.swift` 17:28:54、
`NativeMLXObservation.swift` 17:28:45），期间无源码编辑。因此：

- **相同**：工作树、源码、模型快照、45 项运行期报告与 38 项后验审计的证据链；
- **不同**：链接产物（SHA-256 与 LC_UUID 均不同）与二进制体积，原因是 test action 用测试构建设置重建；
- **所以**：207/14/0 证明的是**源码层不回归**，不是"实验所执行的那份字节也跑过测试"；
- Turn 28 的同类表述也隐含了未被建立的"单一二进制身份"，此处一并更正。

登记文件：`g1g3-run/BUILD_IDENTITY_NOTE_turn29.txt`（由 `driver/make_build_identity_note.py` 从磁盘生成）。
若要闭合，需要在实验镜像上执行同源测试（如用该构建产出的 xctestrun 做 `test-without-building`）；
本轮未做，不扩大范围，不改判定口径。

### 5. 状态（逐项分列，不合并）

- G1：`is_settlement_restored` PASS、`result_reuse_via_IS` PASS、`real_model_continuation` PASS、
  `u1_reprefill_observed` PASS（并记录 U1 prefill 被重算）。
- G3：`old_kv_unreachable` PASS（tier A）、`cache_reference_release` PASS（tier B）、
  `resource_reclaim` PASS（tier C）、`physical_page_return` **BLOCKED**（tier D）。
- `forward_calls`（逐层）：**NOT_INSTRUMENTED**，只以 `generation_tokens` 作 token 粒度代理并显式标注。
- 路径：`restricted_production_path` —— HTTP 推理路由经代码级核实不可直接使用（TLS→403、无 authorization→503、
  缺 proof 头→401），因此本轮证据**不等于**完整无旁路的常规生产请求路径已跑通。
- Git：HEAD `de362ef46118402b40356c8c9e3633395a151717`，分支 `localb-b3-closure-20261016`，
  staged 0，未 commit/push，G2 封存批次未触碰。

### 6. 本轮自审出的证据缺陷（全部已修，并保留修复前后记录）

1. `produce_handoff` 携带 `target_value` → 删除字段 + consume 入口强门（rc=7）。
2. r10 ES2 继承 `SIMIGO_EXPERIMENT_TARGET` → 洗环境 + 门扩展 + NC7。
3. r11 控制组未洗环境，被新门拦成 rc=7 → 修驱动，重跑 r12。
4. `lifecycle_resume_delta` 自比恒 0 → 修 `preRes2` 来源，重建后 mp3 = 1。
5. `SIMIGO_COUNTERFACTUAL_BASELINE_VALUE` 未登记为值通道 → 本轮新增 4 项检查（两跑 prompt/output 均排除 baseline）；
   同时把 `RUN_BINDING.json` 里过强的「no value-carrying variable」改成精确表述：不携带**本跑产出值**，
   baseline 携带的是另一跑的值且对生成惰性（`SimiGoG1G3Entry.swift:346-349`）。
6. App 回归套件与实验镜像不是同一 link product → 登记 `BUILD_IDENTITY_NOTE_turn29.txt`，回归结论降级为「同源码、非同二进制」。

### 7. 本轮最准确的研究表述

真实模型的跨进程 IS 恢复与续算已获得**阶段性实验支持**（受控差异、digest 链、输出级关联、旁路审查）；
但完整生产路径等价性（`restricted_production_path`）、逐层 forward 观测（NOT_INSTRUMENTED）、
物理页归还（BLOCKED）仍有明确边界，三者不得与已 PASS 项合并表述。


### 8. 后续批次：RC1 发布候选构建（`/Users/mr.simi/SimiGo-Agent-Runs/simigo-rc1-20261023`）

Turn 30 按「先完成发布候选构建与同产物验证」的要求另起批次，标识 `simigo-rc1-de362ef4-20261023`。
本节的**数值一律不在此转抄**，以批次内 `RC_IDENTITY.json`（由 `driver/make_rc_identity.py` 从磁盘工件组装）
与 `RC_REPORT_20261023.md` 为准，批次清单 `MANIFEST_SHA256_rc1.txt` 自校验 0 mismatch。

- **步骤 1 固定源码**：`RC_SOURCE_FREEZE.json`（HEAD/分支/暂存区/逐文件摘要/tracked patch/模型 revision/
  tokenizer 摘要/构建命令/工具链），全部步骤跑完后由 `driver/verify_rc_source_digests.py` 复验，工作树零漂移。
- **步骤 2 构建**：`build-for-testing` 到批次内独立 derivedData，保存 `build_for_testing.log` 与
  `artifact_identity_*.json`（bundle 逐文件摘要 + tree 摘要 + LC_UUID）。
- **步骤 3 同产物测试**：改用 `test-without-building -xctestrun`，闭合了 §4.1 与 `BUILD_IDENTITY_NOTE_turn29.txt`
  登记的「回归与实验非同一二进制」缺口：bundle 内所有文件 mtime 早于测试启动，且测试后与实验后 tree 摘要一致，
  因此**构建 = 测试 = 实验是同一份字节**（Turn 29 的结论是「同源码、非同二进制」，本批次升级为同二进制）。
- **步骤 4 最小跨进程流程**：在**同一 bundle 原地**执行（不复制、不重签名），ES1 结算 → 退出确认 → ES2 按 handoff
  state id 从 IS 恢复 → 真模型续算；七个负控按预期失败，证据与进程自记 Mach-O 身份一并留存。
  G1 四项 PASS；G3 在本批次仅 `old_kv_unreachable` PASS，tier B/C 因未跑 memprobe 而 **NOT_RUN/NOT_INSTRUMENTED**
  —— 它们仍只属于 Turn 29 的那份链接产物，不得移交给 RC 产物。
- **步骤 5 非干预**：`rc_noninterference.py` 四快照 + `rc_noninterference_diff.py` 窗口差异。
  最小实验窗口违规数 0；正式 IS 数据库主文件、G2/历史封存批次、两个工作树（产品仓与研究仓）在 RC 窗口内
  均无文件被改。
- **发布门槛发现（新增，未修）**：**App 测试套件不隔离**，`test-without-building` 期间写入真实 `~/.simigo`
  （WAL/shm、branch-checkpoints、prefix-pool、bootstrap-report）。因此「测试通过」不是只读操作，
  交付前必须登记为风险或先做写隔离；本轮未经授权未修改测试代码。
- **干净态复现核验（回应「能否从干净状态复现构建」）**：以 `git archive HEAD` + tracked patch + 冻结清单里的
  未跟踪文件重建源码目录，复验逐文件摘要一致后再次 `build-for-testing`：**构建成功**，在同一份复现产物上重跑
  最小流程 **G1 同样 PASS**；但产物**不逐字节相同**（dylib 字节数/LC_UUID/tree 摘要均不同，Debug 产物带
  绝对构建路径与每次链接随机 UUID）。结论：**构建可复现 ≠ 字节可复现**，当前不能宣称跨机字节级可交付。
- 判定口径未变：`restricted_production_path`、`physical_page_return` BLOCKED、逐层 `forward_calls`
  NOT_INSTRUMENTED、结算契约把 `RESULT=` 捕获值约束为等于 state 的 `next_input`（只支持「结算值被恢复并参与
  真实模型续算」，不支持「任意任务产物都能独立于预期值被结算复用」）。
