# Release Plan — REL-56ff

## 1. 发布范围与组件清单

| 组件代码 | Flag 状态 |
|---|---|
| COMP-0cce | assigned |
| COMP-1872 | assigned |
| COMP-0137 | assigned |

## 2. Rollout 三阶段排程

| 阶段 | 目标比例 | 执行窗口 | 前置条件 |
|---|---:|---|---|
| Phase 1 | 14% | Maintenance window MW-0a05 | 组件清单确认；各组件 flag 均保持 assigned |
| Phase 2 | 50% | Maintenance window MW-0a05 | Phase 1 完成且发布通道 REL-56ff 状态正常 |
| Phase 3 | 100% | Maintenance window MW-0a05 | Phase 2 完成且无阻断异常 |

## 3. Maintenance Window 标注

- 全部 rollout 阶段均在 **MW-0a05** 内执行。
- REL-56ff 的生产激活尚未启动，需在 MW-0a05 内按 Phase 1 → Phase 2 → Phase 3 顺序执行。
