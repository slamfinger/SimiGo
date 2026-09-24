# G1.9-A Group Execution Trace — Design, Pre-Run Audit, First Capture — 2026-09-25

Status: G19A_GROUP_TRACE_FIRST_CAPTURE_PASS / MEASURED_LOCALITY_ANALYSIS_PENDING
Authorization: docs/00-governance/SIMIGO2_G19A_ISOLATED_INSTRUMENTATION_AUTHORIZATION_20260925.md
Boundary: ISOLATED_INSTRUMENTATION / EVENT_ONLY_TRACE / NOT_PREDICTION / NOT_DEMAND / EXPERT_DEMAND_NOT_INSTRUMENTED

## Design

The G1.9-B identity probe validated a single proxy capture point (layer 0
fused MoE switch down_proj output) on one forward. This phase extends the same
isolation discipline to a full group/layer execution trace:

```text
Traced module per decoder layer MLP down-projection
        ↓  (event-only: no MLXArray retained)
ExecutionTraceEventBox  {sequence, modulePath, decoderLayer, outputShape, ms}
        ↓
measured execution trace (per forward pass × per layer)
```

Isolation discipline (unchanged from G1.9-B):

- No MLX internals are modified; instrumented subclasses replace leaf modules
  inside the loaded model object only.
- Quantized switch and quantized dense paths recompute the exact same math
  (`MLX.gatherQuantizedMM` / `MLX.quantizedMM` with cloned parameters).
- Event-only capture: events record path/layer/shape, never activations, so
  tracing holds no live tensors.

Phase-1 verification battery (the authorized STOP-gate question — "can a
trustworthy real execution trace be obtained without changing model compute
semantics"):

```text
V1 logits identity    baseline vs instrumented single-forward SHA-256 bitwise
V2 execution unchanged  generation text identical baseline vs instrumented
V3 trace stability    two instrumented generations produce identical event
                      streams (timestamps excluded)
V4 overhead           warmup-symmetric steady-state timing + peak memory delta
```

## Pre-run audit findings (three defects found and fixed before trusting traces)

1. **Nested-perform deadlock hazard.** Wrapping a whole probe run in one
   `container.perform` while `ChatTemplateGeneration.generate` performs its
   own container access deadlocks the runtime (observed: 0% CPU, model
   resident, indefinite hang). Fix: non-nested protocol — baseline, install,
   and instrumented forwards run in separate perform blocks; module
   replacement persists on the model object across blocks.
2. **QuantizedLinear latent defect in the identity probe.** The existing
   `InstrumentedLinear` branch clones any `Linear`, but `QuantizedLinear` is a
   `Linear` subclass — cloning it as a plain Linear silently changes compute
   semantics for dense quantized checkpoints. Fix: dedicated
   `QuantizedLinear` branch recomputing `MLX.quantizedMM` with the cloned
   quantized parameters (mirror of the existing QuantizedSwitchLinear
   handling). Registered G1.9-B results are unaffected (switch paths only).
3. **Observation-path filter.** A `.mlp.down_proj` suffix filter misses fused
   MoE paths (`mlp.switch_mlp.down_proj`). Fix: accept both variants; module
   count per model is now a reported field (48 for Qwen3-Coder).

## First capture — Qwen3-Coder-30B-A3B-Instruct-4bit (positive control)

Command:

```bash
simigo2ctl group-trace-audit MODEL_DIRECTORY \
  --prompt "Count from one to twelve." --max-tokens 32
```

```text
status                         = PASS
instrumentedModuleCount        = 48 / 48 decoder layers
V1 logitsIdentityPass          = true   (SHA-256 bitwise equal, Δ = 0)
V2 textIdentityPass            = true   ("1, num2, 3, 4 …" identical; output
                                          oddity is the model's own, identical
                                          in baseline and instrumented runs)
V3 traceStabilityPass          = true   (two instrumented generations: 1536
                                          events, identical streams)
V4 steadyStateOverheadPercent  = −6.8%  (single-run timing noise; event-only
                                          capture designed for ≈0 cost;
                                          peak memory overhead 0 MB)
traceEventCount / passCount / eventsPerPass = 1536 / 32 / 48
```

Measured trace shape: every forward pass executes all 48 switch-MLP layer
groups, with the per-pass sequence length growing token by token. The down_proj
output shape carries a ×8 expert-activation flattening (Qwen3 top-k metadata
visible in shape only — the router is not instrumented and no expert demand is
modeled, per the authorization boundary).

## Phase-1 verdict

For this configuration the Phase-1 STOP condition is satisfied:

```text
instrumented ≈ baseline  = PASS (V1 + V2, bitwise / exact)
trace stable             = PASS (V3)
overhead acceptable      = PASS (V4: indistinguishable from noise, 0 MB)
```

The first measured execution trace exists as a registered artifact. The next
phase — measured-locality analysis (recurrence → transition locality →
temporal stability) on captured traces, and the decision on reopening the
Predictor question — is PENDING and remains a separate gate. Predictor /
probability / speculative loading / Expert or Token×Expert demand / production
MLX modifications / async I/O remain unauthorized.

Raw artifact:

```text
simigo2-experimental/results/instrumentation-audits/qwen3-coder-group-trace.json
```
