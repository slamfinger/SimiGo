# ES-T2 Research Design — Tier-2 Computational Bridge

日期：2026-09-30  
状态：`EST2_DESIGN_LOCKED / T2A_DESIGN_DELIVERED / T2A_EXECUTION_AWAITING_AUTHORIZATION`  
研究问题（human 克制定义，锁定）：**在没有完整 History、没有旧 Physical
Representation 的条件下，一个独立存活的 Tier-1 State 要重新驱动计算，
还缺少什么？**  
纪律基线：先研究缺口，不直接设计 State；「研究缺什么」与「设计
compressed context carrier」不是一回事。

## 1. 前置事实（ES-R2 Seal，`0b7b976`，只引用不重跑）

```text
R2-A  FORMATION-SUFFICIENT：Tier-1 = {storageKey, position: N,
      continuation-anchor: tail(N)} 三标量可形成独立权威 State 记录
      （FSB-1），跨 P-loss + process death 存活（Gate B 实测）
C-2   Tier-1 无法 S→R'：唯一 P→R seam 需要 meta+safetensors（均缺席）；
      免 history 会话路径只能创建 position ~1 的新执行（State 的 17
      不可 honoring；模型逐字要求上下文）
C-3   缺口 = compressed context carrier 类载体，观察宇宙内不存在
      （边界发现，非唯一性主张）
```

## 2. T2-A 定位：不实现 Tier-2

T2-A 是**依赖普查**，不是 carrier 设计。本轮不回答「Tier-2 应该是什么」，
只回答「Gate C 失败路径上，S→R' 究竟缺哪些依赖、缺到什么程度」。
KV、History、任何现有 Representation 都**不预设为答案**——由代码事实
与最小实验裁定。

## 3. Gate C 失败路径的依赖追踪框架

Gate C 两次尝试的失败点（已核事实）：

```text
Attempt 1（P→R seam）：loadSessionCache 需要 {meta(transcript+标记),
  safetensors(KV)}——Tier-1 carrier 无法替代任一输入
Attempt 2（免 history 会话）：ChatSession(container, history:) 只能从
  调用方提供的消息文本建立上下文——carrier 三标量中无任何文本内容；
  会话落于 position ~1 而非 17
```

T2-A 将沿两条失败路径逐项追踪「重新产生 R'(17) 的信息闭包」：

```text
路径 α（重算型）：context 文本 → full prefill → KV(17)
  依赖 = 完整 transcript（17 条）+ tokenizer + 模型权重
  —— transcript 在 C 空间缺席（被禁）；此路径 = H→R'（Gate C 已证，
     非 Tier-2）
路径 β（装载型）：既有 KV 快照 → 装载 → KV(17)
  依赖 = safetensors/pool 快照（= 旧 P 或其等价物）
  —— 此路径 = P→R（被禁）
路径 γ（???）：{identity, position: 17, anchor} → KV(17)
  —— 观察宇宙内不存在该入口（C-3）；T2-A 的核心问题 = 路径 γ 需要
     什么输入才可能存在
```

## 4. 依赖闭包清单（T2-A 普查对象）

| 依赖 | Tier-1 已有 | 当前来源 | 必须恢复？ | 预登记普查问题 |
|---|---|---|---|---|
| Identity | ✓ | State | 已满足 | — |
| Position | ✓（标量） | State | 已满足（断言级）；**执行级待查**（position 与 KV/token 长度的绑定关系，A2 落差） | 恢复 position 断言后，什么机制使计算真正发生在 17？ |
| Continuation anchor | ✓（断言） | State | 断言已满足；**验证/执行待查**（需 tail 原文或其等价物） | anchor 的验证需要什么最小上下文？ |
| Model compatibility | ✗ | 环境/metadata | 待确认（换模型=同一 State？G-B2-3 遗留） | 跨格式同源判定 |
| **Context 内容** | ✗ | History 或 P | **重点** | 17 条消息的语义内容可否以非 transcript 形态携带？（压缩/摘要/锚点扩展……**不预设**） |
| **Attention/KV 中间结果** | ✗ | P | **重点** | E0：KV 含 GDN 固定态[1,3,8192]+注意力 KV[1,2,31712,256]——GDN 态与注意力态的可重建性是否对称？（待实验，不预设） |
| 其他模型内部态 | ? | 未确认 | 待调查 | sampling state / rotary cache / 等运行时暂态 census |
| 下一步计算输入 | ? | 生成链 | 待调查 | continuation 的「下一用户输入」属于 State 还是外部？ |

## 5. observed / inferred / unknown 分离

```text
observed（已有 file:line/实验底账）：Gate C 两失败点；KV 形态二分
  （E0）；meta 字段集；ManagedSession 字段集；delta 契约锚=history 末端
inferred（T2-A 分析可能产出，须标注）：路径 γ 的输入需求类；
  GDN/attention 态的可重建性差异
unknown（T2-A 只登记不裁）：压缩载体的存在性与形态；position-执行
  绑定机制；模型内部态全集
```

## 6. 最小实验 fixture（T2-A 设计）

```text
空间 = /tmp/simigo-palace1-e1/es-t2/（新建，不含任何真实数据）
组成 = state-carrier.json（Tier-1 三标量）+ 代码追踪底账
     【不含】safetensors / meta.json / pool 条目——保证 S 唯一输入
T2-A 主体 = 代码级依赖追踪（只读 grep/sed）+ 最小运行时探针（如需：
  沿用 R2n 隔离配方，env+tunable，零 durable 写入）
真实 ~/.simigo = READ-ONLY（全程）
不涉及其他主体真实内容（样本仍为 5401315f 自有会话）
```

## 7. 成功 / 失败 / 不可判定标准（预注册）

```text
T2-A1 单一缺失信息   —— 闭包可闭合于一个具体信息项（如「position 标量
                        + tail 原文 N 字」即可重算）
T2-A2 缺失计算上下文 —— 闭包需要一类上下文载体（transcript 的真子集
                        或压缩形态），无单一字段解
T2-A3 缺失计算结构   —— 信息闭包不可闭合：需要的不是更多信息，而是
                        一种计算结构/机制（如 KV 的中间态本身不可由
                        文本重建）
T2-A4 依赖无法闭包   —— 追踪在当前代码/实验边界内无法完成
（另设 T2-A0：闭包已被 Tier-1+环境满足——即 Gate C 结论被推翻；
  预期概率极低，登记以完整）
```

## 8. 禁止事项

```text
❌ 修改生产代码 / 创建 State object / schema / 新增持久化 / 新增 API
❌ 新增 reader（forkPoint 纪律延续）
❌ 重开 ES-R1 C-4
❌ 性能实验
❌ 跨 backend / backend takeover
❌ 把 KV、History 或任何现有 Representation 预设为答案
❌ 破坏真实 ~/.simigo（READ-ONLY）
❌ 涉及其他主体真实内容
❌ T2-B/C/D 提前执行；T2-D（Semantic Reuse）继续 LOCKED
```

## 9. T2-A 产物（执行后交付）

```text
① S→R' 计算依赖闭包表（逐项：依赖/来源/是否必须/载体形态）
② 第一阻断依赖（first blocking dependency）定位
③ T2-A1/A2/A3/A4 四选一预注册归类（含证据）
④ observed/inferred/unknown 三分清单
⑤ 停止：不设计 Tier-2、不实现、不进 T2-B
```

## 10. Seal/推进条件

```text
T2-A 完成即停，交 human 裁定：
  T2-A1/A2 → 或可定义 Tier-2 carrier 的最小研究目标（仍须新 gate）
  T2-A3    → 路线转向计算结构研究
  T2-A4    → INCONCLUSIVE，重新界定实验边界
ES-T2 全程不自动推进；每 gate 独立授权。
```
