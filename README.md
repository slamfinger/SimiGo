# SimiGo

> **Execution-State-Centered Runtime for Long-Lived Model Execution**

SimiGo 是面向 Apple Silicon / macOS 的本地 AI Runtime。它通过 OpenAI-compatible API 提供模型执行，并将 **Execution State** 与具体模型、物理表示及驻留状态分开管理。

当前产品仍是 Research Preview。SimiGo 不宣称已经成为通用生产级推理服务器，也不宣称已完成 backend-independent Execution State conformance。

## 当前发行版（v2.2.3 · build 33）

**v2.2.3 · build 33**

- [GitHub Release / DMG（需仓库访问权限）](https://github.com/slamfinger/SimiGo/releases/tag/v2.2.3)
- 文件：`SimiGo-v2.2.3-33-740484b5.dmg`
- 平台：Apple Silicon，macOS 26.4+
- SHA-256：`f34b74d784e040297224479ca2ba0aa1c8390a4cfbbadd97111325fb212ec322`
- 签名：Apple Development（Team ID `YPXU8M53F9`）；未 notarize。

下载后请先校验 SHA-256。该发行物未公证，首次打开可能受 Gatekeeper 限制；不要运行未经校验的副本。

## 能力概览

- MLX / `mlx-swift-lm` 本地模型执行；另有 llama.cpp / GGUF 受管执行入口。
- OpenAI-compatible Chat Completions、Responses 与 Text Completions 路由；支持流式和非流式输出。
- Execution State 生命周期、Session / Branch 隔离、checkpoint / restore 与请求生命周期管理。
- Physical KV / Prefix Reuse、资源准入、驻留回收与运行时观测。
- Tool Calling 的解析与外部 Agent 转交；SimiGo 不执行 Agent 工具，也不负责 Agent 规划或编排。
- Information Space（IS）宿主可在不加载模型时运行；模型服务启动时接管默认端口，停止后回落到 IS 宿主。
- MCP 生命周期接口，供外部 Agent 显式记录结算与失败信息。

具体路由的受管/旁路边界、请求作用域与复用条件见 [Agent 接入说明](docs/AGENT-ACCESS.md)。功能可用不代表每种 Agent、wire 或部署形态都已完成安装版端到端验收。

## v2.2.4 / build 34

v2.2.4 / build 34 仍是未发布的本地候选，不是 GitHub Release 或 GA。候选产物为 ad-hoc 签名且未 notarize；尚未完成正式 Developer ID 签名、公证与发布 DMG。安装版已对 IS 宿主启动、真实 GGUF 接管 API 端口及停止后回落做了特定验证，但这不等于完整发行验收。产物身份和证据范围见 [RELEASE.md](RELEASE.md)。不要将本地候选 tag、构建或测试结果称为正式发行。

## Quick Start

### 使用 DMG

1. 从 [v2.2.3 Release](https://github.com/slamfinger/SimiGo/releases/tag/v2.2.3) 下载 DMG。
2. 校验上述 SHA-256。
3. 按安装器提示安装并启动菜单栏 SimiGo。
4. Execution State 图入口：菜单栏 → **Execution State Graph...**。

### 源码构建

普通源码构建需要 macOS、Xcode 与仓库源码。Runtime package 位于 `Packages/SimiGoRuntime`。

```bash
git clone https://github.com/slamfinger/SimiGo.git
cd SimiGo
tools/open_source_audit.sh
xcodebuild build \
  -project SimiGo.xcodeproj \
  -scheme SimiGo \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build/release
```

### 测试与用户数据隔离

App-hosted 测试可能写入真实的 `~/.simigo`（IS 数据、checkpoint、prefix pool 与日志）。不要将普通 `xcodebuild test` 视为用户数据隔离测试。

使用仓库提供的隔离入口：

```bash
tools/run_isolated_tests.sh --tag local-run1
```

脚本会建立隔离根并对测试前后状态进行差分；若隔离条件、测试或非干扰检查失败则以非零状态退出。具体边界以脚本及其运行结果为准。

## 架构边界

```text
Execution State       ≠ KV Cache
Execution State       ≠ Residency State
Execution Continuity  ≠ Computation Semantics
SimiGo Runtime        ≠ Model Backend
```

Execution State 描述身份、lineage、position、continuation 与 lifecycle；Representation / Residency 描述它由什么承载、当前是否驻留。当前主要执行基质是 MLX，参考 carrier 为 `R_Reference_v1`。State Graph reference implementation 不等于 MLX 或 llama.cpp conformance，也不证明 backend-independent Runtime 已完成。

## IS 当前证据边界

IS 中的 **recorded、committed、retrievable 是不同状态**。目前已有有限的 `replay=1` 与结算/复用观察，但不能据此声称同 scope 的已结算答案已在受控安装版链路中被后续请求稳定消费。取消轮终态、本地请求来源身份和 Agent 分类检索资格等未关闭问题见 [Open Problems](docs/knowledge/open-problems/README.md)；数据合同及其测试范围见 [IS External Turn Contract](docs/architecture/IS_EXTERNAL_TURN_CONTRACT_20261030.md)。

云端模型 API 代理已从产品源码删除。使用自身云端 API 的 Agent 不会通过 SimiGo 本地推理路由；可通过 MCP 生命周期接口显式接入。SimiGo 不将 ChatGPT-Web2API 作为核心 backend。

## 文档入口

| 主题 | 文档 |
|---|---|
| 产品概览、公开版本 | 本页 |
| 安装与服务配置 | [部署指南](部署指南.md) |
| Agent API / MCP 接入及边界 | [docs/AGENT-ACCESS.md](docs/AGENT-ACCESS.md) |
| 当前 Runtime 设计 | [Execution Runtime Design](docs/architecture/EXECUTION_RUNTIME_DESIGN_V16.md) |
| IS 外部轮次数据合同 | [IS External Turn Contract](docs/architecture/IS_EXTERNAL_TURN_CONTRACT_20261030.md) |
| 当前未关闭问题 | [Open Problems](docs/knowledge/open-problems/README.md) |
| 实验索引 | [Experiments](docs/experiments/README.md) |
| 架构决策索引 | [Decisions](docs/decisions/README.md) |
| 发布候选身份与边界 | [RELEASE.md](RELEASE.md) |
| 许可与第三方声明 | [OPEN_SOURCE.md](OPEN_SOURCE.md)、[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)、[TRADEMARKS.md](TRADEMARKS.md) |

历史研究叙事与归档路线保留在 `docs/research/`、`docs/evolution/`、`docs/history/` 和证据目录中；这些资料用于追溯，不应替代当前产品说明或被误读为当前实现/授权。

## License

源码与参考实现采用 Apache-2.0；研究文档、Contract 与证据采用 CC-BY-4.0；SimiGo 名称与官方品牌不随源码许可授予。模型权重不随本仓库或 DMG 分发。

详见 [LICENSE](LICENSE)、[LICENSE-DOCS](LICENSE-DOCS)、[NOTICE](NOTICE)、[OPEN_SOURCE.md](OPEN_SOURCE.md)。
