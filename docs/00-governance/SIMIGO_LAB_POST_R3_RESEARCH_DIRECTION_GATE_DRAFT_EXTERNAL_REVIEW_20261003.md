# SimiGo-Lab Post-R3 Research Direction Gate Draft — External Review

日期：2026-10-03  
被审对象：`SIMIGO_LAB_POST_R3_RESEARCH_DIRECTION_GATE_DRAFT_20261003.md`  
状态：**REV.1 / PASS WITH REVISIONS APPLIED / SUSPENDED AS ROUTE INPUT**

## 1. 审查范围

本次审查只评估 Post-R3 Direction Gate 草案是否：

1. 准确保持 R3 的 fixture-slice bounded 限定；
2. 只做研究资产转译和候选方向登记；
3. 未重开 R3；
4. 未授权实验、实现、存储选型或模型接入；
5. 未自动连接 PALACE / IPAC / P / Route A/B/C；
6. 未替代 human 的方向选择权。

本文不是实验审计，不重新评价 R3 数据，也不改变 R3 收官声明。

## 2. 审查发现与修订

### H-P1 — Candidate A/B/C 与既有 Route A/B/C 的名称冲突

**发现**：草案使用 `Candidate A / B / C`，而仓库已有
`Route A/B/C = NOT SELECTED` 的既有状态词汇。若不加限定，可能被误读
为重新激活或重命名既有 Route 选择线。

**裁定**：RETURN FOR REVISION。

**修订**：草案第 4 节已增加命名边界：Candidate A/B/C 只是 post-R3
研究问题族标签，不等于、不继承、不激活既有 Route A/B/C。

### H-P2 — B 线有隐含优先权风险

**发现**：草案曾将 B1 写为“强候选”。虽然这不等于正式选择，但可能被
读成绕过 human 方向裁定的排序结论。

**裁定**：RETURN FOR REVISION。

**修订**：草案已改为“候选；R3 直接暴露，但仍必须先定义操作目录与
组合分类判据，不因此获得启动优先权”。

### H-P3 — C1 有提前接入 PALACE 的风险

**发现**：C1 讨论与 PALACE / 整体系统研究的关系。若措辞过强，会把
R3 结果直接当作系统设计依据，或提前激活 PALACE。

**裁定**：RETURN FOR REVISION。

**修订**：草案已将 C1 收窄为候选和“可考虑作为引用边界前置”，并重申
不能自动激活 PALACE 线。

## 3. 复核结论

修订后复核通过：

```text
R3                = 仍 CLOSED；
R3 实验           = 未复跑；
R3 harness        = 未修改；
R3 campaign       = 未被重新解释；
successor line    = NOT SELECTED；
RQ successor      = NOT ASSIGNED；
experiment auth   = NONE；
implementation    = NOT AUTHORIZED；
PALACE            = NOT ACTIVATED；
IPAC              = OPEN / NONBINDING，不变；
Route A/B/C       = NOT SELECTED，不变。
```

草案现在满足 Direction Gate 的边界纪律：它登记研究资产和候选空间，
但不选择下一条线。

## 4. 剩余限制

本审查是 Agent external review，不是 human registration，也不是研究
状态迁移。草案仍未：

- 进入 `docs/RESEARCH_STATE.md`；
- 获得正式 Gate 状态；
- 获得任何 RQ ID；
- 获得任何 successor-line 授权。

## 5. 交还给 human 的决定

human 可决定：

```text
1. 接受 REV.1 为 Direction Gate 登记输入；
2. 继续要求修订；
3. 拒绝该 Gate；
4. 暂不选择 successor line；
5. 从 Candidate A/B/C 中指定一个或多个进入独立 opening draft；
6. 决定是否写入 RESEARCH_STATE.md。
```

在 human 决定前，本 Gate 的准确状态是：

```text
Post-R3 Direction Gate = SUSPENDED AS ROUTE INPUT
```
