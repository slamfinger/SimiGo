# SimiGo Lab Named-Source Conformance Profile V1 — 2026-09-29

## Result

```text
PROFILE_ID = NAMED_SOURCE.CYBER_TIEL.MATRIX_V2.TOP16_RANK2.TWO_SEEDS
PROFILE_EVALUATION = PASS
SEEDS = 42 / 43
POSITIONS_PER_SEED = 139
TOP16_CONTAINMENT = 278/278 ACROSS BOTH SEEDS
MAX_REFERENCE_RANK = 2
TOP1_FLIPS = 12 TOTAL / 6 PER SEED / ALLOWED
SEED_OUTCOMES_IDENTICAL = TRUE
```

登记：

```text
NAMED_SOURCE_CONFORMANCE_PROFILE_V1_REGISTERED
EXECUTABLE_PROFILE_EVALUATION_PASS
TOP1_FLIPS_ALLOWED_AS_OBSERVATION
TOP16_CONTAINMENT_AND_RANK2_REQUIRED
TWO_UNIQUE_SEEDS_REQUIRED
SEED_OUTCOME_IDENTITY_REQUIRED
```

## Profile rules

```text
minimum seed count                         = 2
unique seeds required                      = true
position count must match across seeds      = true
top16 containment required                  = true
maximum reference rank                      = 2
top1 flips allowed                          = true
per-position seed outcomes must be identical = true
top1 agreement                              = observation, not hard threshold
```

这个 profile 明确区分：

```text
hard gate      = top16 containment / max rank / two-seed reproducibility
soft evidence  = top1 agreement
observation    = top1 flips do not imply semantic equivalence
```

## Certified evidence

| Seed | Positions | Top1 agreement | Top16 containment | Max rank | Flips |
| --- | ---: | ---: | ---: | ---: | ---: |
| 42 | 139 | 133 = 95.683% | 139 | 2 | 6 |
| 43 | 139 | 133 = 95.683% | 139 | 2 | 6 |

两 seed的 `(promptID, position)` outcomes完全一致：

```text
139/139 identical
```

## Executable interface

```bash
simigo2ctl named-source-profile-evaluate \
  --compare results/backend-conformance/cross-backend-cyber-tiel-margin-compare-matrix-v2-all.json \
  --compare results/backend-conformance/cross-backend-cyber-tiel-margin-compare-matrix-v2-all-seed43.json
```

实现：

```text
NamedSourceConformanceProfile.Gate.cyberTielMatrixV2
NamedSourceConformanceProfile.evaluate
NamedSourceConformanceProfile.seedEvidence
CLI: named-source-profile-evaluate
```

Unit tests覆盖：

```text
two-seed pass
single-seed fail
rank-3 fail
seed outcome mismatch fail
```

## Profile artifact

```text
simigo2-experimental/results/backend-conformance/named-source-cyber-tiel-matrix-v2-profile-evaluation.json
```

## Validation

```text
Swift tests = 161 PASS / 0 FAIL
```

## Numerical drift correction — 2026-09-29 later audit

F32 control tensor audit观察到 GGUF F32与 MLX BF16 control tensors存在 finite
drift，且 zero-drift tensors为 `0/260`。因此 named-source profile V1只能证明
shared lineage/tokenizer substrate与 topology，加上 fixed-trajectory near-boundary
output profile；不能解释为 same-checkpoint或 dequantization-equivalent payload。
详见 `SIMIGO_LAB_CYBER_TIEL_F32_CONTROL_DRIFT_AUDIT_20260929.md`。

## Lineage correction — 2026-09-29 later audit

后续 GGUF/MLX lineage audit确认这两个 artifact共享 Ornith/Huihui tokenizer
substrate，CyberTiel是 publication/build alias；底层 chain为
`Ornith 1.5 → Huihui-Ornith-1.5-abliterated → CyberTiel quantization`。
因此本 profile中 “named-source”不得解释为 same-checkpoint closure。详见
`SIMIGO_LAB_NAMED_SOURCE_LINEAGE_AUDIT_20260929.md`。

## Boundary

该 profile 只适用于 named-source Cyber-Tiel MLX oQ4e与 MTP UD-Q4_K_XL GGUF
variants、Matrix V2 的 12 prompts / 139 positions、fixed MLX greedy trajectory、
top-16 logprob observation和 canonical LLAMA profile。它不是 same-checkpoint
closure、tokenizer-file identity proof、quantization equivalence、MTP root
cause、performance benchmark或 production readiness。

## Next

1. 新 prompt set必须重新计算 profile evaluation，不得复用本 artifact。
2. 后续模型/quantization pair可注册独立 profile ID。
3. 若未来要求 top1 agreement threshold，必须作为新 profile version，不改写本 V1。
