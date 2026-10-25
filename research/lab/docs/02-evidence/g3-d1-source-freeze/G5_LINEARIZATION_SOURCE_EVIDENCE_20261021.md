# G5 Termination/Commit Linearization — Source-Level Evidence Pack

Round: fourth G3/G4/G5 review response (2026-10-21).
Reviewer standing objection: "a pre-commit check is not a linearization point;
G5 stays partial until the latest diff proves a SHARED adjudication mechanism."
This pack answers that objection with the current source and the current race
tests, so the reviewer can adjudicate the MECHANISM rather than re-request a
design. Nothing here claims D1 release; it only establishes that the shared
mechanism exists and is tested.

Scope note: this file lives under `docs/02-evidence/`, which is NOT part of the
G7b frozen scope (`Sources/`, `Tests/`, and `docs/00-governance/SIMIGO2_G3_*`).
Adding it therefore does not move `source_sha256`; the freeze stamped this round
(`979a9e35…`) stays valid and is re-verified at the end of this document.

---

## 1. The mechanism the reviewer asked to confirm (Option A: shared domain)

Reviewer's counter-example was this two-statement shape, where a concurrent
termination can land in the gap:

```
guard terminalAbortReason == nil else { throw .terminated }
// <-- window: a latch here is invisible to the check above
try commitDelivery()
```

The current implementation does NOT use that shape. The terminal read, the
decision, and the commit transition are ONE mutually-exclusive region of a
single `G3Adjudication` object.

### 1a. The domain object (`G3PerArmKVCache.swift` L347-371)

```
public final class G3Adjudication: @unchecked Sendable {
    public let domain: String
    let lock = NSRecursiveLock()
    public func adjudicate<R>(_ body: () throws -> R) rethrows -> R {
        lock.lock(); defer { lock.unlock() }; return try body()
    }
    @discardableResult
    public func tryAdjudicate<R>(_ body: () throws -> R) rethrows -> R? {
        guard lock.try() else { return nil }   // non-blocking probe used by tests
        defer { lock.unlock() }; return try body()
    }
}
```

The session, its ledger, the settlement gate, and the commit region all resolve
`lock` to THIS recursive lock (`private var lock: NSRecursiveLock { adjudication.lock }`
at L383, L571, L985). There is exactly one lock per arm, not three that happen to
be held together.

### 1b. `commitDelivery` — the linearization point (L762-807)

The whole body is wrapped in `adjudication.adjudicate { … }`:

```
return try adjudication.adjudicate {
    guard boundaryAdoptsAdjudication else { … return .refusedBoundaryNotAdjudicating }
    if let reason = terminalSnapshot().effectiveTerminationReason {   // terminal READ
        … ledger.markPostSettlementTermination(reason)
        … return .refusedTermination(reason: reason)
    }
    if boundary.isolationAborted { … return .refusedTermination(…) }  // native write-gate view
    if isCancelled() { … ledger.recordCancellation(.atCommitCutoff); return .refusedCancellation }
    try finalize()
    ledger.recordPhase(.commit, .succeeded("result_delivered"))       // COMMIT TRANSITION
    ledger.markCommitAdjudicatedUnder(adjudication.domain)
    return .committed
}
```

`terminalSnapshot()` (L658-668) reads `boundary.terminatedReason`, the session
tombstone `_abortReason`, and the settlement phase under the SAME lock. Because
the region is held from the terminal read through the commit transition, there
is no gap in which a latch can be missed.

### 1c. Termination is written by ENTERING the same domain (L724-742)

```
public func terminate(reason: String) {
    adjudication.adjudicate {
        if _abortReason == nil { _abortReason = reason }
        if let ledger = _runLedger, ledger.bindingConsumed {
            ledger.markPostSettlementTermination(reason)
        }
    }
}
func noteExternallyLatchedTermination(_ reason: String) {
    adjudication.adjudicate { … }   // gateway latch hops in through here
}
```

The gateway latch (`G3KVAllocationGateway.swift` L145-165) and the MLX boundary
latch (`G3PerArmKVCache.swift` experimental L222-226) both write only after
`adoptTerminationAdjudication` has registered the arm's domain, and every latch
runs `domain.adjudicate { … }`. Lock order is fixed domain → gateway/boundary
lock, never the reverse, so the domain cannot deadlock against a refusing write.

### 1d. Consequence: the two-case exhaustiveness the reviewer required

A termination either
- enters the domain BEFORE the commit region → the region's `terminalSnapshot()`
  sees it and refuses (`.refusedTermination`), or
- enters AFTER the commit region returns → the latch's own `adjudicate` block
  sees the recorded commit and files it via `markPostSettlementTermination`.

There is no third state, because there is only one lock. That is precisely what
`guard … ; commit()` could not promise.

### 1e. Fail-closed when a boundary refuses the domain

If a boundary does not adopt the domain (`boundaryAdoptsAdjudication == false`),
`commitDelivery` returns `.refusedBoundaryNotAdjudicating` and the executor
refuses the arm. The protocol default (`G3ArmCacheBoundary` extension, L78-80)
returns `false`, so a boundary that has not made the promise cannot silently
claim a linearization it does not have. This is the reviewer's Option-B guard
folded into Option A: an execution path that cannot join the shared domain is
denied the commit, rather than left with an unsynchronized pre-check.

### 1f. The PRODUCTION execution path reaches this region (not just test doubles)

The reviewer's sharpest point: "even if all tests pass, that does not rule out
the window." Passing tests only prove the test doubles behave. The production
route is therefore traced end-to-end, and it contains no
`guard terminal == nil; commit()` shape:

1. Composition root builds the session over the real MLX boundary:
   `G3ArmCacheSession(armID:boundary:)` — `G3PerArmKVCache.swift` (experimental)
   L379 / L391 / L415.
2. Session init mints ONE `G3Adjudication(domain: "arm:<id>")` and hands it to
   the boundary: `boundaryAdoptsAdjudication =
   boundary.adoptTerminationAdjudication(domain)` — contract L612-621.
3. The MLX boundary adopts INSIDE that domain and forwards it to the gateway:
   `domain.adjudicate { _terminationDomain = domain; gateway.adoptTerminationAdjudication(domain, …) }`
   and returns `true` — experimental L222-236.
4. The gateway registers the same domain and writes every latch inside it —
   `G3KVAllocationGateway.swift` L145-165.
5. The production commit calls the adjudicated region, NOT a pre-check:
   `let commit = try session.commitDelivery(isCancelled:…, finalize:{})`, then
   maps `.refusedBoundaryNotAdjudicating → throw`, `.refusedTermination → throw
   armTerminated`, `.refusedCancellation → throw CancellationError`,
   `.committed → proceed` — `MLXPrefixRecomputeExecutor.swift` L304-318. The
   comment there names the reviewer's exact counter-example as the thing it
   refuses to reintroduce.
6. A post-cutoff cancel is only reported (`recordCancellation(.afterCommitCutoff)`),
   never used to un-commit — executor L324-326.

So in the real run one `G3Adjudication` object serializes the gateway latch, the
session tombstone, the binding-violation latch and the commit transition. The
executor fail-closes if the boundary ever declines to join. This is confirmed
directly at runtime by `G3CancellationPointTests.realGatedRunCommitsUnderTheArmDomain`
(asserts `boundaryAdoptsAdjudication` and the ledger transition
`commit.adjudicated_under=arm:` on the real `runGatedGeneration` body), and the
racing variant `gatewayLatchRacingTheRealRunNeverBecomesCleanEvidence` (8 iters).

---

## 2. Clean-evidence protocol for a post-commit termination

Reviewer requirement: "if termination arrives after a successful commit, the
consumed binding must not be disguised as unconsumed; and whether the run still
counts as clean evidence must be stated by the protocol."

Both facts are kept, and the run is disqualified by rule, encoded in the derived
aggregate rather than left to the reader:

```
public var isFullyDelivered: Bool {          // G3PerArmKVCache.swift L316-319
    settleEntered && bindingConsumed && delivery.completed
        && postSettlementTermination == nil
}
```

`settled` in the runner record is set to exactly this (`G3DualArmRunner.swift`
L361); `bindingConsumed` stays true. So a late termination keeps the consume
fact but flips `settled`/`isFullyDelivered` to false with the reason carried.

### `settled` is a derived field, not a base fact

Reviewer requirement: forbid re-using `settled:false` as a proxy for the three
axes. It is not — it is computed from the three independent axes plus the late
termination flag, and the axes are stored and snapshotted separately
(`settleEntered`, `bindingConsumed`, `delivery`, `cancellation`,
`postSettlementTermination`). The old boolean is retained only for report
compatibility.

---

## 3. The four scenarios, mapped to tests that pass on current source

Suite: `G3CommitLinearizationTests` (9). Reproduce:

```
cd simigo2-experimental
swift test --scratch-path .build/out \
  --filter 'G3CommitLinearizationTests|G3SettlementAxesTests'
```

Recorded result this round: XCTest 20 tests, 0 failures
(G3CommitLinearizationTests 9/9 + G3SettlementAxesTests 11/11).

**Independent re-run 2026-10-21 (this session, mounted worktree, exit 0):**
`--filter 'G3CommitLinearizationTests|G3SettlementAxesTests|G3SettlementAxesReportTests'`
→ **24 tests, 0 failures** (linearization 9/9, settlement-axes report 4/4,
settlement-axes 11/11). This is a live re-run against the code that the frozen
manifest names, not a carried-forward number — it is the reproduction the
reviewer's unmounted session could not perform.

Production-path suite (`G3CancellationPointTests`, Swift Testing, real per-arm
MLX boundary + weightless model on CPU) re-run this round: 9/9 passed, 0 failed,
including `realGatedRunCommitsUnderTheArmDomain()` and
`gatewayLatchRacingTheRealRunNeverBecomesCleanEvidence()` — these are the tests
that exercise §1f's production reachability chain, not a test double.

| Reviewer scenario | Test | What it proves |
| --- | --- | --- |
| termination before commit | `testTerminationBeforeCommitRefusesAndPreservesReason` | region read refuses, reason preserved, consume not rolled back |
| commit before termination | `testTerminationAfterCommitKeepsTheCommittedFactAndIsFiledByTheLatchItself` | commit stands; the LATCH itself (no re-read/sampling) files the late termination; `isFullyDelivered` goes false |
| termination concurrent with commit | `testConcurrentTerminationAndCommitIsAlwaysClassified` (8 iterations) | every outcome is committed XOR refusedTermination, never unclassified; race_stop always visible |
| cancellation after the final check | `testCancellationAtTheCommitCutoffRefusesTheCommit` + `testCancellationObservedAfterTheCutoffDoesNotUndoTheDelivery` | cutoff IS the commit region; a later sample is an observation, not an un-commit |
| (extra) genuine mutual exclusion | `testDomainHeldByOneParticipantBlocksTheOther` | while one participant holds the domain, `tryAdjudicate` fails to enter — proves real exclusion, not favorable interleaving |
| (extra) settlement gate vs latch | `testSettlementGateAndLatchRaceIsAlwaysClassified` | the gate's terminal read → single-use → consume is the same domain |
| (extra) throwing consume | `testThrowingConsumeInsideTheDomainKeepsTheAxesDistinct` | entered ≠ consumed preserved through a throw |
| (extra) fail-closed boundary | `testNonAdoptingBoundaryRefusesTheCommitFailClosed` | `.refusedBoundaryNotAdjudicating` when no shared domain |

**Scenario-3 assertion strength (reviewer's "no unclassified result")**. The
current-source run of `testConcurrentTerminationAndCommitIsAlwaysClassified`
(240 iterations, both interleavings biased to occur) is a TOTAL assertion, not a
smoke test: every iteration's `outcome` passes through a `switch` whose `default`
branch is `XCTFail("unclassified commit outcome")`; the aggregate check
`committed + refused == 240` forbids any fall-through to `.refusedCancellation`
or the sentinel `.refusedBoundaryNotAdjudicating`; and a happens-before journal
asserts that whenever `latch:exit` precedes `commit:enter` the outcome MUST be
`.refusedTermination(reason: race_stop)`, while a `.committed` outcome may never
follow a completed prior latch. So the determinate-before/after relation the
reviewer required is asserted per iteration, and a lost termination is a hard
failure, not a tolerated race. Result on current source: 0 failures.

`AdjudicatingBoundary.latch` (test double, L76-90) writes inside
`domain.adjudicate { … }` and calls `report` still inside it, mirroring the
production gateway contract — so the tests exercise the same domain-entry rule
the real latch uses.

---

## 4. G3 five fault positions (reviewer §II) — distinguishable, tested

Suite: `G3SettlementAxesTests` (11). Each of the reviewer's five positions has
an assertion that keeps the axes independent:

| Fault position | Test | Preserved facts |
| --- | --- | --- |
| fail before the settlement gate | `testRefusedSettlementLeavesBothAxesFalse` | not entered, not consumed, delivery not completed |
| gate entered, consume not finished | `testThrowingConsumeRecordsEnteredWithoutConsumed` | `settleEntered=true`, `bindingConsumed=false`, `settlementPhase=bindingConsumeFailed` |
| consumed, registration fails | `testPostConsumeRegistrationFailureLeavesConsumedAndDeliveryFailed` | consume NOT rolled back; `registration=failed`, `commit=notEntered` |
| consumed, decode fails | `testPostConsumeDecodeFailureKeepsConsumedAndMarksDecodeFailed` | consume kept; `decode=failed`, `commit=notEntered` |
| delivery completes | `testConsumedIsIndependentOfDelivery` | consumed alone is not delivery; all four stages required for `isFullyDelivered` |

---

## 5. What this pack does NOT claim

- Not D1 release and not Phase-2 acceptance. **Update (Revision 5, 2026-10-21):**
  Phase 1 subsequently closed the mechanism-level gaps this pack once listed as
  open — G6 (dual worker + supervisor, distinct PIDs, reclaim), G7a (one-shot
  marker, replay refusal, fail-closed), G8a at the entry (the bound worker's
  `.g3` run refuses at `provider_trust` before generate/consume), and G7b
  execution identity is now `bound` for a real `G3D1Worker` (no longer
  `control-only` / `unclosed`). See `docs/00-governance/SIMIGO2_G3_D1_ENTRY_BOUNDARY_DECISION_V0.1_20261021.md` §10.
- What is still genuinely open: the G8a **cleared-gate** path (non-empty trusted
  registry) and a **real-model** ES → IS → new-ES continuation (Phase 2), which
  is what actually answers the research question. Neither is authorized by this
  pack; D1 remains NO-GO.
- Not independent re-run by the reviewer: the counts above are recorded from
  runs in this worktree; the reviewer's session cannot mount it, which is why
  this document quotes the source directly.
- Not "real model executed": every test here is model-free (weightless stand-in
  models / CPU device), consistent with "broad model-free verification," not
  model acceptance.

## 6. Freeze consistency at this round

`source_sha256 = 2b027bb8…`, `runner_sha256 = 2c7af27b…`, 204 in-scope files,
execution identity `bound` (real G3D1Worker, self-hash `1f9baa57…`, launch match
true). NOTE on the digest: this pack recorded `979a9e35…` / 195 files, then
`9a75d08c…` / 204 files after Revision-5 §10. Two later in-scope governance edits
each moved `source_sha256` again — recording the reviewer's adjudication as §11
(`131cb448…`) and then locking the final口径 as §12 (`2b027bb8…`) — and the chain
was re-converged after each (stamp → real-worker `--launch` → re-stamp → verify,
all exit 0). The G5 mechanism itself is unchanged by that churn — the executor,
ledger, session and settlement source quoted in §1–§4 were NOT edited; only the
digests and the governance prose moved. This evidence pack lives under
`docs/02-evidence/` (out of the G7b scope), so adding/editing it here never
changes `source_sha256`. NOTE on the bound
launch: the worker's `exit_code=12` is the EXPECTED fail-closed branch — an
identity-only `--launch` supplies no run ID, so `G3D1WorkerCore.swift:59-60`
returns `.runError` before dispatch. The `bound` facts are identity-verified +
marker-consumed + running-hash match; no model ran and no binding was consumed.
The exit-0 gate-refused evidence comes from the supervisor path, which does set a
run ID and reaches the constrained entry (`provider_trust` refusal).

## 7. Full-suite total against the frozen tree (reviewer §IV reconciliation)

One complete `swift test --scratch-path .build/out` on the current tree (exit 0,
no failures) — recorded so the reviewer's §IV provisional counts can be
reconciled to the exact code that was stamped:

| Bundle | Count | This round | Reviewer table said |
| --- | --- | --- | --- |
| `SimiGoRuntimeContractTests.xctest` | 130 | 0 failures | 120 (pre-this-round) |
| `SimiGo2ExperimentalTests.xctest` | 383 (5 skipped) | 0 failures | 383 (5 authorized skips) |
| `G3D1SupervisorTests.xctest` | 12 (2 skipped) | 0 failures | (Phase-1 G6/G7a harness) |
| Swift Testing | 75 tests / 11 suites | passed | 71 / 11 (pre-this-round) |

Bundle-level figures read directly from this round's single integrated
`swift test` run (exit 0): `Executed 130 tests, with 0 failures` for
RuntimeContract, `Executed 383 tests, with 5 tests skipped and 0 failures` for
Experimental, `Executed 12 tests, with 2 tests skipped and 0 failures` for
G3D1SupervisorTests, and `Test run with 75 tests in 11 suites passed` for Swift
Testing. The +10 RuntimeContract and +4 swift-testing deltas are the tests added while
answering this review (settlement-axis decode-failure case, the commit-
linearization suite, the production-path cancellation cases). They support
"broad model-free verification," not "D1 real-model execution accepted." The 5
Experimental skips remain the pre-existing authorization-gated runs, still not
executed here. Re-verify of the frozen manifest after adding this out-of-scope
pack: `ROUNDTRIP PASS 204/204 files=204`, `VERIFY PASS 2c7af27b…`
(`source_sha256 = 2b027bb8…`), `BOUNDARY PASS`, and `EXECUTION BINDING bound`
(`marker_consumed=True`, `launch_match=True`), all exit 0. The earlier figures —
`195/195 / 7502b39f…`, `204/204 / c43a32a6…`, and `204/204 / 04eaa85b…`
(`source 9a75d08c` then `131cb448`) — were the pre-§10, post-§10 and post-§11
manifests, each superseded as the in-scope governance prose grew (§11 adjudication,
§12 locked口径) and the chain re-converged. NOTE: the default full-suite run above
is 12 supervisor tests with 2 skipped; the subprocess-enabled run is a SEPARATE
12/12 and is not merged into this table's single-run figures.

## 8. Exhaustiveness audit — no reachable entry mutates shared state outside the domain

The reviewer's method-A burden is not just "the good path is synchronized" but
"prove other reachable entries cannot change termination state during commit
contention." A source sweep of every termination/commit write site answers it:

**One lock, three owners.** `G3RunLedger.lock`, `G3ArmCacheSession.lock` and
`G3RunSettlement.lock` are all literally `adjudication.lock` (contract L383 /
L571 / L985) — `private var lock: NSRecursiveLock { adjudication.lock }`. The
ledger holds NO second lock, so a ledger write cannot slip beside a commit.

**Every termination write is domain-guarded** (contract `G3PerArmKVCache.swift`):

| Site | Guard |
| --- | --- |
| `terminate` L726, `noteExternallyLatchedTermination` L739 | `adjudication.adjudicate { }` |
| commit-region writes L774/785/792 | inside `commitDelivery`'s `adjudicate { }` |
| `concurrent_runStep` L839 | session `lock` (= domain) |
| `settle` entered/consume/post L1055-1068 | `adjudicate { }` (L1045) |
| ledger `markPostSettlementTermination` L505, `recordCancellation` L465, `markSettleEntered` L482, `markBindingConsumed` L491, `markBindingConsumeFailed` L498, `markSettlementRefused` L473 | ledger `lock` (= domain) |
| gateway `latchTerminationLocked` L174, refuse-write latch L340-347 | `domain.adjudicate { }` when registered (domain→gateway order); pre-adoption latches are reported into the ledger at `adoptTerminationAdjudication` (experimental L231-233), so none is lost |
| MLX `latchBindingViolation` L277-290 | domain when installed, else boundary lock + reported on adoption |

**Single commit-success writer.** `grep` over all production `Sources/` finds
exactly one `.commit.succeeded` write: L803, inside the `commitDelivery` domain
region (the only other textual hit, executor L302, is a comment). There is no
backup or fallback path that can record a delivery as committed outside the
region.

**No guard-then-separate-commit shape.** `terminalAbortReason` — the exact symbol
in the reviewer's pseudo-code — is read in the production commit path only via
`terminalSnapshot()` INSIDE the domain region. Its other two uses
(`G3DualArmTerminations.terminations` L938-939) are a reporting accessor that
feeds the runner's pre-dispatch refusal map; they read under the same lock and do
NOT precede a separate commit. The forbidden `guard terminal == nil; commit()`
two-statement sequence does not exist in any reachable production path.

Conclusion for method A: settlement entry, binding consumption, every
termination latch, and the single commit transition all serialize on ONE
`G3Adjudication`, and no reachable writer bypasses it. That is the
source-structure guarantee the reviewer required — independent of how many tests
pass.
