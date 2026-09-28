# SimiGo v2.0 Beta — Execution State Technical Freeze

Date: 2026-09-29  
Status: **Technical route frozen; release tag not created.**

## Freeze decision

SimiGo v2.0 Beta has completed the initial engineering validation of
Execution State as a runtime abstraction for inference lifecycle management.

This is a deliberate scope freeze, not a claim that Execution State has been
formally proven as a universal inference-runtime abstraction.

```text
BETA-AUDIT-3 = PASS / RETURN TO RELEASE PATH
P0 = 0
P1 = 0
P2 = 0
```

Implementation baseline:

```text
FAIL baseline     eb2247bddbfbae8d40be247b1534c46a8dc160c4
fix commit        62ef12134c4cbe1b41d2f4fde2c47de9f79a39d1
audit receipt     f15bde1
branch            main
release tag       not created
```

## Frozen technical boundary

The following boundaries are frozen for Beta:

- Logical State / Physical Representation separation.
- fork / restore / suspend / reuse / release lifecycle.
- generation / save / load / delete lifecycle consistency.
- `SessionGenerationGate` as the lifecycle serialization domain.
- checkpoint durability and generation/hash fail-closed checks.
- SaveReceipt / digest-at-write persistence semantics.
- cooperative cancellation at the lifecycle boundary.
- oversized model validation path.
- unified-memory / MLX backend architecture.
- inference-hot-path non-regression: no per-token/per-step lock and no new
  hot-path copy/hash/serialization.

No additional product feature may become a prerequisite for the first Beta
release.

## Evidence chain

### Lifecycle consistency

`BETA-AUDIT-3` closed the last known lifecycle race windows:

```text
generation ↔ save     PASS
generation ↔ load     PASS
generation ↔ delete   PASS
```

Evidence:

```text
testGenerationGateBlocksSaveUntilGenerationCompletes       PASS
testGenerationGateBlocksLoadCommitUntilGenerationCompletes PASS
testGenerationGateBlocksDeleteLifecycleUntilGenerationCompletes PASS
```

### Regression receipt

Current SimiGo scheme:

```text
85 selected / 0 failures / 8 environment-gated skips
```

C1 targeted:

```text
testCheckpointPairMismatchFailsClosed        PASS
testCheckpointGenerationMismatchFailsClosed  PASS
```

The historical “95/95” manifest is not reproduced in the current scheme and is
not used as a release claim.

### Dependency provenance

```text
Package.resolved SHA256
4072b69845ca1684b363cf7ea965f696e19979a100eb015ab891a500cba94f3c

mlx-swift     ef5f1b6bb24e27922189316362f3057c64261704
mlx-swift-lm  fd5d1b4a8a5ad83e1d78617fecc817fa196a64fc
```

No dependency drift was introduced by BETA-AUDIT-3.

## Release path

The next phase is release validation, not feature development:

1. clean-tree / commit / dependency receipt check;
2. external smoke validation on the release build;
3. small public technical description;
4. collect feedback before deciding the next development phase.

## Public framing

Use:

> SimiGo v2.0 Beta: an initial engineering implementation of Execution State
> for inference runtimes.

Core question:

> Can Execution State serve as a runtime abstraction for inference lifecycle
> management?

Do not claim that a new inference engine was invented or that Execution State
has been universally proven.

## Upstream boundary

Upstream work should expose only validated backend primitives, for example:

- representation snapshot / checkpoint primitive;
- KV representation lifecycle;
- fork/copy semantics;
- representation identity / save receipt;
- cooperative cancellation.

SimiGo remains the Execution State / runtime-policy layer. Upstream remains the
backend-primitive layer. The two boundaries must not be merged into one
architecture proposal.
