# SimiGo 2.0 Phase 0 — MLX Parameter Swap Gate 3 Results

**Date**: 2026-09-24  
**Status**: GATE_3_PARAMETER_SWAP_SEMANTIC_RESTORE_PASS / GROUP_RESIDENCY_INFERENCE_PENDING  
**Model**: `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit`

## 1. Gate

Verify that a selected fused MoE parameter is load-bearing and that a perturb /
restore cycle returns deterministic inference to its baseline:

```text
load real Qwen3-Coder model
→ generate baseline
→ zero one switch_mlp gate_proj tensor
→ generate perturbed output
→ restore the saved tensor
→ generate restored output
→ compare output and parameter fingerprint
```

## 2. Result

```text
targetParameterKey              = model.layers.0.mlp.switch_mlp.gate_proj.weight
prompt                          = Return exactly one word: ping
baselineOutput                  = pong
perturbedOutput                 = ping, newline, three backticks
restoredOutput                  = pong
perturbedDiffers                = true
restoredParameterMatchesBaseline = true
baselineEqualsRestored          = true
```

The command exited successfully. The selected parameter changed the output, and
restoration returned both the parameter fingerprint and deterministic output to
baseline.

## 3. Diagnostic controls

Two failed probes were retained as useful boundaries:

1. `model.layers.0.mlp.gate.weight` (the router gate) produced identical
   baseline, perturbed, and restored `pong` output for this prompt. This is not
   evidence that the router is globally inert; only that zeroing this one layer
   did not alter this narrow generation.
2. The first `switch_mlp.gate_proj` restore failed because MLX parameter update
   mutates the `MLXArray` wrapper in place. The restore value accidentally
   became the perturbed value. This was fixed by evaluating an independent
   snapshot before perturbation.

## 4. Conclusion

Gate 3 passes at parameter-swap and semantic-restore level:

```text
MLX parameter replacement        = PASS
Selected parameter load-bearing  = PASS
Parameter fingerprint restore    = PASS
Deterministic output restore     = PASS
```

This does not yet prove execution-state-driven group residency during inference.
The remaining hard gate is to release/rematerialize a whole group around real
model execution while preserving outputs and measuring peak memory, reload
cost, latency, and output identity.
