# ES-T3 B′ 线封存裁定（CLOSED / LIMITED）+ C-0 任务令

日期：2026-10-01  
状态：`BPRIME_SEALED_CLOSED_LIMITED / GATE_C_READINESS_REVIEW_TASKED / GATES_C-D_LOCKED`  
裁定人：human（B′ 续 vs 封存决定权行使）

## 1. 裁定：B′ 封存，不在当前样本上追加 probe

继续增加 probe 只会在同一样本上提高实验数量，而不是提高解释力——
B′-3 已达当前样本的判别力边界。

## 2. B′ 证据包（封存时定稿形态）

```text
B′-1 源码侦察（424b07b）
     → newCache(parameters:) 无 state 参数
     → 解释 A 获得先验支持，但未证明
B′-2 原始差分（ab20168）
     → 0 text / 0 LCCP → 判别力不足
     → EXECUTED-UNINFORMATIVE（human 裁定 5108427：不作 A 证据）
B′-3 扩展观测面（09332a2）
     → toolCalls 纳入 / token count 纳入
     → listing probe：b0 = b3
     → summary probe：b0 = b3
     → 两类 probe 均无观察差异
```

其中 **P-1** 把 B′-2 的「观测异常」彻底解释掉：**0 字符不是 0
generation，而是 generation 走到了 tool-call channel**——B′-2 的
实验缺陷已被机制性解释，不是留下的模糊「可能」。

## 3. 档案诚实表述（裁定原文，逐字落档）

> **A 获得源码结构证据支持，并得到当前黑盒 continuation probes 的一
> 致性支持；B 尚未被逻辑排除，但当前实验没有发现其可观察后果。**

B′-3 不能证明 A：实际得到的只是——在当前模型、当前 restore 状态、
当前两个 probe 类型与当前观测面下，没有观察到 b0/b3 的 continuation
差异。支持「当前 probe 没有检测到 GDN 差异」，不构成「GDN 没有被
消费」（A：未进入 MambaCache/forward；B：进入但对当前 continuation
不敏感——B 未被排除，即预注册限制条款）。

## 4. CLOSED / LIMITED 的准确含义（与 PASS 区分）

> **B′ 已经完成了预定的消费可观测性验证；当前观测面没有发现 GDN
> 差异，并达到当前样本的判别力边界。**

它不是：「B′ 证明了 GDN 不被消费」。

## 5. 保留的研究入口：独立样本验证（SEPARATELY SCOPED）

若未来需要提高判别力，下一实验定义为**独立验证样本**，不是 B′-4：

```text
Sample 1  Qwen3-Next / session X          b0 = b3（已完成）
Sample 2  新 session / 不同 continuation   b0 = b3 ?
Sample 3  必要时不同架构                    b0 = b3 ?
```

多独立样本恒等 + 源码结构证据并存会明显增强 A 的证据链——但那是
**新的验证实验**，须另立研究入口（新问题定义门），B′ 线不无限延长。
本入口仅登记，NOT STARTED，不分配 RQ ID。

## 6. C-0 任务令：Gate C readiness review

下一步 = 非常短的 readiness review，先回答一个问题：
**Gate C 到底要证明什么？**

约束：

```text
❌ 不得因 B′ 无差异把 Gate C 偷换成「证明 GDN 没有用」
❌ Gate C 必须仍围绕原 T3 问题：Representation 内部计算分量能否在
   restore 后成为未来计算的实际基础
✔ 若当前证据不支持 GDN 作为命题载体，Gate C 应针对另一个更直接的
   carrier / consumption boundary——是否值得开启、测哪个依赖，
   readiness review 交付后由 human 决定
```

## 7. 禁止事项（裁定原文登记）

```text
❌ 再做十几个自然语言 probe（同一样本）
❌ 为「逼出差异」不断改变 prompt
❌ 把 GDN zeroing 的 null result 当成 negative proof
❌ 因源码偏向 A 就宣布 GDN 是 write-only
❌ 把「Attention KV = operative carrier」直接升级成「Execution State」
```

## 8. 当前门位

```text
ES-T3
├─ A  = CLOSED（源码证据偏向 A——见 §3 诚实表述）
├─ B  = CLOSED（B-3：KV operative carrier；GDN 尚无消费证据）
├─ B′ = CLOSED / LIMITED
│      ├─ B′-1 PARTIAL / INCONCLUSIVE
│      ├─ B′-2 EXECUTED / UNINFORMATIVE
│      └─ B′-3 EXECUTED / NULL DIFFERENCE
└─ Gate C/D = LOCKED（C-0 readiness review 交付后，开启与否归 human）
```
