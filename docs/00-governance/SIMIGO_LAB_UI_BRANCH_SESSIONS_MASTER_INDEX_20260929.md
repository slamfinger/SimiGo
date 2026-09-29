# SimiGo Lab UI Branch Sessions Master Index — 2026-09-29

## Result

```text
UI_BRANCH_SESSIONS = CONSOLIDATED_PASS_WITH_BOUNDARY / EVIDENCE_INDEX_COMPLETE / PRODUCT_PERSISTENCE_OPEN
```

新的 master index把 UI1–UI14纳入同一 evidence index。它是 harness-level evidence
index，不是 product UI、persistent session实现、production cancellation readiness或
performance benchmark。

## Scope

```text
backends   = LLAMA GGUF Cyber-Tiel; oversized MLX Qwen3-Coder-Next
workloads  = depth-1 branch; nested/repeat; cancellation; long-running branch;
             long-running cross-backend matrix; LLAMA/MLX controlled
             memory-pressure action pilots
boundary   = harness-level prefix representation; different model artifacts/tokenizers
```

## Entry index

| ID | Scope | Status | Artifact |
| --- | --- | --- | --- |
| UI1 | LLAMA depth-1 pilot | PASS | `ui-branch-session-llama-pilot.json` |
| UI2 | MLX oversized pilot | PASS | `ui-branch-session-mlx-oversized-pilot.json` |
| UI3 | depth-1 same-shape cross-backend matrix | PASS_WITH_BOUNDARY | `ui-branch-session-crossbackend-matrix.json` |
| UI4 | LLAMA nested + repeat | PASS | `ui-branch-session-llama-nested-repeat.json` |
| UI5 | MLX nested + repeat | PASS | `ui-branch-session-mlx-nested-repeat.json` |
| UI6 | nested same-shape cross-backend matrix | PASS_WITH_BOUNDARY | `ui-branch-session-nested-crossbackend-matrix.json` |
| UI7 | LLAMA explicit cancellation | PASS | `ui-branch-session-llama-cancellation.json` |
| UI8 | MLX cooperative cancellation | PASS | `ui-branch-session-mlx-cancellation.json` |
| UI9 | cancellation cross-backend outcome matrix | PASS_WITH_BOUNDARY | `ui-branch-session-cancellation-crossbackend-matrix.json` |
| UI10 | LLAMA six-turn long-running branch | PASS | `ui-branch-session-llama-long-running.json` |
| UI11 | MLX six-turn long-running branch | PASS | `ui-branch-session-mlx-long-running.json` |
| UI12 | long-running cross-backend outcome-shape matrix | PASS_WITH_BOUNDARY | `ui-branch-session-long-running-crossbackend-matrix.json` |
| UI13 | MLX controlled memory-pressure action | PASS | `ui-branch-session-mlx-memory-pressure.json` |
| UI14 | LLAMA controlled memory-pressure action | PASS | `ui-branch-session-llama-memory-pressure.json` |

## Coverage checks

| Check | Result |
| --- | --- |
| `ALL_ENTRY_REPORTS_PASS` | PASS |
| `ALL_ENTRY_STATUSES_EXPECTED` | PASS |
| `DEPTH1_LLAMA_AND_MLX_PRESENT` | PASS |
| `DEPTH1_CROSSBACKEND_MATRIX_PRESENT` | PASS |
| `NESTED_LLAMA_AND_MLX_PRESENT` | PASS |
| `NESTED_CROSSBACKEND_MATRIX_PRESENT` | PASS |
| `CANCELLATION_LLAMA_AND_MLX_PRESENT` | PASS |
| `CANCELLATION_CROSSBACKEND_MATRIX_PRESENT` | PASS |
| `NO_PRODUCT_UI_CLAIM` | PASS |
| `NO_PERSISTENT_SESSION_CLAIM` | PASS |
| `LONG_RUNNING_LLAMA_PRESENT` | PASS |
| `LONG_RUNNING_MLX_PRESENT` | PASS |
| `LONG_RUNNING_CROSSBACKEND_MATRIX_PRESENT` | PASS |
| `ENTRY_COUNT_MATCHES` | PASS |
| `MEMORY_PRESSURE_MLX_PRESENT` | PASS |
| `MEMORY_PRESSURE_LLAMA_PRESENT` | PASS |

## Consolidated observations

1. Depth-1 Execution State semantics在 LLAMA和 oversized MLX上均有 PASS evidence。
2. Nested graph和 repeated release/restore/switch在两个 backend上均有 harness-level
   PASS evidence；cross-backend same-shape matrix也 PASS。
3. Cancellation outcome-shape matrix在 LLAMA explicit DELETE与 MLX cooperative
   token-boundary cancel之间 PASS；机制差异保留，不伪装为同一 primitive。
4. LLAMA和 MLX long-running branch均能 restore到 fork point和 final position，
   且 sibling/root survival semantics保持。
5. 所有结果都是 harness-level observation，不是 product UI、persistent session、
   production cancellation readiness或 performance benchmark。
6. UI10和UI11均已验证 six-turn long-running branch的 fork-point/final-position
   restore；UI12跨backend outcome shape一致，但模型 artifact、tokenizer和
   execution engine不同；这不构成 same-checkpoint closure、persistent session或
   performance equivalence。
7. UI13验证 multi-branch controlled release/restore pressure action下的
   recovery exactness、release semantics、root/control survival和 zero swap。
   这是 session pressure action，不是 OS memory pressure。
8. UI14在 LLAMA prefix-representation harness上验证相同的 controlled pressure
   outcome semantics。LLAMA release action作用于 Swift prefix registry，不代表
   llama-server native cache释放。

## Master artifact

```text
simigo2-experimental/results/backend-conformance/ui-branch-sessions-master-summary.json
```

## Open items

```text
PRODUCT_UI_SURFACE
PERSISTENT_OR_MULTI_PROCESS_SESSIONS
ARBITRARY_DEPTH_BRANCH_GRAPH
SAME_MODEL_OR_SAME_CHECKPOINT_CROSS_BACKEND_CLOSURE
MEMORY_PRESSURE_CROSSBACKEND_UI_MATRIX
OS_MEMORY_PRESSURE_INJECTION_VALIDATION
PRODUCTION_CANCELLATION_READINESS
```

## Non-claims

```text
❌ product UI
❌ persistent / multi-process session
❌ arbitrary-depth branch graph
❌ same-checkpoint cross-backend closure
❌ production cancellation readiness
❌ performance benchmark
❌ OS memory-pressure validation
```
