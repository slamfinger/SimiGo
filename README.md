# SimiGo

> **Execution continuity beyond a model's KV cache**  
> **让已完成的计算脱离旧执行载体，在新的执行链中被验证、恢复和继续使用。**

SimiGo studies how a completed computation can outlive the model process and its KV cache. It separates **Execution State (ES)**—the authority for continuation—from **Information Space (IS / PALACE)**—the ledger for settled results, provenance, dependencies, and validity. A fresh execution may consume a prior result when the result's own integrity, validity, dependency closure and declared semantic contract still verify. Producer model or Agent identity is recorded as provenance and does not by itself gate semantic reuse; only a physical KV representation is identity-bound. Releasing the model process and its KV cache and then consuming the settled result from a genuinely new execution state has been exercised on MLX and llama.cpp; per-backend readings and the public replication chain are tracked in the [experiment index](docs/experiments/README.md).

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
  + source / producer provenance
  + version
  + dependency closure
  + validity basis
  + settlement contract
```

这里必须区分三种身份，不能把它们合并成一道“生产者身份”准入锁：

- **信息来源身份**：结果由谁产生。用于溯源与审计，不作为语义复用的默认条件。
- **执行主体身份**：谁正在使用这份信息。记录本次消费；除显式权限或任务策略外，不垄断信息。
- **物理表示身份**：某个 KV 表示能否被当前引擎直接恢复。必须严格验证模型、tokenizer、KV 布局、命名空间与前缀边界。

因此，语义复用的准入是：**完整性 ∧ 有效性 ∧ 依赖闭包 ∧ 语义合同 ∧ 权限策略**。只有物理 KV 恢复才额外要求**表示兼容**。生产者身份不能替代信息自身的事实：同一个模型不证明结果仍然有效，不同的模型也不证明结果失效；只有当任务显式声明“必须由某个模型、执行环境或工具版本产生”时，该身份才成为一项依赖。

只有当消费请求满足上述准入条件时，新的执行才能复用该结果。缺失、失效、输入变化、依赖不满足或显式合同不匹配时，系统必须拒绝这次消费；对显式消费合同，只有调用方授权重算时才进入重算路径。

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

### 三条路径：是坐标不同，不是功能不同

同一次感知到"答案已经有了"的请求，在实现里有三条彼此不同的落点。区分它们的不是省了多少，而是两件事：**是否发生了模型调用**，以及**是否诞生了一份可再判的结算**。

| | 没有诞生结算 | 诞生了结算 |
|---|---|---|
| **零模型调用** | **只读应答复用**（read-only answer reuse）：同文本直接返回，复用事件 `consumer_state_id: nil` | **消费**（consumption）：新谱系 + 声明契约 + consumer ES + `DERIVED_CONSUMPTION` |
| **≥1 次模型调用** | **拒绝**：类型化理由落到失败审计，结算写入数为 0 | **生成 / 续接**（continuation）：子执行状态 + 生成类结算 |

这三个词与论文 §3.3 的网格同源，定义只在术语正本里出现一次：[ES/IS 术语正本](docs/research/es-is/TERMINOLOGY_V0.1_20261109.md)。其中"只读应答复用"过去在实现侧被称为 `hint`，那是分支绰号，不是论文用词；"结算指纹"也**不是** KV 层的 `kvFingerprint`。

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
       settlement（结算动作）
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

这是 SimiGo 要证明的目标路径。图中的“释放旧模型进程与旧 KV Cache，再由新 ES 恢复”是核心研究验收条件，**不是对当前所有 backend 均已通过的声明**。

## 研究方向

### 1. Execution State：执行连续性，而非缓存连续性

建立独立于模型物理缓存的执行身份、lineage、分支和 continuation 语义。新执行应能明确声明其父状态、推进位置和消费依据，而不是通过复用旧 KV 来伪装成同一次执行。

### 2. Information Settlement：让结果成为可验证对象

研究如何判断一个结果是否语义充分、来源明确、版本可识别、依赖闭包完整。结算不仅保存输出，还要保存后续核验所需的合同、摘要与身份溯源。未通过验证的输出不能升级为可复用结果。

### 3. Dependency-aware Validity：只失效受影响的结果

结果的有效性取决于其上游来源和依赖。依赖变化时，系统应沿依赖图识别受影响的闭包，拒绝失效结果，并在授权策略允许时只重算必要部分，而不是清空全部历史或盲目复用旧结果。

### 4. Carrier Independence：跨模型进程与 KV 生命周期

这是关键实验方向：在旧模型执行结束后，真实释放旧 KV Cache，甚至退出旧模型进程；随后启动新的执行上下文，通过 IS 验证并消费已结算结果。必须区分数据库恢复、测试夹具恢复、同进程答案复用与真实模型冷启动后的 continuation。

### 5. Agent Continuity：显式接入，而非默认宣称自动接入

本地受管 Agent 请求可以使用 SimiGo 的 ES/IS 生命周期；使用自有云端 API 的 Agent 可通过 MCP 显式提交执行与结算信息。Agent 的 transcript 采集、MCP 可调用和完整 ES/IS 端到端接入是不同层次，不能互相替代。

## 当前实现与证据：已经做到什么，尚未证明什么

| 主题 | 当前证据支持的结论 | 证据边界 |
|---|---|---|
| ES 生命周期 | 产品与 Runtime 中已有状态记录、分支/continuation 与受管推进路径；fork、隔离、迁移/reattach 均有实验覆盖 | 分支快照与导出恢复目前只有 MLX 有宿主，GGUF 显式拒绝分支快照；早期实验只对其登记的模型与配置成立 |
| IS / PALACE | 内容寻址对象、摘要校验、结算记录、来源与身份溯源、依赖边与失效机制均已实现；检索结算、来源绑定与引用依赖边在同一事务内提交；语义准入的十条推论已逐条测试（2 条附条件），A 路真实模型的成对试验、跨模型消费与 MCP 结算均有读数 | 成对读数只有 A 路一个本地模型；B 路（云端 Agent 自声明）与 C 路（采集桥）已实现但未跑成对读数；安装版复验仍待补 |
| 新 ES 消费已结算结果 | `SettlementConsumption` 创建新的 consumer ES、派生结算和依赖边；合同测试覆盖零模型调用、显式身份约束/依赖/输入变化拒绝 | 当前明确合同是 `exact-repeat` v1（显式 opt-in）；载体独立性验收已在 MLX 与 llama.cpp 上分别做过，样本量与自动复用路径仍有限 |
| 真实 GGUF 请求复用 | llama.cpp/GGUF E2E 覆盖首次生成、结算，以及同一运行中相同问题再次请求时零模型调用；产品侧 continuation 已接，KV 声明为 nil | 零调用复用那个测试没有卸载模型、销毁旧 KV Cache 或重启模型进程；分支快照在 GGUF 上显式拒绝；本地 GGUF 文件的 producer 身份已改为按字节内容的 SHA-256（HF hub blob 布局校验后才采信文件名），同名同尺寸不同字节不再得到同一身份。该缺口是身份唯一性与溯源问题，从未被证明为语义准入绕过 |
| MLX / llama.cpp | 两侧各有载体机制与各自读数：MLX 走 PrefixPool 导出/恢复，llama.cpp fork 走 slot attach 与保存/恢复 | 跨引擎只有值能过，KV 表示不可移植；不能把单侧读数外推为统一 conformance |
| Transcript collection | 采集轮次写入 IS 检索面：`committed` 轮可被其它会话引用，`recorded` 轮不可 | C 路只写 IS、不补 ES 结算（设计边界），因此不进入 settlement consumption。采集侧与本地 GGUF 身份的 2026-11-10 审核项已修复，见[未关闭问题清单](docs/knowledge/open-problems/README.md)第 8–14 条 |

**实验已覆盖的链条**：真实模型完成并结算结果 → 旧模型执行载体及 KV Cache 确实释放 → 新模型执行上下文建立新的 ES → IS 重新验证完整性、有效性、依赖闭包与显式合同（身份仅作溯源或显式依赖） → 新 ES 消费结果且不重跑已完成工作。这条链条已在 MLX 与 llama.cpp 上分别做过实验。

## 当前产品形态

SimiGo 是面向 Apple Silicon / macOS 的**本地 AI 运行时**，当前发布版本 **2.2.7 (3)**
（[Release](https://github.com/slamfinger/SimiGo/releases/tag/v2.2.7-3)，ad-hoc 签名、未公证）。
研究侧仍在推进，产品侧已经是一条能装、能日常使用的路径：

- **本地执行入口**：OpenAI-compatible 路由（`/v1/chat/completions`、`/v1/completions`、
  `/v1/responses`），两条受管后端——内置 MLX，与 llama.cpp / GGUF（可检测已装、按锁定版本
  重建或采用外部服务端）。
- **信息空间常驻**：没有模型时由信息空间宿主占用 8000（`/health` 报
  `simigo-information-space`，推理路由拒绝）；启动模型自动接管、停止自动回落，不需要手动切。
- **MCP 12 工具**：外部 Agent 可显式驱动 ES / IS 生命周期（`simigo_es_begin` /
  `simigo_es_settle` / `simigo_is_search` / `simigo_chat_round` / `simigo_project_note` 等）。
- **轮次进库**：新轮次写库即补摘要与关键词（本地模型，只在空窗跑，有人用就让位），按内容
  判据进房间，每轴最多一个房间。房间可人工新建、改名、多选合并、把工作目录挂到房间下；
  **轮次归属没有人工入口**——它由判据决定，合并时源房间的判据词记成目标别名。
- **采集与时间**：一个按钮把目录里的会话搬进库（Markdown 会话导出、Codex 日志、ChatGPT
  导出、Google AI Studio、DeepSeek `conversations.json`、flat 导出），同时回填来源时间。
- **缺口与补录**：设置页显示五项缺口（轮账、时间、摘要、关键词、房间），缺了才出现
  「开始」；一次按序跑完并以房间归属收尾，可中途停止。口径见
  [信息空间缺口账](docs/decisions/IS_GAP_LEDGER_20261113.md)。
- **局域网模式**：菜单可开启，绑定 `0.0.0.0` 并经 Bonjour 广播；非回环连接必须走 TLS，
  受保护路由要带客户端凭证，登记第二台设备走 `SIMIGO_LOCALB_MGMT` 命令行。信任前提是
  **单机、单人、局域网可信**——开放局域网等于把信息空间交给能证明身份的那台机器。
- **不做的事**：不代理 Agent 的云端模型请求；不等同于通用 Agent planner，不替客户端接管
  工具规划与执行。

## 获取安装包与源码构建

**安装包**：从最新 Release 获取——
[SimiGo v2.2.7 (3)](https://github.com/slamfinger/SimiGo/releases/tag/v2.2.7-3)，
资产 `SimiGo-v2.2.7-3-871be00c.dmg`（24,094,374 B，SHA-256
`9134a9edcb2136c231f033395b1dd7e9636207d41061e8c9d81ba60a7c949adf`）。
下载后请自行核对 SHA-256；DMG 内 App 为 ad-hoc 签名、未公证，首次打开需放行。
产物身份与安装形态的当前记录见 [RELEASE.md](RELEASE.md)。

**从源码构建**需要 Apple Silicon macOS 与 Xcode：

```bash
git clone https://github.com/slamfinger/SimiGo.git
cd SimiGo
tools/open_source_audit.sh
xcodebuild build \
  -project SimiGo.xcodeproj \
  -scheme SimiGo \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build/release \
  ENABLE_CODE_COVERAGE=NO \
  CLANG_COVERAGE_MAPPING=NO
```

最后两个开关不能省：本机的 `xcodebuild` 默认会给 C 目标加 `-fprofile-instr-generate`，
打出来的包大六成（24 MB → 38 MB），测试构建还可能在 `yyjson` 上撞
`___llvm_profile_runtime` 未定义符号。它们只关插桩，不改优化与产物行为。

模型权重由用户从模型发布方另行获取并遵守其许可；本仓库不分发模型权重。App-hosted 测试可能触及真实 `~/.simigo`，普通 `xcodebuild test` 不构成用户数据隔离保证；测试隔离边界见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 研究与工程文档

- [30 分钟外部入口](docs/REVIEW_ENTRY_30MIN.md)：读三样 · 跑一条最小链 · 给出判断（[英文终审稿](docs/REVIEW_ENTRY_30MIN_EN.md)）。服务外部 scrutiny，非正式审查邀请；最小链分三层，零构建全链演示尚不存在。
- [文档导航与归档规则](docs/README.md)
- [Agent API / MCP 接入合同](docs/AGENT-ACCESS.md)
- [IS 外部轮次数据合同与证据边界](docs/architecture/IS_EXTERNAL_TURN_CONTRACT_20261030.md)
- [Execution State 历史研究脉络](docs/research/EXECUTION_STATE_RESEARCH_STORY_20260922.md)
- [当前未关闭问题](docs/knowledge/open-problems/README.md)
- [实验索引](docs/experiments/README.md)
- [架构决策索引](docs/decisions/README.md)
- [Transcript collection 接入历史与边界](docs/history/COLLECTION_INTEGRATION_20261105.md)
- [当前发布记录](RELEASE.md) · [历史发行候选记录（v2.2.4 build 34）](docs/releases/HISTORICAL_CANDIDATE_v2.2.4-34.md)
- [部署与源码构建](部署指南.md)

`docs/research/`、`docs/evolution/`、`docs/history/` 与证据目录保留研究和实现演进记录。历史规格、实验结论和候选构建不自动代表当前产品能力或新的实现授权。

## License

源码与参考实现采用 Apache-2.0；研究文档、Contract 与证据采用 CC-BY-4.0；SimiGo 名称与官方品牌不随源码许可授予。模型权重不随本仓库分发。

详见 [LICENSE](LICENSE)、[LICENSE-DOCS](LICENSE-DOCS)、[NOTICE](NOTICE)、[OPEN_SOURCE.md](OPEN_SOURCE.md)。
