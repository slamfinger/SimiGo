# Future database equivalence audit requirements

A future equivalence campaign must produce and preserve:

```text
1. exact post-implementation repository commit and clean-state proof;
2. database engine/version/platform;
3. initialized database file hash and size;
4. logical schema version/hash;
5. complete DDL/schema;
6. transaction boundary records;
7. object inventory: IDs, sizes, hashes, contents;
8. index inventory: append order and exact entries;
9. dependency history: append order and exact entries;
10. LAST-entry current resolution;
11. EPR004-equivalent executable/cwd/argv/process facts;
12. required-artifact existence/size/hash checks;
13. ES2 and ESN decisions with expected-vs-actual records;
14. U-ledger counts;
15. observer-equivalent C1-C4 checks;
16. explicit rejection taxonomy results.
```

The audit must distinguish semantic IS state from engine metadata. Engine
metadata is not evidence unless declared as a decision input.

## Fail-closed mappings

Any mismatch maps to rejection:

```text
EQ-1 failure → OBJECT_SET_MISMATCH;
EQ-2 failure → OBJECT_IMMUTABILITY_VIOLATION;
EQ-3 failure → INDEX_ORDER_OR_ENTRY_MISMATCH;
EQ-4 failure → DEPENDENCY_HISTORY_MISMATCH;
EQ-5 failure → CURRENT_RESOLUTION_MISMATCH;
EQ-6 failure → READ_RESULT_MISMATCH;
EQ-7 failure → DECISION_EQUIVALENCE_MISMATCH;
EQ-8 failure → EXTRA_OBSERVABLE_STATE;
schema failure → SCHEMA_AUTHORITY_MISMATCH;
EPR failure → PROVENANCE_MANIFEST_MISMATCH.
```
