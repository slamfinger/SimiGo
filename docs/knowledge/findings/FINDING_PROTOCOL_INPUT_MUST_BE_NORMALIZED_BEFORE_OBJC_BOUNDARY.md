# Finding：协议输入必须在进入 Foundation / ObjC 边界前完成类型归一化

**日期**：2026-09-22

## Finding

2026-09-19 的生产冻结复现表明，协议字段 tools: null 在 parseChatParams 中被强制送入 JSONSerialization，触发不可由 Swift try? 捕获的 ObjC exception，并最终表现为服务级冻结。

最小修复不是增加 watchdog 或连接队列，而是在进入 Foundation / ObjC API 前完成输入类型守卫。

## Evidence

- docs/lessons/incident-app-crash-and-server-hang-2026-09-19.md
- docs/experiments/V17_RUNTIME_MATRIX/ 的复现与最小补丁回归证据

## Architectural implication

协议层应负责：
1. 识别 nullable / optional 输入；
2. 将外部 JSON 表示归一化为内部语义；
3. 只有通过类型检查后才进入可能触发 ObjC exception 的 API。

Runtime watchdog、listener 隔离等只能作为故障缓解，不能替代边界输入正确性。

## Boundary

该 Finding 针对已确认的 tools:null 路径，不意味着所有 Foundation / ObjC 异常都能用相同方式处理。
