# SimiGo Lab Cyber-Tiel Full Matrix Margin Seed43 Reproduction — 2026-09-29

## Result

```text
FULL_MATRIX_MARGIN_V2_SEED43 = PASS_WITH_BOUNDARY / ACCEPTANCE_GATE_REPRODUCED
CASES = 12
POSITIONS = 139
LLAMA_TOP1_AGREEMENT = 133/139 = 95.683%
TOP16_CONTAINMENT = 139/139 = 100%
MAX_REFERENCE_RANK = 2
TOP1_FLIPS = 6 / ALLOWED
```

登记：

```text
CYBER_TIEL_FULL_MATRIX_MARGIN_V2_SEED43_PASS
FULL_MATRIX_ACCEPTANCE_GATE_REPRODUCED
PER_POSITION_OUTCOME_IDENTICAL_TO_SEED42
MLX_GREEDY_TRAJECTORY_REPRODUCED
```

## Protocol

完整重复 seed42 的 full-scope chain：

```text
1. cross-backend-token-record        MLX only
2. cross-backend-token-compare       LLAMA only, seed43
3. cross-backend-margin-record       MLX only, scope=all
4. cross-backend-margin-compare      LLAMA only, scope=all, seed43
```

配置：

```text
cases        = 12
families     = 12
positions    = 139
topK         = 16
max tokens   = 24
seed         = 43
Phase1 gate  = 768 MiB steady swap delta
Phase2 gate  = 512 MiB steady swap delta
```

## Token matrix reproduction

```text
status              = PASS_WITH_BOUNDARY
output identity     = 9/12
mismatches          = P6 cjk / P11 docstring / P12 risk
MLX trajectory      = semantically identical to seed42
```

MLX是 greedy decode且 Phase1 record不使用 sampling seed；seed42与 seed43
record的 generated token IDs逐 case一致。

## Margin acceptance gate

| Metric | seed42 | seed43 |
| --- | ---: | ---: |
| positions | 139 | 139 |
| top1 agreement | 133 / 139 | 133 / 139 |
| top1 agreement ratio | 95.683453% | 95.683453% |
| top16 containment | 139 / 139 | 139 / 139 |
| max reference rank | 2 | 2 |
| top1 flips | 6 | 6 |
| gate | PASS | PASS |

分层：

| Group | Positions | seed42 agreement | seed43 agreement |
| --- | ---: | ---: | ---: |
| Identity cases | 67 | 67 / 67 | 67 / 67 |
| Mismatch cases | 72 | 66 / 72 | 66 / 72 |

## Per-position reproduction

对每个 `(promptID, position)` 比较：

```text
LLAMA top1 token ID
reference in LLAMA top16
reference rank in LLAMA
```

```text
identical outcomes = 139/139
differences        = 0
```

因此 seed43 不只是 aggregate count复现；每个 position的 LLAMA outcome shape也与
seed42一致。MLX reference trajectory亦逐 case一致。

## Validation

```text
Swift tests = 157 PASS / 0 FAIL
```

## Artifacts

```text
simigo2-experimental/results/backend-conformance/cross-backend-cyber-tiel-mlx-record-matrix-v2-seed43.json
simigo2-experimental/results/backend-conformance/cross-backend-cyber-tiel-token-compare-matrix-v2-seed43.json
simigo2-experimental/results/backend-conformance/cross-backend-cyber-tiel-margin-record-matrix-v2-all-seed43.json
simigo2-experimental/results/backend-conformance/cross-backend-cyber-tiel-margin-compare-matrix-v2-all-seed43.json
```

Margin record SHA-256：

```text
7a0881b1c67ded5095a7e552a8517e1783c1cc79b05ad02cbaf68e4384df6399
```

Margin compare SHA-256：

```text
9144057b5d7c480df79b1c348a747fc3313dca55386a8149c755bc0ce9b00a87
```

实现变更：

```text
CrossBackendMarginProbe.runCompare 增加显式 seed
CLI cross-backend-margin-compare 增加 --seed
```

## Boundary

结果限定 named-source Cyber-Tiel MLX oQ4e与 MTP UD-Q4_K_XL GGUF variants、
Matrix V2 12 prompts、fixed MLX trajectory、139 teacher-forced positions、top-16
logprob observation、canonical LLAMA profile和本机。seed只作用于 LLAMA compare
请求；MLX greedy record不使用 sampling seed。不建立 same-checkpoint closure、
tokenizer-file identity proof、quantization equivalence、MTP root cause或
production readiness。

## Next

1. 将 seed42/43 double-run注册为 named-source acceptance的最低复现要求。
2. 扩展 prompt set后重复 double-run。
3. 对 6 个 fixed flip points做 batch-shape / runtime-build ablation。
