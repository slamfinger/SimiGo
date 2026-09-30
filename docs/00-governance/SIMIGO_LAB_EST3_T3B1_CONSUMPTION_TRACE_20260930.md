# ES-T3 T3-B′ Results — (1,3,8192) Consumption Trace

日期：2026-09-30  
状态：`T3B1_PARTIAL_INCONCLUSIVE_AT_SOURCE_DEPTH / B′-2 DECISION WITH HUMAN`  
唯一问题：**restore 后 (1,3,8192) 组内容有没有真正进入后续 forward
computation？**（解释 A：restore 未挂载→write-only；解释 B：挂载且
forward 消费，本 probe 不敏感）  
方法：B′-1 只读 vendor 源码追踪（mlx-swift-lm ChatSession / Evaluate /
TokenIterator / KVCache / Qwen3Next）；B′-2 未执行（等源码结论）。

## 1. 追踪结果（逐跳，file:line）

```text
① durable 边界（融合）         loadArraysAndMetadata 全量读入 →
                              cache_classes 拆分 + state 提取
                              （KVCache.swift vendor）——单文件无组件入口
② snapshot 结构               PromptCacheSnapshot{ cache: [KVCache]
                              （逐层，线性层=MambaCache）, metadata,
                              state: LMOutput.State?（opaque 字典）}
③ ChatSession restore         loadSessionCache → ChatSession(container,
                              cache: snapshot.cache, state: snapshot.state,
                              history: restoredHistory)——三件同行
④ state 携带                  self.state = state（ChatSession:319/331）→
                              lmState（:1012/:1301）
⑤ TokenIterator 交接          TokenIterator(input, model, cacheStorage:
                              kvCache, state: lmState, …)
                              （ChatSession :1393-1396）——「Seed the
                              carried state and read back the
                              post-prefill state」vendor 注释自证
                              state 意图进入 prefill
⑥ 模型消费点                  TokenIterator: model.prepare(input, cache:
                              cache, state: state, prefill:)（Evaluate
                              :865）；逐步 model(previous, cache:, state:)
                              （:913）；asyncEval([token] + cache.state)
                              （:945）——state 与 cache state 数组均进入
                              eval 面
⑦ Qwen3Next 侧               newCache(parameters:) 无 state 参数——线性层
                              一律 fresh MambaCache()（Qwen3Next.swift
                              :836-844）；Qwen3Next.swift 内零处读取
                              LMOutput.State（grep 实证）；callAsFunction
                              (inputs, mask, cache:) 无 state 入参
```

## 2. 裁定

```text
B′-1 = PARTIAL / INCONCLUSIVE AT THIS SOURCE DEPTH
  · 已证：lmState 确实从 ChatSession 一路传入 TokenIterator 与
    model.prepare/generate 面（⑤⑥）——「协议层存在 state 通道」
  · 未决：Qwen3Next 是否在 prepare/prefill 中把 LMOutput.State 的
    serialized arrays 挂载到 MambaCache——消费点未在本轮源码深度内
    定位（⑦ newCache 无 state 入参是强不利证据，但 prepare 路径的
    挂载点未穷尽）
  · 实证侧锚点：Gate B b3（GDN 内容零化）probe 与 b0 逐字一致——
    若挂载+消费成立，零化应造成可观测差异；恒等结果偏向解释 A
    （未挂载）但不足以排除解释 B（不敏感）
```

## 3. B′-2 决定权移交

```text
按 human 规则（源码无法确定 → 可做 B′-2），B′-2 的执行决定权归 human：
  B′-2 形态 = 预先限定的更长/结构化 probe（如「详细列出参考文件目录」
  类需会话语境的延续任务），b0 vs b3 差分
  判读：恒等 → (a)/不敏感强支持；分歧 → (b) 获支持
  边界不变：无完整 History/无旧 P/不修改任何代码/无性能测试
```

## 4. Non-claims

```text
✔ 未宣称 write-only（解释 A 未证）；未宣称 forward 不敏感（解释 B 未证）
✔ 未执行 B′-2；未进入 Gate C/D；未修改任何代码
✔ 追踪止于本轮源码深度（evaluate 内部机制未穷尽——如实登记）
```
