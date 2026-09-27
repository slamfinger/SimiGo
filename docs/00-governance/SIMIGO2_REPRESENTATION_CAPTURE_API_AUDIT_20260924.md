# SimiGo 2.0 Representation Capture API Audit — 2026-09-24

Status: G1.9-A COMPLETE / G1.9 INSTRUMENTATION ROUTE REQUIRED  
Model: `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit`  
Boundary: EXPLORATORY / NO REPRESENTATION ASSERTION

## Command

```bash
swift run --package-path simigo2-experimental simigo2ctl rep-audit \
  /Users/mr.simi/.cache/huggingface/hub/models--mlx-community--Qwen3-Coder-30B-A3B-Instruct-4bit/snapshots/6e302ea604ad9ab206367e2c501d1571023e7b6d
```

## Result

```text
modelType                    = Qwen3MoEModel
observedModulePathCount      = 627
candidateLayerPaths          = model.layers.0 .. model.layers.47
stableObservationContract    = false
recommendedRoute             = isolatedInstrumentation
forwardExecuted              = false
```

The probe traverses the installed public MLX module tree only. It does not call
`model(input)` and does not materialize an activation. Its boundary marker is:

```text
MODULE_INVENTORY_ONLY / NOT_ACTIVATION_CAPTURE / FORWARDS_SEMANTICS_UNCHANGED
```

## Decision

The current public `LanguageModel` path exposes logits and runtime/cache state,
not a stable layer-indexed hidden-state return value. Discovering
`model.layers.N` module boundaries is therefore not sufficient to claim capture
of `H_i(x)`.

Consequently:

1. Direct public-API representation capture = REJECTED.
2. Safetensors parameter inventory = not representation evidence.
3. Group ablation effect = not representation evidence.
4. G1.9 must use a separate instrumentation route.

The next probe must preserve forward semantics, compare baseline and
instrumented token identities, record overhead, and emit only the compact
metadata defined by `REPRESENTATION_CAPTURE_FEASIBILITY_AUDIT_v0.1.md`.

This result does not authorize Predictor, Probability, Preload, harness-wide
instrumentation, or causal-demand claims.
