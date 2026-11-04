# Invariant：Session 在完成可复用条件前不得进入可复用池

**日期**：2026-09-22

## Invariant

Session 对象存在，不等价于 Session 可复用。

尤其在新建 session 的 prefill 尚未成功完成即被取消时，session 必须保持不可复用状态或被逐出；不得仅以 sessions[key] 是否存在判断 readiness。

## Evidence

- docs/lessons/cancel-mid-prefill-poisoned-session-2026-09-17.md
- 2026-09-17 真机前后对照：修复前同 key 可复用毒 session 导致重复挂起；修复后逐出并重新建立健康 session。

## Scope

当前最小实现使用 rawEv == 0 作为诊断辅助条件。该条件不是长期完整语义。

## Target Model

长期应显式区分：

ABSENT → READY → RUNNING
           ↘ INVALID

其中只有 READY 才允许作为后续请求的可复用 session。

## Boundary

该 invariant 针对 session 生命周期与复用资格，不规定 Physical KV 的内部实现，也不把复用路径中途取消自动判定为同一类“毒 session”。
