# PALACE V2 G1 Result Gate — HUMAN RULING REGISTERED

日期：2026-10-02  
对象：G1 主探针（`225741b`）+ 初始可发现性（`4b1e0df`）  
Verdict：**`G1 主探针 PASS`**（结果门裁定逐字登记）  
性质：gate 裁定登记——不产生 PALACE Schema、不产生 Execution State
新定义

## 1. 裁定表（human 原文逐字）

| 项目 | 裁定 |
|---|---|
| G1 主探针 | **PASS** |
| C-1 | **OBSERVED** |
| C-2 | **OBSERVED** |
| C-3 | **OBSERVED** |
| C-4 | **PARTIAL / BOUNDED** |
| C-5 | **OBSERVED** |
| H-G1-01 | **SUPPORTED — exploratory evidence** |
| H-G1-02 | **UNVERIFIED + state-dependency signal** |
| G1 是否已产生 PALACE Schema | **否** |
| 是否产生 Execution State 新定义 | **否** |
| 是否出现 Execution State 相关工程证据 | **是** |
| 下一实验 | **OQ-B：v1 → 修改 → v2** |
| CJK PDF | 暂缓 |
| E6 | 暂缓 |

## 2. H 判定的边界（human 裁定，效力高于记录原文）

### H-G1-01 = SUPPORTED — exploratory evidence

```text
关键证据 = Step3 发现 B 件为「三版/差异」工作表后，后续探索
          路径发生实质改变（超出 query→search→result）
已证明   = 「先前发现的信息会改变后续探索行为」
未证明   = 「必须把该信息持久化到动态索引中才能完成后续探索」
          （替代解释：重读 L0/L1 可重新得到该事实——边界必须守住）
```

### H-G1-02 = UNVERIFIED + Evidence: STATE-DEPENDENCY-SIGNAL

```text
已有 = query-state dependency 迹象（Step3/Step5 依赖此前发现）
控制 = 重读 L0+L1 仍可重算 ⇒ 不能由「过程像 State」反推
      「State 必要」
升格实验（human 指定形态）= 任务 A → 形成中间发现 → 中断 →
  不重新提供完整上下文 → 只恢复已有工作状态 → 继续；
  对照 State restore vs L0/L1 cold recomputation——若无 State
  出现信息损失/路径丢失/重复工作/无法定步（而非仅效率差），
  H-G1-02 才开始具有强证据
```

## 3. 变化溯源三层登记（human 结构）

```text
① 找不到源头（原施工方案 ∉ Corpus-1）= Source Trace Failure
② 找到局部支撑事实（61,540万 → 62,327万 → +787万 ← 三单位汇报）
③ 找到多个数字但无法建立业务口径关系（8.10亿/9.48亿 ×
   313,356万/32.99亿）
——比「可以追溯」的笼统结论更有研究价值
```

## 4. 四类现实证据（human 归纳登记）

```text
第一类  文件名不是信息拓扑：filename sequence ≠ content topology
        （表2 全变 / F6 回到 F3 / F7 回到 F1 / 附表6·7·临时用电不变）
第二类  同名文件不是同一信息：path+filename+mtime+size 不足以
        理解实际工作对象（A=项目部汇总 vs B=三版/差异表）
第三类  时间和「当前状态」不是一回事：8.10亿/9.48亿 + 公式态/
        数值态——「用户当前工作中操作哪个状态」问题出现；
        接近 Execution State 话题但**不定义为 Execution State**，
        保留为 G1 观察
第四类  真实工作过程产生路径依赖（information exploration path）：
        处理信息本身改变下一步处理信息的路径
```

## 5. 强表述登记（human 原文，不越界版本）

> **从首次目录扫描开始，PALACE 的信息工作就可能表现为一个持续
> 演化的执行过程；目录、时间、内容变化构成自然分叉，而用户实际
> 探索的位置决定当前分支。**

尚缺 = 证明该分支是否需要被系统作为可恢复的 State 保留
（OQ-B → 后续 E6 的验证目标）。

## 6. Gate state

```text
G1 REAL CORPUS
├── Corpus-1 selection       PASS
├── Initial Discoverability  PASS
├── Main Probe               PASS
├── C-1/C-2/C-3/C-5          OBSERVED；C-4 PARTIAL/BOUNDED
├── H-G1-01                  SUPPORTED — exploratory evidence
├── H-G1-02                  UNVERIFIED + state-dependency signal
├── PALACE Schema            未产生（禁止不变）
├── Execution State 新定义   未产生
└── 下一实验                 = OQ-B（v1 → 修改一个 cell → v2；
                              极小实验；CJK PDF 暂缓；E6 暂缓）
```
