# SimiGo v2.2.7 发布说明

## 一、版本

| 项 | 值 |
| --- | --- |
| 版本 / 构建号 | 2.2.7 / 1 |
| 版本性质 | 正式发布；此前各版本的应用内说明为草稿记录 |
| 分支 / 提交 | `main`；发布时以 tag 指向的提交为准 |
| tag | `v2.2.7` |
| 平台 | Apple Silicon macOS 26.4+ |
| 产物 | `SimiGo-v2.2.7-1-<exe8>.dmg`（exe8 为可执行文件 SHA-256 前八位） |
| 签名 | ad-hoc，未公证；首次打开需绕过 Gatekeeper |

## 二、SimiGo 是什么

SimiGo 是一个围绕 **Execution State（ES）** 与 **Information Space（IS / PALACE）**
的本地 AI 运行时。它研究的不是缓存留多久，而是一个更基本的问题：

> 模型已经完成的一段计算，能否脱离原模型进程与旧 KV Cache，在新的执行链里被
> 验证、恢复并继续使用？

在这个产品里，「算过」不再等于「模型还开着、上下文还在、KV 还驻留」。一段完成
的计算被写成一个**可再判的结算对象**：

```text
R = payload + 来源 + 版本 + 依赖闭包 + 有效性依据 + 语义合同
```

新的执行要使用它，必须重新通过准入：

**完整性 ∧ 有效性 ∧ 依赖闭包 ∧ 语义合同 ∧ 权限策略**；只有恢复物理 KV 表示时，
才额外要求**表示兼容**（模型、tokenizer、KV 布局、命名空间、前缀边界）。

生产者身份是溯源，不是语义门：同一个模型不证明结果仍然有效，不同的模型也不证明
结果失效；只有当任务显式声明「必须由某个模型、环境或工具版本产生」时，身份才成为
一项依赖。

## 三、三个权威边界

| 层 | 职责 | 不是 |
| --- | --- | --- |
| **ES — Execution State** | 执行身份、lineage、位置、分支、continuation；决定执行如何继续 | KV Cache、模型进程、聊天记录 |
| **IS — Information Space** | 保存已结算结果及其来源、版本、依赖、有效性、消费记录 | 第二套执行权威、无条件向量缓存、普通对话历史 |
| **Backend / carrier** | 承载实际计算与物理状态：MLX、llama.cpp、模型进程与 KV | 结果语义、ES 身份、IS 的有效性裁决 |

数据库只负责保存与校验，不替模型判断语义充分性，也不自行推进执行。

## 四、本版实现的能力

### 4.1 执行状态（ES）

七操作生命周期：`create / continue / save / fork / restore / discard / release`，
在「执行状态图」窗口里以 State 为顶层对象操作。

- 检查点原子落盘：`save` 固定当前语义闭包，不产生新的语义状态。
- `restore` 失败即封闭：身份、模型绑定、锚点、记录校验任一不符即拒绝。
- `fork` 保留父：子值拷贝父在分支点的闭包，父不受影响。
- `discard` 原子移除检查点绑定，不留幽灵续接；`release` 只清持久绑定，不废除
  逻辑状态。
- 分支另有 HTTP 面：`/v1/branches/{fork,list,delete}`，持独立权限。

### 4.2 信息空间（IS）

- **结算对象**：结果、来源、版本、依赖闭包、有效性依据、合同一体写入；对象按
  内容寻址（`object_id` 由内容派生），改一个字节就是另一个对象。
- **依赖**：每条依赖带时间区间，可回溯任一时刻的地址；依赖变更即触发下游失效
  与重算判定。
- **校验与修复**：`reconcile` 按根重算有效性，文件变了就产出新结算，根不见了
  只做标记、不清索引。
- **检索**：`searchSettledContent` 在已结算内容上按词检索，返回可引用的片段。
- **失败审计**：被拒绝的消费以类型化理由落审计，结算写入为 0。
- **库内房间**：见 4.4。

### 4.3 复用与消费的三条路径

同一次「答案已经有了」的请求，落点有三处，区别是**是否发生模型调用**、**是否
诞生可再判的结算**：

| | 未诞生结算 | 诞生结算 |
| --- | --- | --- |
| 零模型调用 | 只读应答复用 | 消费（新谱系 + 声明合同 + consumer 状态） |
| ≥1 次模型调用 | 拒绝（类型化失败审计） | 生成 / 续接（子执行状态） |

释放模型进程与 KV、再从全新的执行状态消费已结算结果，已在 MLX 与 llama.cpp
上演练过；尚待补齐的是每个后端上可复现的读数。

### 4.4 轮次进库：摘要、关键词、房间

- 新轮次进库即补**摘要**与**关键词**（本地模型），只在空窗运行：有人用模型就让位，
  待办队列上限 64 轮 / 1 MiB，超出等下一个空窗。
- 每轮按内容判据进房间，**每轴最多一个房间**：项目轴（`project`）、性质轴
  （`nature`）、兜底（`fallback`）；两轴可各挂一个，这是平铺加轴，不是嵌套。
- 判据不写死客户名：产品自身轴写在代码里，目录房间的判据从库里读（目录名不进
  开源仓）。
- **房间维护在房间这一层**：新建、改名、多选合并、删名并把归属交给别的房间、
  把工作目录挂到房间下。轮次归属没有人工入口——它由判据决定。
- **合并保留判据**：合并把源房间的判据词记成目标别名（`space_room_aliases`），
  这些词的命中继续算在目标头上，下一次判断不会把源房间造回来；合并链跟随到最新
  目标。人建的无判据房间不记别名。

### 4.5 采集与时间

- **信息采集**：一个按钮管两件事——把所选目录里的会话搬进库，同时把该目录记为
  时间回填的来源。
- 识别格式：Markdown 会话导出、Codex 日志、ChatGPT 导出、Google AI Studio、
  DeepSeek `conversations.json`、flat 导出。
- **来源时间**：只写 `source_time`，能从会话 id 认出来的按 id，认不出的按导出
  文件兜底，不改其他列。
- 采集完立即判房间，新轮次不等人工操作即被认识。

### 4.6 服务与接口

- **本地 HTTP**（默认 8000）：默认只绑定回环 `127.0.0.1`，仅本机可访问。
- **路由**：`/health`、`/v1/models`、`/v1/chat/completions`、`/v1/completions`、
  `/v1/responses`、`/v1/branches/{fork,list,delete}`、
  `/v1/simigo/{env,roots,search,is/{status,settlement,dependency,file,object,reconcile}}`、
  `/mcp`。未列出的路由一律拒绝（fail-closed）。
- **MCP 12 工具**：`simigo_is_search`、`simigo_is_status`、`simigo_roots_list`、
  `simigo_root_register`、`simigo_is_reconcile`、`simigo_is_settlement`、
  `simigo_es_begin`、`simigo_es_settle`、`simigo_es_fail`、`simigo_chat_round`、
  `simigo_project_brief`、`simigo_project_note`。
- **授权**：每条路由一个固定权限——推理 → `P-INFERENCE`；检索、根目录、`/mcp`
  → `P-SRS-WRITE`；结算 / 依赖 / 对象 / 状态读 → `P-INFO-READ`；分支三条 →
  `P-BRANCH-CONTROL`。权限从不取自请求头、查询参数或 JSON 字段。
- **回环明文的例外**：主端口以明文兼容方式监听时，回环连接对 `P-INFERENCE` /
  `P-INFO-READ` / `P-SRS-WRITE` 免签名证明，响应带 `unprotected-by-LOCALB`。
  `P-BRANCH-CONTROL` 不在其列：分支操作在任何传输上都要走完整的
  challenge → 签名 → 消费。默认 `.secure` 模式下主监听是 TLS，这个例外不出现。
- **宿主常驻**：无模型时信息空间宿主占用 8000（`/health` 报
  `simigo-information-space`，推理路由拒绝）；启动模型自动接管 8000，停止模型
  自动回落宿主，不需要手动切换。

### 4.6.1 局域网模式与调用凭证

- **开关**：菜单可切「局域网」模式，生效后绑定 `0.0.0.0`，并通过 Bonjour
  （`_http._tcp`）广播服务名。
- **传输**：非回环连接上的明文一律被拒——在监听层拒绝，不是策略层放行后再拦；
  必须走 TLS。明文连接不具备任何配对 / 证明资格。
- **凭证**：受保护路由的请求必须携带 `x-simigo-localb-client-key-id`、
  `x-simigo-localb-challenge`（32 字节）、`x-simigo-localb-proof-v2`（64 字节签名）。
  服务端先确认传输是 TLS，再查客户端公钥注册表，最后按路由权限表裁决。
- **注册表**：客户端公钥登记在追加式账本（`.localb-registry.events`）加一份离线
  checkpoint（`~/.simigo/localb/trusted-checkpoint.json`）里；可登记、可改状态
  （`ACTIVE` / `RETIRED` / `LOST` / `REVOKED`，迁移单调，`REVOKED` 为终态）；
  凭证带过期与 TLS SPKI 钉。
- **登记第二台设备**：图形界面里没有入口；命令行有——
  `SIMIGO_LOCALB_MGMT=pair-issue`（配 `SIMIGO_LOCALB_CLIENT_PUBKEY_HEX`）与
  `pair-approve`（配 `SIMIGO_LOCALB_CREDENTIAL_ID` / `SIMIGO_LOCALB_SECRET_B64URL` /
  `SIMIGO_LOCALB_CLIENT_PUBKEY_HEX` / `SIMIGO_LOCALB_PAIRING_PROOF_HEX` /
  `SIMIGO_LOCALB_TLS_SPKI_HEX` / `SIMIGO_LOCALB_SRS_KEY_ID`）。默认只在隔离的
  `SIMIGO_HOME` 下生效，要动真实家目录须显式加 `SIMIGO_LOCALB_ALLOW_REAL_ROOT=1`。
- **信任前提**：单机、单人、局域网可信。开放局域网等于把你的信息空间对能证明身份
  的那台机器开放可读（`P-INFO-READ`）与可写（`P-SRS-WRITE`）。放不放、放给谁，
  由你决定并自担。

### 4.7 模型后端

- **Native MLX**：内置运行时，无需外部依赖。
- **llama.cpp**：GGUF；可检测已装、按锁定版本重建、或采用外部服务端；不执行
  `curl | bash`，未安装官方 `hf` 时不自动安装。
- 加载走**文本优先**：先尝试文本工厂，仅当失败且检查点是复合 VLM 布局时清缓存
  回退 VLM 工厂；两条都失败时错误同时携带两条信息。

### 4.8 设置与运维

三页：设置（模型与服务）、信息空间（工作目录、缺口与补录、库内房间、采集回执）、
版本（版本号、仓库去处、升级影响）。

- **缺口驱动**：状态刷新数四个缺口（轮账、时间、摘要、关键词），看到缺才出现
  「开始」；一次按序跑完四步并以房间归属收尾；「停止」可中途打断正在进行的生成。
- **收尾**：补录完成行、采集回执、命令控制台的执行/下载/构建/记录状态到点自动收；
  成功的收，失败的留。

## 五、系统要求与安装

- Apple Silicon，macOS 26.4 及以上。
- 打开 DMG，把 `SimiGo.app` 拖入 `Applications`；首次运行需在「系统设置 → 隐私与
  安全性」放行（ad-hoc 签名，未公证）。
- 首次运行向导会建立外部工作目录、检测或构建 llama.cpp、写入默认配置。

## 六、证据状态（2026-11-13，本机）

| 项 | 结果 |
| --- | --- |
| 包测试 `swift test`（`Packages/SimiGoRuntime`） | 420 例，0 失败（416 契约 + 4 实验） |
| 应用构建 `xcodebuild -scheme SimiGo -configuration Debug` | 成功 |
| GitHub Actions `main` | run 650（提交 `97cff10`）9/9 通过 |
| 真库（记录时刻） | 3,225 轮；`space_turns` 3,558 行；`turn_digests` 3,225；房间 6 个（含 2 个目录房间） |
| 房间合并演练（库副本） | 合并前 380 / 353（SimiGo / 信息空间），合并后 696 / 0；重复执行结果不变 |

真库数字随应用运行时的增量写入变化，上表是记录时刻的读数，不是不变量。

## 七、已知限制

- 未做 Developer ID 签名与公证。
- 房间面板「合并」的端到端路径未在真实库上执行：合并演练走脚本实现，Swift 侧
  `mergeSpace` 目前只有单元测试。
- 停止按钮对真实生成的打断、队列上限、让位路径，只有代码与单元测试。
- 一次性回执的收尾时序未做真机计时验证。
- 全量重算未在真库执行。
- 每个后端「跨执行边界消费」的可复现读数尚未成文。
- 局域网模式下为第二台设备登记客户端公钥没有图形入口；命令行入口见 §4.6.1
  （`pair-issue` / `pair-approve`，动真实家目录须 `SIMIGO_LOCALB_ALLOW_REAL_ROOT=1`）。
- 局域网模式的端到端路径（TLS 握手、Bonjour 发现、签名证明消费）在 1.x 版本上
  跑通过，只是当时没有把它作为一条独立验收项写进文档；本版未重跑这条路径，
  回环路径不受影响。

## 八、文档入口

- 仓库：<https://github.com/slamfinger/SimiGo>
- 集成契约：`docs/AGENT-ACCESS.md`
- 术语正本：`docs/research/es-is/TERMINOLOGY_V0.1_20261109.md`
- 决策记录：`docs/decisions/`
- 许可与第三方声明：`LICENSE`、`THIRD_PARTY_NOTICES.md`
