# Path A Controlled Integration Plan

Date: 2026-10-06  
Status: `PATH A ACCEPTED · CONTROLLED INTEGRATION PLAN DELIVERED · MERGE EXECUTION AWAITING HUMAN APPROVAL`  
Human selection: `PATH A — default entry becomes Lab Information Place current entry`  
Rejected / retained alternatives: `PATH B control · PATH C parked · PATH D not needed`  
Frozen Contracts: `UNCHANGED`  
Scope guard: `INTEGRATION PLANNING ONLY · NO MERGE EXECUTION · NO SEMANTIC REWRITE · NO MEMPALACE MUTATION · NO PROBE EXECUTION · NO EXPERIMENT · NO CONTRACT CHANGE`

## 1. Objective

Make the default Lab entry surface carry the current Information Place:

```text
Fresh Agent
  ↓ default repository entry
main
  ↓ docs/RESEARCH_CONTEXT_INDEX.md
L0 Context Index
  ↓ docs/research-capsules/v1/C01..C15
L1 Research State Capsules
  ↓ current route / guards / evidence pointers
lawful continuation
```

This is not a simple branch overwrite. It is a controlled integration of a
diverged research line into the default entry.

## 2. Integration inputs

```text
TARGET BASE        = origin/main @6c3cf6a
SOURCE TIP         = codex/execution-state-research-20260929 @3f467d3
MERGE BASE         = dd61b495
DIVERGENCE         = origin/main has 2 commits not on research;
                     research has 327 commits not on origin/main.
CAPSULE BATCH BASE = 14de9fd
```

Local `main` currently points to `dd61b495` and is behind `origin/main`; it must
not be used as the integration target.

## 3. Machine probe result

`git merge-tree --write-tree origin/main codex/...`

```text
Result                 = CLEAN
Proposed merged tree   = bac63b9d415e02bf9280311504c39479e8356d82
Conflicts              = NONE
```

Protected semantic documents:

```text
I-1   Persistence / Resolve
      blob unchanged:
      48c00abde2be019d3557fda7ab488f121d509680

I-1c  Instantiate Completeness
      blob unchanged:
      2f4b18c72fb27af1408656bb63c07beda97519dd

I-1d  Runtime Realization / Verification
      introduced by research branch:
      22284bba048e0b93fd825c4fa718cf93b5b55154
```

No Frozen Contract blob is rewritten by the proposed merge tree.

## 4. Required integration form

Use a merge commit with both parents:

```text
parent 1 = origin/main @6c3cf6a
parent 2 = research branch tip @3f467d3 or later authorized research tip
```

Do not use a fast-forward, squash, rebase-overwrite, or force-reset. The diverged
ancestries must remain inspectable.

## 5. Execution sequence

### Phase A — preflight

```text
1. Re-run merge-tree and require CLEAN.
2. Assert target base = origin/main @6c3cf6a.
3. Assert source tip = current authorized research tip.
4. Assert working tree clean.
5. Record protected blobs listed above.
```

### Phase B — controlled merge

```text
1. Create integration branch from origin/main.
2. Merge research tip with --no-ff.
3. If any conflict appears, stop and return to Human.
4. Do not hand-resolve Frozen Contract conflicts; such a conflict is a stop
   condition, not an implementation opportunity.
```

### Phase C — post-merge assertions

```text
A1  docs/RESEARCH_CONTEXT_INDEX.md exists.
A2  docs/research-capsules/v1/C01..C15 exist; capsule count = 15.
A3  I-1 and I-1c blobs remain exactly:
    48c00abde2be019d3557fda7ab488f121d509680
    2f4b18c72fb27af1408656bb63c07beda97519dd
A4  I-1d remains exactly:
    22284bba048e0b93fd825c4fa718cf93b5b55154
A5  No semantic authority file is rewritten relative to its accepted authority.
A6  L0 states:
    Repository HEAD = current integration commit, verified dynamically.
    L0 indexing baseline = 14de9fd.
    Capsule batch base = 14de9fd.
    Semantic authority ≠ repository HEAD.
A7  RESEARCH_CONTEXT_INDEX declares default main as the current entry surface.
A8  RESEARCH_STATE.md retains route, PRQ, A4, and Core Sufficiency boundaries.
A9  Working tree clean.
```

### Phase D — publication and retest

```text
1. Push integration branch and fast-forward main only after assertions pass.
2. Rerun fresh-Agent recovery from the default entry.
3. Required result:
   Agent discovers L0.
   Agent reads the relevant L1.
   Agent reconstructs the current PALACE / Information Space route state.
   Agent identifies the legal next transition.
4. Record PASS / FAIL with raw transcript and hashes.
```

## 6. Failure handling

Stop without rewriting semantics if:

```text
merge-tree becomes conflicted;
any protected Frozen Contract blob changes;
L0/L1 files are absent after merge;
capsule count is not 15;
fresh-Agent rerun again recovers a stale default surface;
validation would require semantic repair or hidden completion.
```

## 7. Non-claims

This plan does not claim that:

```text
main has historically been the research authority;
the merge validates Information Space semantics;
a carrier or backend is selected;
MemPalace is approved;
implementation or experiment is authorized;
repository HEAD becomes semantic authority.
```

## 8. Next authorization

Executing this plan requires explicit Human approval for:

```text
controlled merge execution,
default-main update,
post-merge push,
fresh-Agent rerun.
```
