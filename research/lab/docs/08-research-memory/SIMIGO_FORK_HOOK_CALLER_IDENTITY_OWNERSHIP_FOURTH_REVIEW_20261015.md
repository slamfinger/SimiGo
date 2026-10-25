# FORK-HOOK-CALLER-IDENTITY-01 — fourth ownership closure review

Date: 2026-10-15  
Review ID: FORK-HOOK-CALLER-IDENTITY-01-OWNERSHIP-FOURTH-REVIEW  
SimiGo-Lab merge reviewed: c81f4de6bd7f4ce9924eab9a3b406075fd4f29d4  
Host implementation commit: 1dec46e32f8ac91ae6070954fbaff447c071a220  
Fork revision pinned by Package.resolved: eab689575cc1fff7aa2e8b25941b6bd6f4050173  
Prior review: f050e7de9c6d0ac9fb3064a8196d5bc3a1325754

## Decision: ACCEPT — FCI-OWN-03/04/05 closed within the reviewed scope

The current fork API and host implementation resolve the three findings from the third review. This is a source-level review of the pushed commits and recorded evidence; Swift builds/tests were not independently executed in this review environment.

## Finding-by-finding disposition

### FCI-OWN-03 — transferable owner identity: CLOSED

In the fork's CrossSessionPrefixLookup, owner is now a private stored property without a public accessor. isOwned(by:) compares the private stored identity with a token supplied by the caller but does not return or expose the stored token. The host retains its token in its own private ownershipToken and verifies the current slot through isOwned(by:).

The previously described wrapper (read original.owner, then reconstruct with that token) is no longer expressible through the public API. A wrapper can still forward calls under its own token, but that token is not identical to the host's private token and is rejected by slotIsOurs().

Test-evidence nuance: testSameTokenWrapperIsUnconstructibleAndForeignWrappersAreNotOurs does not attempt an executable same-token construction (which should fail at compile time because no accessor exists); its runtime assertion tests a fresh foreign token. The closure decision relies on inspection of the fork's declared access control and API shape, with the runtime foreign-token test as supporting—not sole—evidence. Do not describe this test alone as dynamically executing a same-token attack.

### FCI-OWN-04 — registry/slot divergence permits implicit takeover: CLOSED

install() again checks Self.active independently of static slot occupancy. A different active instance causes ordinary install to throw OwnershipError.hookOwnedByOther, even if the context slot is nil. Explicit forceTakeover: true remains the deliberate displacement path.

The new testRegistryActiveInstanceBlocksPlainInstallEvenWithEmptySlot covers A active → context slot externally cleared → B ordinary install rejected; it also covers explicit takeover, the displaced A uninstall returning false, and B's eventual release.

### FCI-OWN-05 — ownsNoHookSlot reports release while a foreign hook remains: CLOSED

The property now requires both Self.active !== self and ChatSession.crossSessionPrefixLookupWithContext == nil. A preserved foreign wrapper therefore keeps the property false until the slot is genuinely empty.

The new testOwnsNoHookSlotFalseWhileExternalWrapperRemains covers both the retained-wrapper and cleared-slot states.

## Evidence and remaining boundaries

- The prior foreign-token forwarding-wrapper test remains in place.
- The submitting engineer reports 376 executed / 3 skipped / 0 failures and a successful app build. These are recorded results, not an independent rerun by this reviewer; repository status checks were not available from the inspected commit metadata.
- The owner-storage change, registry guard, and slot-empty predicate do not change the evaluate-to-hook consultation arguments or caller-origin derivation. The standing real A-session-during-B identity-refusal evidence and canonical strict cold/warm equivalence remain applicable under the previously agreed no-rerun condition.
- Same-directory content drift remains the accepted residual. This decision makes no claim about G-5/G-8/G-10, power-loss durability, or universal concurrency.
- GUI promotion ACCEPT is unchanged. The five real SwiftUI click-through checks remain OPEN / NOT YET EXECUTED and must not be marked PASS on the strength of this review.

## Final ruling

The three ownership findings from the third review are closed within the current scope. No additional ownership-code revision is requested. Preserve the frozen boundaries and continue to track the five GUI click-through items separately.
