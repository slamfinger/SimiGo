# R4 Capability Gap Matrix — B 线交付

日期：2026-10-01  
状态：`B_LINE_DELIVERED / READ_ONLY / C_GATE_HANDOFF / NO_P4_DESIGN`  
任务令：R4-0 → A1-A4 → B Capability Gap Matrix（human 2026-10-01，
Lab `f1e35be`）  
上游：A 线判据
`SIMIGO_LAB_EXECUTION_STATE_CONTINUATION_CRITERIA_D1_20261001.md`  
性质：只读能力盘点。**核心纪律：严格区分「未知」（未测）与「做不到」
（已证否定/有边界）。**

## 1. 能力矩阵

| 能力 | 当前证据 | 状态 | 未知≠做不到 注记 |
|---|---|---|---|
| State formation | ES-D1 J-C：形成事件存在（checkpoint commit）、信息在场、durable schema 不捕获 | **已证/部分**（gap 已定位） | gap 在 schema 层；FSB-1 证明可形成——未证「不可形成」 |
| State persistence | ES-R2 Gate B：三标量 carrier 跨进程死亡+P 丢失存活 | **已证**（Tier-1） | — |
| restore | E1 R0/R1 fail-closed；产品 restore-replay E2E | **已证**（P+H 融合路径） | 融合路径≠唯一可能形态 |
| continuation（S+X→Y） | R2n=H-full 基线可复算；产品池 warm（E2 HIT 17/17）；S-only 路径未测 | **待定义**（A 线判据已备） | 分裂=产品证同会话前缀、研究证 S-only 未做——非「做不到」 |
| fork | 产品 fork 钩子在案（Route B token 级跨会话共享/分支 checkpoint）；研究线 P4 拓扑从未直接测 | **未知** | 产品机制存在 ≠ P4 已证；未知 ≠ 做不到 |
| shared base | P4 未直接研究（Research Line Review） | **未知** | 同上 |
| incremental continuation | P5 分裂：同会话前缀增量产品已证（池 warm 84×）；S₀+Δ 独立基点增量未测 | **部分/未知** | 同上 |
| backend independence | Contract 零 MLX target+三 backend battery（Runtime 侧）；BACKEND2 audit G-B2 三缺口（token id 空间/history 载体/跨格式同模型） | **部分；待判断** | Runtime 契约层证据 ≠ State 语义层证据 |

## 2. 前线判读（防止新线继承旧悲观）

```text
C-2（存在≠可执行）与 Closure L3（UNVERIFIABLE-AS-IS）检验的拓扑是：
  「无 H、无旧 P 条件下 S→R' 的重物化」

P4 的拓扑不同：
  fork-from-common-base 允许各分支的增量计算由 backend 完成
  （纠偏地图的分工：SimiGo 管「从哪里继续」，backend 管「怎么
  继续」）——不预设 S 脱离其现行融合载体。

⇒ C-2 / L3 不构成对 P4 的否证。P4 是真正的新地带（unknown），
  不是已知失败的延伸。
```

## 3. P4/P5 候选命题（candidate only；升级须经 C 门）

```text
P4（候选）：一个已形成的 Execution State S₀ 能否作为多个未来计算
  分支的共同基点——S₀→S_A、S₀→S_B，且：
  (i)   共同基点身份成立（A3 判据：两分支起点同 key/position/anchor）
  (ii)  分支发散（两分支后续输入不同）
  (iii) 分支独立（A 的后续计算不污染 B，B 不污染 A，均从 S₀ 真实
        开始）

P5（候选）：从 S₀ 开始的未来计算能否只执行增量——S₀+Δ→Result
  不重算 S₀ 之前的历史，且 Result 满足 SUFF-2 基线等价。

顺序：P4 → P5（不反过来）。
两命题均为候选，未证，不提前宣布成立。
```

## 4. C-gate handoff（交付到此停止）

```text
A 判据 + B 矩阵 + P4/P5 候选已备。
下一步 = C Reframing Upgrade Gate（human）：
  「P4/P5 是否真正属于 SimiGo 的核心问题？」
  YES → D 抽样纪律预置 → P4 实验设计 → human 授权 → 执行
  NO  → 停车（避免再度 backend 深挖）
```

## 5. D 纪律预注册（吸收 B′ 教训；任何未来 P4/P5 设计的先决约束）

```text
① 至少两个独立未来分支
② 至少一个 independent sample
③ 不允许为产生差异而修改 prompt
④ 不允许以单 vendor/单模型/单样本直接推广；backend-specific 结果
   必须显式标注
⑤ observation null 不得自动解释成 mechanism null（B′-3 限制条款
   延续）
⑥ 不允许为实验制造理论上不存在的 carrier，再把构造结果当成
   pre-existence（C-0 边界延续）
```

## 6. Non-claims

```text
✔ 本文档零实验、零代码、零实现方案
✔ 「已证」条目全部引用仓内封存证据；「未知」条目一律不得在设计
  文档中被改写为「已证否定」
✔ P4/P5 候选命题的成立判定只能来自未来预注册实验
```
