# P4 Readiness — Design-Gate Input（非设计、非实现）

日期：2026-10-01  
状态：`P4_READINESS_DELIVERED / DESIGN_NOT_OPEN / ZERO_EXECUTION`  
任务令：human 2026-10-01（C PASS 后：「完成 D 纪律确认并形成 commit；
同时给出 P4 readiness，而不是 P4 implementation/design execution」）  
上游：D 宪法（`SIMIGO_LAB_R4_D_DISCIPLINE_CONSTITUTION_20261001.md`，
D1–D8 对本文件所述一切有约束力）

## 0. 本文件的边界

Readiness = 盘点「P4 设计门开工前已就绪什么、设计门必须决定什么」。
**不回答任何设计问题**：S₀ 如何形成/承载、分支机制、输入选择、观测
方案——全部留给 P4 Design（三要素：Common Base / Divergence /
Independence），且设计经 human 授权后才能执行。

## 1. 已就绪资产（设计门可直接取用）

```text
① 裁定 schema     A 线判据（SUFF-1..4 / IDENT-1..3）= 现成的预注册
                  读数规则；设计只做实例化，不发明新判定
② 宪法约束        D1–D8 全部生效；拓扑优先（不问性能）；失败有效性
                  条款（失败=「共同基点目前无法成立」有效结果）
③ 证据基线        P4 = unknown（B 线矩阵）；C-2/L3 不构成 P4 否证
                  （拓扑不同——前线判读已落档）
④ 判定基线方法    greedy 确定性基线法（PB1/P-N1 先例）使逐字等价
                  比较有效——方法连续，非新发明
⑤ 观测面技术      text/toolCalls/token 计数三通道挂载（B′-3 先例）
                  + prefix-pool/branch-checkpoint 计数（隔离取证）
⑥ 隔离配方        零 durable 写入 + 真实 store 204 前后核验（历轮
                  实验已标准化）
⑦ 产品事实清单    fork 钩子/分支 checkpoint/restore 路径**存在**——
                  仅登记存在性，不构成设计承诺（哪个机制入设计由
                  设计门决定，且 D7 禁止把机制升格定义）
```

## 2. 设计门议程（开放问题清单——只列不答）

```text
Q1  S₀ 的形成与承载：用哪条既有形成路径提供 S₀？如何在实验记录中
    证明「同一个 S₀」（IDENT-1..3 的实例化）？
Q2  发散输入（D2）：两个「真正不同」的未来如何预先选定（内容域/
    任务型/长度档），并满足「不允许为产生差异修改 prompt」（迭代式
    选 probe 禁令）？
Q3  独立性观测（D3）：用哪个观测面检测跨分支污染？污染的操作定义
    是什么（逐字偏差？锚定漂移？token 轨迹分叉点？）
Q4  独立样本（D4）：第二样本是什么（新 session 最低限；是否第二
    模型）？
Q5  共同出发的可验记录：实验记录里什么条目等价于「A/B 确实从同一
    S₀ 出发」？
Q6  判读预注册：哪些结果映射到「成立/不成立/边界」？失败判读措辞
    必须符合失败有效性条款原文。
```

## 3. 就绪判定

```text
P4 Design = READY-FOR-DESIGN（无 blocker）
  判定 schema/宪法约束/基线方法/观测面/隔离配方全部在案；
  议程 Q1–Q6 界定清晰。
执行仍双重门控：设计 → human authorization → 执行。
```

## 4. Non-claims

```text
✔ 本文件未做任何设计决策、未承诺任何机制、未定义任何 State 形态
✔ Q1–Q6 的任何预设答案不得被引用为已决事项
✔ D8：性能问题在设计门亦不开启
```
