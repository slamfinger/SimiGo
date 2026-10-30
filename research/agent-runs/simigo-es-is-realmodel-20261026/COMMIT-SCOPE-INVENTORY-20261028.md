# 提交范围清单 · 2026-10-28（#95，只读盘点，未执行任何 git add / commit / tag）

## 0. 证据身份

| 项 | 值 |
|---|---|
| HEAD | `b0852511`（`fix(release): read the installer dialog version from the staged bundle`） |
| 已跟踪改动 | 12 个文件（全部 `M`，暂存区为空：`git diff --cached --stat` 无输出） |
| 未跟踪路径 | 17 项（其中 1 项体积 **16 GB**） |
| `git diff`（含 research） | `e2333dac794acf5b277aa86c8a3f826c694e28f689c9865c8b32bc99948230bc` |
| `git diff -- ':!research'`（纯代码） | `2d4486b767c3317e7663144d3849ea872eba11e3cbf482d6dd917e3ab2885660` |
| 与 §3.31 的关系 | §3.31 记录的正是纯代码 hash `2d4486b7…`，今天仍相等 ⇒ **自 a18 真机窗口以来代码零漂移**，差异只在验收文档自身变长（`e2333dac…`） |
| 漂移判定（独立于 hash） | 最晚源码 mtime `2026-10-28 01:23:04`（`HTTPServerChat.swift`）早于 Release 构建日志 `01:34:19`（`build/w1-release-build.log`，`** BUILD SUCCEEDED **`）⇒ 当前安装版 build-31 二进制由当前代码构建 |
| 计数变化说明 | owner 裁定的「26 项」是本轮设计文档写出之前的计数；本窗口新增 2 份设计 + 1 个探针脚本 ⇒ 现为 12 M + 17 ?? = 29 |

## 1. 三分结论

- **① W1（#91 已 GO）必要代码与测试**：7 个文件中的 **大部分** 属于此组，但 `HTTPServerChat.swift` 与 `SimiGo/Inference/NativeMLX.swift` 各含非 W1 hunk（见 §3）。
- **② 其他尚未验收的变化**：5 组独立能力，每组需要各自的裁定与证据（见 §2）。
- **③ 临时产物**：13 项未跟踪路径，一律不进暂存区（见 §4）。

## 2. 逐文件清单

### ① W1 · multipart content 归一化（#91 GO）

| 文件 | 改动 | 测试层证据 | 真机证据 |
|---|---|---|---|
| `SimiGo/Model/TypesBridge.swift` | +27：`JSONValue.messageText` —— 全仓唯一一份 content 展平实现 | `SimiGoTests/TypesBridgeTests.swift` 4 例新增，14/14 全绿 | §3.31 G1：`prefillStep … est=1252`（a17 同请求为 `est=0`） |
| `SimiGoTests/TypesBridgeTests.swift` | +56：两种 wire 形态收敛、非文本 part 跳过、标量/空形态、`informationScope` 表示不变性 | 同上（点名套件 `TypesBridgeTests` 9/9） | — |
| `SimiGo/Inference/NativeMLX.swift` | 6 处取值改走 `messageText`（规模估读 `:1411/:1420/:1441`、`makeChatMessages :2484`、账本对账 `:2580`、工具轮吸收 `:2630`）；**删除本地 `coerceContent`（−16）**；`:2816` 注释同步 | `MessagesConversionEquivalenceTests` 2/2（专门守住 `coerceContent`→`messageText` 的等价性）；`w1-check-build.log` `** BUILD SUCCEEDED **` | §3.31 G2 |
| `SimiGo/Inference/OversizedRuntime.swift` | 本地 10 行形态分支 → `messageText` | 编译门（Debug + Release） | — |
| `SimiGo/Protocol/HTTPServerResponses.swift` | `lastUserText` 1 行 | `HTTPChatParamsTests` 3/3 | — |
| `SimiGo/Protocol/ManagedContinuationEntry.swift` | 注入写回改 `content.messageText`（2 行） | 点名套件（受管续跑类未单跑） | — |
| `SimiGo/Protocol/HTTPServerChat.swift` | W1 部分：`:89` 取值、`attach()` 写回归一、`informationScope` 生成键 `:294` | 同 `TypesBridgeTests::testInformationScopeIsRepresentationInvariant` | §3.31 G1 |

测试读数来源：`build/w1-app-tests.log`、`build/w1-app-tests-isolated.log`（2026-10-28 01:28 / 01:32，`Executed 14 tests, with 0 failures`，套件 = `HTTPChatParamsTests` 3 + `MessagesConversionEquivalenceTests` 2 + `TypesBridgeTests` 9）；`build/w1-check-build.log`（Debug）、`build/w1-release-build.log`（Release，DMG 源）。

### ② 其他尚未验收的变化

**②-A IS 上下文冻结与回放 —— #87（owner 判「待做」）**
- `Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoISContextLedger.swift`（**新** 122 行）
- `Packages/SimiGoRuntime/Tests/SimiGoRuntimeContractTests/SimiGoISContextLedgerTests.swift`（**新** 122 行，7 例）
- `SimiGo/Protocol/HTTPServerChat.swift`：`stabilize` 调用、`contextInject` 埋点、中途索引回放循环、`contextFreezingEnabled`（默认开 `!= "0"`）
- 测试层证据：**7/7 全绿（2026-10-28 02:21 现场重跑 `swift test --filter SimiGoISContextLedgerTests`，exit 0）**
- 真机证据：a16 `replay=1 frozenStale=1` + `mode=extend cacheEff=0.74`（§3.13/§3.30 系），a18 §3.31 T1 `replay=1`
- **仍缺**：负对照 `SIMIGO_IS_CONTEXT_FREEZE=0`（owner 明令等其重启安排，不得自行重启安装实例）；接入层 HTTP 测试零覆盖（全仓无任何测试引用冻结路径）

**②-B 零模型调用答案复用 —— 阶段一「命中就不调模型」（#81 未 GO）**
- `Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift`：+36，只读 `answeredDemand(sessionID:query:)`
- `SimiGo/Protocol/HTTPServerChat.swift`：`ReusableAnswer` / `isAnswerReuseEnabled` / `reusableAnswer`（四道 fail-closed 门）/ `recordReusedAnswer` / 模型动作前的短路返回块（约 +107）
- 真机证据：§3.31 结论 2 —— a18 T2 `0.23s`、`[IS_REUSE] … model_calls=0`、两条 `chat_messages` 共享同一 `content_object_id`（字节级同一份结算正文），且发生在**零持久化 KV** 的默认配置下
- **仍缺**：测试层覆盖为**零**（`grep` 全仓，无测试引用 `answeredDemand` / `isAnswerReuseEnabled`）。单窗口单问句正例 ≠ 已验收。

**②-C 上游 provider 与免 Key 回环 —— 阶段 1-A（#80 的一部分）**
- `SimiGo/App/CloudBackend.swift` +70：`UpstreamProvider{openai,ollama,lmstudio}`、`isLoopbackUpstream`、`requiresAPIKey`、`modelsProbeURL()`
- `SimiGo/Protocol/RemoteOpenAIBackend.swift` ±6：无 Key 时不再强制 `Authorization` 头
- 事实核查：**只有 `requiresAPIKey` 有消费方**（`RemoteOpenAIBackend`）；`UpstreamProvider` 与 `modelsProbeURL()`、`defaultPort` 在产品码里**零调用方**（设置 UI 未接线）
- 证据：测试层零覆盖、真机零读数（mtime `2026-10-27 22:27`，未参与任何探针）
- 归组建议：这是「Qoder CN 接本地模型」那条线的开头，不该混进 W1 提交

**②-D 前缀分歧诊断口径**
- `SimiGo/Inference/NativeMLX.swift`：`firstPrefixMismatch` 现在跳过「assistant 工具回显丢失」这一类已被门控容忍的差异（注释绑定 2026-10-26 实测）
- 性质：**只改 trace，不改门控判定**；单独一个 hunk，可独立成提交，也可暂不提交

**②-E 版本递增**
- `SimiGo.xcodeproj/project.pbxproj`：`CURRENT_PROJECT_VERSION` 30 → 31（两处 target 配置）
- 属发布行为：v2.2.1 tag 已指向 build 30，是否让 build 31 成为一次正式发布需 owner 单独裁定；**不可当作 W1 的附带改动**

**②-F 文档与探针**
- `research/…/ACCEPTANCE-20261026-BUILD-97043902.md`：+112（§3.31，逐字 trace、对象去重表、G1–G5、四条结论、否定结论、GO/NO-GO）
- `research/…/W2PRIME-DESIGN-20261028.md`（**新**，#92 DEFER 的设计记录）
- `research/…/SESSION-CONTINUATION-DESIGN-20261028.md`（**新**，#90 设计，待裁定）
- `research/…/COMMIT-SCOPE-INVENTORY-20261028.md`（**新**，本文件）
- `research/…/freeze-probe-20261028.py`（**新** 117 行，#87 负对照/复验探针；按惯例应与 ②-A 同进同退）

**②-G 阶段 1/2/3 新增文档（2026-10-28 晚补记，均为拟入库）**
- `docs/AGENT-ACCESS.md`（**新**，阶段 1 首版接入范围；含 §2.6 默认态告警与 D-1 指针）
- `research/…/STAGE1-GAP-MATRIX-20261028.md`（**新**，§4.7 Release 编译复验、§4.8 D-1、§4.9 待决清单）
- `research/…/LAB-DOC-CLEANUP-PLAN-20261028.md`（**新**，阶段 3 盘点与删除候选）
- 未跟踪项计数校正：写本文件时为 17 项临时路径；2026-10-28 晚实际为 **30 项 = 17 项拟入库 + 13 项临时**
  （临时含 `exports/`、4 个 `.xctestrun`、2 个 `Test-refusal.xcresult` 等）。`git add -A` 仍会吸入 16 GB 的
  `isolated-20261026-190618/`，第 ③ 节的风险结论不变。

### ③ 临时产物（不进暂存区，也未删除任何一项）

| 路径 | 体积 |
|---|---|
| `research/…/isolated-20261026-190618/` | **16 GB** |
| `research/…/c0b-20261027-041301/attempt1-probe-defect/` | 732 KB |
| `research/…/c1-20261027-041445/source-snapshot/` | 440 KB |
| `research/…/c0b-20261027-041301/isolation/` | 484 KB |
| `exports/`（2 个 tar.gz） | 380 KB |
| `research/…/b7-20261027-0338/source-snapshot-20261027/` | 348 KB |
| `research/…/c0b-20261027-041301/Test-refusal.xcresult` | 196 KB |
| `research/…/c6d-stage2-logs-20261027/xctestrun_{diag,final,final-kvblocked,final-kvfree}.xctestrun` | 4 个文件 |
| `research/…/dep-root/` | 8 KB |

- `build/` 已被 `.gitignore:6` 忽略，a16/a17/a18 全部窗口产物与 `w1-*.log` 不会出现在暂存候选里。
- **风险提示（事实）**：这 17 项未跟踪路径里没有任何一项是「小文件」意义上的安全项，`isolated-20261026-190618/` 单目录 16 GB；任何 `git add -A` / `git add .` 都会把它们全部吸入。owner「不将工作区整体打包」的裁定在这一条上有直接的量级依据。
- 我没有删除、移动或压缩其中任何一项；是否清理、按哪个引用核对后再清理由 owner 决定（同 `#78` 那批的处理方式）。

## 3. 不可分性（这一条必须 owner 定，不能由我默认）

`SimiGo/Protocol/HTTPServerChat.swift` 里三个范围是**交错**的，6 个 hunk 的归属为：

| hunk | 归属 |
|---|---|
| `@@ -86,7 +86,7`（`lastUser` 取值） | ① W1 |
| `@@ -103,7 +103,35`（stabilize + contextInject 埋点） | ②-A |
| `@@ -119,28 +147,41`（`attach()` 写回归一 **和** 回放循环 **和** 取消 `guard !context.isEmpty`） | ① 与 ②-A 在同一 hunk 内 |
| `@@ -168,6 +209,79`（ReusableAnswer 四门 + recordReusedAnswer） | ②-B |
| `@@ -177,7 +291,7`（`informationScope` 生成键） | ① W1 |
| `@@ -696,6 +810,40`（模型动作前的零调用短路） | ②-B |

事实与后果：
1. 按文件粒度 `git add` 无法表达 owner 的逐项裁定——W1 的 GO 会连带把 ②-A、②-B 一起写进提交。
2. 逐 hunk 拆分可以技术上做到（`@@ -119` 那处需手工编辑合成一个从未存在过的中间版本），但**拆分后的源码组合就是新的 hash**，既不等于 a16 那次的构建，也不等于 a18 build-31 的构建。按既有口径「同一源码 ≠ 同一个二进制」，拆出来的 W1-only 提交**没有真机读数可引**，只能引测试层的 14/14。
3. 我的建议（属建议，非授权）：把 ① + ②-A 冻结回放 + ②-B 零模型调用作为**一个「受管入口治理」提交单元**提交，理由是三者在 a18 同一窗口同一二进制里被同一次读数覆盖（G1/G2/G4 + `replay=1` + `model_calls=0`），拆分反而制造未验证组合；②-C、②-D、②-E 各自独立成提交或继续留在工作树。

## 4. 建议的提交切分（等授权，未执行）

| # | 提交内容 | 文件 | 可引证据 |
|---|---|---|---|
| C1 | `fix(protocol): normalize chat message content into one canonical text form` | TypesBridge.swift, TypesBridgeTests.swift, NativeMLX.swift(仅 W1 hunks), OversizedRuntime.swift, HTTPServerResponses.swift, ManagedContinuationEntry.swift, HTTPServerChat.swift(仅 W1 hunks) | 测试层 14/14；真机 §3.31（若按 §3 建议合并则含 ②-A/②-B） |
| C2 | IS 冻结回放（#87） | SimiGoISContextLedger.swift, SimiGoISContextLedgerTests.swift, freeze-probe-20261028.py, HTTPServerChat 相关 hunks | 契约层 7/7（02:21 现场重跑）+ a16/a18 真机；**负对照仍缺** |
| C3 | 零模型调用答案复用（#81） | SimiGoESISDatabase.swift, HTTPServerChat 相关 hunks | §3.31 T2；**测试层零覆盖，建议先补 DB/HTTP 测试** |
| C4 | 文档 | ACCEPTANCE §3.31 + 三份设计/清单 | 与对应代码提交同批或独立 `docs(research)` |
| 留树 | ②-C provider、②-D 诊断口径、②-E build 31 | CloudBackend.swift, RemoteOpenAIBackend.swift, NativeMLX 的 `firstPrefixMismatch` hunk, project.pbxproj | 无充分证据，等各自裁定 |

## 5. 本文件不包含的东西（明确边界）

- 未执行 `git add` / `commit` / `push` / `tag` / `stash`；暂存区仍为空，HEAD 仍 `b0852511`。
- 未删除或移动 ③ 中任何临时产物。
- 未触碰运行中的安装实例，未启动 `SIMIGO_IS_CONTEXT_FREEZE=0`（#87 负对照仍为待做）。
- 未对 #90 做任何产品码改动；`SESSION-CONTINUATION-DESIGN-20261028.md` 是待裁定的提案。
