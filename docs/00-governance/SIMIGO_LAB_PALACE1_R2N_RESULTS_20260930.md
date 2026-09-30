# PALACE-1 E1-R2n Results — history Necessity for Cold Reconstruction

日期：2026-09-30  
状态：`R2N COMPLETE / AWAITING SECOND-LAYER`  
问题（human 裁定措辞）：**改变 history → cold reconstruction 的实际行为
是否改变？**（integrity boundary 已由 E1.5-Q2 钉死；本轮补 necessity
boundary）  
隔离（全程零产品代码修改、零 durable 写入）：

```text
SIMIGO_PREFIX_POOL=0（产品自带 env 开关，经 TEST_RUNNER_ 转发生效）
+ RuntimeTuning.conditionalRestoreEnabled=false（产品 static-var 可调面，
  测试进程内）
+ 每用例独立 sessionId → 强制 cold-start 分支（NativeMLX:763-778）
实测 durable 写入 = ZERO（branch-checkpoints 204 前后不变；pool 24 不变）
```

执行：`Palace1E15bHistoryNecessityTests.swift`（加法式）；69.3s；
TEST SUCCEEDED；观测 `r2n-observations.jsonl`（已落库）。
执行披露：直连 generate 须先按产品客户端协议注册
`RuntimeLifecycleCoordinator`（HTTP server 的常规动作）；env 转发须用
`TEST_RUNNER_` 前缀（xcodebuild 机制——同时解释了 E1 期 TEST_RUNNER_HOME
无效的原因）。

## 1. 预登记对照

| 预登记 | 观测 | 判定 |
|---|---|---|
| P-N1 greedy 确定性（n0a ≡ n0b） | 两次响应逐字相同 =「继续执行。」 | **CONFIRMED** |
| P-N2 history 内容扰动（尾条 assistant 追加 needle）→ continuation 改变 | n1 =「收到，需要我深入查看哪个具体文件的内容？」≠ n0（模型把 needle 当成了新指令语境） | **CONFIRMED** |
| P-N3 工具历史全删（3 条）→ continuation 改变 | n2 =「I don't know what "PALACE-1 R2n probe" refers to…」（模型失去指代） | **CONFIRMED** |

## 2. 判定提升（按 human 术语）

```text
history：
  E1.5-Q2   restore 接受扰动          → integrity boundary 之外
  R2n       扰动 → continuation 改变  → necessity boundary 之内
  ⇒ 状态提升：「continuation semantic candidate」
    → observed continuation-bearing durable information
  （仍然不叫 State——E3 与更多扰动面未做）

modelId：human 判定采纳——移至 nucleus candidate 外围
  （compatibility context，非 State 本体；restore 门 + container 选择）

当前 nucleus candidate（精化后）：
  caller-key 寻址 + history（observed continuation-bearing）
  外围：modelId（compatibility context）
```

## 3. E0 → E1 → E1.5 → R2n 证据链（完整版）

```text
物理层    E0   4.7GB = 40层×K/V（BF16/F32 混合）；position 有 token 长度
               物理影子 ≠ Contract 逻辑轮次
恢复层    E1   R0 meta 三键自足识别；R1 原生 restore 把 safetensors 作为
               前置（fail-closed ×3）；R2 能力 = cold-start 一等分支
验收层    E1.5 restore 验收边界：storageKey 字段值=informational；
               history 无完整性门；generation=presence；SHA=表示字节；
               modelId=兼容
必要层    R2n  history 内容扰动 → continuation 改变（P-N2）；
               tool 执行历史删除 → 模型失去指代（P-N3）；
               greedy 确定性成立（P-N1，比较方法有效）
```

## 4. 边界与非声明

```text
✔ 单一样本、单一 probe、贪心解码——necessity 已证「存在性」
  （存在使行为改变的扰动），非「任意扰动都改变」的普适命题
✔ 未宣称 history = State（E3/更多扰动面未做）
✔ 隔离配方 = 产品自带配置面（env + static-var tunable），零产品代码
  修改；durable 写入实测为零
✔ Prefix Pool necessity（E2）未触碰——pool 本轮整体关闭
```
