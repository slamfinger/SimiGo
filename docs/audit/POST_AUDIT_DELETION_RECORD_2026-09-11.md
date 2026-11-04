# Post-audit deletion record — 2026-09-11

## Canonical runtime baseline

This simplification branch is intentionally based on:

`df5b31b9517e541777ed87271774c468b4724422`

That commit was previously used as a real-device performance audit baseline and was recorded as production-code-zero-change. It demonstrated 11 consecutive warm-hit rounds with increasing prompt prefixes and passed KV ledger alignment on the tested dense model.

## Why later audit code is not merged back

The 2026-09-09 audit introduced or expanded several custom runtime layers while investigating legitimate semantic questions. The historical branch `audit-candidates-2026-09-09` preserves those documents and code history.

The simplification decision is:

- do not preserve audit experiments as production runtime;
- do not replace a deleted custom layer with another custom layer of equivalent purpose;
- use official `mlx-swift` / `mlx-swift-lm` facilities first;
- use Swift structured concurrency and standard synchronization where application-level coordination is genuinely required;
- add a new abstraction only after a concrete official API gap is demonstrated.

## Deleted / abandoned audit directions

The following were specifically rejected as production architecture during the simplification pass:

- AdmissionReservationLedger
- S1 BatchSequence / BatchedDecodeScheduler / InferenceModelCapabilities experimental layer
- PhysicalKVContinuation / PhysicalKVContinuationRecorder as a second cache-state protocol
- CancellationCommitToken as a second cancellation/commit authority
- audit-only continuation snapshot plumbing
- audit-only warm-hit state seams

## Evidence retained

Historical findings remain on:

- branch: `audit-candidates-2026-09-09`
- branch: `kv-continuation-impl-2026-09-09`

Relevant audit records cover admission, cancellation, lifecycle, Physical KV residency, Qwen35/Mamba state, TokenIterator boundaries, memory governance, and upstream MLX semantics.

## Final engineering rule

Production inference behavior must be expressible through the official model/session/generation/cache APIs whenever those APIs already provide the required semantics. The application layer should own only application concerns such as HTTP/OpenAI protocol mapping and service process management.
