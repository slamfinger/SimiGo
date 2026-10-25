# SimiGo Lab UI Branch Sessions Cancellation — 2026-09-29

## Result

```text
UI7 = PASS / LLAMA_SESSION_CANCELLATION_WITH_BOUNDARY
```

登记：

```text
UI_SESSION_EXPLICIT_CANCEL_RECOVERY_PASS
UI_CANCELLED_BRANCH_PHYSICAL_RELEASE_PASS
```

这是 LLAMA harness pilot；不是 cross-backend cancellation closure 或生产
readiness claim。

## Session graph

新增 `UIBranchSessions.runCancellationLLAMA` 与 CLI
`llama-branch-session-cancel`。每轮建立：

```text
root
├── long branch       -> explicit LLAMA stream, then cancel
├── control branch    -> sibling identity control
└── recovery branch   -> forked only after cancel
```

Lifecycle：

```text
create / bind root
fork long + control
capture long physical prefix
start long stream
wait cancel-delay
DELETE stream
wait all slots idle
release cancelled long prefix
restore root
verify root replay identity
fork recovery branch
restore / replay control branch
```

## Validation

使用 canonical mitigated LLAMA profile：

```text
Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL
ctx2048 / parallel4 / slot512
ubatch8 / threads4 / threads-batch4
cycles2 / cancel-delay100ms / seed42
```

八项 checks 全部 PASS：

| Check | Result |
| --- | --- |
| `CANCEL_ACCEPTED` | PASS |
| `CANCELLED_SLOT_FREED` | PASS |
| `CANCELLED_LONG_PHYSICAL_RELEASED` | PASS |
| `ROOT_RECOVERY_IDENTICAL` | PASS |
| `CONTROL_RECOVERY_IDENTICAL` | PASS |
| `ROOT_AND_CONTROL_PREFIXES_DIVERGED` | PASS |
| `RECOVERY_LINEAGE_ISOLATED` | PASS |
| `CYCLES_COMPLETE` | PASS |

两次 explicit stream DELETE 均返回 `204`；cancelled long prefix 的 physical
binding 都成功 release。取消后 root replay 和 control sibling replay 均与取消前
一致。observation 中的 DELETE→free latency 只记录当前 pilot 行为，不建立性能
结论。

同一 commit 全仓 Swift verification：

```text
157 PASS / 0 FAIL
```

计数来源：`SimiGoRuntimeContractTests 19` + `SimiGo2ExperimentalTests 137` +
Swift Testing `1`。

## Artifact

```text
simigo2-experimental/results/backend-conformance/ui-branch-session-llama-cancellation.json
```

## Boundary

结果限定 current LLAMA model、canonical mitigated profile、single seed、short
recovery completions、explicit stream cancellation 和 harness-level prefix
representation。long stream 与 logical prefix branch 是不同层面的执行载体；
本实验验证 Swift Session control plane 在 explicit backend cancel 后能否保持
root / sibling / recovery 的 Execution State semantics，不修改 native KV
authority。

## Non-claims

```text
❌ MLX / cross-backend cancellation closure 已完成
❌ cooperative MLX cancellation UI matrix 已完成
❌ production cancellation 已验证
❌ persistent / multi-process session 已验证
❌ performance 结论已建立
```

## Next

1. 将 W9 cancellation 扩展到 oversized MLX cooperative cancellation。
2. 若两边 PASS，再做 same-shape UI cancellation cross-backend matrix。
3. 继续保持 CLI control plane，暂不构建 UI surface。
