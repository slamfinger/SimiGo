# SimiGo Lab Cyber-Tiel QKV Row Assignment Audit — 2026-09-29

## Result

```text
QKV_ROW_ASSIGNMENT_AUDIT = PASS_WITH_BOUNDARY / PERMUTATION_HYPOTHESIS_SUPPORTED
SAME_SEGMENT_ASSIGNMENTS = 3/3 PASS
Q/K CROSS ASSIGNMENT     = HIGH / AMBIGUOUS
V SEGMENT                = SEPARABLE
FULL_ELEMENT_MAPPING     = NOT ESTABLISHED
```

登记：

```text
CYBER_TIEL_QKV_ROW_NORM_ASSIGNMENT_PASS
QKV_ROW_NORM_PERMUTATION_HYPOTHESIS_SUPPORTED
QK_SEGMENT_IDENTITY_AMBIGUOUS
V_SEGMENT_DISTRIBUTIONALLY_SEPARABLE
LAYOUT_MAPPING_STILL_UNRESOLVED
```

## Scope

使用 QKV segment diagnostic输出的 row L2 norms，对 GGUF与 MLX dequantized
`attn_qkv` 的 Q/K/V row populations做 Hungarian assignment audit：

```text
Q2048 ↔ Q2048
K2048 ↔ K2048
V4096 sampled to 2048 ↔ V4096
```

以及全部 cross-segment assignments。该 audit只使用 row norm scalar；不建立
element-level mapping，也不声称 quantizer drift。

## Same-segment assignments

| Segment | Assignment cost mean | Assignment cost max | Matched norm MAE | Matched Pearson | Gate |
| --- | ---: | ---: | ---: | ---: | --- |
| Q2048 | 0.0659900 | 1.4587468 | 0.0659900 | 0.5066660 | PASS |
| K2048 | 0.0443534 | 1.3441234 | 0.0443534 | 0.6598681 | PASS |
| V4096 sample | 0.0866736 | 3.0840210 | 0.0866736 | 0.5719384 | PASS |

Gate：

```text
same segment assignment cost mean < 0.10        = 3/3 PASS
same segment matched relative mean < 0.25       = 3/3 PASS
same segment matched norm Pearson > 0.50        = 3/3 PASS
```

## Cross-segment assignments

| GGUF segment | MLX segment | Assignment cost mean | Matched Pearson | Interpretation |
| --- | --- | ---: | ---: | --- |
| Q2048 | K2048 | 0.0485477 | 0.6513951 | high / ambiguous |
| K2048 | Q2048 | 0.0599772 | 0.5675769 | high / ambiguous |
| Q2048 | V4096 | 0.3519453 | 0.3269191 | separable |
| K2048 | V4096 | 0.3483272 | 0.2699293 | separable |
| V4096 | Q2048 | 0.3481227 | 0.0324263 | strongly separable |
| V4096 | K2048 | 0.2956678 | 0.0979268 | strongly separable |

Q/K cross assignment高于 V cross assignment，支持此前 best segment order
`(K,Q,V)`中的 Q/K ambiguity。V segment与 Q/K可区分。

## Interpretation

1. same-segment row-norm assignment全部 PASS，说明 GGUF/MLX Q/K/V populations
   在各自对应 segment内存在可匹配 row-norm permutation。
2. Q/K cross assignment也较强，说明 Q/K segment identity在这个 scalar-norm层
   并不明显。
3. V segment与 Q/K可区分，但 V4096只 sampled到 2048 rows，结果有采样边界。
4. 该 audit支持 permutation hypothesis，但不建立 element-level mapping。
5. 因此 large quantized tensor drift attribution继续 BLOCKED。

## Artifacts

```text
simigo2-experimental/scripts/cyber_tiel_qkv_segment_diagnostic.py
simigo2-experimental/scripts/cyber_tiel_qkv_row_assignment_audit.py
simigo2-experimental/results/backend-conformance/named-source-cyber-tiel-qkv-row-assignment-audit.json
```

QKV segment diagnostic新增：

```text
--debug-norms PATH
```

可导出 Q/K/V block row norms供 assignment audit复现。

## Boundary

结果限定 layer1 `attn_qkv`、GGUF Q8_0、MLX affine dequant、假设的
Q2048/K2048/V4096 segments、V4096 sampled to 2048和本机 artifacts。不建立
element mapping、same-checkpoint closure、quantizer equivalence或 MTP mechanism。

## Non-claims

```text
❌ full QKV layout已解析
❌ element-level mapping已证明
❌ Q/K一定是互换
❌ quantizer drift已归因
❌ same checkpoint
```

## Next

1. 对 Q/K/V full row populations（不 sample V）重复 assignment。
2. 引入 row mean/std/quantile signature，验证 assignment不是只由 norm决定。
3. 结合共同上游 HF source tensors后，才能把 permutation map转换为 canonical
   conversion mapping。
