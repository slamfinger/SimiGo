# Phase B Experiment Results

Date: 2026-10-05
Status: `RUN_COMPLETE · AWAITING_HUMAN_REVIEW`
Run root: `a_e_execution/../phase_b/run/runs/20261005-120000-phase-b`
Design: `phase_b/experiment_design/EXPERIMENT_DESIGN.md` (frozen at `973da1d`)

---

## Observed matrix

| Condition | C transition_status | C dep_declared | N transition_status | N dep_declared | Replicated? |
|---|---|---|---|---|---|
| F-PRESENT | COMPLETED | true | DEGRADED | false | divergent (L-status) |
| F-ABSENT | **BLOCKED** | **true** | **BLOCKED** | **true** | ✅ replicated |
| F-STALE | COMPLETED | true | COMPLETED | false | same status, divergent self-report |
| F-CONFLICTING | COMPLETED | true | **BLOCKED** | **true** | ❌ divergent |
| F-IRRELEVANT | **COMPLETED** | true | DEGRADED | false | ✅ no block in either |

---

## Criterion-by-criterion H3 assessment

### Criterion 1: F condition changes transition eligibility

**Supported for F-ABSENT.** Both models block when F is absent, and complete when F is present. The F condition (present vs absent) changes the transition from executable to non-executable.

**Not supported for F-STALE.** Neither model blocks; both deploy (incorrectly including gamma) and self-report the transition as COMPLETED. Information condition changed output quality but not transition eligibility.

**Divergent for F-CONFLICTING.** C completes (resolves conflict by applying the stricter negative constraint); N blocks. C/N do not agree.

### Criterion 2: blocked/completed difference is reproducible

**Supported for F-ABSENT.** Both C and N produce BLOCKED.

### Criterion 3: transition eligibility is explicitly dependent on F

**Supported for F-ABSENT.** Both models declare the dependency with specific reasons:
- C: "No baseline compatibility record available to validate sequential deployment"
- N: "No baseline compatibility record is available in this context, making it impossible to verify compatibility rules 1 and 2"

### Criterion 4: C/N replicate

**Supported for F-ABSENT.** Both models produce the same transition status and declare the dependency.

### Criterion 5: F-IRRELEVANT does not produce equivalent block

**Passed.** C completes normally. N completes the deployment decision (marks as DEGRADED but does not block). Neither model blocks because irrelevant information is present.

---

## Primary finding

```text
F-ABSENT → BLOCKED + dependency_declared = true
Replicated on C and N
F-IRRELEVANT control passed
```

This is **H3 candidate evidence** for the specific transition tested.

## Secondary findings

### F-STALE does not support H3

Neither model blocks on stale information. Both deploy using the outdated compatibility record (including gamma, which should be blocked). Both self-report `compatibility_info_current = true` despite the prompt stating the record is dated 2026-09-01.

This means: **stale Information degrades output correctness but does not block transition eligibility in the tested frame.** This is more consistent with H2 (attached state / quality) than H3 (constitutive condition) for this specific Information dimension.

### F-CONFLICTING diverges across models

C resolves the conflict by applying the stricter constraint (blocks gamma, deploys alpha/beta, marks COMPLETED with dependency_declared = true).
N cannot resolve the conflict and blocks the transition.

This divergence means F-CONFLICTING does not produce a replicated H3 pattern in this run. The two models process the semantic inconsistency differently.

### F-PRESENT anomaly in N

N marks the F-PRESENT baseline as `DEGRADED` despite producing the correct deployment decision. This appears to be N's interpretation of the `transition_status` field rather than a behavioral difference. C marks the same cell as COMPLETED.

### F-IRRELEVANT implementation note

The initial F-IRRELEVANT prompt incorrectly stated "No baseline compatibility record is available," making it equivalent to F-ABSENT. This was corrected to include F present plus an unrelated information object before C was run. N's F-IRRELEVANT cell was re-run with the corrected prompt. The flawed N F-IRRELEVANT v1 output is archived at `F_IRRELEVANT_v1_flawed/`.

---

## Claim boundary

Per the human review instruction:

> Even if F-ABSENT → BLOCKED + dependency_declared is observed, the maximum claim is:
> **Evidence supports that this Execution State transition is Information-conditioned.**

NOT claimable from this run:
- Information is constitutive of Execution State in general
- The two-layer model extends to Information conditions
- Mechanistic proof of Information-state dependency

---

## Updated status

| Hypothesis | Status after this run |
|---|---|
| H1 (Information = external input) | **WEAKENED** (F-ABSENT blocks in both models; Information is not merely optional input) |
| H2 (Information = attached state) | **PARTIALLY SUPPORTED** for F-STALE (quality degraded but transition completed) |
| H3 (Information = constitutive condition) | **CANDIDATE EVIDENCE** for F-ABSENT (replicated, controls passed); **NOT SUPPORTED** for F-STALE; **DIVERGENT** for F-CONFLICTING |

The overall picture is: **the absence of required Information blocks the transition; staleness does not; conflict is model-dependent.**

This suggests that different Information validity dimensions may have different relationships to Execution State executability. The "absence" dimension is the strongest H3 candidate. The "staleness" dimension is more H2-like. The "conflict" dimension is unresolved.
