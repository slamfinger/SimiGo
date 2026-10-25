# Empty database-backed IS initialization design

## Scope

One initialization creates one fresh SQLite database containing only the three
accepted logical stores:

```text
is_objects
is_index_entries
dependency_entries
```

No logical rows are inserted. No logical import is performed. The database is a
carrier artifact, not an equivalence result.

## Behavior

The initializer:

```text
1. refuses an existing output path;
2. creates the parent directory when needed;
3. creates the exact accepted schema;
4. validates table set, columns, row counts, and SQLite integrity;
5. records engine/version/platform, implementation hashes, exact execution
   repository commit, database path/hash/size, logical row counts, and
   initialization time;
6. writes INITIALIZATION_MANIFEST.json beside the database.
```

## Boundary

The initialized database is empty. It contains no D, D', SRS, continuation,
index entry, or dependency mapping. It is READY FOR EQUIVALENCE CAMPAIGN
AUTHORIZATION only; it is not evidence of carrier equivalence.
