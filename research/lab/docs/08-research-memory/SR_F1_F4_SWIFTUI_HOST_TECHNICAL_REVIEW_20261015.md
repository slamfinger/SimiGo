# F1 / F4 / SwiftUI Host — Integrated Technical Review

> **Review ID:** `REVIEW-SR-F1F4SWIFTUI-20261015`
> **Date:** 2026-10-15 (Asia/Shanghai)
> **Repository HEAD:** `1f80d50e` (main)
> **Nature:** READ-ONLY integrated review. Coordinates three independent evidence lines — F1 (fork numerical diagnostics), F4 (host lifecycle + caller identity closure), SwiftUI chat-host mount — into a single timeline. Does NOT change code, rerun experiments, modify research contracts, or open a new authorization cycle.
> **Source files (original evidence, unchanged):**
> - F1/F4: `simigo2-experimental/docs/02-evidence/f1-f4-diagnostics/20261015-e88eca5c/README.md`
> - Canonical prefill F4: `simigo2-experimental/docs/02-evidence/canonical-prefill-f4/20261015-a4781328/README.md`
> - SwiftUI mount: `simigo2-experimental/docs/02-evidence/gui-promotion-acceptance/20261015-swiftui-mount/README.md`

---

## 0. Review Scope and Guardrails

This review coordinates three already-evidenced lines, each with its own acceptance bar and gate record. It is not itself a new measurement. The review:

- Coordinates F1's fork numerical diagnostics (bit-equality across prefill shapes).
- Coordinates F4's host lifecycle closure + registered caller-identity residual.
- Coordinates the SwiftUI chat-host mount (canonical-prefill gate host path).
- Correlates their timeline, does NOT rewrite the original READMEs.

It does **not** trigger:
- Code modification
- Experiment rerun
- Research contract change
- New authorization cycle

PR #5–#9 closed conclusions are unchanged. V1–V4 remain un-authorized.

**Correction of the `sidebar-prefill-guard` naming error:** The earlier review introduced a term `sidebar-prefill-guard` that did not correspond to any actual code object. The correct UI binding-protection object is:

```
simigo2-experimental/Sources/SimiGo2App/SimiGo2App.swift
  - class ChatAppModel: ObservableObject (line 94)
    - @Published var loadedModelDirectory: URL?          (line 102)
      @Published private(set) var loadedExecutionPath: ExecutionPath?  (line 101)
      - private var bindingMatchesRequest: Bool           (line 132, computed)
        guard bindingMatchesRequest (lines 311, 435 in loadSmallScale/main flow)
```

The guard checks that the currently-loaded execution path and model directory still match the user's active request. Two commits implement it (not re-run as experiments):
- Directory-level binding protection: `108e52d1f889d49aa243132fea367499c6069fa1`
- Publish binding only after successful load: `edb79fad072c8ed3d0249069fc5a7009e81eb160`

These belong to the chat-host mount, **not** a sidebar. `sidebar-prefill-guard` should be deleted from any review record and NOT treated as a new code object or research task.

---

## 1. F1 — Fork Numerical Diagnostics (Timeline: Early Divergence → STRICT PASS)

### 1a. F1 Early Diagnostics — Divergence (e88eca5c)

The **early** F1 diagnostics showed output divergence across different prefill shapes. This was a real finding at that time:

- **Finding 1:** Chunk-shape sensitivity is real and cold-only — the pure-cold remainder-chunked path `coldSegmented` flips the same compound token as the warm path; **no snapshots involved**.
- **Finding 2:** The flip site is numerically marginal — top-1 ("head", 23.75) vs top-2 (" Ahead", 23.50): a **0.25-logit margin** decides it. Any prefill-shape perturbation can cross it.
- **Finding 3:** Save→load fidelity is EXACT — artifact-sourced-from-unchunked-session equals direct single-forward KV bit-exactly across 48 layers (`keysMaxAbsDiff = 0`, `valuesMaxAbsDiff = 0`). Serialization path is **ACQUITTED**.
- **Finding 4:** The `diff=26` was a confounder, itself a finding — the balanced session's INTERNAL KV differs from both single-forward and [900|68]-forward by max-abs ~26; the fork's ChatSession prefill internals (logits-position reservation, internal chunk shapes) produce materially different KV from any externally reproducible shape.
- **Finding 5:** Warm ≠ segmented-cold — they diverge from each other (position 35/36).

Per the approved decision logic, this lands in branch 2 (warm ≠ segmented cold → inspect serialization/adoption/suffix); inspection acquits serialization while locating the residual in session-internal prefill shape composition. **Diagnostics only; bit-equality bar stands unchanged pending human adjudication.**

### 1b. F1 Subsequent Ruling — Canonical Prefill STRICT PASS (a4781328)

The canonical prefill profile obtained **STRICT PASS ×3** (stride 512@512; stride 256@512 and @768): chunk sequences, completion token counts, and texts all exactly equal; adoption hit exactly at stable boundary. Achievable via public ChatSession chunking API; no fork interface change needed for equality. Token-ID exposure remains a registered fork API gap (chunk sequence + generationTokenCount are the finest public record).

**Time-ordering rule:** Do NOT continue to describe early F1 divergence as current acceptance failure. The STRICT PASS supersedes the early finding — the earlier diff=26 was explained as a confounder, itself a finding; serialization is acquitted. Early divergence is now understood to live in fork's session-internal prefill shape composition, not a serialization bug.

---

## 2. F4 — Host Lifecycle + Caller Identity Closure (Timeline: Registered-Open → Closed)

### 2a. F4 Early Record — Open Residual (e88eca5c)

The `e88eca5c` evidence recorded caller-identity residual as **REGISTERED-OPEN**:
- `switchModel` now: bump generation → release hook → DROP old container → load new. Rollback RELOADS previous model; double failure reports host deactivated with original error.
- Host-issued sessions carry their generation (`HostSession`): post-switch generate attempts throw `sessionStale`.
- Global hook installs with generation-bound `admissionGuard`; refused lookups return nil (cold) and record an observed miss.
- **Registered residual:** a raw pre-switch `ChatSession` created outside the host can still reach the global hook; fork's hook signature carries no caller identity, so full closure needs a fork-side session-identity API. Mitigations: namespace separation, fork's layer-count guard, token-chain admission.
- **Measurement defect recorded honestly:** the `foreignHookCold` leg invoked hook AFTER switch-back (legitimate hit); correct placement (raw A tokens while B active) not measured. Correct `foreignHookCold = false` is expected same-model result, NOT evidence about residual.

Suite: **365 executed / 3 skipped / 0 failures**. Real-model F4 legs: `staleSessionRejected = true`, `reAdoptedHitObserved = true` at full 900 boundary.

### 2b. F4 Subsequent Ruling — FORK-HOOK-CALLER-IDENTITY-01 CLOSED

The mainline later recorded **FORK-HOOK-CALLER-IDENTITY-01 CLOSED** within original authorization scope (fourth review round bc50ce14; fork eab6895; SimiGo c81f4de6):

- Context hook with calling-session model origin (real evaluate-path refusal evidence), and slot ownership closed across FCI-OWN-01..05 with final shape being UNREADABLE owner token (isOwned-only comparison), INDEPENDENT registry check, true-emptiness release semantics.
- **Retained:** five GUI click-through items OPEN pending local human execution; G-5/G-8/G-10, power-loss durability, universal concurrency unaffected; same-directory content drift remains accepted sliver.

**Time-ordering rule:** Do NOT treat early F4 README directly as current state. The original registered OPEN residual has since been closed within the authorization scope; do not describe the early README as reflecting current fork-side closure status.

---

## 3. SwiftUI Chat-Host Mount — Promotion ACCEPTED (Timeline: REVIEW COMPLETE → ACCEPT)

### 3a. SwiftUI Mount Evidence Timeline

- **Mount Complete (5-item matrix):** `codex/swiftui-small-scale-mount`, branch executed; Engine code + DCC-1 Tier-1 untouched.
- **F3 Retraction issued:** measurement bug found and fixed — DURATION→seconds divided attoseconds by 1e15 instead of 1e18, inflating fractional seconds 1000x; engine's per-token latency stat carried same bug. All seconds-intent sites fixed (367/3/0). Corrected run: cold 1.28-1.30s vs warm 0.66-0.68s wall (48% paired savings), TTFT 0.88→0.29s (3x), hook 1 hit @512 per warm leg, swap stable — `pass = True` under corrected criterion. F3 CLOSED WITH POSITIVE EVIDENCE for canonical small-scale path; retraction recorded in `simigo2-experimental/docs/02-evidence/f3-benefit-protocol/20261015-8cbff75c/`.
- **F4 Reopen Fixes:** switchModel captures previous DIRECTORY only (old ActiveModel kept container alive across next load); host-issued generations register in-flight and switch cancels + drains them (bounded 120s, overrun fails switch with old state untouched) before dropping container; foreign-hook residual measurement moved into B-active window. Real 30B→35B→30B legs all PASS including `foreignHookCold = true` in correct window (B active, A tokens → nil).
- **GUI PROMOTION ACCEPT:** `chatSession.evaluate` can supply caller's model DIRECTORY (ModelConfiguration.id retains local URL); opt-in `crossSessionPrefixLookupWithContext` variable closes cross-model hole with zero legacy-behavior change and no DCC-1 involvement; exhaustive refusal table, accepted same-directory sliver, acceptance criteria, non-goals included. Fork implementation requires separate authorization.

### 3b. SwiftUI Mount Guard Implementation (SimiGo2App.swift)

```swift
final class ChatAppModel: ObservableObject {         // line 94
  @Published var loadedExecutionPath: ExecutionPath?   // line 101, private(set)
  @Published var loadedModelDirectory: URL?            // line 102, private(set)
  private var bindingMatchesRequest: Bool { ... }       // line 132, computed guard
  // guard bindingMatchesRequest at lines 311 and 435 (loadSmallScale / main flow)
}
```

The guard enforces that loaded path + model directory match the user's active request. Two implementation commits (not rerun as experiments):
- Directory-level binding protection: `108e52d1f889d49aa243132fea367499c6069fa1`
- Publish binding only after successful load: `edb79fad072c8ed3d0249069fc5a7009e81eb160`

Suite: **367 executed / 3 skipped / 0 failures** (post-F3-fix); **369/3/0** in some integrated-build runs.

### 3c. Timeline Rule — Five GUI Click-Through Items REMAIN OPEN

The five-item matrix evidence (canonical strict equality; content-identity isolation + B-window foreign-hook nil; corruption fail-closed; release-first switch round trip with drain; corrected-instrument 48% wall / 3x TTFT benefit) is assembled with real-model evidence; but the five GUI click-through items are NOT executed because:
- No automated GUI-interaction harness exists.
- Interactive click-through remains a human step.

**Time-ordering rule:** GUI PROMOTION ACCEPTED, but five interactive click-through checks are NOT executed and must be recorded as OPEN post-acceptance supplementary verification. This does not invalidate ACCEPT itself (which was based on the five-item matrix evidence), but it means clicking-through cannot be marked PASS in any audit.

---

## 4. Integrated Timeline (All Three Lines)

```
Date          Line     Gate Status                        Evidence
------------  -------  --------------------------------   -----------------------------
2026-10-14    UI       REVIEW COMPLETE / DECISION SUBMITTED — no implementation
2026-10-14    UI       MOUNT COMPLETE / FIVE-ITEM MATRIX EVIDENCED
2026-10-15    F3       RETRACTION + POSITIVE BENEFIT (measurement bug fixed)
2026-10-15    UI       SMALL-SCALE HOST PATH IMPLEMENTED / NOT PASS
2026-10-15    F4       canPrefillProtocol STRICT PASS ×3; f4 lifecycle fixes
2026-10-15    UI       GUI PROMOTION ACCEPT (fourth review round bc50ce14)
2026-10-15    F1-F4    FORK-HOOK-CALLER-IDENTITY-01 CLOSED within orig auth scope
2026-10-15    all      tokenizer revision identity audit (read-only)

Key rule: F1/F4 have EARLY findings (E88ECA5C, REGISTERED-OPEN) that are
LATER superseded by subsequent rulings (canonical prefill STRICT PASS; fork
caller-identity closure). Do NOT use the early READMEs to state current gate
status; always read the subsequent ruling.
```

---

## 5. Guardrails (Preserved)

- F1 bit-equality across prefill shapes is NOT a stable property of this stack — even between two cold paths. Bounded by e88eca5c evidence.
- F4 registered residual (raw pre-switch ChatSession reaching global hook) is CLOSED within original authorization scope; full closure needs fork-side session-identity API. Measurement defect recorded honestly (`foreignHookCold` leg invoked after switch-back).
- SwiftUI mount: GUI PROMOTION ACCEPTED, but five interactive click-through checks NOT executed (no automated harness). Recorded as OPEN post-acceptance supplementary verification. Does not invalidate ACCEPT but clicking-through cannot be marked PASS.
- Do NOT re-run F3 (measurements already fixed and positive evidence established); do NOT reopen E4 (verified 2026-09-25).

## 6. References to Existing Evidence (unchanged)

- F1/F4: `simigo2-experimental/docs/02-evidence/f1-f4-diagnostics/20261015-e88eca5c/README.md`
- Canonical prefill F4: `simigo2-experimental/docs/02-evidence/canonical-prefill-f4/20261015-a4781328/README.md`
- SwiftUI mount: `simigo2-experimental/docs/02-evidence/gui-promotion-acceptance/20261015-swiftui-mount/README.md`
- F3 retraction + positive measurement: `simigo2-experimental/docs/02-evidence/f3-benefit-protocol/20261015-8cbff75c/`
- UI binding-protection implementation commits: `108e52d`, `edb79fad`
- FORK-HOOK-CALLER-IDENTITY-01 closure records: `8d4a0c7`, `bc50ce14`

**Closing:** F1/F4 and GUI mount all have established evidence; the subsequent rulings (canonical prefill STRICT PASS, fork caller-identity closure) supersede early findings. No new experiments required; do NOT re-run F3 or reopen E4.
