# 阶段 4 发布收敛草案（2026-10-28）

> 状态：**草案，未落地**。本文件不改 README、不改 `docs/`、不提交、不打标签、不发布。
> 依赖裁定：D1（复用默认态）、D2（两份孤儿草稿）、D3（安装版真机复验）、D4（提交/推送/发版）、
> D6（D-2 修法）。文中 `<<D1>>` / `<<VERSION>>` / `<<BUILD>>` / `<<COMMIT>>` / `<<DATE>>` 为待定占位符。
>
> 依据文件：`README.md`（615 行，工作区）、`docs/AGENT-ACCESS.md`（226 行）、
> `gh release view v2.2.1`、`git rev-parse HEAD` / `git status --porcelain`、
> `STAGE1-GAP-MATRIX-20261028.md` §4.12 / §4.13 / §4.13.1 / §4.13.2 / §4.14。

---

## 0. 公开面事实校正（2026-10-28 逐项核实）

路线文档（goal 正文）的前提是「公开 Releases 最近仍是 v2.1.14、README 仍指向 v2.1.0」。
前半句**已过期**，后半句**仍成立**。发布文案必须建立在下面的实测事实上：

| 事实 | 读数 | 来源 |
| --- | --- | --- |
| 最新公开 Release | **v2.2.1**，发布于 2026-10-27T13:49:03Z（body 生成于 13:34:53Z），非 draft、非 prerelease | `gh release view v2.2.1` |
| v2.2.1 资产 | `SimiGo-v2.2.1-30-f6a4decf.dmg`，33,169,238 B，sha256 `07e62a59…4882b2`；staged 可执行文件 `f6a4decf…93d736` 与 `/Applications/SimiGo.app` 字节一致 | 同上 |
| v2.2.1 自述验证范围 | 安装版真实模型 3 次 chat completions（26.5 s / 35.7 s / 9.0 s）、`/health`、`/v1/models`、结算行落库、`/v1/simigo/search` 二次 `reused=true` | 同上 |
| v2.2.1 自述未验证 | KV-free K1–K3 与默认关闭读数取自**另一二进制** `dd993d4d…`，不迁移；安装器弹窗文案未经 GUI 目视；多租户/非 Apple Silicon | 同上 |
| README 下载入口 | 仍是 `v2.1.0`（`:24`、`:29`、`:49`）；`v2.1.0.dmg`（`:34`） | `README.md` |
| README 版本表 | 仍写 `v2.1.0 (build 10)`（`:201`），当前阶段仍写 v2.1.0（`:193`） | 同上 |
| 工作区版本 | `MARKETING_VERSION = 2.2.1`（pbxproj `:403`、`:435`），`CURRENT_PROJECT_VERSION = 31`（`:391`、`:423`） | `grep project.pbxproj` |
| 工作区状态 | HEAD `b0852511`（= v2.2.1 tag 提交），**55** 个未提交路径 | `git status --porcelain` |
| 已发布二进制能力 | v2.2.1 build 30 **不含**复用短路、MCP 生命周期工具、completions 旁路标记（tag 上逐项 0 处） | `docs/AGENT-ACCESS.md:3-5` |

结论：下一次发布不是「v2.1.14 之后的首发」，而是**首次把阶段 1/2 的 Agent 接入能力带上二进制**。
版本号因此必须前进（建议 `2.3.0` / build `32`：新增的是对外能力面，不是修复）；最终由 D4 定。

---

## 1. 五项对外必答 → 可写 / 不可写

路线要求 Release 与首页说明五件事。下表把每件事压到「有证据的可写句」与「禁止句」，供 D4 前的文案审阅直接用。

### 1.1 SimiGo 当前已经实现什么

可写：受管入口（`/v1/chat/completions`、`/v1/responses`）在生成前解析 ES demand、检索 IS、
命中已结算结果即 0 调用复用、成功后原子写入「子 ES 状态 + 结算 + 生产者身份 + advancement」；
`/v1/completions` 是**声明的兼容旁路**（响应固定带 `simigo.managed=false`）；云端 Agent 可经
`POST /mcp` 使用九个工具完成 begin / search / settle / fail / settlement 读回。

证据：`docs/AGENT-ACCESS.md` §2.1–§2.6、§3.2–§3.6；`STAGE1-GAP-MATRIX-20261028.md` §4.3.5（实现点）、
§4.12（MCP 套件 9/9）、§4.13.1（复用 4/4）、§4.13.2（Release 上 ES/IS 合同 51/51）。

禁止：把「九个工具」写成「完整任务编排/批量调度」；把旁路写成「已支持 completions 受管」。

### 1.2 本地 Agent 如何接入统一 ES/IS 管控

可写：任何能自定 OpenAI-compatible base URL 的本地/自托管 Agent，把 base URL 指向
`http://127.0.0.1:<APIPort>/v1` 即进入受管路径，**不需要**额外字段；作用域按
`session_id` / `thread_id` / `agent_id` 解析（JSON 优先、header 次之）；请求带稳定的会话标识
才能获得跨轮「同一问题」判定。身份与结果合同记录的是**调用方声明的** model / tokenizer，
换模型不会复用旧结果（身份不一致即拒绝）。

证据：AGENT-ACCESS §2.1–§2.4、§2.7；§4 表「MCP 身份自证」行。

禁止：写「任意 Agent 自动接入」——首版只有方式 A/B，进程内直接加载模型的 Agent 明确不支持接管
（§1、§4 第一行）；写「Ollama / LM Studio 已作为上游 provider 接入」——R2-A 暂缓（§4 第二行）。

### 1.3 云端 Agent 如何保留原 API 并把结算存入 SimiGo

可写：云端 Agent 继续调用自己的 OpenAI / Anthropic 等 API，只把执行生命周期交给 MCP；
`simigo_es_settle` 是**唯一**会写入可作为回答复用结算的工具；`simigo_is_search` 写的是检索结算
（`is-retrieval:<demand_id>`、`validation_status=IS_RETRIEVAL`），永远不会变成 `reusable_answer`；
`fail` 只落审计。判据是「MCP 连通 ≠ 结果已记录」，必须 settle 才算入库。

证据：AGENT-ACCESS §3.2–§3.6；`HTTPServerMCP.swift` settle 分支。

禁止：写「MCP 接通即自动记录」；写「检索→结算→复用闭环已可用」——D-2 未修前
**带来源的 settle 拿不到复用**（§4.11、AGENT-ACCESS §3.6 注），这句必须等 D6 落地后才可写。

### 1.4 持久化 KV 验证到什么范围

可写（限定式）：在已验证范围内，持久化 KV 不构成语义连续性、已结算结果消费、suspend 资源释放
与跨进程续跑的必要条件（K1–K3、默认关闭读数）；该结论绑定**具体二进制与模型**，
不外推到全部 Backend / 模型 / workload。

证据：`C6D-STAGE3-PRODUCT-ACCEPTANCE-20261027.md`、`C6D-KVFREE-TESTLAYER-20261027.md`；
v2.2.1 Release body 已按此口径声明 K1–K3 不迁移到新二进制。

禁止：写「KV-free 已全局证明」；把 Debug 构建的 mode=extend / 取消记录 / 缓存命中读数与
Release 内存指标拼接；用测试层读数冒充安装版验收。

### 1.5 哪些能力仍在开发中

可写：provider adapter（Ollama / LM Studio 作为上游）暂缓；批处理调度（并发 1/2/4）未启动；
真实第三方 Agent 端到端读取（#100）未做，目前只有测试层与 stand-in；跨模型真实读数未取；
MCP 工具粒度鉴权未做；D-1（Responses 工具续轮被复用短路）与 D-2（来源结算与复用互斥）
按裁定推进中。

证据：AGENT-ACCESS §4 全表；`STAGE1-GAP-MATRIX` §4.8、§4.11、§4.14。

---

## 2. README 改动清单（按行号区块，草案文本）

以下全部是**替换/插入文本**，未写入文件。行号对应当前工作区 `README.md`（615 行）。
`<<VERSION>>`、`<<BUILD>>`、「启动服务」的具体菜单文案以 D4 与实机为准。

### R-1　`:24-43`：下载区（替换整块）

```markdown
## Download — v<<VERSION>> Managed Agent Integration Preview

当前公开 DMG：

```text
https://github.com/slamfinger/SimiGo/releases/tag/v<<VERSION>>
```

| Asset | Requirement | Checksum |
|---|---|---|
| `SimiGo-v<<VERSION>>-<<BUILD>>-<hash>.dmg` | Apple Silicon macOS 26.4+ | 见 Release 页面 |

该 DMG 使用 **ad-hoc signature**，未做 notarization。首次打开若被 Gatekeeper
拦截，请先校验 Release 页面 SHA-256，再移除 quarantine 属性：

```bash
xattr -dr com.apple.quarantine SimiGo.app
```

不要绕过校验直接运行来源不明的副本。
```

### R-2　`:45-53`：Quick Start「下载运行」（替换整块，新增两条接入路径）

```markdown
## Quick Start

### 下载运行

1. 从 [v<<VERSION>> Release](https://github.com/slamfinger/SimiGo/releases/tag/v<<VERSION>>)
   下载 `SimiGo-v<<VERSION>>-<<BUILD>>-<hash>.dmg`。
2. 校验 Release 页面的 SHA-256。
3. 拖入 `/Applications`，打开菜单栏 SimiGo，并在菜单栏启动 HTTP 服务
   （监听 `127.0.0.1:8000`，端口可在设置中修改）。
4. State Graph 入口：菜单栏 → **Execution State Graph...**。

### 接入 Agent

- **本地 Agent（方式 A）**：把 OpenAI-compatible base URL 指向
  `http://127.0.0.1:8000/v1`。之后每轮自动完成 ES 前置、IS 检索、命中即 0 调用复用与原子结算；
  请求带稳定的 `session_id`（或 `thread_id` / `agent_id`）以获得跨轮「同一问题」判定。
- **云端 Agent（方式 B）**：保留它自己的云端 API，把 MCP 端点
  `http://127.0.0.1:8000/mcp` 加入其配置，按 begin →（复用或云端调用）→ settle 接线。
  **MCP 连通不等于结果已记录**：只有 `simigo_es_settle` 成功才写入权威结算。

完整字段、复用条件与工具合同见 [docs/AGENT-ACCESS.md](docs/AGENT-ACCESS.md)。
```

### R-3　`:11-22`：核心能力列表（在 `:22` 后插入三条）

```markdown
- 受管 Agent 入口：Chat Completions / Responses 在生成前解析 ES demand、检索 IS，命中已结算结果即 0 调用复用
- 云端 Agent 经 MCP 参与同一套 ES/IS 生命周期（begin / search / settle / fail / settlement 读回）
- 声明的兼容旁路：`/v1/completions` 不做受管治理，响应固定带 `simigo.managed=false`
```

### R-4　`:193-230`：当前阶段与状态表（替换整块）

```markdown
**当前阶段：v<<VERSION>> Managed Agent Integration Preview，不是 GA。**

已发布二进制上完成的是**安装版真实模型**的受管请求、结算写入与复用读回；
测试层的合同套件读数不等同于安装版验收。目前不宣称为生产级通用推理 Runtime，
也不宣称已经完成 Backend-independent Runtime。

## 1. 当前状态

| 项目 | 当前状态 |
|---|---|
| Version | `v<<VERSION>>` (build <<BUILD>>, tag `v<<VERSION>>`) |
| Stage | Managed Agent Integration Preview |
| Platform | Apple Silicon macOS |
| Minimum macOS | 26.4 |
| Primary execution substrate | MLX / `mlx-swift-lm` |
| Reference carrier | `R_Reference_v1` |
| API | OpenAI-compatible（受管：`chat/completions`、`responses`；声明旁路：`completions`） |
| Agent 接入 | 方式 A 本地模型 OpenAI-compatible 入口；方式 B MCP 生命周期 |
| Answer reuse | 已实现；默认态 `<<D1 裁定>>` |
| MCP | 九个工具，`POST /mcp`（无状态 Streamable-HTTP 子集） |
| Oversized model validation | Qwen3-Coder-Next-4bit |
| Oversized validation machine | 32 GiB Apple Silicon |

当前公开证据已经覆盖：

- Execution State 生命周期与连续性
- Fork / Restore / Reattach / Discard / Release
- Save / checkpoint 与 fail-closed restore（v2.1 reference app）
- Oversized Model 执行
- Segment-level physical residency
- Cancellation
- Runtime consistency contract
- Residency / physical-state reconciliation
- Durable Execution State checkpoint integrity
- Cross-session Prefix Reuse 与物理 retention
- Release suspend / resume lifecycle consistency
- Failure Matrix 全量审计
- ES/IS 受管入口：demand 解析、IS 检索、0 调用复用、原子结算（`docs/AGENT-ACCESS.md`）
- 云端 Agent MCP 生命周期：begin / search / settle / fail / settlement 读回
- KV-free 有限范围验证（K1–K3、默认关闭；结论绑定具体二进制与模型）

最新 Failure Matrix 结果（2026-09 审计范围）：

> **P1 = 0**

剩余项目已经分类为 Beta boundary、GA work item 或 product scope。
```

### R-5　`:557-561`：「当前工作」（替换三条）

```markdown
### 当前工作

- 阶段 1/2 接入能力的发布收敛（安装版真机复验、文案与文档同步）
- 受管复用的两处边界裁定与修复：Responses 工具续轮短路（D-1）、检索来源结算与复用（D-2）
- provider adapter 评估（Ollama / LM Studio 作为上游），按 R2-A 暂缓，先完成真实第三方 Agent 接入
```

### R-6　`:498-509`：文档表（插入一行）

```markdown
| `docs/AGENT-ACCESS.md` | Agent 接入说明：受管入口、复用条件、MCP 生命周期与首版边界 |
```

### 不建议动的地方（明确保留）

- `:108-139` 的 v2.1.0 章节：作为历史 reference app 记录保留，但标题已标明版本，不再作为下载入口；
- `:141-166` 的 v2.0 能力：同上，属已发布历史；
- `:589-605` Long-term thesis 与 `:573-587`「SimiGo 不是什么」：均为边界声明，随新能力只做加法不做删改；
- `:81-103` 测试隔离警告：仍准确，且与本次发布的「测试产物 ≠ DMG」口径一致。

---

## 3. GitHub Release 正文草案（下一版）

沿用 v2.2.1 的既有版式（Date / Build / Tag / Platform / Code signing → Artifact →
what was actually verified → explicitly not verified → changes → diff），不搬历史实验过程。

```markdown
# v<<VERSION>>

Date: <<DATE>>
Build: `<<BUILD>>` (`CFBundleVersion`)
Tag: `v<<VERSION>>` → `<<COMMIT>>`
Platform: Apple Silicon macOS
Code signing: ad-hoc (`Identifier=SwiftUI.SimiGo`, `TeamIdentifier=not set`). Gatekeeper will
refuse a plain double-click on first launch — use right-click → Open, or
`xattr -dr com.apple.quarantine /Applications/SimiGo.app`.

## Artifact

| File | Size | SHA-256 |
|---|---|---|
| `SimiGo-v<<VERSION>>-<<BUILD>>-<hash>.dmg` | <bytes> | `<sha256>` |

## What's new

### 1. Local Agents enter managed execution (mode A)

Point any OpenAI-compatible client at `http://127.0.0.1:8000/v1`. Each managed turn
(`chat/completions`, `responses`) resolves an ES demand, retrieves the Information Space,
reuses an already-settled answer with **zero model calls** when the same question in the same
scope is still valid, and otherwise generates and settles atomically. `/v1/completions` is a
**declared bypass** — its responses always carry `simigo: {"managed": false, ...}`.

### 2. Cloud Agents keep their own API, join the same information space (mode B)

`POST /mcp` exposes nine tools for the execution lifecycle: `simigo_es_begin`, `simigo_is_search`,
`simigo_es_settle`, `simigo_es_fail`, `simigo_is_settlement`, and the carrier tools.
Connecting is not recording: only a successful `simigo_es_settle` produces an authoritative,
reusable answer settlement; retrieval settlements (`is-retrieval:<demand_id>`) can only be cited
as a source, never served as an answer. <<D6: 若 D-2 未修，此处追加：search → settle(with source)
→ begin 目前拿不到 reusable_answer；替代是 settle 时给 session_id + query 而不带 demand 引用。>>

### 3. Answer reuse

Reuse requires all four gates: an `ADVANCED` demand for the identical question in the same scope,
a still-valid answer settlement, still-valid retrieval settlements (if any), and a matching
producer model/tokenizer identity. Reuse is a read: no new settlement, no new ES state, and the
response reports `model_calls: 0`. Default state: `<<D1 裁定>>`.

### 4. Persistent KV: what is actually verified

In the verified range, persistent KV is not a precondition for semantic continuity, settled-result
consumption, suspend resource release, or cross-process continuation (K1–K3, default-off readings
on the binaries named in the research record). This is a bounded claim about those binaries and
models — not a general backend-independent guarantee.

### 5. Still in development

- Provider adapters (Ollama / LM Studio as upstream providers) — deferred (R2-A).
- Real third-party Agent end-to-end adoption — test-layer evidence only so far (#100).
- Cross-model real-engine identity readings; MCP per-tool authorization.
- Batch scheduling (concurrency 1 / 2 / 4) — not started.
- Two managed-reuse edge cases are registered and pending ruling: Responses tool-continuation
  short-circuit (D-1) and retrieval-sourced settle vs reuse (D-2).

## What was actually verified on this binary

<<D3 之后填写，格式与 v2.2.1 相同：进程身份、服务响应、结算写入与复用读回、真实模型时延。
在填写前本节必须写「pending」，不得沿用 v2.2.1 的读数。>>

## Explicitly not re-verified on this executable

- <<按 D3 结果如实列出，例如 KV-free K1–K3 的二进制身份、GUI 目视项、多租户/非 Apple Silicon。>>

## Changes in this release window

<<按 D4 的逻辑提交清单填写（与仓库 git log 一致，不手工润色摘要）。>>

## Diff since v2.2.1

https://github.com/slamfinger/SimiGo/compare/v2.2.1...v<<VERSION>>
```

---

## 4. 声明 → 证据 checklist（发布前逐条打勾）

| # | 对外句（将要写进 README / Release） | 证据位置 | 状态 |
| --- | --- | --- | --- |
| C1 | 受管入口 chat/responses 前置 ES demand、检索、复用、原子结算 | AGENT-ACCESS §2.1–§2.4；代码 §4.3.5；§4.13.1 用例 4/4 | 有 |
| C2 | 复用四条件与「复用是读」 | AGENT-ACCESS §2.4、§2.5 | 有 |
| C3 | `/v1/completions` 声明旁路 `managed=false` | AGENT-ACCESS §2.1、§2.5；实现已核对 | 有 |
| C4 | 作用域解析键与「身份是声明」 | AGENT-ACCESS §2.3、§4 | 有 |
| C5 | MCP 九工具与传输语义 | AGENT-ACCESS §3.1–§3.2；§4.12 9/9 | 有 |
| C6 | settle 是唯一可复用结算写入点；检索结算不可复用 | AGENT-ACCESS §3.4；DB 合同测试 | 有 |
| C7 | 「MCP 连通 ≠ 已记录」 | AGENT-ACCESS §3.4 | 有 |
| C8 | 检索→结算→复用闭环 | **D-2 未修时不成立**（§4.11） | **阻塞（D6）** |
| C9 | 复用默认态 | 代码默认开 vs R1-A 默认关（§4.9 D1） | **阻塞（D1）** |
| C10 | 受管复用不截断工具轮（Responses） | **D-1 未修时不成立**（§4.8） | **阻塞（D5）** |
| C11 | KV-free 有限范围结论 | C6D 验收 + KV-free 测试层两档文档 | 有（限定式） |
| C12 | Release 构建上合同一致 | §4.13.2 51/51（testability Release） | 有（仅测试层） |
| C13 | 安装版真实模型读数 | v2.2.1 有；**新构建没有** | **阻塞（D3）** |
| C14 | 第三方 Agent 真实接入 | #100 未做 | **不可写** |
| C15 | provider adapter | R2-A 暂缓 | **不可写「已支持」** |
| C16 | 批处理并发 1/2/4 | 阶段 5 未启动 | **不可写「已支持」** |

同时刻意的**负面句式**（发布文案与 README 必须保留其一，防止过度声明）：

- 「进程内直接加载模型的 Agent 不构成接入，这是声明的不支持边界」；
- 「测试产物 ≠ 可发布 DMG；测试层读数 ≠ 安装版验收」；
- 「复用只发生在本机受管入口；远端后端转发与 `/v1/completions` 不参与治理」。

---

## 5. 与待裁定的映射（发布阻塞项）

| 裁定 | 影响本草案的哪几行 | 若不先裁定 |
| --- | --- | --- |
| **D1**（`SIMIGO_IS_ANSWER_REUSE` 默认态） | R-4 状态表 `Answer reuse` 行；Release §3「Default state」 | 文案只能写「默认开，`=0` 可关」，与 R1-A 冲突或与代码不符 |
| **D2**（删除两份孤儿草稿） | 仅影响 §11 文档表是否列它们；本草案默认不列 | 无阻塞 |
| **D3**（安装版真机复验） | Release「What was actually verified on this binary」整节 | 该节只能写 pending，等于没完成发布验收 |
| **D4**（提交/推送/发版） | 版本号、Tag、Changes 清单、Diff 链接 | 全部占位符无法落地 |
| **D5**（D-1 修法） | Release §5 的 D-1 句；README 不写 | 发布文案须保留「Responses 工具续轮可被复用短路」的已知缺陷声明 |
| **D6**（D-2 修法） | Release §2 追加句、C8 | 发布文案须保留「检索→结算→复用当前不可用」的已知缺陷声明 |

如果 D4 决定「先发布、缺陷后修」，本草案仍然可用，但必须把 C8/C10 的负面声明写进
Release 的 *Still in development*，且 README 的 `docs/AGENT-ACCESS.md` 链接保持在 §3.6 注
（该注已是当前事实）。不允许删注换发布。

---

## 6. 本草案没有做的事

- 没有修改 `README.md`、`docs/AGENT-ACCESS.md` 或任何产品代码；
- 没有提交、没有打标签、没有推送、没有构建 DMG、没有触碰 `/Applications/SimiGo.app`；
- 没有把 §4.13.x 的测试层读数搬进 ACCEPTANCE 文档或 Release 正文；
- 没有为发布引入新证据口径：所有可写句都指向既有文档或既有记录。
