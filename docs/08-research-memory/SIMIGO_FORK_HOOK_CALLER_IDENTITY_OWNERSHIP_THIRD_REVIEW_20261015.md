# FORK-HOOK-CALLER-IDENTITY-01 — third ownership closure review

Date: 2026-10-15  
Review target: SimiGo-Lab main merge 398c43d504df357b1fa0b14ceadb8d19c37b0d4e  
Fork target: slamfinger/mlx-swift-lm@0a291ab2f61b3cafcbb96511b9ba5561a6d2a6c8  
Prior review: 09a2e9d332bd72c720c0d53e330e5ca81d1eb4db  
Review ID: FORK-HOOK-CALLER-IDENTITY-01-OWNERSHIP-THIRD-REVIEW

## Decision: REVISE — FCI-OWN-02 is not yet closed

The new comparable-owner mechanism is stronger than the marker probe for wrappers that use a distinct token, and the submitted test demonstrates that specific case. Source inspection finds that the ownership token can itself be copied into a wrapper. There is also a registry/slot divergence path that bypasses the explicit-takeover rule, and the ownsNoHookSlot implementation contradicts its documented contract.

These findings concern hook ownership/lifecycle only. They do not reopen the GUI promotion ACCEPT, DCC-1 Tier-1, or other frozen boundaries.

## FCI-OWN-03 — the owner token is transferable through the public API

In Libraries/MLXLMCommon/ChatSession.swift, CrossSessionPrefixLookup is a public struct with public owner, a public OwnerToken.init(), and a public initializer accepting an arbitrary owner token. In the host, slotIsOurs() checks only whether the current slot's token is identical to the cache's token.

A forwarding wrapper can therefore preserve the original token, not just create a foreign one:

    let original = ChatSession.crossSessionPrefixLookupWithContext!
    ChatSession.crossSessionPrefixLookupWithContext =
        ChatSession.CrossSessionPrefixLookup(owner: original.owner) {
            tokens, caller in original.lookup(tokens, caller)
        }

This leaves the wrapper fully functional and makes slotIsOurs() return true. Same-instance install() can report idempotent success, and uninstall() can clear the external wrapper. The existing test uses foreignLookup(forwardingTo:), which deliberately creates a new token and does not cover token reuse.

### Narrow closure requirement

Ownership must compare an identity that a wrapper cannot copy from the original holder. Prefer comparing the current slot to the exact installed holder object (e.g. make the holder a reference type and retain that instance), or expose a fork-owned controlled ownership API that does not publish a transferable owner token. Do not treat a public token field plus public token-accepting initializer as unforgeable ownership.

Add a regression for a wrapper that forwards the original lookup and reuses the original owner identity; install() must not claim the slot as an untouched idempotent install and uninstall() must not clear the wrapper.

## FCI-OWN-04 — nil slot allows implicit takeover while another registry owner remains

The current install() checks for a foreign context-slot owner only when the context slot is non-nil. The earlier independent guard Self.active != nil && !forceTakeover was removed. If cache A remains Self.active but an external change clears the context slot, cache B can call ordinary install(): the slot is nil, so the foreign-slot guard does not throw; B replaces Self.active without forceTakeover: true.

This violates the stated singleton semantics that a live different owner blocks ordinary installation and that a model-switch transfer requires explicit takeover.

### Narrow closure requirement

Restore an independent registry guard: when Self.active is non-nil and not the instance being installed, ordinary install must fail regardless of whether the static slot is nil; only explicit takeover may transfer the registry. Add a test that installs A, clears the context slot externally, and proves B's ordinary install throws and leaves A as the registry owner.

## FCI-OWN-05 — ownsNoHookSlot can report complete release while a foreign hook remains

Its documentation says true means this cache no longer owns the context slot and no context hook remains. The current implementation returns Self.active !== self && !slotIsOurs(). After uninstall correctly preserves a foreign wrapper, active !== self is true and the foreign token differs, so this property returns true even though the context slot is non-nil.

The GUI's direct check of both static slots is a stronger independent guard and remains valid; this finding concerns the public helper's documented meaning and any caller relying on it.

### Narrow closure requirement

Either restore the non-nil slot check in ownsNoHookSlot (and keep legacy-slot verification separate as documented), or rename/redefine the property to mean only “this cache does not own the slot” and audit all callers. Add a test asserting it is false while a foreign wrapper remains and true only after the context slot is empty.

## Evidence and retained boundaries

- The foreign-token forwarding-wrapper test is useful and should remain.
- The real raw ChatSession A-during-B identity evidence and canonical strict cold/warm equality evidence remain applicable to the caller-identity path: this patch changes slot representation/ownership, not the evaluate-to-hook caller/context or lookup arguments. The submitting engineer reports 373 executed / 3 skipped / 0 failures and app build success; this review did not independently run Swift builds/tests.
- Same-directory content drift remains the accepted residual. No claim is made about G-5/G-8/G-10, power-loss durability, or universal concurrency.
- GUI promotion ACCEPT remains active. The five real SwiftUI click-through checks remain OPEN / NOT YET EXECUTED; do not mark them PASS from this ownership review.

## Required next review artifact

Submit the narrow FCI-OWN-03/04/05 corrections and their targeted tests. No new experiment authorization or expensive identity-probe rerun is requested unless the evaluate-to-hook path changes.
