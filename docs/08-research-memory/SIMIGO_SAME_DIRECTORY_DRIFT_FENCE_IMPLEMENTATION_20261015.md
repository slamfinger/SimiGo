# Same-directory model revision fence — implementation branch

Date: 2026-10-15  
Branch: codex/same-directory-drift-fence  
Base: SimiGo-Lab main at 8d4a0c7ab518b609e41907f29dc9dae9a8fd861d  
Scope: narrow follow-up to the accepted same-directory content-drift residual.

## Change

This branch adds an optional metadata-revision fence to the existing host-owned context hook. The host captures a revision across relevant weight, JSON/configuration, tokenizer, vocabulary, merge, and chat-template files before the existing streaming content identity calculation. It confirms the revision after content hashing, after container loading, and immediately before hook installation. The expected revision is bound into the hook.

Before returning a reusable prefix, the hook confirms:
1. the calling session's directory still matches the active model path (existing rule); and
2. the active model directory's current lightweight metadata revision still matches the captured revision (new rule).

If either check fails, the hook records a miss and returns nil, leaving ChatSession on its normal cold-prefill path. The host must be reactivated to restore prefix reuse after an observable revision change.

## Why metadata, not another content hash

The full SHA-256 content identity already costs O(model bytes) at activation. Rehashing large model weights at every ChatSession consultation would be an unacceptable hot-path cost. This fence instead fingerprints relevant files' relative paths, sizes, creation timestamps, and modification timestamps on each lookup. It is intended to catch ordinary file replacement or mutation under the same directory path without hashing model bytes again.

## Explicit residual

This does NOT prove byte-for-byte identity. An in-place rewrite that preserves size and all tracked timestamps can evade the metadata fence. Filesystem metadata may also have provider-specific behavior. The previously accepted same-directory drift sliver is therefore narrowed for ordinary observable updates, not closed universally. No G-5/G-8/G-10, power-loss durability, or universal concurrency claim follows.

The caller-origin API and evaluate-to-hook call shape are unchanged. This patch does not edit the fork or alter DCC-1 Tier-1 semantics. GUI promotion ACCEPT remains unchanged; the five GUI click-through items remain OPEN pending local human execution.

## Verification

Added a targeted regression that first observes a valid strict-prefix hit, modifies the same-directory safetensors file with same-size bytes and a changed modification timestamp, then verifies the next lookup is a cold miss and does not add a hit.

This branch has not been built or tested in the current remote review environment. The PR is a code candidate pending a local Swift build/full suite and review of per-lookup metadata enumeration cost.
