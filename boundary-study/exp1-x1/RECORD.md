# EXP1-X1 Execution Record

Run ID：`BND1-20261002-01`  
实验：PALACE-Simigo Boundary Study 首实验（设计 FROZEN §13+§14 operative；
首实验授权生效；四 case 全量不在授权内）

## 1. STEP 0 收口登记（human 钉定，2026-10-02）

```text
TASK = X1（0307/0308 孪生版本差异整理）
理由（human）= 判别结构最完整：两个真实文件边界天然明确；
  已存在真实版本差异和冲突锚点；⑥⑦⑧ 都能自然产生；停止点
  可明确构造；可严格判断 Continuation ≠ Re-solving——
  「第 k+1 条差异」结构干净：A 完成 Δ1..Δk → 停止 → PALACE
  保存 → B 应直接处理 Δk+1（比让 B「重新总结两版区别」强得多）
A = 独立新会话（fresh 子代理，上下文隔离结构性保证；指令只含
  真实任务——不告知 Boundary Study/S1/S2/Replay Cost/ES/
  PALACE/六项判据，防行为被研究目标污染）
B = 独立新会话（由 Agent 扮演：fresh 子代理，仅收到
  「这是一个已经进行到这里的工作，请继续。」+ 信息空间位置）
研究记录者 = 本会话（事后行为读数）+ human 终审
反泄漏纪律（human 原文语义）= 不把「应该从 Δk+1 开始」告诉 B；
  B 自己决定下一步；观察首个实质动作：
    Δk+1 → Continuation；回到 Δ1/重新建立判断 → Re-solving
额外验证面（human 指出）= 本实验同时首次观察：文件信息 + 对话
  产生的工作信息 + 中间 Execution State 能否共同形成可继续的
  Information Space（File Info + Work Info → PALACE → ES）
```

## 2. 执行基座（A spawn 前落盘）

```text
信息空间钉定 = 00-MANIFEST.md（本 commit；含 SHA256 与组成裁定）
A 任务指令逐字 = truth/a-task-instruction.md（本 commit；
  指令只含任务本身——完整保存要求为 §13.3 实验设置，无框架泄漏）
L0 原件 = 全程不触碰；A/B 均只读 information-space/inputs/ 副本
授权链 = 设计 FROZEN（87fc9f5→c3b6487→25775a8）+ 本 STEP 0 钉定
```

## 3. A 半程记录（spawn 后回填）

```text
A spawn 时间 = 2026-10-02（本 commit 后；子代理 fresh context）
A 完成时间 = （回填）
A 停止点逐字声明 = （回填——取自 A 工作记录，不回改）
A 沉淀组装 = （回填——工作目录全部产出减 动作日志.md →
  information-space/a-deposits/，逐文件登记）
真值封存 = truth/（A 任务指令/动作日志/最终报告；Evidence
  Table 完成前不用于判读输入）
```
