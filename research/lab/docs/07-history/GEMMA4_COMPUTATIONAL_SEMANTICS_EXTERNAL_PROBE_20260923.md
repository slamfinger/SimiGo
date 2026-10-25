# Gemma 4 Computational-Semantics External Probe

**Date**: 2026-09-23  
**Status**: EXTERNAL_OBSERVATION_REGISTERED / ROUTE_NOT_SELECTED  
**Nature**: candidate-observation record; not a Concrete Instance, R-INTERNAL gate, or theory declaration

## 1. Purpose

This record registers a read-only external probe of the local model

```text
models--mlx-community--gemma-4-12b-coder-fable5-composer2.5-4bit
```

as a candidate observation for the deferred research road
`COMPUTATIONAL_SEMANTICS`. It does not declare `(P1,θ1)`, does not alter the
concrete-instance chain, and does not select a research route.

## 2. Probe result

The checkpoint config declares:

```text
architecture = Gemma4UnifiedForConditionalGeneration
model_type   = gemma4_unified
quantization = 4-bit affine, group size 64
vocab_size   = 262144
text layers  = 48
KV heads     = 8
audio_config = present
```

However, the checkpoint weight index contains only text-backbone tensors.
No audio or vision weights are present.

The observed layers are:

```text
Declared Model   ≠ Loaded Model   ≠ Executable Model
```

More explicitly:

```text
Declaration     : unified multimodal model declared
Instantiation   : full unified instantiation fails; text-only load succeeds
Execution       : high-level generation protocol is incomplete
Semantics       : consistency remains OPEN
```

## 3. mlx-swift-lm observations

### VLM / unified path

`gemma4_unified` is registered for `Gemma4Unified` and its processor. Loading
the local checkpoint fails because the declared audio configuration causes the
loader to require:

```text
embed_audio.embedding_projection.weight
```

but that tensor is absent from the checkpoint.

### LLM / text-only path

`gemma4_unified` is also registered as `Gemma4Model` in the LLM path. The local
checkpoint loads as a text-only model:

```text
type          = Gemma4Model
vocab         = 262144
layers        = 48
KV per layer  = 8
active memory = 6390 MiB
```

### Generation protocol

A high-level one-token generation attempt fails with a prefill/decode mismatch:

```text
Cannot reshape array of size 20480 into shape (1,1,16,256)
```

For a five-token prompt, this is consistent with the prompt still being treated
as decode-position input rather than having been consumed by a text-only
`prepare` path.

## 4. Python mlx-lm observation

With `mlx-lm==0.31.3`, loading fails because Python MLX-LM has no
`gemma4_unified` model module. It has `gemma4` and `gemma4_text`, but not the
unified type declared by this checkpoint.

## 5. Candidate four-layer classification

| Layer | Observation |
| --- | --- |
| Declaration | Unified multimodal architecture is declared. |
| Instantiation | Full unified instantiation fails; text-only instantiation succeeds. |
| Execution | Text-only loading succeeds; high-level generation fails. |
| Semantic consistency | OPEN. |

This classification is probe-specific. It is not generalized to all Gemma 4
checkpoints, dense models, MoE models, or mlx-swift-lm.

## 6. Research meaning

The probe motivates distinctions that a future computational-semantics surface
must make explicit:

```text
Declared(M)
Instantiated(M)
Executable(M)
SemanticallyConsistent(M)
```

The observed implications are only negative in this local case:

```text
Declared(M) does not imply Instantiated(M)
Instantiated-text-only(M) does not imply Executable(M)
```

No positive implication or architecture-independence claim is registered.

## 7. Boundaries

This record does not declare a concrete instance, projection, regime, action
set, admissible rule family, loss, value set, argmin, or oracle. It does not
select `COMPUTATIONAL_SEMANTICS`, `INSTANCE_FAMILY`, or any other road. It does
not create R-INTERNAL-20, reopen R-INTERNAL or R_ASSEMBLY, define R_ORACLE,
unblock Δ/gap/FinLoss/NECT, or enter STEP⑤/STEP⑥. No further implementation,
harness, data collection, profiling, measurement, or experiment authorization
follows from this record.
