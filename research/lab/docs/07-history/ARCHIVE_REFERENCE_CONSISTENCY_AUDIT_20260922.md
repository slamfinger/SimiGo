# Archive Reference Consistency Audit — 2026-09-22

**Repository:** `slamfinger/SimiGo-Lab`  
**Branch:** `refactor/research-archive-20260922`

## 1. Purpose

Audit the archive refactor for stale entry-point state, incorrect layer references,
and accidental promotion of historical results into current research state.

This is an archive/provenance audit only. It does not register STEP ④, define an
estimand, reopen a closed line, authorize implementation, or authorize measurement.

## 2. Scope

Checked the current branch's primary entry points and newly created archive-layer
records, including:

- root `README.md`;
- `docs/ARCHIVE_INDEX.md`;
- `docs/AGENT_CONTEXT.md`;
- `docs/07-history/LEGACY_ASSET_MAPPING_20260922.md`;
- `docs/07-history/PROVENANCE_CHAIN_AUDIT_20260922.md`;
- `docs/07-history/ARCHIVE_CROSS_LAYER_INTEGRITY_20260922.md`;
- Track B findings, decisions, and architecture mapping;
- Track B and Track E work-space READMEs;
- exp06 and runtime2-skeleton entry points.

The GitHub code-search index did not return branch-scoped matches for this
feature branch, so this pass treats the explicit branch-local entry points and
archive records above as the authoritative audit surface rather than claiming a
literal every-file text scan.

## 3. Findings

### R-01 — Root README state drift

**Found:** root `README.md` still presented historical Track B/Track E work as if
it were the active laboratory state and did not clearly expose the current
Definition / Opening gate.

**Disposition:** FIXED.

The README now states:

- Definition / Opening;
- STEP ③ PASS;
- STEP ④ estimand NOT STARTED;
- RQ ID not assigned;
- implementation/harness construction forbidden;
- data collection/performance measurement forbidden;
- historical/forward workspaces retain their provenance and do not imply
  authorization.

**Git anchor:** `f2576927814b5d50bd136559b7a465972b4da02a`.

### R-02 — Archive layer/state separation

**Result:** PASS for the audited archive records.

The new Findings/Decisions/Architecture records explicitly identify themselves as
provenance bridges and do not claim to replace the frozen closure or
`RESEARCH_STATE.md`.

### R-03 — Historical result promotion

**Result:** no promotion identified in the audited records.

Track B findings retain tested scope and explicit exclusions. Simulation,
accounting, and live measurements remain distinguished. Track E's historical
effect/accounting material is not relabeled as current runtime evidence.

### R-04 — Prediction/result conflation

**Result:** no conflation identified in the audited records.

The provenance and cross-layer audits explicitly preserve the rule:
prediction ≠ evidence/result.

### R-05 — STEP ③ / STEP ④ boundary

**Result:** PASS.

The audited records consistently state that STEP ③ PASS does not complete STEP ④,
does not assign an RQ ID, and does not authorize measurement or implementation.
STEP ④ estimand remains NOT STARTED.

### R-06 — Closed/frozen research-line reopening

**Result:** PASS.

Track B remains CLOSED / FROZEN. Track E closure is treated as a historical
terminal record. Archive mappings do not reopen either line.

### R-07 — Historical paths

**Result:** PASS.

Original `track-*`, `exp-*`, and `runtime2-skeleton/` paths remain intact.
The archive refactor uses index/mapping overlays rather than destructive moves.

## 4. Residual caution

The branch-local GitHub code-search service did not provide usable results for
the audit branch. Therefore this record is **not** a claim that every text file
in the repository has been exhaustively searched for stale terminology.

A future exhaustive text scan should be performed when branch-aware repository
search is available or through a checked-out repository copy. It should focus on
old current-state wording, especially historical Track E progress labels and
unqualified references to exp06 as an executable next step.

## 5. Gate effect

**NONE.**

This audit:

- does not modify `RESEARCH_STATE.md`;
- does not define an estimand;
- does not create an RQ;
- does not authorize implementation;
- does not authorize measurement;
- does not reopen Track B or Track E.

## 6. Conclusion

One concrete entry-point inconsistency was corrected. The audited archive records
now preserve the intended distinction:

```
current state      → RESEARCH_STATE
completed research → Closure / Endpoint
historical evidence → Evidence / History
bounded synthesis  → Findings
registered choices → Decisions
architecture effect → Architecture
future ideas       → Research Memory
```

No further archive-layer changes are justified solely for structural completeness.
