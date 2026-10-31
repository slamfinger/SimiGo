# SimiGo

**SimiGo 是面向长时模型执行的本地 AI Runtime。** 它以 Execution State 为核心，将逻辑执行连续性与 KV Cache、物理驻留和具体推理 Backend 分开管理。

当前平台为 Apple Silicon macOS，主要推理 Backend 为 MLX，并通过 OpenAI-compatible API 对外提供模型服务。

## 当前状态

- **最新公开版本：** [v2.2.3](https://github.com/slamfinger/SimiGo/releases/tag/v2.2.3)，build 33。
- **产品阶段：** Reference App / Research Preview，尚非 GA。
- **平台：** Apple Silicon，macOS 26.4 或更新版本。
- **模型：** 模型权重不随本仓发布，需单独获取并遵守其授权。
- **开发分支：** Qoder Collection 正在独立分支集成；未合并、发布的代码不属于 v2.2.3 安装包。

## 主要能力

- 通过 OpenAI-compatible API 提供本地模型生成，支持流式与非流式请求。
- 管理 Session、Branch、Execution State 的身份、lineage、position 和生命周期。
- 支持 checkpoint、restore、请求取消，以及 generation 与 suspend/resume 的生命周期协调。
- 管理 MLX 表示的准入、物理驻留、释放和恢复。
- 支持 Prefix Reuse、Tool Calling 转交及 Tool Governance。
- 通过独立 Runtime Contract 表达执行与模型能力边界。

**核心区别：** Execution State 不等同于 KV Cache；释放物理表示不等于删除逻辑执行状态。

## 下载运行

从 [v2.2.3 Release](https://github.com/slamfinger/SimiGo/releases/tag/v2.2.3) 获取公开 DMG。Release 页面列出 SHA-256 和首次启动的 Gatekeeper 处理方式；先校验工件，再安装运行。

## 源码构建与测试

需要支持项目依赖的 macOS、Xcode 和 Swift 工具链。

~~~bash
git clone https://github.com/slamfinger/SimiGo.git
cd SimiGo

# 构建 Debug XCTest 宿主
xcodebuild build-for-testing \
  -project SimiGo.xcodeproj \
  -scheme SimiGo \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/test \
  -enableCodeCoverage NO \
  CODE_SIGNING_ALLOWED=NO

# App XCTest 必须使用隔离 harness
tools/run_isolated_tests.sh --tag local
~~~

MLX-free 的 Qoder Collection package 可独立测试：

~~~bash
swift test --package-path Packages/SimiGoCollection --filter SimiGoCollectionTests
~~~

不要用未配置隔离根的普通 xcodebuild test 替代 App isolation harness。Harness 会将 App 状态、cache、state graph 和 Qoder transcript 根重定向到新建隔离目录，并审计用户状态是否被改动。

## 架构边界

~~~text
Execution State
  identity · lineage · position · continuation · lifecycle
          ↓
Representation
  prefix · checkpoint · other backend-specific carriers
          ↓
Residency
  admission · materialization · eviction · reconciliation
          ↓
Physical Backend
  MLX and other explicitly integrated engines
~~~

当前实现不宣称已经完成 Backend-independent Runtime。Reference carrier、MLX carrier 和不同 Backend 的能力必须按各自测试证据区分。

## Qoder Collection（开发分支）

Qoder Collection 只读扫描 Qoder transcripts，将识别出的候选与游标持久化到独立 inbox。当前 App 接入使用 collection-only 模式：

- Qoder transcript 树只读；
- collector 状态位于 SimiGo 管理目录；
- 当前不向 Information Space 写入，不执行 settlement、RULED_ALLOW 或 WA；
- 候选采集不等于已结算知识。

实现边界与测试入口见 [SimiGoCollection README](Packages/SimiGoCollection/README.md)。该能力只有在对应开发分支合并并发布后才进入正式产品版本。

## 文档与许可

- [部署指南](部署指南.md)：服务配置与运行方式。
- [Execution State Runtime Design](docs/architecture/EXECUTION_RUNTIME_DESIGN_V16.md)：架构设计。
- [Information Space External Turn Contract](docs/architecture/IS_EXTERNAL_TURN_CONTRACT_20261030.md)：外部信息进入 IS 的状态与边界。
- [Reference App Architecture](docs/V2.1_REFERENCE_APP_ARCHITECTURE.md)：Reference App 的产品实现。
- [Open Source Policy](OPEN_SOURCE.md) · [Trademarks](TRADEMARKS.md) · [Third-party notices](THIRD_PARTY_NOTICES.md)。

代码和文档的许可范围不同，以各目录许可证及仓库根目录的许可声明为准。
