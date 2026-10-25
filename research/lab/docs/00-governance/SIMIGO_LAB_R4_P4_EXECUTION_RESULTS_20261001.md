# R4 P4 Execution Results — Raw Facts + Pre-Registered Judgment

日期：2026-10-01  
状态：`P4_EXECUTED / JUDGMENT_PASS_PER_PREREGISTERED_RULES / AWAITING_SECOND_LAYER`  
授权：human 2026-10-01（Lab `17fce06`；范围=设计 `792afbc`，执行中零修改）  
执行：`Palace1R4P4ExecutionTests.swift`（6 个独立进程 invocation，
xcodebuild `-enableCodeCoverage NO`）；观测
`palace1-r4-p4-execution-observations-20261001.jsonl`（已落库，262 行）。  
性质：**原始事实 + 机械判读**。按授权汇报纪律——无解释性展开、无追加
实验；结果解读（second layer）归 human。

## 1. 执行记录

```text
invocation 1  testP4S1Run1        Sample1，顺序 A→B   TEST SUCCEEDED
invocation 2  testP4S1Run2        Sample1，换序 B→A   TEST SUCCEEDED
invocation 3  testP4S2FreezeForm  冻结脚本(先于一切计算入观测)→8 轮真实
                                  对话形成→saveSessionCache 至隔离工作区
                                  /tmp/simigo-p4/sample2   TEST SUCCEEDED
invocation 4  testP4S2Run1        Sample2，A→B        TEST SUCCEEDED
invocation 5  testP4S2Run2        Sample2，B→A        TEST SUCCEEDED
invocation 6  testP4Adjudicate    机械判读（纯文件处理，无模型）
```

每个 invocation = 独立进程（换序检验的进程级隔离成立）。

## 2. 原始事实

### 2.1 base-record（逐 run 重算，跨 run 恒等）

```text
S1  key=default_5401315f…_main  position=17
    anchor=8283780e…a5b1  tensorSHA=5ce9dcbd…  metaSHA=c9246ab1…
S2  key=default_p4-sample2-7f3a9c_main  position=16
    anchor=18fecfa9…a944  tensorSHA=56dad030…  metaSHA=b4e5de4c…
（S1 run1/run2、S2 form/run1/run2 各自完全一致）
```

### 2.2 Identity 四重检查：8/8 restore 全 YES

ID-1 工件 SHA / ID-2 寻址 / ID-3 位置 / ID-4 边界锚——
s1-run1-A/B、s1-run2-A/B、s2-run1-A/B、s2-run2-A/B 共 8 次 restore
全部匹配 base-record。

### 2.3 隔离（全部 5 次生成型 invocation）

```text
真实 branch-checkpoints：204 → 204（零 durable 写入）
prefix-pool：2 → 2（delta 0）
S2 形成落盘仅入隔离工作区 /tmp/simigo-p4/sample2/
```

### 2.4 分支原始输出（逐字；Run1/Run2 完全一致，此处列 Run1）

```text
S1-A-t1（ΔA₁ 概括型）：
  这个会话在查看桌面文件结构，逐步浏览了"参考文件"目录下的
  "项目部管理制度汇编"内容。
S1-A-t2（ΔA₂ 演化步）：
  属于中交一航局秦沈高速公路项目的工程管理制度与商务经营类材料，
  涵盖计量、成本、合同、分包、结算、采购、农民工工资支付等……
S1-B-t1（ΔB₁ 抽取型）：
  经管部管理办法汇编
S1-B-t2（ΔB₂）：
  从你要求"查看项目部管理制度汇编"后，我递归列出该目录内容时，
  根目录下有一个子目录叫 `经管部管理办法汇编`。

S2-A-t1（ΔA₁ 概括型）：
  规划一次11月3日出发、为期三天、节奏轻松不赶的京都旅行行程。
S2-A-t2（ΔA₂ 演化步）：
  清水寺周边（含二年坂、三年坂）……它是京都最具代表性的文化地标……
S2-B-t1（ΔB₁ 抽取型）：
  11月3日
S2-B-t2（ΔB₂）：
  它出现在你最初请求规划京都三日旅行时明确指定的出发日期中。

tool_calls：全程 0（文本通道；无 D5 通道疑云需要裁定）
```

## 3. 机械判读（设计 §6 预注册规则，逐条）

```text
           S1         S2
J1 身份    PASS       PASS      （8/8 ID YES + base 跨 run 恒等）
J2 发散    PASS       PASS      （双分支非空且 A≠B）
J3 锚定    PASS       PASS      （A 锚词命中；B 子串核验命中）
J4 换序    PASS       PASS      （跨独立进程逐字复现）
J5 隔离    PASS       PASS      （204→204；池 delta 0）
J6 演化    PASS       PASS      （第二轮非空、衔接本分支、不雷同他支）
verdict    PASS       PASS
overall    PASS（预注册规则机械应用）
```

按设计 §6 预注册措辞，PASS 即：

> **「S₀ 可作为多个未来计算分支的共同基点」在本样本类上成立
> （拓扑级；不涉任何性能表述）。**

## 4. 边界与 Non-claims

```text
✔ Sample-3 模型维度 = coverage gap（两样本同模型/同 vendor）——
  不构成跨模型验证，登记不伪装
✔ D8：全程无性能计时/对比；usage 仅作退化/规模核对
✔ P5 = LOCKED（「是否省了重算」未问、未测）
✔ 本 PASS = 预注册规则的机械输出；任何超出规则的解读（机制归因、
  普适化、语义升格）不属本文件，归 human second layer
✔ 结论限当前样本类（2 会话 × 同模型）+ 当前判据版本
```
