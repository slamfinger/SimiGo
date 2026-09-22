# Research Question — Upstream Semantics and Execution Fork

**Status:** Retrospective registration / evidence mapping  
**Date:** 2026-09-22

## Research question

Can SimiGo obtain an independently executable child execution state from a running parent without recomputing the common prefix and without introducing a second physical-KV authority when the current MLX / MLXLMCommon public API is used?

## Scope

- MLX / MLXLMCommon versions and source snapshots recorded by F0.
- Apple Silicon real-device execution.
- Execution fork / shared-prefix semantics.
- This question does not generalize to all future upstream versions.

## Existing knowledge

- Disk fork exists as an explicit workflow and pays a large persistence/copy cost.
- `KVCache.copy()` provides independent deep-copy semantics rather than a documented sequence-sharing abstraction.
- The public API search found no sequence-identity equivalent of llama.cpp `seq_cp` / `seq_rm`.

## Unknown

Whether a future upstream release will expose a sufficient shared-prefix / sequence-identity capability.

## Evidence channels

- C1: upstream API/source audit.
- C3: controlled F0 execution experiment.

C3 is only partially independent because its protocol includes source inspection; its measured execution component is the independent portion.

## Evidence

- `docs/experiments/EXECUTION_FORK_F0_PROBE_20260918.md`
- `docs/experiments/EXECUTION_FORK_F0_PROBE_RESULTS_20260919.md`
- `docs/research/participants/PARTICIPANT_INDEPENDENCE_20260922.md`

## Result

For the tested dependency pins and model, the public API does not currently provide the required shared-prefix execution primitive. The evidence supports an upstream capability gap, not a proof about future versions.

## Falsification / reopening condition

Reopen when a tested upstream version exposes a documented sequence identity / shared-prefix mechanism, or an equivalent API that can be demonstrated to create independently executable child state without full prefix duplication.

## Boundary

This result does not authorize SimiGo to build a parallel KV authority. It instead defines the condition under which such a design question should be reopened.
