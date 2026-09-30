# P4 Design — Common Base / Identity / Divergence / Independence / Sample / Judgment

日期：2026-10-01  
状态：`P4_DESIGN_DELIVERED / EXECUTION_LOCKED / AWAITING_HUMAN_AUTHORIZATION`  
任务令：human 2026-10-01（放行设计门；依据 D 宪法 `9676641` + 
readiness `f581fbe`）  
约束：不新增研究命题；不修改 A 线判据（SUFF/IDENT 只实例化）；不研究
KV/GDN/hidden/cache 内部机制；不提出 State 内部定义；不比较性能；不做
P5；不执行实验；不因 API 方便把 API 形态升格 SimiGo 语义；不按「可能
成功」反向改判据。

## 0. 设计总览

```text
                    ┌─ restore(S₀) → ΔA₁ → ΔA₂   (branch A)
   S₀ (同一工件) ────┤
                    └─ restore(S₀) → ΔB₁ → ΔB₂   (branch B)

相位顺序（严格）：base-record → 逐分支独立 restore → 分支内两轮演化
   → 记录。换序重跑（Run 2 = B 先 A 后）用于独立性判定。
每分支独立 restore 自同一 fixture（字节同一工件）——排除共享内存
   对象带来的伪关联：恢复后的一切相关性只能来自 S₀ 本身。
```

研究级理由（非 API 便利）：「同一 S₀」的语义 = 同一字节工件 + 同一
身份三元组；共享一个活内存对象测的是 fork **机制**，两个独立 restore
测的是基点**语义**。本设计不声明 S₀ 是什么（D7）。

---

## 1. 要素 I — Common Base（S₀ 的实例化与记录）

```text
S₀ 来源   系统自身形成路径的真实 checkpoint（checkpoint commit 产物），
          只读复制进隔离 fixture 目录（复制=运输，非构造——D6）。
          零手术、零内容修改；两分支用同一 intact 工件。
base-record（任何分支运行前写定，分支记录必须引用它）：
  · caller key（IDENT-1）
  · position N（IDENT-2）
  · anchor = N 处 transcript 尾哈希（IDENT-3）
  · fixture safetensors + meta.json 的 SHA256
  · 形成溯源（由哪个真实计算会话的 commit 事件产生）
```

## 2. 要素 II — Identity（共同出发的证明——本设计的核心证据问题）

**威胁模型（human 指定）**：两个分支各自 restore 后得到「内容相似/
看起来相同、实则分别形成」的状态——必须证明消耗的是**同一工件实例**
与**同一身份三元组**，而非巧合相似。

四重身份检查（每次 restore 都做，逐分支记录）：

```text
ID-1 工件同一   harness 读取所用 fixture 文件的 SHA256，必须等于
     base-record（防偶然的分歧副本）
ID-2 寻址同一   恢复后 session 的 storageKey == base-record key
ID-3 位置同一   恢复后 position == N
ID-4 边界同一   对恢复后 history 重算尾哈希 == base-record anchor
```

任一不匹配 ⇒ 该次运行 **INCONCLUSIVE**（基点身份未成立——实验无效，
不计入 P4 正反证据），不是 P4 FAIL。

## 3. 要素 III — Divergence（预先规定的两个独立未来）

选律（预注册，禁迭代）：输入必须① grounded 于 S₀ 历史（检验共同
基座的落地），② 任务型不同/答案形态不同，③ 走文本通道（B′-2 教训；
观测面仍记 toolCalls 以防通道迁移），④ 现在一次性定死，执行与观察
不得更改。

**Sample 1（既有 PALACE/T3 会话 5401315f，历史=桌面文档浏览）预注册：**

```text
ΔA₁「PALACE-1 E3 probe: 这个会话此前在做什么？用一句话概括。」
    （E3-C0 逐字先例=已知 ANCHORED 行为，降低退化输出风险）
ΔA₂「接着上一句，再补充一点：这些文件属于什么性质的材料？」
    （分支内第二轮=演化步）
ΔB₁「从这个会话中找出一个文件或目录的名称，原样写出名称，不要解释。」
    （抽取型，答案形态不同；锚定可机器核验：输出实体须是 S₀
    transcript 的子串）
ΔB₂「用一句话说明你是从会话的哪个部分注意到它的。」
锚定判据 A：输出含 {桌面, 参考文件, 管理制度} 中至少一词（E3 先例）
锚定判据 B：输出含 S₀ transcript 中的某一实体（子串核验）
```

**Sample 2（新建会话）预注册脚本**：真实生成 8 轮对话——主题「京都
三日旅行规划」，命名实体（锚词来源）：{京都, 岚山, 伏见稻荷, 11月3日,
清水寺}；脚本正文在执行准备阶段按此骨架生成后**冻结**再形成 S₀′
（先冻结后形成，防调参）。Δ 输入按 Sample 1 同构生成（概括型/
抽取型/各一轮演化），在脚本冻结时一并预注册。

## 4. 要素 IV — Independence（独立演化的可观察判据）

```text
污染通道关闭清单：
  · 内存共享    排除（逐分支独立 restore——见 §0）
  · durable 残留 隔离配方：零 durable 写入 + 真实 store 204 前后
                核验 + prefix-pool 计数 delta（任何分支不得留下
                他方可读痕迹）
  · 顺序依赖    换序重跑检验（下）

换序协议（独立性主检验，Gate H 跨进程逐字先例背书）：
  Run 1：restore → ΔA₁→ΔA₂（分支 A）→ 新 restore → ΔB₁→ΔB₂（分支 B）
  Run 2（独立进程）：restore → ΔB₁→ΔB₂ → 新 restore → ΔA₁→ΔA₂
  独立性判据：O_A(Run1) ≡ O_A(Run2) 且 O_B(Run1) ≡ O_B(Run2)
  （greedy 逐字）；任一不等 ⇒ 顺序污染 ⇒ Independence FAIL

「独立演化」判据：每分支第二轮（ΔA₂/ΔB₂）非空且锚定于本分支第一轮
  内容（A₂ 须与 ΔA₁ 的回答衔接——衔接判据：A₂ 输出不与 ΔB₁/ΔB₂
  输出雷同，且对 A₁ 为后续性回答；逐字雷同跨分支 ⇒ 退化为退化，
  判 INCONCLUSIVE 并按 D5 先裁通道）
```

## 5. 要素 V — Independent Sample

```text
Sample 1 = 既有会话 5401315f 的真实 checkpoint（现成 intact 工件）
Sample 2 = 新建会话：隔离工作区内真实多轮对话（§3 脚本）经系统自身
   形成路径 commit 形成 S₀′——不同会话、不同历史、同形成机制。
   （D6：由真实计算形成，非手工拼装。）
诚实边界：D4 严格读法要求脱离「当前 Qwen3-Next / 当前 session」。
   Sample 2 覆盖 session 维度；**模型维度（第二模型）受本地可用模型
   限制**，登记为 Sample 3 = 后续独立验证（模型可用时），不静默丢弃、
   不谎称已覆盖。
```

## 6. 要素 VI — Judgment（判读预注册；失败有效性条款全文继承）

```text
PASS（两样本一致满足 J1–J6）：
  J1 基点身份：所有 restore 通过 ID-1..4
  J2 发散真实：O_A、O_B 文本通道均非空，且 O_A ≠ O_B
  J3 内容敏感：各分支输出满足各自预注册锚定判据
  J4 顺序独立：换序重跑逐字复现
  J5 隔离成立：零 durable 写入；池 delta 记录无他读痕迹
  J6 独立演化：每分支第二轮非空且衔接本分支
  ⇒ 「S₀ 可作为多个未来计算分支的共同基点」在本样本类上成立
     （拓扑级；不涉任何性能表述）

FAIL（有效研究结果，原文形式）：
  J2/J3/J4/J6 任一在隔离与身份完好的前提下不成立
  ⇒ 判「共同基点拓扑在当前样本类与判据下不成立」——有效结果，
     不得修改判据后重试使路线成立

INCONCLUSIVE（可重跑，不计正反证据）：
  ID-1..4 任一失败（基点身份未建立）
  J5 失败（隔离破损——修复后重跑）
  D5 通道疑云：文本 0 但 toolCalls>0 等——先按 B′-3 P-1 方法裁定
     通道，再归入上述判读
```

## 7. 执行剖面（仅陈述规模；执行本身 LOCKED）

```text
每样本：Run1(4 generate) + Run2(4 generate)；Sample 2 另加形成对话
  （8 轮真实生成→commit）。两样本合计 ≈ 16+8 generate + 记录。
全部 greedy、maxTokens 有界；usage 仅记录 generationTokens/promptTokens
  作退化/规模核对——**不作任何性能读数（D8）**。
```

## 8. 禁止与非声明

```text
❌ KV/GDN/hidden/cache 内部机制零接触；restore 只走产品公共路径
❌ 不新增命题；SUFF/IDENT 原样实例化（各样本锚定判据=实例化，
   非判据修改）
❌ 无性能计时/对比；无 P5（「是否省了重算」不问）
❌ API 便利不构成语义论证（§0 已按研究级理由陈述 restore 选择）
❌ 本设计未经 Human Authorization 不得执行；执行后判读按 §6 预注册
   规则机械进行
```

**设计到此停止。EXECUTION LOCKED——等待 Human Authorization。**
