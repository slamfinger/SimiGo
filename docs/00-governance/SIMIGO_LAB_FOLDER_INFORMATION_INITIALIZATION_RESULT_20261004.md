# Folder Information Initialization Result

Date: 2026-10-04  
Status: `IMPLEMENTED / TESTED / REAL-RUN EXECUTED / BOUNDED OBSERVATION`  
Question: Can existing `InformationCore + SQLiteStore` turn a real physical
folder’s currently observable logical information into a persistent
Information Space initial state?

## Scope

This experiment only implements folder initialization. It does **not**:

```text
copy physical files;
add relations;
add file/folder/version IDs;
add change watchers;
add history or diff engines;
add search, embeddings, summaries, or knowledge graph;
modify InformationCore semantics or SQLiteStore persistence rules;
modify Execution State Contract, IPAC, or PALACE.
```

## Existing semantics preserved

```text
Information remains immutable.
InformationID remains mechanism-side and opaque.
InformationStore remains store/fetch only.
SQLiteStore remains first-write-wins / idempotent.
Source paths locate physical objects; payloads are not copied into a
  separate file store.
No Relation semantics are added.
```

## Implementation

The minimal runnable entry is in `t4ctl`:

```sh
t4ctl initialize <folder-path> [database-path]
```

It recursively observes regular files and directories, forms Information for:

```text
1. directory inventory snapshots;
2. TXT / Markdown / Markdown-alias text content.
```

It does not fabricate Information for unsupported, empty, or unreadable files.

## Real run

Test folder:

```text
test-folder/
├── a.txt
├── b.md
├── binary.bin
├── empty.txt
└── sub/
    └── c.txt
```

Report:

```text
directories scanned        = 2
files scanned              = 5
Information formed         = 5
Information stored         = 5
extraction succeeded       = 5
extraction skipped         = 2
extraction failed          = 0
SQLite information rows    = 5
```

Stored records:

```text
1. root directory inventory
   identity = 56c44a87db3ec4864e6bbcc1
   source   = /tmp/information-space-init/test-folder
   mode     = directory-inventory

2. a.txt
   identity = fba1f7ce9a9703c1beccc517
   source   = /tmp/information-space-init/test-folder/a.txt
   mode     = verbatim-text

3. b.md
   identity = 6c1dfe82fe39204edb814ca5
   source   = /tmp/information-space-init/test-folder/b.md
   mode     = verbatim-text

4. sub directory inventory
   identity = ca483b4bc6e2b858b706e290
   source   = /tmp/information-space-init/test-folder/sub
   mode     = directory-inventory

5. sub/c.txt
   identity = 4a476f7f4ed0b10cacba82b0
   source   = /tmp/information-space-init/test-folder/sub/c.txt
   mode     = verbatim-text
```

## Verification

```text
TXT / Markdown content roundtrip:
  a.txt  = PASS
  b.md   = PASS
  sub/c.txt = PASS

source roundtrip:
  all five source paths resolve to existing physical objects = PASS

unsupported file:
  binary.bin skipped as unsupported or non-text = PASS

empty file:
  empty.txt skipped because current SQLiteStore decode requires nonempty
  content = PASS

repeated initialization:
  same report counts = PASS
  SQLite information row count remained 5 = PASS
  no existing Information was overwritten = PASS
```

Automatic tests:

```text
swift test --package-path tools/t4ctl
5 tests / 0 failures
```

## Observed

```text
A real physical folder became a persistent Information Space initial state.
Text content was stored verbatim.
Absolute source paths can return to the original physical objects.
Directory Information is represented as a current inventory observation.
Repeated initialization made successful no-op stores.
Unsupported and empty files were honestly skipped.
```

## Inference

Within this implementation slice, existing `InformationCore + SQLiteStore` is
sufficient to create `Information₀` for text-bearing folders and directory
inventory observations.

## Open gap

```text
The current SQLite decode path cannot represent an empty-text Information.
The current InformationStore contract has no list/query API.
Unsupported binary/document formats cannot yet form Information.
Directory Information is an inventory observation, not a directory content
  payload.
These gaps are recorded only; no fix is authorized in this step.
```
