# SimiGo 2.0 Chat Template Application

**Date**: 2026-09-24  
**Status**: SUPPORTED / VALIDATED_WITH_GEMMA4_DENSE_GATE5  
**Scope**: runtime benchmark inference and dense Gate 5

## 1. Behavior

SimiGo 2.0 now applies the model's own chat template before benchmark generation.
The lookup order is:

```text
chat_template.jinja in the model directory
→ tokenizer_config.json / tokenizer-internal configured template
→ raw encode fallback only when no template exists
```

For standalone Jinja files, SimiGo reads `chat_template.jinja`, passes it as a
literal template, adds the assistant generation prompt, and sets
`enable_thinking=false` when the template supports that variable.

## 2. Why this matters

The earlier dense Gate 5 direct-generation probe bypassed chat formatting and
produced repeated-token output. Applying the checkpoint template makes runtime
validation follow the model's intended prompt format and removes ambiguity
between bad residency behavior and bad prompt formatting.

## 3. Gemma4 dense Gate 5 validation

Using the bundled Gemma4 `chat_template.jinja`:

```text
all 15 generated outputs           = ping
outputIdentityPass                 = true
idleReductionObserved              = true
maximum idle reduction             = 3,186,621,696 bytes
reloadReductionVsNaiveObserved     = true
reload reduction vs naive          = 3,185,049,600 bytes
benchmarkPass                      = true
```

Memory remained state-sensitive:

```text
CORE + one dense MLP group    = 3,514,801,674 bytes
CORE + two dense MLP groups   = 5,108,112,522 bytes
all groups resident           = 6,701,423,370 bytes
```

## 4. Boundary

Muse-Glimmer text-only has no bundled chat template, so it still uses the raw
fallback. A model with no template can run, but repeated-token output cannot be
used as a semantic-quality claim.
