# SimiGo Lab Cyber-Tiel Tensor Topology Audit — 2026-09-29

## Result

```text
TENSOR_TOPOLOGY_AUDIT = PASS_WITH_BOUNDARY / TEXT_MODEL_TOPOLOGY_MATCH
GGUF TENSORS          = 753
MLX PHYSICAL TENSORS  = 2010
MLX LOGICAL GROUPS    = 1066
TEXT MODEL MAPPING    = 733 / 733 GGUF ↔ MLX logical groups
KNOWN EXTRAS          = GGUF nextn 20 + MLX vision 333
UNACCOUNTED TENSORS   = 0
```

登记：

```text
CYBER_TIEL_TEXT_MODEL_TENSOR_TOPOLOGY_MATCH
GGUF_NEXTN_BLOCK_ISOLATED_AS_GGUF_ONLY
MLX_VISION_STACK_ISOLATED_AS_MLX_ONLY
NO_WEIGHT_BYTES_OR_DEQUANTIZED_VALUES_COMPARED
```

## Scope

只解析：

```text
GGUF header / metadata / tensor headers
MLX safetensors headers / index.json
```

不读取、不反量化、不比较任何模型权重值。因此本 audit建立 tensor topology
boundary，不建立 same-checkpoint closure。

## Source

上游 lineage audit：

```text
results/backend-conformance/named-source-cyber-tiel-lineage-audit.json
```

模型：

```text
GGUF = Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL
MLX  = Cyber-Tiel-Coder-35B-A3B-MLX-oQ4e
```

## Text model mapping

Global：

```text
token_embd.weight      ↔ language_model.model.embed_tokens
output.weight          ↔ language_model.lm_head
output_norm.weight     ↔ language_model.model.norm
```

Regular blocks `blk.0–39`：

```text
40 blocks
30 linear-attention blocks × 19 tensors = 570
10 full-attention blocks   × 16 tensors = 160
regular text total                     = 730
```

全部 730个 regular GGUF tensors都映射到对应 MLX logical tensor group。MLX侧
quantized logical group聚合 `weight` / `scales` / `biases`。

完整 text mapping：

```text
730 regular GGUF tensors
+ 3 global GGUF tensors
= 733 / 733 mapped
```

## Known format-specific extras

### GGUF-only

`blk.40` 是 GGUF nextn/MTP-related block，包含 20 tensors：

```text
attention q/k/v/output and norms
MoE gate/up/down tensors
nextn.eh_proj / enorm / hnorm / shared_head_norm
```

MLX snapshot没有对应 nextn block。

### MLX-only

MLX snapshot包含 vision stack，共 333 logical tensor groups：

```text
vision_tower.patch_embed / pos_embed / blocks / merger
multi_modal_projector 相关 tensors
```

这些不在 text-only GGUF topology中。

## Counts

| Group | Count |
| --- | ---: |
| GGUF total | 753 |
| GGUF regular mapped | 730 |
| GGUF global mapped | 3 |
| GGUF nextn-only | 20 |
| MLX physical | 2010 |
| MLX logical groups | 1066 |
| MLX text logical groups mapped | 733 |
| MLX vision-only logical groups | 333 |

checks：

| Check | Result |
| --- | --- |
| `GGUF_VERSION_SUPPORTED` | PASS |
| `REGULAR_BLOCK_COUNT_40` | PASS |
| `FULL_ATTENTION_INTERVAL_4` | PASS |
| `REGULAR_GGUF_TENSORS_MAPPED` | PASS |
| `GLOBAL_AND_REGULAR_MLX_MAPPED` | PASS |
| `KNOWN_EXTRAS_ONLY` | PASS |
| `GGUF_NEXTN_IDENTIFIED_AS_GGUF_ONLY` | PASS |
| `MLX_VISION_IDENTIFIED_AS_MLX_ONLY` | PASS |

## Interpretation

1. 两 artifact的 text-model tensor topology可完整对应。
2. 差异可全部归因于已知 format/export边界：GGUF nextn/MTP-related block与
   MLX vision stack。
3. 没有未解释的 missing/unmapped text tensors。
4. 本 audit不证明权重数值等价；oQ4e与 UD-Q4_K_XL payload仍不同。

## Validation

```text
script syntax       = PASS
artifact assertions = PASS
Swift tests         = 161 PASS / 0 FAIL
```

## Artifacts

```text
simigo2-experimental/scripts/cyber_tiel_tensor_topology_audit.py
simigo2-experimental/results/backend-conformance/named-source-cyber-tiel-tensor-topology-audit.json
```

## Boundary

结果限定 current local snapshots、header topology、tensor names/dimensions和
GGUF quantization type labels。不建立 same-checkpoint closure、dequantized
tensor equality、runtime equivalence或 performance equivalence。

## Next

1. 选择 shared text tensors做 dequantized numerical drift sampling。
2. 将 nextn/MTP block单独纳入 MTP mechanism study。
3. MLX vision stack不在 text-only GGUF protocol内，不得混入 named-source
   text gate。
