# SimiGo-Lab O6 MLX Oversized Cancellation A/B — PASS — 2026-09-29

## Decision

Protocol：

```text
RQ3.O6.MLX.OVERSIZED.CANCELLATION.AB.V1
```

Result：

```text
PASS / O6_MLX_OVERSIZED_CANCELLATION_AB_PASS
```

这补上 MLX oversized cancellation/release/recovery 的显式 A/B 缺口。它仍是
harness-level evidence，不是 production cancellation 或 performance claim。

## Implementation

新增：

```text
simigo2-experimental/Sources/SimiGo2Experimental/O6CancellationAB.swift
```

CLI：

```text
simigo2ctl o6-cancel-ab MODEL --cycles 3 --tokens 4 --segment-size 8
```

两臂共用同一真实 Qwen3-Coder-Next-4bit segmented core：

```text
model            Qwen3-Coder-Next-4bit / qwen3_next
segment size     8
max tokens       4
cycles           3
cancel point     one complete greedy token
memory ceiling   30,720 MiB
```

OFF arm：

```text
direct cooperative cancel after one token
→ direct releaseAllSegments()
→ direct full replay
```

ON arm：

```text
coordinator fork child at parent checkpoint
→ cooperative cancel after one token
→ bind/capture cancelled consumed prefix
→ Execution State release oversized representation
→ coordinator restore to fork point
→ representation-consuming replay
```

每个 cycle 交替 OFF/ON 先后顺序。OFF 不执行 binding consume/restore contract
operations，但执行与 ON 相同的 physical `releaseAllSegments()` action。

## Results

全部语义和资源 gate：

| Check | Result |
| --- | ---: |
| cooperative cancel one token | **3/3** |
| direct recovery exact | **3/3** |
| Execution State recovery exact | **3/3** |
| cancelled prefix exact | **3/3** |
| release removed current binding | **3/3** |
| restore to fork point | **3/3** |
| parent non-interference | **3/3** |
| residency bounded / zero swap | **PASS** |
| segment transitions executed | **PASS** |

资源：

```text
peak footprint      8,132 MiB <= 30,720 MiB
max swap            0 MiB
segment transitions 210
```

Diagnostic wall-time 只作 harness 运行记录：

| Metric | Mean |
| --- | ---: |
| direct cancel | `9,284.342ms` |
| direct recovery | `37,626.793ms` |
| Execution State cancel | `9,283.465ms` |
| Execution State fork/capture | `0.008ms` |
| Execution State release/restore | `4.775ms` |
| Execution State recovery | `36,946.490ms` |

不能将上述耗时解释为性能差、性能改进、production cancellation latency 或上游
MLX runtime claim。

Artifact：

```text
simigo2-experimental/results/o6-workload-matrix/
  qwen3-coder-next-4bit-cancellation-ab.json
```

## Verification

修改 Swift 后重新执行：

```text
swift test
```

Result：

```text
SimiGoRuntimeContractTests 19/19 PASS
SimiGo2ExperimentalTests   137/137 PASS
Swift Testing              1/1 PASS
Total                     157 PASS / 0 FAIL
```

## Boundary

本 A/B 覆盖当前 Qwen3-Coder-Next-4bit、segment size 8、cacheless segmented
re-forward executor、short code prompt 和 cooperative token-boundary
cancellation。它不等价于 external backend cancellation、higher concurrency、
production workload 或 universal MLX behavior。

## Non-claims

```text
❌ production cancellation readiness 已完成
❌ wall-time 是性能结论
❌ 跨模型 / 跨 backend universal cancellation 已证明
❌ higher concurrency curve 已收口
❌ Qwen4Exp 已验证
```
