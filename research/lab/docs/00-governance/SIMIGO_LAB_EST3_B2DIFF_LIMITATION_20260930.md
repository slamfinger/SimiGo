# ES-T3 T3-B′-2 Results — Discriminative Power Limitation Note

日期：2026-09-30  
状态：`BPRIME2_EXECUTED / MEASUREMENT_LIMITATION / ALTERNATIVE DESIGN WITH HUMAN`  
执行：b0（完整 GDN）vs b3（GDN 组零化）各自 restore（position 17）→
同一结构化指代 probe「详细列出参考文件目录下的所有子目录和文件名。」→
greedy（temperature 0，maxTokens 128）→ 记录 text chunks；零 durable
写入（204 前后核验）；观测 `b2diff-observations.jsonl`（已落库）。

## 1. 实测

```text
b0: restore OK(17) → text output = 0 字符
b3: restore OK(17) → text output = 0 字符
O_b0 == O_b3 = ""（trivially identical；LCCP=0 无信息量）
零 durable 写入；真实 store 204 不变
```

## 2. 判别力不足说明（按预设指令提交）

双侧「零文本输出」使 LCCP 度量退化为平凡恒等——**本轮差分对 A/B 解释
无判别力**。且 0 字符 ≠ 模型未产出：最可能的机制 = 本会话既有的
tool-call 模式（E3 记录：会话历史中「列出目录」类请求 → assistant 发
tool_calls；本次 probe 恰为同类请求）——模型的产物可能是 **tool call
而非文本 content**，而本轮观测面只捕获了 `onChunk` 文本（Generation
result 的 toolCalls/finishReason 未记录）。

## 3. 诚实记录的边界

```text
✔ 双侧 restore/生成全程无崩溃、零 durable 写入
✔ 「0 字符」≠「无 token 生成」——token 层产物未观测（测量面限制）
✔ A/B 解释仍双未决；本轮不构成对任一解释的支持或否定
```

## 4. 替代设计选项（请示 human）

```text
(a) 改用不触发 tool-call 模式的 probe（如「用一句话总结这次会话做了
    什么」——E3-C0 已证此型 probe 产生 ANCHORED 文本），重跑差分
(b) 观测面扩展：记录 GenerationResult.toolCalls / finishReason /
    全 token 流，使「0 文本」可解释
(c) (a)+(b) 同时
```
