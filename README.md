# SimiGo

> **Execution continuity beyond a model's KV cache.**  
> **让已完成的计算结果脱离旧执行载体，在新的执行链中被验证、恢复和继续使用。**

SimiGo 是一个围绕 **Execution State（ES）** 与 **Information Space（IS / PALACE）** 展开的本地 AI Runtime 与研究项目。它研究的不是简单地延长缓存寿命，而是：当一段计算已经完成，其结果是否能够在语义充分、来源可验证、依赖闭包完整的条件下，从原模型进程及旧 KV Cache 中独立出来，并在新的 ES continuation 中恢复使用，而不必重复执行已经完成的工作。

## 核心研究问题

长上下文推理和 Agent 执行会反复产生昂贵的计算。传统 KV Cache 复用依赖原有模型执行上下文、物理缓存和驻留状态；一旦模型卸载、缓存释放或执行进程更换，后续请求往往需要重新计算。

SimiGo 探索另一种边界：

```text
旧 ES / 模型执行
       │
       ▼
结果完成并结算（settled）
       │
       ▼
IS / PALACE
来源 · 版本 · 依赖闭包 · 有效性依据 · 结算记录
       │
       ▼
释放旧执行载体 / 旧 KV Cache
       │
       ▼
新 ES continuation
       │
       ├── 依赖完整且仍有效 → 恢复已结算结果
       │
       └── 缺失、失效或依赖变化 → 只重算必要闭包
```

研究目标是让“计算完成”成为可验证、可跨执行边界延续的事实，而不是让某份 KV Cache 永久驻留。

## ES 与 IS 的职责

| 概念 | 职责 | 不等同于 |
|---|---|---|
| **ES — Execution State** | 执行身份、lineage、position、continuation、分支与结算推进；是继续执行的权威 | KV Cache、模型进程或某种张量布局 |
| **IS — Information Space / PALACE** | 保存已恢复/已结算结果及其来源、版本、依赖和有效性依据；支持检索、核验与后续消费 | 普通聊天历史、无条件向量缓存或第二套执行权威 |
| **Backend / carrier** | 承载具体阶段计算及物理状态，例如模型执行与 KV Cache | ES 身份本身或 IS 的语义记录 |

核心规则：**ES 决定如何继续；IS 说明哪些已结算结果可以被恢复及其依据；Backend 负责实际计算和物理承载。** 结果不能仅因“曾经写入数据库”就自动成为可复用结果。记录、结算、可检索和被后续执行实际消费，是不同的状态与证据层次。

## 研究进展与证据边界

SimiGo 的研究经历了从可分支执行状态，到跨表示生命周期，再到跨执行上下文的信息连续性：

- 早期 Execution State 研究在受测范围内验证了 fork / continuation、分支隔离、多分支生命周期、表示转换、迁移/reattach 与 discard。该闭环只对其登记的模型、配置和实验范围成立，不代表通用生产 Runtime 已被证明。
- 当前产品源码包含 ES 生命周期、IS 数据与检索路径、本地受管推理入口，以及供外部 Agent 显式使用的 MCP 生命周期接口。
- 本地受管请求已实现生成前 IS 检索、满足条件时的零模型调用复用，以及成功后的 ES / IS 结算路径。
- **尚不能据此宣称跨执行边界的完整问题已经普遍解决。** 同 scope 已结算结果在受控安装版链路中被后续请求稳定消费、旧 KV Cache 释放后的真实模型恢复、不同 Agent/wire 的完整端到端资格与行为，仍须按各自证据范围验收。
- Qoder transcript collection 当前是可选、只读的采集入口；采集候选不等于 IS 结算，也不代表 collection → ES/IS 已完成端到端接线。

因此，SimiGo 不宣称已完成 backend-independent ES conformance，也不宣称所有 Agent 已自动接入 ES/IS。

## 当前产品形态

- 面向 Apple Silicon / macOS 的本地 Runtime。
- 通过 OpenAI-compatible API 提供本地模型执行入口；当前源码包含 MLX 与 llama.cpp / GGUF 受管执行路径。
- 受管 Chat / Responses 路由可执行 ES demand、IS 检索、条件复用与结算；Text Completions 保持声明的兼容旁路。
- 无模型时可运行 Information Space 宿主；外部 Agent 可通过 MCP 显式提交 ES 生命周期信息。使用自有云端 API 的 Agent 仍由其自身调用云端模型，SimiGo 不代理其 provider API。
- Tool Calling 的解析与外部 Agent 转交不等于 SimiGo 自身负责 Agent 规划或执行工具。

具体接口与限制见 [Agent 接入说明](docs/AGENT-ACCESS.md)。当前未关闭问题见 [Open Problems](docs/knowledge/open-problems/README.md)。

## 获取源码与构建

**当前首页不提供旧 DMG 下载指引。** 截至本次仓库检查，GitHub Releases API 未返回已发布 Release；历史 v2.2.3 下载说明和 v2.2.4/build 34 本地候选均不应被当作当前主线的可下载发行物。正式安装包发布后，再以对应 Release 页面、提交身份、签名状态和 SHA-256 为准。

从源码构建需要 Apple Silicon macOS、Xcode 与仓库源码：

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

模型权重由用户从模型发布方另行获取并遵守其许可；本仓库不分发模型权重。App-hosted 测试可能触及真实 `~/.simigo`，不要把普通 `xcodebuild test` 当作用户数据隔离保证；隔离测试入口及其保证见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 文档入口

| 主题 | 文档 |
|---|---|
| Agent API / MCP 接入合同 | [docs/AGENT-ACCESS.md](docs/AGENT-ACCESS.md) |
| IS 外部轮次数据合同与证据边界 | [IS External Turn Contract](docs/architecture/IS_EXTERNAL_TURN_CONTRACT_20261030.md) |
| 历史 Execution State 研究脉络 | [Execution State Research Story](docs/research/EXECUTION_STATE_RESEARCH_STORY_20260922.md) |
| 当前未关闭问题 | [Open Problems](docs/knowledge/open-problems/README.md) |
| 实验索引 | [Experiments](docs/experiments/README.md) |
| 架构决策索引 | [Decisions](docs/decisions/README.md) |
| Qoder collection 接入历史与边界 | [Collection Integration Record](docs/history/QODER_COLLECTION_INTEGRATION_20261105.md) |
| 历史发行候选记录 | [RELEASE.md](RELEASE.md) |
| 部署与源码构建 | [部署指南](部署指南.md) |

`docs/research/`、`docs/evolution/`、`docs/history/` 与证据目录保留研究和实现演进的历史记录。历史规格、实验结论和候选构建不得自动解释为当前产品能力或新的实现授权。

## License

源码与参考实现采用 Apache-2.0；研究文档、Contract 与证据采用 CC-BY-4.0；SimiGo 名称与官方品牌不随源码许可授予。模型权重不随本仓库分发。

详见 [LICENSE](LICENSE)、[LICENSE-DOCS](LICENSE-DOCS)、[NOTICE](NOTICE)、[OPEN_SOURCE.md](OPEN_SOURCE.md)。
