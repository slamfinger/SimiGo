# C12 — Folder Information Initialization

## Research State Capsule

```text
Research Object          = Folder Information Initialization real run
Status                   = IMPLEMENTED / TESTED / REAL-RUN EXECUTED / BOUNDED OBSERVATION
Result commit            = 616fe77
Last verified            = 2026-10-06 @ 14de9fd
Capsule lineage          = existing InformationCore/SQLiteStore → first real folder initialization
```

## Research Question

Can existing `InformationCore + SQLiteStore` turn a real physical folder’s
currently observable logical information into a persistent Information Space
initial state?

## What was established

```text
Test folder contained 5 files / 2 directories.
5 Information values were formed and stored.
5 extraction operations succeeded; 2 skipped; 0 failed.
SQLite information rows = 5.

TXT / Markdown content roundtrip = PASS.
Source-path roundtrip = PASS.
Binary and empty files were honestly skipped.
Repeated initialization remained idempotent and did not overwrite.
```

This showed that a real folder can become a persistent Information Space initial
state using existing `InformationCore + SQLiteStore`.

## Evidence

```text
docs/00-governance/SIMIGO_LAB_FOLDER_INFORMATION_INITIALIZATION_RESULT_20261004.md
docs/02-evidence/folder-information-initialization-20261004/
```

## Bounding

The run implemented only folder initialization. It did not copy physical files,
add relations, IDs, watchers, history, diff engines, search, embeddings,
summaries, or knowledge graph.

## What it does NOT prove

```text
That arbitrary binary/document formats can form Information.
That empty-text Information is representable.
That InformationStore should have list/query APIs.
That directory Information is a content payload.
That the system is a complete Information Space.
```

## Dependencies

- InformationCore immutable Information semantics.
- InformationStore store/fetch contract.
- SQLiteStore first-write-wins persistence.

## Constraints

```text
No Relation semantics added.
No file/folder/version IDs added.
No change watchers or history/diff engines.
No search, embeddings, summaries, or knowledge graph.
No Core semantics or SQLite persistence rules modified.
No Execution State Contract, IPAC, or PALACE modified.
```

## Current unresolved seam

Open gaps recorded, not fixed:

```text
empty-text Information cannot be represented;
no list/query API;
unsupported binary/document formats cannot form Information;
directory Information is only an inventory observation.
```

## Next legal transition

Any fix or extension requires a separate Human authorization and semantic finding.

## Source documents / commit

| Claim | Source | Commit |
|---|---|---|
| Real folder initialization result | Folder Initialization Result | 616fe77 |
| 5 formed / 5 stored / idempotent | Result §Real run / §Verification | 616fe77 |
| Unsupported/empty honestly skipped | Result §Verification | 616fe77 |
