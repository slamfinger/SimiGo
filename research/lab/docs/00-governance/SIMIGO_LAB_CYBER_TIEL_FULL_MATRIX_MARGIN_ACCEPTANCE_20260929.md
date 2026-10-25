# SimiGo Lab Cyber-Tiel Full Matrix Margin Acceptance — 2026-09-29

## Result

```text
FULL_MATRIX_MARGIN_V2 = PASS_WITH_BOUNDARY / ACCEPTANCE_GATE_PASS
CASES = 12
POSITIONS = 139
LLAMA_TOP1_AGREEMENT = 133/139 = 95.683%
TOP16_CONTAINMENT = 139/139 = 100%
MAX_REFERENCE_RANK = 2
TOP1_FLIPS = 6 / ALLOWED
```

登记：

```text
CYBER_TIEL_FULL_MATRIX_MARGIN_V2_PASS
NAMED_SOURCE_ACCEPTANCE_GATE_PASS
IDENTITY_CASE_TOP1_PERFECT_SUBSET_OBSERVED
MISMATCH_CASE_TOP1_NEAR_BOUNDARY_FLIPS_ONLY
```

这不是 same-checkpoint closure，也不是 quantization equivalence。

## Protocol V2

在 Margin V1 的 P6/P11/P12 mismatch-only study上扩展为 Matrix V2 full scope：

```text
scope           = all
cases           = 12
families        = 12
positions       = 139
topK            = 16
Phase1          = MLX only
Phase2          = LLAMA only
reference path  = complete MLX greedy trajectory
```

Acceptance gate：

```text
top1 flips allowed             = true
top16 containment required     = true
max reference rank limit       = 2
gate pass                      = true
```

## Aggregate

| Group | Cases | Positions | Top1 agreement | Top16 containment | Max rank |
| --- | ---: | ---: | ---: | ---: | ---: |
| Identity cases | 9 | 67 | 67 / 67 = 100% | 67 / 67 | 0 |
| Mismatch cases | 3 | 72 | 66 / 72 = 91.667% | 72 / 72 | 2 |
| Full matrix | 12 | 139 | 133 / 139 = 95.683% | 139 / 139 | 2 |

6 个 top1 flip全部落在 mismatch cases；9 个 token-identity cases的每个 greedy
position在 LLAMA top1也完全一致。

## Per-case

| ID | Family | Positions | Top1 agreement | Max rank |
| --- | --- | ---: | ---: | ---: |
| P1 | baseline | 2 | 2/2 | 0 |
| P2 | counting | 24 | 24/24 | 0 |
| P3 | list | 11 | 11/11 | 0 |
| P4 | code-transform | 13 | 13/13 | 0 |
| P5 | exact-json | 6 | 6/6 | 0 |
| P6 | cjk | 24 | 21/24 | 1 |
| P7 | ambiguous-continuation | 3 | 3/3 | 0 |
| P8 | long-prefix-code | 2 | 2/2 | 0 |
| P9 | constraint | 2 | 2/2 | 0 |
| P10 | repeat | 4 | 4/4 | 0 |
| P11 | docstring | 24 | 23/24 | 2 |
| P12 | risk | 24 | 22/24 | 1 |

## Acceptance finding

1. 全部 139 positions都满足 top16 containment。
2. 全部 positions的 reference rank最大为 2。
3. 仅有的 6 个 top1 flip都是 close-candidate near-boundary flips。
4. identity cases不只是 final sequence相同；其完整 greedy trajectory也在 LLAMA
   top1逐 position一致。
5. mismatch cases的 final sequence不同，但 fixed MLX trajectory上仍有 91.667%
   next-token top1一致，且 no top16 dissociation。

因此在本 protocol内，named-source acceptance gate PASS。该 gate不要求 top1
100% agreement，但要求所有 reference tokens contained in top16且 rank不超过 2。

## Resource

```text
Phase1 MLX steady swap delta  = 0 bytes <= 768 MiB
Phase2 LLAMA steady swap delta = 0 bytes <= 512 MiB
```

两阶段仍严格顺序执行，MLX与 llama-server未同时驻留。

## Validation

```text
Swift tests = 157 PASS / 0 FAIL
```

## Artifacts

```text
simigo2-experimental/results/backend-conformance/cross-backend-cyber-tiel-margin-record-matrix-v2-all.json
simigo2-experimental/results/backend-conformance/cross-backend-cyber-tiel-margin-compare-matrix-v2-all.json
```

Record SHA-256：

```text
0aa9739f2c9bf3c5faf5cfa1a543f291f72c959feeb09b77e6816b0a3b16d13b
```

Compare SHA-256：

```text
986d399de2180a9f5fd72c2735bf5835e1d119ca54e395aad26ea14d3610d39f
```

实现：

```text
CrossBackendMarginProbe.Scope.all
CrossBackendMarginProbe.AcceptanceGate
CLI: cross-backend-margin-record --scope all
CLI: cross-backend-margin-compare --scope all
```

## Boundary

结果限定 named-source Cyber-Tiel MLX oQ4e与 MTP UD-Q4_K_XL GGUF variants、
Matrix V2 的 12 prompts/139 positions、top-16 logprob observation、canonical
LLAMA profile和本机。固定 MLX trajectory，不比较两条 divergent paths。不建立
same-checkpoint closure、tokenizer-file identity proof、quantization equivalence、
MTP root cause或 production readiness。

## Next

1. 在第二个 seed重复 full matrix V2。
2. 将 gate阈值注册为 named-source conformance profile，而非隐含约定。
3. 若扩 prompt set，重算 gate并保持 top16 containment/rank limit不变。
