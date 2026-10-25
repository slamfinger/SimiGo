# IS Layout Declaration — SRS-REAL-CLOSURE-01 (round 1, document form)

> **This file is a DECLARATION only.** No Information Space is materialized
> by fixture preparation. Every runtime directory state below is created
> exclusively under the later EXECUTION authorization, whose IS_MUTATION
> effect scope must name the run IS directory (Design v0.2 §9).

## Runtime layout (created at execution time)

```text
<run_is_dir>/
  objects/<sha256>             write-once content-addressed objects;
                               never overwritten, never deleted
  index.jsonl                  append-only: {"srs_identity", "record_object"}
                               per line; never rewritten
  current/
    dependencies.jsonl         the ONLY mutable fixture state:
                               append-only current-resolution mapping
                               {"dependency_id", "content_address", "revision", "reason"};
                               resolution reads take the LAST entry per
                               dependency_id
```

## State classes (Design v0.2 §3, R1)

```text
immutable objects              D, D', SRS record, continuation records
append-only index              SRS identity → record object
mutable current-resolution     dependency_id → current content address /
                               revision (N1 updates ONLY this)
```

## Materialization sequence (execution stage)

```text
1. materialize (runner): write D object; write initial resolution entry
   (dependency_id → D, revision 1, reason "initial materialization");
2. es1: compute U once (ledger entry flushed before return); settle SRS;
   write SRS record object + index entry; exit;
3. es2: resolve via index; verify byte hash; schema-validate; read current
   dependency via mapping; compare pinned vs current; invoke SRS-VAL;
   on REUSE compute Δ; write continuation record; exit;
4. mutate-n1: write D' object (NEW immutable object; additive write);
   append resolution entry (dependency_id → D', revision 2); SRS index and
   all existing objects untouched; original SRS continues to pin D;
5. esn: same as es2 (negative control; expected BLOCK via DP-1
   dependencyBlockingInvalidation);
6. observer (separate process, after all exits): re-hash all objects;
   re-derive U ledger counts from raw event logs; verify temporal order;
   verify persisted-vs-resolved byte equality; emit observer_verdict.json.
```

## Invariants

```text
I-1  object bytes == their content address (write-once integrity);
I-2  index entries are append-only; no entry is rewritten or removed;
I-3  resolution mapping is append-only; latest entry per dependency wins;
I-4  nothing outside <run_is_dir> is written by any ES process;
I-5  D and the original SRS record are never modified by any stage,
     including the N1 negative control.
```
