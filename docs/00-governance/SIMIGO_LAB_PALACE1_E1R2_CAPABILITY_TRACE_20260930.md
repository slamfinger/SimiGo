# PALACE-1 E1-R2 Capability Trace — Client-Cooperative Recompute Path

日期：2026-09-30  
状态：`CAPABILITY TRACE COMPLETE / AWAITING SECOND-LAYER`  
性质：**只读代码追踪**——不运行、不修改、不碰 `~/.simigo`；回答唯一问题：  
> R2（丢失 Physical Representation 后重建可继续执行）所需的能力，
> SimiGo 现在到底有没有？  
基线：产品仓 `main @ dc12a0c`；上游：E1 interim（`dd825cb`）+ human 指令

## 1. 结论

```text
R2 所需能力 = 已存在，且是产品的一等公民路径（cold-start 分支）。
它不需要 checkpoint、不需要 pool、不需要任何新机制——
它就是无 checkpoint 时的正常会话建立方式。
```

## 2. 完整调用链（file:line）

```text
客户端（fragment-continuation 契约：每轮传全量对话）
  → HTTPServer /v1/chat/completions
  → NativeMLX.generate(messages: [JSONValue], …)          NativeMLX.swift:485-493
  → let incoming = Self.makeChatMessages(messages)        :641
  → generateUsingChatSession 会话获取三分支                :672-

  分支 1  live-session 复用（delta）                       :674-677
          条件 = 既有会话 + incoming.count > history.count
                 + kvFingerprint 相同 + isPrefix
          （本 E1 场景不可用：进程重启后 sessions 为空）

  分支 2  Route B 前缀池命中                               :713-762
          admit（消息流 token 链对账）→ load（sidecar 对账）
          → coveredMessages = tokenCount/2 → ChatSession(快照)
          → bindings.bind(executionID: storageKey, …)（FORK-3 step-9）
          失败自愈：回退冷路径，「绝不静默续算在未对账表示上」
          （本 E1 场景可选加速，非必需）

  分支 3  【R2 的答案】cold reconstruction                 :763-778
          let history = Array(incoming.dropLast())
          let session = ChatSession(container,
              history: history, generateParameters: …, tools: …)
          ManagedSession(historyJSON: Array(messages.dropLast()), …)
          state.sessions[storageKey] = managed
          —— 无 live session、无 pool 命中时的【正常】建立方式：
             同一 storageKey（同 branch）+ 全量 prefill + 继续生成
          后续：每成功轮自动 checkpoint（:1218-1224）重新落盘该分支
```

## 3. R2 依赖核验（对照 E1 判据）

| R2 所需 | cold-start 分支的供给 | 状态 |
|---|---|---|
| meta.history 作 history 源 | `makeChatMessages(messages)`——messages 由客户端给；meta.history 就是该数组的 durable 副本（E0：17 条逐字） | 已具备 |
| 同一 branch（storageKey 寻址） | `state.sessions[storageKey] = managed`——key 由 caller 传同一 sessionId/branch | 已具备 |
| 同源 model | container 由 `start(ModelInfo)` 加载；load 路径 modelId 同源校验先例（:1628-1631） | 已具备（E0 meta.modelId 可校验） |
| tool 消息回灌 | makeChatMessages/makeToolSpecs 既有；E0 实测 meta.history 含 tool×3 | 已具备 |
| full prefill（KV 重建） | 分支 3 构造即冷会话，首轮生成时全量 prefill（prefill progress trace :661-668） | 已具备 |
| 继续 generation | generate 正常返回；T-1 落新 checkpoint | 已具备 |

**R2 不需要**：safetensors、prefix-pool、forkPoint、kvFingerprint、
lineage、tombstone——冷路径一个都不读。

## 4. E1-R2 的诚实边界（trace 不能替代运行证据）

```text
本 trace 回答「能力是否存在」= 是（代码级 CONFIRMED）。
它不回答「实验执行」= R2 的运行时观测（prefill 实际发生、probe 轮实际
生成、T-1 实际重新落盘）仍需在隔离环境跑——阻塞点不变（E1 interim §2：
storage root 绑定 homeDirectoryForCurrentUser，沙箱不可叠加）。
R3 的记录等价比较与 R4 合成判定同样待运行。
另注：cold 路径成功后 T-1 会写【新】checkpoint 文件对——R2 执行的隔离
问题与 E1-R2 能力问题是两个独立问题（本次已把后者钉死）。
```

## 5. 研究含义（供第二层判断，不预答）

```text
① E1 的能力矩阵当前读法：
   R1 fail-closed（checkpoint 依赖表示）
   + cold-start 一等路径（continuation 不依赖 checkpoint）
   = 「原生 restore 依赖表示」与「可继续执行不依赖 checkpoint」
     在同一产品内并存——这正是 R4 想区分的两件事，代码已给出形状
② PALACE 语义研究的新输入：durable minimum 对 continuation 的贡献
   可能就是 meta.history + modelId（44KB），而非 4.7GB KV——
   KV 丢失后系统自发走 cold path（multi-GB → prefill 税），
   语义由 history 携带
③ E1-R2 的执行隔离仍是前置；三选项（加写/env 覆写/叶子沙箱）继续
   悬置待 human；本 trace 不改变其权衡
```

## 6. Non-claims

```text
✔ 只读（grep/sed）；零运行、零修改、零删除
✔ 代码级能力确认 ≠ 运行时实验证据；R2-R4 观测仍 PENDING
✔ 不修改 Contract；不设计 PALACE 语义；不关闭 OP/G
```
