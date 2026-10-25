# ES-T3 Research Design — Computational Result / Representation Decomposition

日期：2026-09-30  
状态：`EST3_DESIGN_LOCKED / T3A_DESIGN_DELIVERED / T3A_EXECUTION_AWAITING_AUTHORIZATION`  
替代假设（human 界定）：**「第三形态」可能已经存在于当前 Physical
Representation 内部，只是被整体封装为不可分解的 P**——T3 验证此假设，
不是 T2 的实现阶段。  
研究问题（锁定）：**当前 Physical Representation 内部，是否已经存在
可以脱离完整 History、并承担未来计算所需部分上下文的独立计算成果？**

## 1. 前置事实（只引用）

```text
T2-A2  carrier-FORM gap：宇宙内载体仅形态 H（transcript）与形态 P
       （KV artifact）；第三形态（State 可携带、计算承载）不存在
E0     checkpoint 工件内部分裂：GDN 固定态 [1,3,8192] BF16（尺寸不随
       position 增长）×50 + 注意力 KV [1,2,31712,256]（尺寸 ∝ position）
       ×30，命名 <layer>.<0|1>，同一 save/load 单元
E1-R1  载入以整工件为前置（meta+safetensors 缺一即 fail-closed）
Gate D/ES-R2  Tier-1 存活但不可操作；State 与 H/P 之间无第三载体
```

## 2. 替代假设（T3 检验对象）

```text
H-implicit  第三形态已潜藏于 P 内部——GDN/attention 两类组件中某类
            （或其组合）已具备独立计算成果的性质，只是当前系统将
            其整体封装
H-null      两类组件只是同一 P 的两个物理字段，无独立计算语义
            （T3 若证 H-null，换假设继续；不硬挖）
```

## 3. Gate A — Representation Component Census（实验设计）

问题：GDN 与 Attention 组件在 生成→save→load→ChatSession 使用→下一
token 的完整生命周期中，是**一个单元**还是**两个可区分的计算构件**？

### 3.1 七问检查项（全部代码级可验证，file:line 交付）

```text
Q1 生命周期绑定   save/load 是否存在按组件（GDN-only / KV-only）的
                  读写入口？safetensors header 的按名随机访问能力是否
                  被 vendor API 暴露？
Q2 position 承载  两类组件的 shape/更新规则与 position 的耦合关系
                  （E0 已证：attention 尺寸∝position；GDN 固定——
                  T3-A 补：vendor 内部 position 计数/rollback 机制作用于
                  哪类组件）
Q3 continuation   下一 token 计算的输入依赖：GDN 态与 KV 是否同时必需？
                  有无「仅 KV 即可算下一 token」或「仅 GDN 即可」的
                  代码路径？
Q4 独立入口       load/restore/使用面是否存在单组件粒度的 API
                  （loadPromptCacheSnapshot materializeArrays 的粒度；
                  ChatSession init 的 cache 参数粒度）
Q5 更新方式       推进一 token 时两类组件的写入路径是否独立
                  （GDN in-place 固定尺寸 vs KV append；vendor 内部
                  实现，只读追踪）
Q6 架构依赖       GDN=Qwen3-Next 线性注意力族特有；attention=通用
                  transformer 分量——vendor 对两类组件的处理是否
                  架构通用
Q7 可替换性       两类组件是否共享同一元数据/校验/生命周期（现状：
                  同一 meta.generation + 同一 SHA 门）——是否存在任何
                  机制将其区别对待
```

### 3.2 普查纪律

```text
✔ 只读（代码 grep/sed + fixture 头解析沿用；必要时 vendor 源码只读
  追踪——mlx-swift-lm 为公开上游，可读其 save/load/prefill 实现）
✔ 零修改、零扰动、零新 State
✔ 物理分解 ≠ 语义分解：Q1–Q7 的任何发现都只记「结构事实」，
  「计算语义差异」的判定留 Gate B 扰动实验
```

## 4. Gate B — Component Necessity（LOCKED，设计登记）

最小扰动矩阵（仅当 A 发现可分离组件时申请执行）：

```text
P 拆分：{GDN only / KV only / GDN+KV} × {position / continuation /
  next-token computation / semantic output}
判定纪律：扰动只证必要性（删 X → 坏 = X 必要），
  不证「X = State」；语义输出判定沿用 P1（greedy 逐字）/P2（锚词）
  规则，执行前明确。
```

## 5. Gate C — Independent Computational Carrier（LOCKED）

判据（human 版）：

```text
H ✗   old P 其余部分 ✗   candidate component ✓
        ↓
     computation
        ↓
      R'
```

成立 ⇒ 「第三形态已潜藏于现有 Representation」获正证据；不成立 ⇒
「内部拆分只是物理实现差异」。两向皆为有效结果。

## 6. Gate D — Representation Independence（LOCKED）

```text
P1 → candidate C 抽离 → 删 P1 → process death → C → R2
严格要求：无完整 History / 无旧 P / 无生产 State API / 无性能测试 /
不改生产架构。成功 ⇒ C → R' 链；否则停在 T3。
```

## 7. 预注册结果（T3-A）

```text
T3-A1 纯物理分解      —— 两类组件仅物理字段差异，无独立入口/语义
T3-A2 计算语义差异    —— 组件承担不同计算语义（如 position 承载
                         /continuation 参与的不对称）
T3-A3 独立生命周期    —— 存在单组件粒度的读取/恢复/使用入口
T3-A4 无法形成独立边界 —— vendor 深度融合，无组件粒度 API/事实可分
（T3-A2/A3 若成立，才产生 Gate B/C 执行申请；A1/A4 则 ES-T3 封存，
  换假设）
```

## 8. 禁止事项

```text
❌ 执行 Gate A（本轮设计 only）
❌ 组件扰动 / 拆 GDN/KV / 单组件恢复尝试
❌ 新 State object / schema / API / persistence
❌ forkPoint 加 reader / C-4 重开 / 性能实验 / backend takeover
❌ 破坏真实 ~/.simigo / 涉及其他主体内容
❌ 把「物理可分」预写成「语义可分」或反向
❌ 修改 Contract / PALACE framing / 既有三链 SEALED 状态
```

## 9. 产物（Gate A 执行后交付）

```text
① 七问检查项逐项事实表（file:line / vendor file:line）
② 组件生命周期图（生成→save→load→使用→下一token，按组件分道）
③ T3-A1…A4 四选一归类（含证据与反例）
④ 停止：Gate B 申请（若 A2/A3）或 ES-T3 封存换假设（若 A1/A4）
```
