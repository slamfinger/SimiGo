# Same-directory model revision fence — implementation branch

Date: 2026-10-15  
Branch: codex/same-directory-drift-fence  
Base: SimiGo-Lab main at 8d4a0c7ab518b609e41907f29dc9dae9a8fd861d  
Scope: narrow follow-up to the accepted same-directory content-drift residual.

## Change

This branch adds an optional metadata-revision fence to the existing host-owned context hook. The host captures a revision across the weight and tokenizer-like files already incorporated into the existing EngineModelIdentity calculation before that calculation runs. It confirms the revision after content hashing, after container loading, and immediately before hook installation. The expected revision is bound into the hook.

Before returning a reusable prefix, the hook confirms:
1. the calling session's directory still matches the active model path (existing rule); and
2. the active model directory's current lightweight metadata revision still matches the captured revision (new rule).

If either check fails, the hook records a miss and returns nil, leaving ChatSession on its normal cold-prefill path. The host must be reactivated to restore prefix reuse after an observable revision change.

## Why metadata, not another content hash

The full SHA-256 content identity already costs O(model bytes) at activation. Rehashing large model weights at every ChatSession consultation would be an unacceptable hot-path cost. This fence instead fingerprints the existing identity inputs' relative paths, sizes, creation timestamps, and modification timestamps on each lookup. It is intended to catch ordinary file replacement or mutation under the same directory path without hashing model bytes again.

## Explicit residual

This does NOT prove byte-for-byte identity. An in-place rewrite that preserves size and all tracked timestamps can evade the metadata fence. Files not included in the current EngineModelIdentity inputs (for example config-only changes) are not redefined or added to the cache namespace by this patch. Filesystem metadata may also have provider-specific behavior. The previously accepted same-directory drift sliver is therefore narrowed for ordinary observable updates, not closed universally. No G-5/G-8/G-10, power-loss durability, or universal concurrency claim follows.

The caller-origin API and evaluate-to-hook call shape are unchanged. This patch does not edit the fork or alter DCC-1 Tier-1 semantics. GUI promotion ACCEPT remains unchanged; the five GUI click-through items remain OPEN pending local human execution.

## Verification

Added a targeted regression that first observes a valid strict-prefix hit, modifies the same-directory safetensors file with same-size bytes and a changed modification timestamp, then verifies the next lookup is a cold miss and does not add a hit.

This branch has not been built or tested in the current remote review environment. The PR is a code candidate pending a local Swift build/full suite and review of per-lookup metadata enumeration cost.

## Local verification (2026-10-15, PR review round)

1. **Blocker found and fixed — HF symlink layout**: the first local run of
   the named check failed: `modelDirectoryRevision` returned nil for the
   real HF snapshot directory (17/17 entries are symlinks into the blob
   store; `isRegularFile` of a link itself is false, so the fail-closed
   path fired and host activation would have been impossible on
   HF-cached models). Fixed in this branch: each candidate resolves
   through `resolvingSymlinksInPath()` and the TARGET's metadata is
   fingerprinted, plus the target blob name — re-pointing a snapshot link
   is itself observable drift.
2. **Stability**: repeated collection over the 30B snapshot yields an
   identical non-nil fingerprint (`cf512dbf031c8584…`, stable across
   runs). Pinned by `DriftFenceDiagnostics` (skips where the local
   snapshot is absent).
3. **Per-lookup overhead**: 200 collections over the 17-entry directory =
   52.9 ms total, **0.264 ms each** — ~0.04% of the measured warm-path
   wall time; negligible on the hook's synchronous path.
4. Submitter's latest local run on the symlink-fix commit: full suite
   `378 executed / 3 skipped / 0 failures`, app build passed. This result
   predates the additional portable symlink-retarget regression added during
   review; that test and the full suite must be rerun before merge.

Merge decision remains with the reviewer; the fence's own honesty
statement (metadata fence, not byte proof) is unchanged by this round.


## Review follow-up — portable symlink regression

The real-machine HF diagnostic uses the opt-in `SIMIGO_HF_DRIFT_DIAG_MODEL_DIR`
environment variable rather than embedding one developer's home path. A
portable XCTest now creates two same-sized blob files and a snapshot entry
symlink, asserts a stable non-nil revision, retargets the symlink, and asserts
the revision changes. At the time of this review note, the earlier 378/3/0 run predated the portable regression and a rerun was still pending. That pending condition is superseded by the completed final verification recorded below.


## Final local verification (2026-10-15, source head 2254bd9d388a27a6095df9a1045269436a4ce05b)

The submitter reports the following results against the exact source head above; the subsequent review-record commit changes this document only:

1. `testModelDirectoryRevisionResolvesSymlinkAndDetectsRetarget`: **PASSED**, using a temporary snapshot-to-blob symlink and confirming that retargeting changes the revision.
2. With `SIMIGO_HF_DRIFT_DIAG_MODEL_DIR` set to the real local 30B HF snapshot: **379 executed / 3 skipped / 0 failures**. `DriftFenceDiagnostics.testHFSnapshotFingerprintStabilityAndOverhead` executed (not skipped) and passed in 0.056 s; app build passed with 0 errors.
3. Fingerprint prefix remained `cf512dbf031c8584…`, stable both within the run and across runs while the 17/17 snapshot entries remained symlinks to unchanged targets.
4. 200 metadata-revision collections took 54.7 ms total, **0.273 ms per collection**, consistent with the prior 0.264 ms measurement and approximately 0.04% of the reported warm path.
5. The existing three skips were unchanged and were reported as previously established skips.

These are submitter-reported local results, not independently reproduced in the remote review environment. GitHub Actions supplied no workflow run or commit status for this head. No failures or new blockers were reported by the final local run.

The assurance boundary remains unchanged: this is a metadata freshness fence, not byte-content proof. Same-size rewrites preserving every tracked timestamp can evade it; inputs outside the existing `EngineModelIdentity` identity set are not added. GUI click-through checks remain OPEN; G-5/G-8/G-10, power-loss durability, universal concurrency, and DCC-1 Tier-1 are not advanced by this PR.
