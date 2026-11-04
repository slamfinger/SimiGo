# SimiGo

> **Execution continuity beyond a model's KV cache**  
> **让已完成的计算脱离旧执行载体，在新的执行链中被验证、恢复和继续使用。**

SimiGo studies how a completed computation can outlive the model process and its KV cache. It separates **Execution State (ES)**—the authority for continuation—from **Information Space (IS / PALACE)**—the ledger for settled results, provenance, dependencies, and validity. A fresh execution may consume a prior result only when its declared contract and dependency closure still verify. The central open proof is to release the original model carrier and KV cache, then demonstrate reuse from a genuinely new execution state.

SimiGo 是一个围绕 **Execution State（ES）** 与 **Information Space（IS / PALACE）** 的 AI Runtime 与系统研究项目。它探索一个比缓存复用更根本的问题：

**当模型已经完成一段计算，能否把结果从原模型进程和旧 KV Cache 中独立出来；在来源、版本、依赖闭包与有效性均可验证的前提下，让新的执行状态继续使用它，而不重复执行已经完成的工作？**

这不是把 KV Cache 保存得更久，也不是给 Agent 增加一份聊天记忆。研究对象是**计算结果的语义结算、载体独立性，以及跨执行边界的连续性**。

## 核心研究命题

传统推理系统通常把“已经算过”与模型进程、上下文窗口和 KV Cache 的物理驻留绑定在一起。模型卸载、进程退出或缓存失效后，后续执行往往只能重新计算。

SimiGo 将问题拆成两个不同的状态：

- **执行状态**：某次计算进行到哪里、从哪里继续、如何分支。
- **信息状态**：哪些结果已经完成并结算、它们依据什么产生、现在是否仍然有效、后续执行能否消费。

对一个已完成结果 (R)，SimiGo 要求它不只是文本或缓存片段，而是带有可验证依据的结算对象：

```text
R = payload
  + source / producer identity
  + version
  + dependency closure
  + validity basis
  + settlement contract
```

只有当消费请求满足声明的合同、来源和身份约束，且结果及其依赖闭包仍然有效时，新的执行才能复用该结果。缺失、失效、输入变化或身份不匹配时，系统必须拒绝这次消费；对显式消费合同，只有调用方授权重算时才进入重算路径。

## ES / IS / Backend：三种不同的权威边界

| 层 | 核心职责 | 不应该被混同为 |
|---|---|---|
| **ES — Execution State** | 执行身份、lineage、position、分支、continuation 与推进记录；决定执行如何继续 | KV Cache、模型进程、聊天记录或物理快照 |
| **IS — Information Space / PALACE** | 保存已结算结果及来源、版本、依赖、有效性与消费记录；为恢复提供可核验依据 | 第二套执行权威、无条件向量缓存或普通对话历史 |
| **Backend / carrier** | 承载实际计算和物理状态，例如 MLX、llama.cpp、模型进程与 KV Cache | 结果语义、ES 身份或 IS 的有效性裁决 |

**ES 是 continuation authority；IS 是 settled information 与 validity 的账本；Backend 是可替换的执行载体。** 数据库负责保存和校验，不替模型判断语义充分性，也不自行决定执行推进。

### 语义结果复用与 KV 表示复用是两条不同路径

SimiGo 并不排斥 KV Cache，也不把所有缓存优化都称为 ES/IS 连续性：

- **语义结算消费**：新的 ES 通过 IS 重新验证已结算结果及其依赖，创建消费记录并继续执行。该路径可以不携带 KV 表示；它复用的是已验证的结果，不是旧模型的张量状态。
- **物理前缀 / KV 加速**：PrefixPool 可以保存和恢复模型前缀表示，结算记录也可以绑定相应 KV 表示的摘要。它解决的是 prefill/表示复用，必须服从模型、tokenizer、KV namespace 与内容边界约束；它不能替代 IS 的语义有效性判断。

因此，“超越 KV Cache”不是禁用 KV，而是**不再把语义结果的可延续性建立在 KV 必须继续驻留这一前提上**。

## 目标执行路径

```text
       ES₁：旧执行状态
              │
              ▼
        模型 / 工具完成计算
              │
              ▼
       语义合同与来源验证
              │
              ▼
       settlement：结果结算
              │
              ▼
       IS / PALACE 记录
       payload · source · version
       dependency closure · validity
              │
              ▼
   释放旧模型进程与旧 KV Cache
              │
              ▼
       ES₂：新的 continuation
              │
              ▼
       重新核验结果与依赖闭包
          ┌───┴────┐
          ▼        ▼
       仍然有效   缺失 / 失效 / 变化
          │        │
          ▼        ▼
       消费结果   拒绝复用
       零重复计算   按策略重算必要闭包
```

这是 SimiGo 要证明的目标路径。图中的“释放旧模型进程与旧 KV Cache，再由新 ES 恢复”是核心研究验收条件，**不是对当前所有 backend 或安装版均已通过的声明**。

## 研究方向

### 1. Execution State：执行连续性，而非缓存连续性

建立独立于模型物理缓存的执行身份、lineage、分支和 continuation 语义。新执行应能明确声明其父状态、推进位置和消费依据，而不是通过复用旧 KV 来伪装成同一次执行。

### 2. Information Settlement：让结果成为可验证对象

研究如何判断一个结果是否语义充分、来源明确、版本可识别、依赖闭包完整。结算不仅保存输出，还要保存后续核验所需的合同、摘要和身份绑定。未通过验证的输出不能升级为可复用结果。

### 3. Dependency-aware Validity：只失效受影响的结果

结果的有效性取决于其上游来源和依赖。依赖变化时，系统应沿依赖图识别受影响的闭包，拒绝失效结果，并在授权策略允许时只重算必要部分，而不是清空全部历史或盲目复用旧结果。

### 4. Carrier Independence：跨模型进程与 KV 生命周期

这是关键实验方向：在旧模型执行结束后，真实释放旧 KV Cache，甚至退出旧模型进程；随后启动新的执行上下文，通过 IS 验证并消费已结算结果。必须区分数据库恢复、测试夹具恢复、同进程答案复用与真实模型冷启动后的 continuation。

### 5. Agent Continuity：显式接入，而非默认宣称自动接入

本地受管 Agent 请求可以使用 SimiGo 的 ES/IS 生命周期；使用自有云端 API 的 Agent 可通过 MCP 显式提交执行与结算信息。Agent 的 transcript 采集、MCP 可调用和完整 ES/IS 端到端接入是不同层次，不能互相替代。

## 当前实现与证据：已经做到什么，尚未证明什么

| 主题 | 当前证据支持的结论 | 证据边界 |
|---|---|---|
| ES 生命周期 | 产品与 Runtime 中已有状态记录、分支/continuation 与受管推进路径；早期实验覆盖 fork、隔离、迁移/reattach 等生命周期场景 | 早期实验只对其登记的模型、配置和范围成立，不等于所有 backend 的统一 conformance |
| IS / PALACE | 当前实现包含内容寻址对象、摘要校验、结算记录、来源/身份绑定、依赖边和失效机制 | 存在账本与验证逻辑，不等于所有语义资格均已在真实 Agent 工作流中证明 |
| 新 ES 消费已结算结果 | `SimiGoSettlementConsumption` 创建新的 consumer ES、派生结算和依赖边；合同测试覆盖零模型调用、身份/依赖/输入变化拒绝 | 当前明确合同是 `exact-repeat` v1；测试通过不等于真实模型卸载后的载体独立性验收 |
| 真实 GGUF 请求复用 | 真实 llama.cpp/GGUF E2E 覆盖首次生成、结算，以及同一运行中相同问题再次请求时零模型调用 | 该测试没有卸载模型、销毁旧 KV Cache 或重启模型进程 |
| MLX / llama.cpp | 产品源码包含两类受管执行路径及各自的实验/测试 | 不能把单个 backend 的测试结论扩展为跨 backend 的完整证明 |
| Qoder collection | 可选、只读的 transcript collection 已进入主线 | collection-only；采集候选到受控 ES/IS 结算消费尚未完成端到端验收 |

**当前最重要的未闭环证据**：真实模型完成并结算结果 → 旧模型执行载体及 KV Cache 确实释放 → 新模型执行上下文建立新的 ES → IS 重新验证来源、身份与依赖 → 新 ES 消费结果且不重跑已完成工作。这个实验必须分别在目标 backend 上给出可复核读数。

## 当前产品形态

SimiGo 当前处于 **Research Preview** 阶段，是面向 Apple Silicon / macOS 的本地 AI Runtime 与研究实现。

- 提供 OpenAI-compatible 本地模型执行入口；当前源码包含 MLX 与 llama.cpp / GGUF 受管执行路径。
- 受管 Chat / Responses 路由包含 ES 推进、IS 检索、条件复用与结算路径；不同 API 路由的合同和旁路范围见 Agent 接入说明。
- 无模型时可运行 Information Space 宿主；外部 Agent 可通过 MCP 显式使用 ES / IS 生命周期工具。
- 使用自有云端 API 的 Agent 仍由其自身调用 provider；SimiGo 不代理其云端模型请求。
- SimiGo 不等同于通用 Agent planner，也不负责替所有客户端自动接管工具规划和执行。

## 获取源码与构建

**当前仓库没有可确认的正式 GitHub Release 下载入口。** 历史 v2.2.3 下载说明和 v2.2.4/build 34 本地候选都不应被当作当前主线发行物。正式安装包发布后，应从对应 GitHub Release 获取，并核对版本、源码提交、签名/公证状态和 SHA-256。

从源码构建需要 Apple Silicon macOS 与 Xcode：

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

模型权重由用户从模型发布方另行获取并遵守其许可；本仓库不分发模型权重。App-hosted 测试可能触及真实 `~/.simigo`，普通 `xcodebuild test` 不构成用户数据隔离保证；测试隔离边界见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 研究与工程文档

- [Agent API / MCP 接入合同](docs/AGENT-ACCESS.md)
- [IS 外部轮次数据合同与证据边界](docs/architecture/IS_EXTERNAL_TURN_CONTRACT_20261030.md)
- [Execution State 历史研究脉络](docs/research/EXECUTION_STATE_RESEARCH_STORY_20260922.md)
- [当前未关闭问题](docs/knowledge/open-problems/README.md)
- [实验索引](docs/experiments/README.md)
- [架构决策索引](docs/decisions/README.md)
- [Qoder collection 接入历史与边界](docs/history/QODER_COLLECTION_INTEGRATION_20261105.md)
- [历史发行候选记录](RELEASE.md)
- [部署与源码构建](部署指南.md)

`docs/research/`、`docs/evolution/`、`docs/history/` 与证据目录保留研究和实现演进记录。历史规格、实验结论和候选构建不自动代表当前产品能力或新的实现授权。

## License

源码与参考实现采用 Apache-2.0；研究文档、Contract 与证据采用 CC-BY-4.0；SimiGo 名称与官方品牌不随源码许可授予。模型权重不随本仓库分发。

详见 [LICENSE](LICENSE)、[LICENSE-DOCS](LICENSE-DOCS)、[NOTICE](NOTICE)、[OPEN_SOURCE.md](OPEN_SOURCE.md)。
