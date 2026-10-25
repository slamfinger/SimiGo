# Cross-Model × Cross-Sample Information Matrix Protocol

Status: `SAMPLE/MODEL FROZEN · EXECUTION NOT STARTED`  
Date: `2026-10-04`

## Boundary

- This is a new research line. It must not run or modify the existing R-D Round 1.
- It must not modify `846` decomposition artifacts, `InformationCore`, Observer, or PALACE.
- The first goal is raw evidence, not proof of 846.
- 846 is touched only after `raw/`, `normalized/`, and `stability/` are complete.

## Matrix

Selected models are four locally proven construction routes:

| Model | Architecture family | Route distinction |
|---|---|---|
| `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit` | `qwen3_moe` | conventional attention + sparse MoE |
| `mlx-community/Qwen3-Coder-Next-4bit` | `qwen3_next` | newer hybrid route + wider sparse MoE |
| `mlx-community/gemma-4-12b-coder-fable5-composer2.5-4bit` | `gemma4_unified` | dense unified multimodal-family route |
| `RadixArk/Muse-Glimmer-q4-MLX` | `muse_glimmer` | dense non-Qwen/non-Gemma route |

Samples are four already-executed research materials:

| Sample | Task nature | Input form |
|---|---|---|
| `S1-release-config` | machine-readable release decision | four JSON files |
| `S2-version-diff` | versioned document comparison | two text extracts |
| `S3-column-unit-audit` | spreadsheet evidence adjudication | mechanical extraction evidence |
| `S4-arithmetic-anomaly-audit` | report consistency review | paragraph and table extracts |

Exact inputs, hashes, tasks, and output schema are frozen in `freeze/samples.json`.
After a run starts, sample files, prompts, model metadata, and output schema must not change.

## Execution rule

For every `(sample, model)` cell, save rendered prompt, raw HTTP response, extracted final
answer, model/runtime metadata, and SHA-256 hashes. No 846 mapping may be recorded before all
16 cells are complete.

## Semantic normalization

For each cell, translate surface output into `observed_structures.jsonl`. One line is one
semantic structure:

```json
{
  "obs_id": "S1--MODEL--O01",
  "sample_id": "S1-release-config",
  "model_id": "...",
  "function": "constraint|decision|evidence|relation|uncertainty|task_rule",
  "subject": "...",
  "relation": "...",
  "object": "...",
  "condition": "...",
  "evidence_refs": ["..."],
  "confidence": "high|medium|low"
}
```

Normalization compares semantic function, not wording, JSON formatting, length, or surface order.
Different tokens with the same source-grounded relation are `V`, not different structures.

## Stability labels

- `M` = model-stable: same structure in at least 3 of 4 models for the same sample.
- `S` = sample-stable: same abstract structure in at least 3 of 4 samples within/across models.
- `SM` = both `M` and `S`; these are the only first-pass candidate common structures.
- `X` = sample/model-specific.
- `V` = same structure in a different representation.
- `?` = insufficient or ambiguous evidence.

Save `stability/structures.json` with `sample_stable`, `model_stable`,
`representation_dependent`, and `candidate_common` booleans plus the label.

## 846 remapping gate

After all three matrices are complete, map only `SM` candidates to atom IDs in the frozen
`synchronous-decomposition-20261004.json`. Per atom record only:
`retained | merge_candidate | representation_variant | sample_specific | model_specific |
not_observed`. No atom is deleted or rewritten; the report only yields next-round candidates.

## First-pass boundary

This matrix is `n=1` per cell. It can expose candidate structures but cannot establish
within-model determinism, architecture-level generality, or irreducibility.
