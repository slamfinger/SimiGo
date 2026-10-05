# SimiGo-Lab Representation Consistency Boundary Result

Date: 2026-10-04  
Status: `EXECUTED / RAW EVIDENCE SEALED / MLX-SLICE BOUNDED`  
Code commit: `3b1d4353d63b1350fbbd7d343137cc2410e65937`  
Evidence directory: `docs/02-evidence/repconsistency-boundary-20261004/`

## Existing harness selection

The existing sealed Gδ-A harness
(`docs/02-evidence/gdelta-minimality-20261001/harness/GDeltaMinimalityTests.swift`)
is llama-server/full-prefix based, not MLX.

The minimum MLX insertion point was therefore the already existing
prefix-recompute path:

```text
ExecutionContinuityCoordinator
  -> MLXExecutionStateBackend
  -> MLXPrefixRecomputeExecutor
  -> real ModelContainer forward loop
```

The experiment adds only a CLI probe around those existing components.

## Command

```sh
swift run --package-path simigo2-experimental simigo2ctl \
  representation-consistency-boundary \
  "$HOME/.cache/huggingface/hub/models--peculiar-ragdoll--Nail-Qwen3.6-35B-A3B-MLX/snapshots/31a0106483c94e9fbb0a6d3360ff122d47377058" \
  --max-tokens 12 --c2-repetitions 3
```

Model type observed: `Qwen35MoEModel`.

## Result

```text
C0:
  accepted              = YES
  real MLX execution    = YES
  generated token IDs   = [271,248068,271,248069,271,27775,383,279,1928,3766,11,488]
  generated text prefix = "\n\n<think>\n\n</think>\n\nBased on the information provided, you"
  logical position      = 0 -> 1
  final representation  = 28 tokens

C1:
  representation binding accepted by coordinator = YES
  execution accepted                             = NO
  real MLX execution                             = NO
  first detection layer = MLXExecutionStateBackend.boundPrefix position check
  error = representationPositionMismatch(bound=999, logical=0)
  logical position stayed 0

C2.rep1:
  accepted              = YES
  real MLX execution    = YES
  generated token IDs   = [271,248068,198,8160,579,264,7047,1817,25,271,16,13]
  difference from C0    = DIFFERENT_FROM_C0(token_ids)
  logical position      = 0 -> 1
  final representation  = 28 tokens

C2.rep2:
  identical to C2.rep1 token IDs/text
  difference from C0    = DIFFERENT_FROM_C0(token_ids)

C2.rep3:
  identical to C2.rep1 token IDs/text
  difference from C0    = DIFFERENT_FROM_C0(token_ids)

C3:
  representation binding accepted by coordinator = YES
  execution accepted                             = NO
  real MLX execution                             = NO
  first detection layer = MLXExecutionStateBackend.boundPrefix position check
  error = representationPositionMismatch(bound=999, logical=0)
  logical position stayed 0
```

## Boundary

```text
first observable divergence:
  C1/C3: backend bound-prefix/position check.
  C2: backend execution output.

detection boundary:
  C1/C3 rejected before MLX executor loop by
  MLXExecutionStateBackend.boundPrefix(for:) via
  ExecutionStateBackendError.representationPositionMismatch.

real backend execution:
  C0/C2 = YES. C1/C3 = NO.

observable output effect:
  C2 differed from C0 in all 3 repetitions,
  with identical C2 token IDs across repetitions.
```

## Controlled-variable assessment

| Variable | C0 | C2 | Assessment |
|---|---|---|---|
| Execution ID | `repconsistency-single` | same | same |
| Logical position | 0 | 0 | same |
| Representation position | 0 | 0 | same |
| Continuation | `repconsistency-next-input` | same | same |
| Model | Nail-Qwen3.6-35B-A3B-MLX snapshot `31a0106...` | same | same |
| Tokenizer | same loaded container tokenizer | same | same |
| Input | same fixed seed text + next input | same | same |
| Generation | greedy argMax, cache nil, seed 42, max 12 | same | same |
| Representation length | 10 tokens | 10 tokens | same |
| Representation content | original token index 8 = `9017` | index 8 = `9018` | changed |

## Interpretation

Only this bounded statement is supported:

> In the current MLX prefix-recompute slice, position mismatch is rejected at
> `MLXExecutionStateBackend.boundPrefix(for:)` before real MLX execution;
> same-ID / same-logical-position / same-length / different-token-content is
> accepted, reaches real MLX execution, advances logical position, and
> produces stable observable output divergence from C0.

## Not established

```text
Not established: KV-cache representations other than this token-prefix strategy.
Not established: llama-server or any second backend.
Not established: semantic quality or correctness of either output.
Not established: representation integrity in general.
Not established: mathematical minimality or contract completeness.
Not established: behavior under sampling, concurrent execution, persistence,
  restore-from-disk, or production chat pipeline.
```

## Potential future design question

Whether content-integrity needs a detection boundary is deferred. This result
does not authorize adding hash, anchor, provenance, or a consistency gate.
