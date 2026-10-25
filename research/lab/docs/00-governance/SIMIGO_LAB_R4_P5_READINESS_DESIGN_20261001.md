# R4 P5 Readiness + Criteria + History-Absence Design

日期：2026-10-01  
状态：`P5_READINESS_DELIVERED / CRITERIA_LOCKED / DESIGN_DELIVERED / EXECUTION_AWAITING_AUTHORIZATION`  
上游：P5-0（Lab `8809986`：P4 PASS=前提；P5 注册）；D 宪法 `9676641`；
P4 设计/结果 `792afbc`/`b0efc99`  
性质：判据锁定 + 实验设计——零执行。**越简单越好**（human 指令）。

## 0. P5 命题与第一问

```text
P5：从已有 S₀ 出发，未来计算是否可以只依赖新增输入 Δ，
    而无需重新计算已完成历史？
形式：S₀ + Δ →（只处理 Δ）→ Result
第一问（human 原话）：已有 S₀ 是否足以让 backend 接受一个新的 Δ，
    并完成 continuation，而不重新提供已经完成的历史？
    ——即测「历史输入是否必须再次进入计算路径」
```

## 1. P5-A 判据（锁定；对应 human 五条件）

```text
P5-1  S₀ 已经形成
      操作化：沿用 P4 base-record（formation 溯源在案；工件 SHA/
      锚/位置恒等已证）
P5-2  Δ 是新的输入
      操作化：Δ 沿用 P4 已预注册输入（ΔA₁ 主、ΔB₁ 副——零新
      probe，零迭代选择）；机械核验 Δ ∉ S₀ transcript
P5-3  未来计算入口不再要求旧 History
      操作化：历史缺席臂（§2 Arm X）——restore 所用 meta 的
      history 字段被清空后，入口仍接受 (S₀, Δ) 并完成 continuation；
      restore 后观测 loaded history count = 0（历史文本不在计算
      入口）
P5-4  Y 与完整历史路径结果一致
      操作化：Y == Y′（greedy 逐字）；Y′ = P4 已记录基线输出
      （Run1/Run2 已证逐字稳定，零重跑）
P5-5  删除/隔离旧 History 后仍成立（防走私条款）
      操作化：Arm X 本身即「删除旧 History 后」的条件——P5-3 与
      P5-5 由同一臂实现；success 只能来自 (S₀ 载体, Δ)，走私通道
      （重读 history 文本）在构造上不存在
```

判据框架声明：本实验证明的是**已有状态的行为能力**（继续 P4 纪律），
不证明任何内部组件是 State（D7）；对 fixture 的 history 清空 =
**依赖性检验的扰动**（b3 零化 / P-N3 删工具历史先例），不是构造新
载体冒充 pre-existence（D6 边界已析）。

## 2. P5-B 历史缺席实验设计

```text
Arm X（历史缺席）                    Arm B（基线 Y′，零新执行）
  S₀ fixture 复制至 /tmp/simigo-p5/   P4 Run1 已记录输出
  meta.history → []（其余字段不动，   （Run1/Run2 已证逐字稳定）：
  cacheSHA256 不变——safetensors      S1-ΔA₁=「这个会话在查看桌面
  零接触）；恢复后观测 history=0       文件结构……」(43 字符)
    ↓                                 S1-ΔB₁=「经管部管理办法汇编」
  只给 Δ → generate → Y               S2-ΔA₁=「规划一次11月3日出发、
  （restore 后观测 history=0）         为期三天……」
                                      S2-ΔB₁=「11月3日」
比较：Y == Y′（greedy 逐字）
```

```text
cells（2 样本 × 2 Δ，全 greedy maxTokens 128，与 P4 同参）：
  X-S1-ΔA₁  X-S1-ΔB₁  X-S2-ΔA₁  X-S2-ΔB₁
身份检查（Arm X 适配版，逐 cell 记录）：
  ID-1′ tensor SHA == S₀ base-record tensorSHA（计算载体字节同一）
  ID-2′ key 同
  手术记录：meta 变更键=[history]，N→0（唯一变更，逐字入观测）
  恢复后 history count = 0
隔离：真实 204 前后核验 + 池计数（宪法延续）
```

## 3. 判读（预注册；失败有效性条款全文继承）

```text
PASS（4 cells 全满足）：
  Y 文本非空 && Y == Y′ 逐字 && 隔离绿
  ⇒ 预注册措辞：「在当前系统形态下，continuation 入口接受 (S₀, Δ)
     而无需历史文本进入计算路径，且结果与完整历史路径逐字一致」
     ——P5 第一问答案 = 是

FAIL（有效研究结果，不得改判据重试）：
  任一 cell：Y ≠ Y′ 逐字 / Arm X load 或 generate 失败（错误原文
  逐字入观测）/ Y 空
  ⇒ 「在当前系统形态下，continuation 入口仍要求历史文本进入计算
     路径（或 (S₀,Δ) 形态未被接受）」——P5 第一问答案 = 否

INCONCLUSIVE（不计正反）：
  隔离破损（204/池异常）；D5 通道疑云（Y 空+toolCalls>0 → 先按
  B′-3 P-1 方法裁通道；裁定后 Y 仍空 ⇒ 归 FAIL）
```

## 4. P5-C 样本（沿用，减变量）

```text
S1 = /tmp/simigo-palace1-e1/esr2/t3gateB/b0（P4 同一 fixture）
S2 = /tmp/simigo-p4/sample2（P4 形成的 S₀′）
Δ  = P4 已预注册 ΔA₁/ΔB₁（零新 probe）
Y′ = P4 Run1 记录输出（Run2 已证逐字稳定）
诚实边界：模型维度 coverage gap 自 P4 延续（同模型同 vendor），
   不伪装跨模型验证
```

## 5. 执行剖面（LOCKED，待授权）

```text
2 invocations（每样本一个进程）：复制+手术 fixture → identity′ →
  restore(history=0) → Δ → Y → 隔离核验 → summary；
判读由代码按 §3 规则机械应用。
不测：latency / token-s / GPU / 内存 / cache 命中率（D8）。
不做：T3 / PALACE / State schema（human 明令）。
```

## 6. Non-claims

```text
✔ 本设计零执行；判据已锁定，执行中不得修改（失败有效性条款）
✔ Arm X 正结果证明的是行为能力（历史不必重进计算路径），不证明
  KV/任何内部组件「是 State」（D7）
✔ history 清空 = 依赖性扰动（b3/P-N3 先例），非载体构造（D6 边界
  已析，§1 框架声明）
✔ 模型维度 coverage gap 延续登记
```
