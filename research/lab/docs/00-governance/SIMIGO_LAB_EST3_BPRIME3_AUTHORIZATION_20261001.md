# ES-T3 T3-B′-2 判读裁定 + T3-B′-3 授权（含预注册读数）

日期：2026-10-01  
状态：`BPRIME2_VERDICT_EXECUTED_UNINFORMATIVE / BPRIME3_AUTHORIZED / GATES_C-D_LOCKED`  
裁定人：human（B′-2 替代设计与 Gate C/D 决定权按 424b07b/ab20168 移交条款
收回行使）

## 1. 裁定一：B′-2 = EXECUTED-UNINFORMATIVE

B′-2（`ab20168`）双侧「0 文本」使 LCCP 度量退化为平凡恒等。
**`LCCP=0` 不得当成解释 A（state 未挂载/不敏感）的证据**——恒等来自
观测截断（tool-call 通道与 token 层产物未记录），不来自 b0/b3 无差异
本身的证明力。B′-2 终态 = EXECUTED / UNINFORMATIVE（已如实落档
`SIMIGO_LAB_EST3_B2DIFF_LIMITATION_20260930.md`），不升格、不引用为
A/B 任一方的支持。

## 2. 裁定二：下一步 = (c) = (a)+(b)，严格拆成两个目的

一次实验同时消掉两个混淆变量，但两目的分别读数、不得混算：

```text
目的 1【观测面扩展】  记录 toolCalls 与 finishReason 功能等价面
                      （本栈无 finishReason 直接暴露：以 onToolCall
                      回调 + GenerationResult.usage.generationTokens
                      + 流正常结束位 作其判别功能替代，如实落档），
                      先确认 b0/b3 的「0 text」是否 = 产物走了
                      tool-call channel
目的 2【换 probe】    采用已知产生 anchored text、不自然触发工具调用
                      的 probe（E3-C0 逐字先例：「PALACE-1 E3 probe:
                      这个会话此前在做什么？用一句话概括。」），
                      重做 b0/b3 对照
```

执行面：同 GT Gate B fixture（`/tmp/simigo-palace1-e1/esr2/t3gateB`
b0/b3），四 cell = {b0,b3} × {listing, summary}，逐 cell 独立
loadSessionCache restore；greedy（temperature 0，maxTokens 128）；
`tools: nil` 与 B′-2 一致；隔离配方同前（restore 关、真实
`~/.simigo` 不动，branch-checkpoints 204 前后核验 + prefix-pool
条目计数如实记录）。

## 3. 预注册读数（执行前锁定）

```text
P-1 观测面判定（listing 对）：generationTokens>0 且 toolCalls>0 且
    text=0  ⇒ 「0 文本 = tool-call 通道产物」成立，B′-2 观测截断
    混淆坐实
    generationTokens>0 且 toolCalls=0 且 text=0 ⇒ 第三机制（流式
    过滤吞没，如 thinking 滤除）登记为新候选
    generationTokens=0 ⇒ 模型未产出 token（即刻 EOS）
P-2 差分判定（summary 对）：b0 vs b3 text 逐字比较 + LCCP
P-3 锚定 sanity（summary-b0）：对照 E3-C0 ANCHORED 先例做存在性
    核对（管线不同：KV+state fixture vs E3 meta-only——只做
    sanity，不做复制声明）
```

## 4. 强制限制条款（裁定原文登记）

> 如果 (c) 之后 b0/b3 仍然恒等，最多说明**当前 probe 下没有观察到
> GDN 差异**；不能直接升级成「GDN 不参与 continuation」的结论。

（对 P-2 的恒等读数同样适用：恒等 = 限缩观察，非机制否定。）

## 5. 裁定三：E3-C-2 对照差异 = 仅登记观察

ES-R2 Gate C attempt 2（无上下文时模型明示索要：「请提供具体的上下文
或任务指令」）与 PALACE1 E3-C-2（主题缺席时模型从 persona 先验自信
虚构）的差异**只登记为观察，不注册为独立结论**——persona、残留上
下文、probe 形式与生成路径均未受控，现在升格为机制解释会把 ES-T3
从「追踪实际消费链」带向另一条实验支线。

## 6. 当前门位

```text
ES-T3
├─ A    = CLOSED（A2 CONFIRMED + A3 PARTIAL in-memory only）
├─ B    = CLOSED（verdict B-3；b3 异常 A/B 双解释未证）
├─ B′-1 = PARTIAL / INCONCLUSIVE（424b07b）
├─ B′-2 = EXECUTED / UNINFORMATIVE（ab20168；本文件裁定一）
├─ next = B′-3（本文件授权；观测面扩展 + 非 tool-call 敏感 probe）
└─ Gate C/D = LOCKED（不变）
```

## 7. 禁止事项

```text
❌ B′-2 的 LCCP=0 被引用为解释 A 证据
❌ B′-3 恒等读数升格为「GDN 不参与 continuation」
❌ E3-C-2 对照差异升格为机制结论或新实验支线
❌ 开启 Gate C/D；完整 History 引入；新 schema/API/persistence
❌ 破坏真实 ~/.simigo；性能 claim
```
