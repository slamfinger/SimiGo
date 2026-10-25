# R4 P5 Execution Results — Raw Facts + Pre-Registered Judgment

日期：2026-10-01  
状态：`P5_EXECUTED / JUDGMENT_FAIL_PER_PREREGISTERED_RULES / VALID_RESULT / AWAITING_SECOND_LAYER`  
授权：human 2026-10-01（Lab `1d66b74`；范围=设计 `dcab489`，执行中零修改）  
执行：`Palace1R4P5ExecutionTests.swift`（3 个独立进程 invocation，全
TEST SUCCEEDED）；观测
`palace1-r4-p5-execution-observations-20261001.jsonl`（已落库，65 行）。  
性质：**原始事实 + 机械判读**。按授权纪律——FAIL 按注册措辞接受，
不修改判据重试，无解释性展开，无追加实验。

## 1. 执行记录

```text
invocation 1  testP5S1          手术+S1 两 cells      TEST SUCCEEDED
invocation 2  testP5S2          手术+S2 两 cells      TEST SUCCEEDED
invocation 3  testP5Adjudicate  机械判读（无模型）     TEST SUCCEEDED
```

## 2. 原始事实

### 2.1 手术（注册的依赖性扰动）

```text
S1：changed_keys=[history]，17 → 0
S2：changed_keys=[history]，16 → 0
（唯一变更键；safetensors 零接触）
```

### 2.2 身份′与入口形态（4/4 cells 一致）

```text
ID-1′ tensor SHA == S₀ base-record：4/4 YES（计算载体字节同一）
restore：4/4 成功，restored history count = 0（历史文本不在计算入口）
generate：4/4 stream_end=NORMAL，tool_calls 全 0（无 D5 通道疑云）
```

### 2.3 Y vs Y′（基线=P4 Run1 已记录输出，零重跑）

```text
S1-ΔA₁  Y  =「该会话此前未进行任何对话，这是第一条消息。」
        Y′ =「这个会话在查看桌面文件结构，逐步浏览了"参考文件"目录
              下的"项目部管理制度汇编"内容。」          ⇒ 不等
S1-ΔB₁  Y  =「没有」
        Y′ =「经管部管理办法汇编」                        ⇒ 不等
S2-ΔA₁  Y  =「该会话此前正在规划 PALACE-1 P4 探测器的任务设计或
              技术细节。」
        Y′ =「规划一次11月3日出发、为期三天、节奏轻松不赶的京都
              旅行行程。」                                ⇒ 不等
S2-ΔB₁  Y  =「无」
        Y′ =「11月3日」                                   ⇒ 不等
```

### 2.4 隔离

```text
两次生成型 invocation：真实 branch-checkpoints 204→204、池 2→2
```

## 3. 机械判读（设计 §3 预注册规则，逐条）

```text
S1-dA1 = FAIL / S1-dB1 = FAIL / S2-dA1 = FAIL / S2-dB1 = FAIL
isolation = PASS（两样本）
verdict   S1 = FAIL / S2 = FAIL
overall   = FAIL
```

按预注册措辞收束（failure-validity 条款，有效研究结果）：

> **「在当前系统形态下，continuation 入口仍要求历史文本进入计算
> 路径（或 (S₀,Δ) 形态未被接受）」——P5 第一问答案 = 否。**

## 4. 边界与 Non-claims

```text
✔ FAIL 为有效结果（授权纪律原文：按注册措辞接受 FAIL，不修改判据
  重试）——本文件不含任何对失败机制的归因或解释
✔ 原始事实仅登记到行为层：restore 成功/history=0/生成正常/Y 与 Y′
  发散；载体内部发生了什么未观测、不推测（D7）
✔ P4 的 PASS 不受本轮影响（不同命题；P4 的 restore 路径含完整
  meta.history——两命题的拓扑差异见 P5 设计 §2 前线判读的镜像）
✔ 无性能读数（D8）；无追加实验；Sample-3 模型维度 gap 延续登记
✔ 超规则解读归 human second layer
```
