# Track E(命名待定)P0.1 Cost Unit Definition——定义探针草案(2026-09-21)

**状态**:定义草案(DRAFT,待审核确认;无采数)。**性质**:P0 终审
钉死的下一步——补成本单位与换算模型,定义闭合前 P3 正式策略比较不解锁。
**输入**:P0 容量侧事实(R_node = 78,246 KiB/节点;Available =
4,449 MiB;MaxResidentNodes = 58)+ M4 边界成本(0.72 token =
0.69 ext + 0.03 rehy)。

## 六个定义项(审计清单逐项提案)

### 1. Capacity constraint:bytes —— 已闭合

R_node = 78,246 KiB/节点(含 padding);Available = 4,449 MiB;
MaxResidentNodes = 58。**角色 = 硬约束**,不是可加成本。

### 2. Horizon T 的定义 —— 提案

**T = 该节点从当前时刻到下一次被访问(或 trace 终止)的 decode 步数**。
单位明确为"步"而非物理时间(热节流使物理时间不可靠,τ̂ 教训沿用)。
oracle 语境下 T = next_access 距离;可实现策略下 T = E[T_remaining]
估计(承 Track B;**估计器鲁棒性先入边界**)。

### 3. Rehydrate cost —— 双单位并列,不入 bytes 加法

0.72 token-equivalent(M4 计量口径)/ 28.9–34.9 ms(M4 时间)。
**角色 = 事件成本**,进入 objective 时以 token 计。

### 4. Externalize cost —— 同上

0.69 token / 27.7–33.4 ms。事件成本,以 token 计。

### 5. External storage cost —— 提案:显式取零

M4/v0 语境 = 同进程内存外化,外化字节仍在设备内存池 → **external
byte cost = 0(显式声明)**。磁盘/远端成本属真源 Track C 问题域,
不入本模型。

### 6. Resident opportunity cost(最难项)—— 三个候选定义

- **(a) byte-steps**:∫ resident_bytes dt(以步计),单位 = KiB·步。
  bytes→token 换算率 ρ 显式参数化,**默认 ρ=1 并声明"非物理单位,
  仅供策略间相对比较"**。
- **(b) nodes-out(挤出计价)**:驻留代价 = 被其挤出的其他节点的预期
  回流成本;单位自然统一为 token,但需 workload 反事实,复杂度高。
- **(c) 留白为外生换算参数 λ(bytes→token),sensitivity 必做**。

**建议:v0.1 采 (a)+(c)**——byte-steps 作相对比较指标(策略排序对
ρ 单调 ⇒ 结论对换算率稳健;若排序随 ρ 翻转,结论必须声明"依赖换算
率");λ sensitivity 单列。

## 统一 objective 提案:双目标字典序(lexicographic)

```
第一层(硬约束):每步 resident_bytes ≤ budget(violation = 直接不可行)
第二层(目标):minimize C_ext × #ext + C_rehy × #rehy(token 单位,
              两事件同单位,可直接相加)
描述层:byte-steps(容量使用强度,描述性)
```

**为什么字典序**:bytes 与 token 的换算率物理上未定义,直接相加 =
伪精度;boundary cost 内部(C_ext/C_rehy)同单位可直接加。**审计指出
的"两列单位混用"由此解答:原 Keep-vs-Leave 不等式改为"约束 + 目标"
两段式**——无预算绑定时不等式左边为免费(M4 已证),有预算绑定时
Keep 的代价通过约束挤压体现,而非折算成 token。

## 开放问题(待审核定夺)

1. 是否引入 ρ/λ 换算做 sensitivity,还是严格字典序?(建议:字典序
   为主 + byte-steps 描述层,ρ sensitivity 单列)
2. miss/stall model(访问外部节点的等待成本)是否入 v1 simulator?
   (提案:不入,维持"强制 rehydrate"简化,如实标注)
3. E[T_remaining] 可实现估计器承 Track B τ̂ 教训——鲁棒性边界先于
   任何估计数字。
4. nodes-out 计价(b)是否值得做?(提案:暂缓,复杂度/收益比不佳)

## 阶段后果

- 本定义经审核确认 → **P3 解锁**(new policy 正式策略比较);
- P3 的 cost-aware oracle 按双目标字典序定义(先可行、后 boundary
  cost);
- **attention 深度 resident-footprint sweep**(P0 审计第④条)作为
  P3 的前置小探针候选;
- Track E 命名继续待 P3 证据。
