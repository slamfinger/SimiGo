# SimiGo Lab Named-Source Evidence Consolidation — 2026-09-29

## Result

```text
EVIDENCE_BUNDLE_V1 = PASS_WITH_BOUNDARY / CONSOLIDATION_COMPLETE
ARTIFACTS = 8
CHECKS = 9/9 PASS
NAMED_SOURCE_ACCEPTANCE_GATE = PASS
SAME_CHECKPOINT_CLOSURE = REJECTED_AT_CONTROL_TENSOR_LEVEL
LARGE_MATRIX_DRIFT_ATTRIBUTION = BLOCKED_LAYOUT_SOURCE_UNRESOLVED
```

登记：

```text
NAMED_SOURCE_EVIDENCE_BUNDLE_V1_CONSOLIDATION_PASS
PROFILE_TWO_SEED_GATE_PASS
TOKENIZER_SUBSTRATE_EXACT
DECLARED_LINEAGE_CHAIN_PASS
TEXT_TENSOR_TOPOLOGY_MAPPED
MARGIN_SEED42_AND_SEED43_PASS
CONTROL_TENSOR_NUMERICAL_DRIFT_OBSERVED
QUANTIZED_LAYOUT_MAPPING_UNRESOLVED
```

## Consolidated verdicts

| Question | Verdict |
| --- | --- |
| Are the GGUF/MLX artifacts on the same declared lineage chain? | PASS |
| Do they share exact tokenizer substrate? | PASS |
| Does the text tensor topology map completely? | PASS, known extras isolated |
| Does named-source acceptance gate pass across two seeds? | PASS |
| Is top1 agreement perfect? | No, 133/139 per seed |
| Are top1 flips allowed? | Yes |
| Are all reference tokens in LLAMA top16? | Yes, 139/139 per seed |
| Are these same checkpoint bytes? | No / rejected at control tensor level |
| Is large-matrix drift attributable to quantizer? | No, layout/source unresolved |

## Evidence set

| Evidence | Verdict | Artifact |
| --- | --- | --- |
| Profile V1 | PASS | `named-source-cyber-tiel-matrix-v2-profile-evaluation.json` |
| Lineage audit | PASS_WITH_BOUNDARY | `named-source-cyber-tiel-lineage-audit.json` |
| Tensor topology audit | PASS_WITH_BOUNDARY | `named-source-cyber-tiel-tensor-topology-audit.json` |
| Margin seed42 | PASS_WITH_BOUNDARY | `cross-backend-cyber-tiel-margin-compare-matrix-v2-all.json` |
| Margin seed43 | PASS_WITH_BOUNDARY | `cross-backend-cyber-tiel-margin-compare-matrix-v2-all-seed43.json` |
| QKV segment diagnostic | PASS_WITH_BOUNDARY / layout unresolved | `named-source-cyber-tiel-qkv-segment-diagnostic.json` |
| F32 control audit | PASS_WITH_OBSERVED_DRIFT | `named-source-cyber-tiel-f32-control-audit.json` |
| Quantized layout pilot | PASS_WITH_BOUNDARY / layout unresolved | `named-source-cyber-tiel-quantized-drift-pilot-layer1.json` |

Bundle SHA-256：

```text
f1f58035026dd597ea5ce46592aaf9f162f99123ea909ab43a73c733c81bf1ab
```

## Key findings

### 1. Named-source acceptance gate

两个 seeds都通过：

```text
positions          = 139
top1 agreement     = 133 / 139 = 95.683%
top16 containment  = 139 / 139 = 100%
max reference rank = 2
top1 flips         = 6 / allowed
seed outcomes      = identical
```

这证明 fixed MLX trajectory上的 near-boundary output behavior可复现，但不要求
top1 agreement完美。

### 2. Tokenizer substrate

```text
base vocab mismatch = 0 / 248044
added token mismatch = 0 / 26
merge mismatch = 0 / 247587
chat template = exact
```

### 3. Declared lineage

```text
Ornith 1.5 35B A3B
  → Huihui-Ornith-1.5-35B-A3B-abliterated
  → CyberTiel MLX oQ4e / CyberTiel GGUF UD-Q4_K_XL
```

CyberTiel是 publication/build alias；这不是 same-checkpoint proof。

### 4. Tensor topology

```text
GGUF total                 = 753
text model mapped          = 733 / 733
GGUF nextn-only            = 20
MLX vision-only            = 333
unexplained MLX language   = 0
```

### 5. Margin behavior

```text
seed42 top1 agreement = 133 / 139
seed43 top1 agreement = 133 / 139
top16 containment     = 139 / 139 per seed
max reference rank    = 2 per seed
```

### 6. Control tensor numerical drift

```text
tensors         = 260
exact tensors   = 30 / 260
zero drift      = 0 / 260
max abs diff    = 101.82308959960938
```

`ssm_norm.weight` exact；`ssm_a`、`ssm_dt.bias` 等显示大 drift。因此两个 payload
不能被解释为 same checkpoint。

### 7. Quantized layout pilot

三个 layer1 large tensors完整 dequant后 elementwise cosine接近零：

```text
0.000224 / 0.000156 / 0.000093
```

但 positional row/column norm correlation也接近零，而 sorted magnitude correlation
较高。因此当前 mapping无法建立，large-matrix drift attribution保持 blocked。

## Consolidated conclusion

当前证据支持一个 bounded conclusion：

```text
shared tokenizer substrate + shared declared lineage + complete text tensor topology
+ reproducible near-boundary output behavior
```

但同一证据集同时否定更强的 claim：

```text
❌ same checkpoint bytes
❌ dequantization-equivalent payload
❌ full tokenizer implementation equivalence
❌ quantizer drift attribution
```

Named-source profile V1因此继续保持 bounded interpretation。

## Validation

```text
bundle checks = 9/9 PASS
failureReasons = []
overallPass = true
```

## Artifacts

```text
simigo2-experimental/scripts/named_source_evidence_bundle.py
simigo2-experimental/results/backend-conformance/named-source-cyber-tiel-evidence-bundle.json
```

## Boundary

结果限定 current local CyberTiel GGUF/MLX snapshots、Matrix V2 12 prompts、139
fixed MLX trajectory positions、seed42/43、top-16 logprob observation、canonical
LLAMA profile和本机。不建立 same-checkpoint closure、tokenizer implementation
equivalence、quantization equivalence、MTP root cause或 production readiness。

## Next

1. 若获取共同上游 Ornith/Huihui source tensors，先做 canonical conversion mapping，
   再重开 large-matrix dequantized drift attribution。
2. 若扩展 prompt set，重新生成 profile、margin、topology和 evidence bundle。
3. Named-source profile V1保持 bounded scope；不得因 consolidated PASS升级为
   same-checkpoint closure。
