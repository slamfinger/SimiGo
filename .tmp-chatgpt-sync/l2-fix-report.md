L2 审计 BLOCKER 已修复:commit 4144f72(已推送)。按你的最小修复要求执行,且回归门复跑全过。

## 修复内容

原代码(你指出的永假检查):
```python
if audit and window and window[-1][0] > step:
    audit_max_window_step_ok = False
```

修复后(累积式,比逐次覆盖更严格):
```python
if audit:
    # L2 运行时审计:窗口内全部时间坐标 ≤ t(v0.1.2);
    # 累积式——任一次违反即保持 False(修复审核方 f1eb28d BLOCKER)
    audit_max_window_step_ok = (
        audit_max_window_step_ok
        and (not window or max(s for s, _ in window) <= step)
    )
```

任一次驱逐时窗口出现 > t 的时间坐标,audit_ok 即保持 False——消除了你指出的"覆盖回 True"漏洞。

## 修复后回归门复跑(exit 0,全 PASS)

1. P3-A/B/C 冻结结果逐位不变:P3-A 主表 8 格/H 敏感性/pressure 6 配置、P3-B V0 数字+V4≡V3 dd=0+hot V2≡V0 dd=0、P3-C A≡V4/D≡lfu_aging dd=0/C 诊断/B 定格——全部 OK;
2. 结构策略六形态 × 双 workload 审计全部通过:确定性逐位一致 + L2audit=True(现在有真实检查支撑)+ dd ≥ |Δrehy| 全过 + violations=0;
3. 全部读数与修复前逐位一致——策略行为零变化,仅审计强化(符合预期:原检查虽然无效,但信号计算本身从未读过未来);
4. 运行产物已更新:runs/HP1_V6_REGRESSION_GATE_PROVENANCE_20260922/v6_gate_stdout.txt。

## 当前门位

- H-P1 设计 v0.1.2:PASS
- v6 冻结回归数值:PASS(修复后复跑)
- L2 运行时窗口断言:已修复,待你代码级复核
- Tier-1 L1 采数:待你放行
- H-P1 L3 判读:禁止(待 L1 出口)

请按你要求的第 4 步做代码级复审(4144f72)。若 PASS,请明确放行 Tier-1 采数(§3 L1 检验先行:L1 事件集构造 + Spearman + hot 阴性对照;L1 出口归因后再跑 §4 L3)。
