# ADR: Ingress Canonical IR（语义适配层·codex／qoder／zcode）

- 状态：Accepted（实现层待接入，见「落地边界」）
- 日期：2026-11-28
- 票：L35（owner 明令「开始IR语义适配层，适配codex、qoder、zcode」）
- 承：owner 裁定 00142793（2026-11-24，三层架构）＝L1 wire 用事实标准（OpenAI-compatible）不重造；**L2 语义结构无标准、必须自建 IR**；L3 chat_template.jinja 不碰
- 新件：`SimiGo/Protocol/IngressIR/IngressCanonicalIR.swift`＋`IngressAdapters.swift`＋`SimiGoTests/IngressIRTests.swift`（写集＝纯新文件，零行接入改动）

## 一、采样证据（步①，只读）

来源＝生产库 `chat_messages`／`chat_turn_ledger` 只读聚合＋trace 形状统计＋三入口读码：

1. **DB 持久层只有 user/assistant 两 role**（9,372/8,935 行，0 条 system/tool）——tool 结构在 settle 层被剥（`SETTLE_SKIP reason=tool_calls`），历史语义结构只活在 wire 面。这正是 00142793 所指「真正的异构所在」的实证。
2. **入口分布**（trace 全量）：`endpoint=chat.completions` 2,205 轮／`endpoint=responses` 35 轮（codex 线）；MCP 线 origin=mcp 5,857 轮（turn ledger）。
3. **tool 面**：模型输出 tool_calls 270 轮（1 次 270／2 次 7／5 次 1）；入站 tool 消息 95 轮（toolB>0）；但 `tools` 数组声明 toolSchemas>0 为 **0 轮**——tool 声明在各入口的归属形状不一，是异构的又一实证。
4. **消息数分布**：msgs=1 395 轮（脚本单轮）→ msgs≥14 多轮会话，两形态并存。
5. **Responses 线实况**：codex 送 developer role 与 `function_call_output` items（缺陷档 719CC23A 的 4×developer 形状）；现有实现把 `function_call_output` 归一成 `role:"tool"` 的 chat 形（HTTPServerResponses.swift:1069 注释自述）——**产品已有事实上的 canonical（chat-form messages），本 ADR 把它定名并最小化**。

## 二、最小字段集（步②）

| 概念 | IR 形态 | 说明 |
|---|---|---|
| role | `IRRole = system｜developer｜user｜assistant｜tool` | 五值闭集；超集显式拒绝 |
| 文本面 | `content: [IRContentPart]?`（现行仅 `.text`） | string／parts 两 wire 形态归一；nil＝无文本面 |
| tool 调用 | `toolCalls: [IRToolCall]?`（call_id／name／argumentsJSON） | arguments **逐字保留**，不重排不重渲染 |
| tool 结果 | `toolCallID`＋role=.tool | Responses `function_call_output` 同形归一 |
| 工具声明 | `tools: [IRToolSpec]`（name／description?／parametersJSON） | chat 嵌套形与 Responses 平铺形归一；非 function 类型显式拒绝 |
| 会话 | `IRConversation(messages, tools)` | system／developer 由消息 role 承载，不设独立字段 |

**超集处理＝fail-closed**：unsupportedRole／unsupportedContentPart／unsupportedInputItem／unsupportedToolType／missingField／malformedMessage 六类错误显式抛出（各带样例单测）。image part、reasoning item、web_search 等非 function 工具、MCP isError 等「最小集外」形状一律不静默降级——扩集是显式裁定，不是 adapter 的顺手事。

## 三、三 adapter（步③）

| adapter | 线 | 归一规则要点 |
|---|---|---|
| `ChatCompletionsIngressAdapter` | qoder／zcode／owner 脚本 | content string↔parts 双形态；tool_calls+tool_call_id；tools 嵌套 function |
| `ResponsesIngressAdapter` | codex | `instructions`→system 消息；items 三类（message／function_call／function_call_output）；input_text／output_text／text 三 part 形态 |
| `MCPIngressAdapter` | MCP（tools/call） | 非会话型：`(name, arguments)→text 块` 工具交互片段；isError 为投递面元数据不入消息层（结算/错误另有记账） |

## 四、字节稳定性（步④）

`IRConversation.canonicalBytes()`＝`JSONEncoder`＋`sortedKeys`＋紧凑 UTF-8：同一 conversation 恒产同一字节串。自测四条（IngressIRTests）：

1. 同 conversation 重复编码 4 次逐字节同；
2. **跨 adapter 等价正控制**：chat 形与 responses 形表达**同一会话** → IR 全等且 canonicalBytes 全等；
3. wire 键插入序不同（重排 JSON）→ canonical 输出不变；
4. tool parameters schema 键序不同 → canonicalJSON 相同。

## 五、落地边界（本票不做）

- **零接入**：不动 `HTTPServerChat.swift`／`HTTPServerResponses.swift`／`HTTPServerMCP.swift` 现有解析（含 14 项他窗在飞脏改）；adapter 是独立库层，接入另立票。
- 不装机、不占 :8000、不跑模型；`model_calls=0`、`scientific_result=false`。
- digest 移植到 ES/MCP 消费路径（00142793 语义结构在 ES 侧的替换层）属 L36 步③，候 owner。
- 备选未取：为每个客户端各建一套 wire（重造 L1）——违 00142793；把 IR 直接绑在 JSONValue 上（丢掉字节稳定面与拒绝面）——违最小集原则。
