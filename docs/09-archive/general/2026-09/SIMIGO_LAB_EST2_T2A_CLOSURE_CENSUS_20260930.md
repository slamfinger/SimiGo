# ES-T2 T2-A Results — S→R' Dependency Closure Census

> **ARCHIVED** 2026-10-20 · line: 通用治理 / 其他 · original: docs/00-governance/SIMIGO_LAB_EST2_T2A_CLOSURE_CENSUS_20260930.md
> Evidence status: unchanged (content frozen; moved only)


日期：2026-09-30  
状态：`T2A_COMPLETE / VERDICT = T2-A2 (CARRIER-FORM GAP) / STOPPED PER DIRECTIVE`  
唯一问题：**路径 γ {identity, position: 17, anchor} → KV(17) 需要什么
输入才可能存在？**  
方法：代码级依赖追踪（Gate C 失败路径 × vendor API 面 × E0 工件分解）
+ 既有实验链引用；零运行时、零修改。

## 1. S→R' 依赖闭包表

目标 = R'(17)：位于 position 17 的 Physical Representation。

| 依赖 | Tier-1 有？ | 当前宇宙载体 | 闭包状态 |
|---|---|---|---|
| identity / addressing | ✓ | caller key + 文件名 | **闭** |
| position 断言 | ✓ | carrier 标量（Gate B 实测跨进程存活） | **闭（断言级）** |
| position **执行**（KV 实际延伸到 17） | ✗ | **两类载体**：①transcript 17 条→full prefill（=路径 α，H 类）②KV artifact（=路径 β，P 类） | **开——第一阻断依赖** |
| continuation 语义（下一条该是什么） | ✗ | history 末端（ transcript） | **开（同根：①）** |
| model 兼容 / tokenizer | ✗ | 环境常量（权重在位，允许） | **闭（环境）** |
| lineage | 部分（forkPoint 代码级） | 无 durable 实例 | 开（非阻断——history 闭包下不需要） |

## 2. 第一阻断依赖（First Blocking Dependency）

```text
【context computation payload】——把会话推进到 position 17 所需的
  上下文计算内容。
当前宇宙中它的载体只有两种形态：
  形态 H = 17 条 transcript 文本（meta.json 内；重放成本 = full prefill）
  形态 P = per-token KV artifact（真实 store 内；与 P 身份融合）
两种形态都被 S→R' 硬约束排除（不读 H、不用旧 P）。
⇒ 闭包开在这一个依赖上：**信息存在（两种形态都在宇宙里），
  但「State 可携带的第三形态」不存在。**
```

## 3. 归类

```text
VERDICT = T2-A2 — 缺失的是一类计算上下文载体（carrier FORM），
非单一信息项（✗T2-A1：至少 transcript/KV 两种已知来源被排除，
缺的是第三形态）；附带 A3 边界注记：该第三形态是否存在、是否存在
非 KV 的压缩计算态（如 GDN 固定态的结构性暗示，见 §4），属下一层
研究问题，本 census 不裁。
```

## 4. Vendor API 层闭合验证（决定性补充事实）

mlx-swift-lm `ChatSession` 公共初始化面（本轮核验）：

```text
位置承载输入恰好两类：
  ① history: [Chat.Message]（H 文本 → 内部 prefill）
  ② cache: PromptCacheSnapshot + state（P 工件 → 直接装载）
无第三种位置输入。
且 vendor 自身 Important 注释警告：「cache 与其 state 必须同行；
  丢 state 只传 cache 可编译，但后续 token 的定位如同 cached prefix
  为空」（ChatSession.swift:40-46）——即 vendor 已文档化
  「表示与计算态拆分 → 不连贯」的危害。
```

⇒ **路径 γ 在 vendor API 面也不存在**——缺口不是 SimiGo 层封装缺失，
而是上游推理 API 的通用形态：位置只能随 H（重放）或 P（装载）进入。

## 5. Census 附带发现：融合工件内部的 Architecture 分裂（E0 延伸）

E0 分解（80 张量 = 40 层 × K/V）内部实为两类物理性质不同的组件：

```text
GDN 固定态   [1,3,8192] BF16   —— 尺寸不随 position 增长
注意力 KV    [1,2,31712,256]   —— 尺寸 ∝ position（17k token 实测）
```

即：**唯一的「压缩计算态」候选物其实已经存在一半**——GDN 固定态就是
一种与位置无关的压缩计算分量，但它与按位置增长的注意力分量熔于同一
工件、同一 save/load 单元，系统内无任何机制区别对待。此为 A3 边界
注记的结构性素材（登记，不设计）。

## 6. Observed / Inferred / Unknown

```text
OBSERVED
  两形态载体（H 文本 / KV 工件）+ vendor 两类初始化输入 + GDN/attention
  内部分裂 + Gate C 两失败点 + 零 durable 写入
INFERRED
  第一阻断依赖 = context computation payload 的第三形态缺失；
  FSB-2 获实验证实；路径 γ 需要新载体形态才可能存在
UNKNOWN
  第三形态是否存在/可构造；GDN 分量能否独立承载 continuation；
  非-KV 压缩载体的信息论下界（全部属 Gate G/H 式后续研究，不预答）
```

## 7. 停止

```text
T2-A 完成（闭包表/第一阻断依赖/归类/三分清单四交付齐）→ 按指令停止。
T2-B/C/D LOCKED；生产 State API/schema 禁止；真实 store 未动（204）。
R2-A…R2-F 终归类与 ES-T2 后续方向归 human。
```
