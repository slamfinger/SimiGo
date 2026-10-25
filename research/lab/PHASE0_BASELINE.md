# Phase 0 Baseline — Research Recovery Layer v0.1

Date: 2026-10-06

## Baseline

```text
BASE_COMMIT       = 27bc8053e34117497f4979995f7f7ad70a180a65
BASE_BRANCH       = integration/path-a-information-place
WORKTREE_STATE    = clean before implementation branch
IMPLEMENTATION    = codex/research-recovery-layer-v0.1
TASK_INPUT        = Research Recovery Layer Enhancement Plan v0.1
```

The requested input was described as `main`, but the working tree was already on
the active Path A integration branch. This branch is retained so recovery work
does not overwrite or bypass the current integration state. The default `main`
position is recorded but not treated as semantic authority.

## Current recovery entries

```text
L0 = docs/RESEARCH_CONTEXT_INDEX.md
L1 = docs/research-capsules/v1/C01..C15
L2 = authoritative governance, contracts, decisions, and rulings
L3 = raw evidence under docs/02-evidence and experiment directories
Current State = docs/RESEARCH_STATE.md
Archive Index = docs/ARCHIVE_INDEX.md
Session Entry = docs/NEXT_SESSION_ENTRY.md
```

## L0-L4 correction

The formal Information Place model at baseline is:

```text
L0 Context Index
L1 Research State Capsules
L2 Authoritative Source Documents
L3 Raw Evidence
```

There is no recovery-layer `L4` in `docs/RESEARCH_CONTEXT_INDEX.md`, the capsule
index set, or the baseline model. Existing `L4` hits are unrelated domains:
runtime residency verification stages (`L4-A/B/C`), cancellation-test levels,
or task dependency levels. Therefore the corrected status is:

```text
Status = B / formal L0-L3; recovery-layer L4 never adopted
Action = do not invent L4
```

## Phase 0 scope

The first implementation slice is read-only census plus recovery navigation
files. It must not move archives, rewrite historical conclusions, change frozen
contracts, reopen Information/MemPalace experiments, or introduce an external
database.
