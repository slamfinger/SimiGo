# Track E(命名待定)Residency M2 结果(2026-09-21)

> **终审判定(2026-09-21):PASS——不需要补跑 M2。**
>
> **措辞纪律(审核"降温"要求,正式入档)**:本实验结论 = "三个预设
> 泛化轴**在当前测试配置下**均通过",不是"泛化性普遍成立";m2a =
> "在测试的 16K/64K 深度上成立",不外推为"深位置普遍成立"。未证明:
> 所有深度 / 所有 segment topology / 任意 execution tree(任意
> DAG / 大规模树)/ 任意 residency pattern。
>
> **架构观察(正式入档,与架构结论分开)**:*Residency representation
> need not equal the resident execution representation's materialized
> form*。**不得**前进一步说"residency architecture 应采用
> segment-preserving externalization"——该架构结论需 M3 证明段表
> 表示可完整继续执行之后才可能成立。
>
> **Execution Tree invariant 抽象(正式入档)**——从测试断言的失败
> 方式自然长出,非画图:同层兄弟 → isolation invariant(逐元素互异);
> parent→child → prefix + extension invariant(前缀逐元素相等 + 严格
> 延伸);externalization → identity/state preservation invariant。
> 树不是"所有节点可互相比较"的集合;不同关系类型用不同 invariant。
>
> Scope ✓:16K/64K 深度;COW segmented externalization;private-page-
> only externalization;shared prefix retained;rehydrated state remains
> segmented;multiple execution nodes;sibling isolation;parent-child
> lineage;parent preservation;five state gates。
> Not established ✗:continuation correctness(M3);arbitrary tree
> topology;cross-device residency(真源 Track C 问题域);rehydration
> performance(M4);residency policy。
>
> **M2 PASS → OPEN M3(Continuation)**:问题从"回来以后看起来还是
> 原来的 Execution State"升级为"回来以后**是不是还能成为原来的
> Execution**"——从 snapshot comparison 跨到 behavioral continuation。
> 主门 = Continuation(Control) == Continuation(Rehydrated) 逐 token;
> 主配置 = m2b 段表路径(COW 子代私有页外化→重挂→继续);第一轮不加
> 多节点/64K/大规模树/性能/policy(单变量纪律)。
>
> 附:a988b8a 执行瑕疵处理经审核通过(不 force rewrite、不删历史、
> 如实记录;脆弱文本锚点匹配弃用,改行号/结构化编辑,已入档)。

> **首跑记录(v1 检查错误如实保留,史料)**:本文档初版记录三轴
> PASS 与 m2c 互异检查修正;初版状态行"待审核方终判"已被上方终审
> 取代;初版"泛化性三轴全部成立"表述按终判降温要求收缩。
> 靶子 = 泛化性:打掉"M1 只在这个 35B、这个 4616 position、这个单节点
> 配置下成立"的解释。代码:`ResidencyM2StateExactness.swift`(exp
> 分支,基于 M1 探针之后;措辞沿用 M1 终判收紧:Execution Identity
> preserved = 状态接地,非 literal ID 字段)。

## 三轴设计与结果

### m2a 深位置(16K / 64K)——PASS

M1 同形探针在深位置重放(P→fork→后缀512→decode 8):

| 配置 | resident 位置 | 载荷 | 五门 |
|---|---|---|---|
| 16K | @16904 | 391 MiB | 全过 |
| 64K | @66056 | 1351 MiB | 全过 |

"浅位置偶然成立"解释被打掉:position 深至 64K,identity 五门
(position/next-input/KV/GDN/State)依旧全过。

### m2b 段表形式直接外化——PASS(架构线索成立)

COW 子代(父代驻留)只外化**私有页**(520 行,73292 KiB;共享前缀
不落盘),重挂回**驻留父代**:

- **表示核查 ✓**:重建子代全部仍为 COW 段表(sharedRows = 父代
  offset),全程**未物化成连续表示**;
- 五门全过(全视图由段表+私有页拼接,逐元素判定);
- 父代完整性 ✓(驻留全程未被子代外化/重挂扰动);
- 冒烟步 ✓(单步 decode,offset +1)。

**结论(待终判)**:residency **不要求**先把 Execution State 强制
物化成另一种表示——外化粒度可以只取节点私有增量,共享前缀留在驻留
结构上。这是 Execution State → Residency 研究的第一条正式架构线索。

### m2c 多节点隔离——PASS(Execution Tree 第一步)

树:P@8192 → A,B(fork+512+4);A→A1,B→B1(fork+256+4)。
四节点**各自独立**外化 → 全部释放(父代留驻)→ 各自独立回来:

- 每节点五门全过(A@8708、B@8708、A1@8968、B1@8968,nextInput 各异);
- **同深度互异** ✓(A≠B、A1≠B1,重建前后一致);
- **谱系保持** ✓(A1 的前 8708 行逐元素 = A;且严格延伸——子代尾部
  ≠ 父代尾部;B1/B 同;重建前后一致);
- 父代 P 完好 ✓。

树上多个节点可以各自离开驻留再回来,不串 identity、不丢谱系。

## v1 失败如实记录(检查语义错误,非机制错误)

m2c 首跑 fatal crash:互异检查对**异深度节点对**(A1@8968 vs
A@8708)做逐元素比较 → shape broadcast 错误。教训:**树的隔离检查
必须按语义分层**——同深度兄弟才做逐元素互异;跨深度用"前缀包含 +
严格延伸"表达(这恰是树结构的正确定义);纯异谱系异深度对形状已互
异,无需比较。修正后全过。

## 诚实性注记

1. 全部判定仍是**状态接地**的 identity 组件保持(M1 终判措辞);
   不声称任何 literal ID 字段存在。
2. 计时(套件 507.4s,64K prefill 为主)描述性;性能归 M4 交替对照。
3. m2b 的"驻留父代"是**同进程内的共享驻留**,不是跨设备;跨设备
   externalization 属真源 Track C(= Multi-device)问题域。
4. 本结果不反推 Track B / M1;失败也只指向"该机制在该配置下不成立"。

## 决策

1. **M2 三轴 PASS → 建议开 M3(Continuation)**:rehydrate 后的
   节点与未离开驻留的 control 逐 token 对照(继承 F2/F5-1/Closure
   v4 验证思想;m2b 的段表重建子代应作为 M3 的重点配置——未物化
   状态的消费性在 M2 只做了单步冒烟)。
2. M4(rehydration tax,交替对照)按序在后,不跳门。
3. **待审核方对 M2 作终判**;Track E 正式命名待真源定夺。
