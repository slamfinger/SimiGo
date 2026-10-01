# SimiGo v2.1.0 — Execution State Reference App

Date: 2026-10-01  
Build: 10  
Tag: `v2.1.0`  
Platform: Apple Silicon macOS 26.4+  
Asset: `SimiGo-v2.1.0.dmg`

## Highlights

- First product-shaped reference implementation of the frozen Execution State
  Contract.
- New **Execution State Graph** window with State as the top-level object.
- Seven-operation lifecycle:
  `create / continue / save / fork / restore / discard / release`.
- Atomic durable checkpointing; save fixes the current semantic closure into
  durable representation without creating a new semantic state.
- Fail-closed restore validates identity, model binding, anchor, and record
  checksum before returning a restored state.
- Parent-preserving fork semantics: the child value-copies the parent closure
  at the fork point and the parent remains untouched.
- Atomic discard removes checkpoint bindings and prevents ghost continuation.
- Release clears durable binding without abolishing the logical state.
- Main UI hides backend/carrier details; representation declaration is exposed
  only in diagnostics.
- Layered open-source release: Apache-2.0 code, CC-BY-4.0 research documents,
  separate trademark boundary, and third-party notices.

## State Graph reference carrier

The v2.1 State Graph uses `R_Reference_v1`:

```text
Σ_R      ReferenceCheckpointV1
C_R      canonical token-prefix array
Inv_R    anchor hash / record checksum / model identity
Rules_R  ρ_R1 anchor integrity · ρ_R2 prefix extension · ρ_R3 record integrity
```

This carrier is intentionally separate from backend conformance claims.

## Verification

- Targeted suite: `ExecutionStateGraphTests`
- Result: `4 tests, 0 failures`
- Coverage: create/continue/fork parent non-interference, save/restore,
  tampered-checkpoint fail-closed behavior, durable graph persistence, discard
  ghost-checkpoint prevention, and release binding clearing.
- Release build: `BUILD SUCCEEDED`

## Boundaries and non-claims

- The v2.1 State Graph does not claim MLX or llama.cpp conformance.
- `R_Reference_v1` is not a backend-independent Execution State proof.
- This is a reference app / research preview, not GA.
- No model weights are distributed in the repository or DMG.
- Future hosted, enterprise, management, support, and proprietary integration
  components are not licensed by this release.

## macOS Gatekeeper notice

The DMG is ad-hoc signed but not notarized. After verifying the SHA-256 on the
GitHub Release page, remove quarantine if macOS blocks first launch:

```bash
xattr -dr com.apple.quarantine SimiGo.app
```

Only run a copy whose checksum matches the official Release asset.
