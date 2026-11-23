# SimiGo 代码骨架入口（CODE_MAP）

**快照**：main `648778e5`（schema v51）· 2026-11-23。
**范围**：产品源码 192 个 Swift 文件 / 101,764 行（排除测试与 `Package.swift`）。
**用法**：先读本页建立模块与入口地图，再按任务进入 [逐文件字典](FILES.md)。
**边界**：本页是导航，不替代源码与测试；行为以当前源码为准。

## 1. 模块规模

| 模块 | 文件 | 行数 | 角色 |
|---|---:|---:|---|
| SimiGoRuntimeContract | 26 | 23,594 | ES/IS 语义核心（MLX-free，SQLite；主文件已拆三件） |
| SimiGo2Experimental | 70 | 21,625 | MLX 载体与证据机器（探针、实验、测量） |
| SimiGoCollection | 23 | 8,194 | 会话采集与独立导出 target |
| LOCALBCore | 6 | 5,469 | 局域网信任域（vendored，swift-crypto） |
| SimiGo/Protocol | 13 | 16,407 | HTTP/MCP 传输壳＋摘要前缀压实 |
| SimiGo/Inference | 24 | 11,662 | 推理编排与生命周期门 |
| SimiGo/App | 13 | 6,183 | macOS UI 壳 |
| SimiGo/System | 5 | 3,708 | 系统集成与引擎身份账本 |
| SimiGo/Headless | 3 | 1,690 | 无头入口 |
| SimiGo/Model | 5 | 1,922 | 模型身份、配置与类型 |
| SimiGo/Lifecycle | 2 | 980 | 运行时生命周期 |
| SimiGo/Observability | 2 | 330 | 运行状态与 trace |
| **合计** | **192** | **101,764** | |

## 2. 模块依赖

```text
SimiGoRuntimeContract (26 / 23,594)  ← ES/IS 核心，65 处 import
        ▲
Protocol (13) · App (13) · Inference (24) · Model (5) · System/Observability (5+2)
        │
        ├─ App → SimiGoCollection (23)
        ├─ Inference → SimiGo2Experimental (70) / LOCALBCore (6) / MLX stack
        └─ Headless (3) → LOCALBCore + carrier + core
```

## 3. 入口索引

ES/IS 核心文件公共前缀：`Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/`。
采集文件公共前缀：`Packages/SimiGoCollection/Sources/SimiGoCollection/`。

| 任务 | 入口 | 继续读 |
|---|---|---|
| App 启动 | `SimiGo/App/MenuApp.swift`（382） | `StatusBarCoordinator.swift`（351）→ `SimiGo/System/Service.swift`（1,356） |
| 服务宿主 | `SimiGo/System/Service.swift`（1,356） | `SimiGo/Inference/InformationSpaceRuntime.swift`（119，无模型）或 `NativeMLX.swift`（4,060）/ `ManagedGGUFRuntime.swift`（287） |
| HTTP / MCP | `SimiGo/Protocol/HTTPServer.swift`（3,767） | `HTTPServerMCP.swift`（2,688）/ `HTTPServerChat.swift`（2,310）/ `HTTPServerCompletions.swift`（778）/ `HTTPServerResponses.swift`（3,810）/ `HTTPServerManagement.swift`（1,319） |
| ES/IS 启动 | `Bootstrap.swift`（205） | `ESISDatabase.swift`（11,597）＋ `ESISDatabaseInformationSpace.swift`（2,621）＋ `ESISDatabaseIndexingAndSearch.swift`（2,079） |
| 结算 / 消费 | `SettlementConsumption.swift`（564） | `NativeDeclarativeResultContract.swift`（690）/ `SnapshotContract.swift`（918）/ `ManagedContinuation.swift`（576）/ `ISAdmission.swift`（306） |
| 检索 | `InformationLoop.swift`（1,355） | `ESISDatabaseIndexingAndSearch.swift`（2,079） |
| 摘要前缀替换 / 压实 | `SimiGo/Protocol/DigestPrefixCompaction.swift`（105） | `ISContextLedger.swift`（268，内存摘要链＋渲染快照持久化）/ `HTTPServerChat.swift`（2,310，替换门）/ `SimiGo/App/TurnDigestScheduler.swift`（1,130） |
| 推理 | `SimiGo/Inference/NativeMLX.swift`（4,113） | `NativeMLXSessionOperations.swift`（857）/ `NativeMLXPrefixPool.swift`（638）/ `PrefixMemoryPool.swift`（431）/ `LifecycleGates.swift`（666） |
| GGUF | `SimiGo/Inference/ManagedGGUFRuntime.swift`（287） | `GGUFEngineClient.swift`（279） |
| 采集 | `CollectionRunner.swift`（384） | `TranscriptSourceAdapter.swift`（82）→ `Adapters/*` → `TranscriptTailer.swift`（1,850）/ `TurnAccumulator.swift`（724）→ `CandidateInbox.swift`（262）/ `Core/CollectionCandidateInbox.swift`（1,163） |
| 无头 | `SimiGo/Headless/EnvBootstrapEntry.swift`（143） | `G1G3Entry.swift`（853）/ `LocalBManagementEntry.swift`（694） |

## 4. 按任务阅读路径

- **协议 / API**：`MenuApp` → `Service` → `InformationSpaceRuntime` 或模型宿主 → `HTTPServer` → `HTTPServerMCP` / Chat / Responses → continuation / settlement 入口 → 核心。
- **结算 / IS**：`Bootstrap` → `ESISDatabase` → `SettlementConsumption` → `NativeDeclarativeResultContract` / `SnapshotContract` / `ManagedContinuation`。
- **采集**：`CollectionRunner` → `TranscriptSourceAdapter` → 各 adapter → `TranscriptTailer` / `TurnAccumulator` → `CandidateInbox`。
- **推理 / KV**：`NativeMLX` → `NativeMLXPrefixPool` / `PrefixMemoryPool` → `NativeMLXSessionOperations`；GGUF 走 `ManagedGGUFRuntime` → `GGUFEngineClient`。
- **摘要 / 前缀替换**：`TurnDigestScheduler`（生成＋有界重试）→ `ISContextLedger`（内存摘要链 / 渲染快照暖加载）→ `DigestPrefixCompaction`（检查点边界＋有界 brief）→ `HTTPServerChat` 替换门（覆盖/连续性/轮账校验，bounded fail-open）；阈值与开关在 `SimiGo/Lifecycle/RuntimeTuning.swift`。
- **UI**：`MenuApp` / `StatusBarCoordinator` → `Settings` / `ExecutionStateGraph` / `TurnDigestScheduler`。

## 5. 平台边界

- `ESISDatabase` 的文件身份读取依赖 Darwin POSIX 接口（`realpath` / `lstat` / `fstat` / `open` + `O_NOFOLLOW`）。
- 核心多处使用 CryptoKit；`LOCALBCore` 使用 swift-crypto，保留跨平台路径。
- `HTTPServer` 使用 Network.framework 与 Security；LOCALBCore 提供跨平台 TLS 组件。
- `SimiGo2Experimental` 是 MLX 载体；Protocol 与 App 不 import 该载体。

## 6. 更新

本页是 `648778e5` 快照。代码变动后同步重算模块计数，并重新生成 [逐文件字典](FILES.md)；不要只改单条数字。
