# Restore Atomicity Coordinator Line — Final Memory

- Date: 2026-10-13
- State: FINAL HANDOFF READY
- Overall Restore Atomicity closure: NOT CLOSED by deliberate evidence-preserving decision.

## Final Verification Snapshot

- Before this final write, the checked-out repository had no `memory/` directory, no
  `memory/restore-atomicity-coordinator-line.md`, and no root `MEMORY.md`.
- The handoff branches and key commits were verified locally before restoring this record.
- The main checkout was clean at `f77c1587`; this memory restoration is the only intentional
  new change in the main worktree.
- A separate worktree exists at
  `/Users/mr.simi/.codex/worktrees/execution-restore-atomicity/materialization-hardening`
  on `codex/materialization-singleflight-test-hardening` with a dirty
  `MaterializationCoordinatorTests.swift`. It is not part of the two handoff branches and must
  not be treated as removable residue without independent human review.

## Research Chain

1. **DCC-0 — Design package**
   - Defined the durable crash-consistency design and implementation boundary.
   - Established the recovery architecture later carried through DCC-1 and DCC-2.

2. **DCC-1 — Durable session baseline and cold-start recovery**
   - Bound the baseline to weight content and made commit-stage semantics total.
   - Implemented durable session baseline and cold-start recovery.
   - Passed its 24 contract-adaptation checks.
   - Final status: ACCEPTED / FROZEN.

3. **DCC-2 — Protocol contract and implementation**
   - `4cf7f1d6` froze the final protocol and load-atomicity contract.
   - `97e2c1f4` implemented SCP v2 durable restore intents and load-failure atomicity.
   - Passed the dedicated 18/18 suite.
   - Final status: ACCEPTED / FROZEN.

4. **DCC-2b — Not initiated**
   - No follow-on proposal was approved.
   - Final status: NOT INITIATED by decision, not by omission.

5. **DCC-3 — Platform semantics review and archive**
   - `7c7e7a47` archived the platform-semantics review and boundary qualifications.
   - Human ruling: ACCEPTED / ARCHIVED.

6. **Materialization startup-window repair**
   - `af44199f` acquired the physical-use lease before single-flight publication.
   - This closes the startup race identified for the materialization path.
   - Human ruling: ACCEPTED / CLOSED as a local engineering task.
   - Task-level conclusion: the startup-lease race repair is complete and the specified
     stability tests passed.
   - Evidence basis is the supplied implementation and verification record; the ruling was not
     represented as an independent checkout or test rerun in the current environment.
   - This ruling does not certify overall Materialization-system concurrency correctness and is
     not an ES-IS research conclusion.

7. **Materialization delete—lease admission race repair**
   - `51c5d475ee1292d6560fab7798b0b5e43afcf1bb` (`51c5d475`) follows `af44199f` as an
     independent fix, not a reopening of the startup-window task or frozen DCC work.
   - It closes the separate window between a delete decision and new lease admission.
   - Current status: local implementation and regression complete, PENDING INDEPENDENT
     ACCEPTANCE.
   - Reported tests are based on the implementation record and are not an independent rerun by
     the recording agent.
   - Acceptance review must inspect all `acquire` call sites, `pendingDeletes`/`deleting`
     transitions, duplicate-delete handoff, and path-generation reuse semantics.
   - This does not justify a general “concurrency safety solved” conclusion.

## Branch and Commit State

- `codex/restore-recovery-coverage`
  - `4cf7f1d6` — DCC-2 protocol contract.
  - `97e2c1f4` — DCC-2 implementation, accepted and frozen.
  - `7c7e7a47` — DCC-3 platform-semantics archive, accepted.
- `codex/materialization-lease-startup-fix`
  - `af44199f` — materialization startup-window repair, accepted and closed locally.
- `codex/materialization-delete-acquire-race`
  - `51c5d475ee1292d6560fab7798b0b5e43afcf1bb` (`51c5d475`) — materialization delete/lease
    admission race repair, pending acceptance; parent is `af44199f`.
- These are local commits only. Pushing or merging either line requires separate authorization.

## Acceptance Freeze

| Object | Status |
| --- | --- |
| DCC-1 | ACCEPTED / FROZEN |
| DCC-2 | ACCEPTED / FROZEN |
| DCC-2b | NOT INITIATED |
| DCC-3 | ACCEPTED / ARCHIVED |
| Materialization startup repair | ACCEPTED / CLOSED (LOCAL ENGINEERING TASK) |
| Materialization delete/lease admission repair | PENDING INDEPENDENT ACCEPTANCE |

## Permanent Capability Boundary

- Process crash: TESTED, limited to covered paths.
- Kernel or system crash: constrained by protocol, but not directly verified.
- Power loss: NOT VERIFIED.
- Media failure: NOT VERIFIED.
- Rename atomic visibility is conditioned on payload being complete, verifiable, and accessible.
- `F_FULLFSYNC` is the strongest Darwin in-process primitive; hardware compliance cannot be
  proven from inside the process.
- No model may upgrade these dimensions to TESTED without an independent authorized project.
- No model may uniformly mark Restore Atomicity CLOSED, TESTED, or PROVEN beyond this record.

## Regression Baseline

- Full suite: 282 passed / 3 skipped / 0 failed.
- Directed regression: 20/20.
- Materialization repair stability check: three consecutive full clean runs at 282 passed /
  3 skipped / 0 failed.
- Materialization delete/lease admission repair, as reported: directed suite 9/9; three
  consecutive full XCTest runs at 285 passed / 3 skipped / 0 failed; three new deterministic
  interleave tests.
- Reported full-run logs: `/tmp/delete-race-full-1.log`, `/tmp/delete-race-full-2.log`, and
  `/tmp/delete-race-full-3.log`.
- DCC-2 suite: 18/18.
- DCC-1 contract adaptation: all 24 checks passed.
- The ActualMLX PID timing transient remains a registered stable observation, not a repaired or
  accepted defect in this line.
- Complete run logs retained at `/tmp/matfix-full-log-*.txt` and
  `/tmp/dcc2-impl-full-log-*.txt` at final verification time.

## Next-Agent Entry Points

1. Treat `af44199f` as the accepted baseline for the materialization startup repair.
2. Independently review `51c5d475` against `af44199f` before accepting it.
3. Do not reopen frozen DCC work as part of follow-on changes.
4. Separately decide whether to push or merge either handoff branch.
5. Treat any newly discovered concurrency gap as a separate project only when supported by a
   concrete code path and reproducible evidence.

## Continuity Rule

- This file is the coordinator-line memory anchor.
- Read it together with root `MEMORY.md`.
- Preserve branch provenance, commit boundaries, test baselines, and qualification language when
  continuing work.
- Do not extend the closed startup-lease task to certify system-wide concurrency correctness.
- Do not merge the startup-window and delete/lease-admission race conclusions into one broad
  concurrency-correctness claim.
