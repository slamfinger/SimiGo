# SimiGo 2.0 Representation Capture Multi-Model Audit — 2026-09-24

> **ARCHIVED** 2026-10-20 · line: 通用治理 / 其他 · original: docs/00-governance/SIMIGO2_REPRESENTATION_CAPTURE_MULTI_MODEL_AUDIT_20260924.md
> Evidence status: unchanged (content frozen; moved only)


Status: G1.9-A MULTI-MODEL PASS / G1.9 INSTRUMENTATION ROUTE REQUIRED  
Boundary: EXPLORATORY / MODULE_INVENTORY_ONLY / NO ACTIVATION CAPTURE

## Scope

The read-only `rep-audit` probe was run against the local checkpoints used by the
recent Qwen3-Coder, Nail-Qwen3.6, Gemma4, and Muse-Glimmer experiments. The
probe traverses the installed MLX module tree without executing `model(input)`.

## Result

| Model | Snapshot | Runtime class | Paths | Layers | Route |
|---|---|---:|---:|---:|---|
| Qwen3-Coder 30B A3B | `6e302ea6` | `Qwen3MoEModel` | 627 | 48 | isolated instrumentation |
| Nail-Qwen3.6 35B A3B | `31a01064` | `Qwen35MoEModel` | 683 | 40 | isolated instrumentation |
| Gemma4 Coder 12B | `6b82053f` | `Gemma4Model` | 714 | 48 | isolated instrumentation |
| Muse-Glimmer local q4 | `4a4f54af` | `MuseGlimmerTextLLMModel` | 680 | 52 | isolated instrumentation |

Layer boundary ranges:

```text
Qwen3-Coder      = model.layers.0 .. model.layers.47
Nail-Qwen3.6     = language_model.model.layers.0 .. language_model.model.layers.39
Gemma4 Coder     = language_model.model.layers.0 .. language_model.model.layers.47
Muse-Glimmer     = model.layers.0 .. model.layers.51
```

All four reports have:

```text
stableObservationContract = false
recommendedRoute          = isolatedInstrumentation
boundary                  = MODULE_INVENTORY_ONLY / NOT_ACTIVATION_CAPTURE /
                            FORWARDS_SEMANTICS_UNCHANGED
```

## Interpretation

The installed public MLX Swift path exposes candidate decoder-layer module
boundaries, but no stable layer-indexed hidden-state return contract on any of
the four model classes. Enumerating these boundaries is therefore not evidence
that `H_i(x)` was captured.

No model changes the G1.9 decision:

1. direct public-API representation capture remains REJECTED;
2. representation capture requires an isolated instrumentation probe;
3. instrumentation must preserve forward semantics and prove output identity;
4. parameter inventory, final logits, and ablation effects remain invalid as
   `H_i(x)` evidence.

## Provenance

Raw reports:

```text
simigo2-experimental/results/representation-audits/qwen3-coder.json
simigo2-experimental/results/representation-audits/nail-qwen36.json
simigo2-experimental/results/representation-audits/gemma4-coder.json
simigo2-experimental/results/representation-audits/muse-glimmer.json
simigo2-experimental/results/representation-audits/summary.json
```

The earlier documented Muse-Glimmer runtime probe used the
`OpensourceWTF/Muse-Glimmer-30B-MLX-q4` snapshot `e1c987b6`; that snapshot is
not currently present in the local Hugging Face cache. The current multi-model
audit therefore used the locally available `RadixArk/Muse-Glimmer-q4-MLX`
snapshot `4a4f54af`. This provenance difference is explicit and must not be
collapsed into the prior runtime result.
