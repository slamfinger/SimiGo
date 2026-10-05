# Real-Task Gap Execution 001 — Gap Register and Second-Run Charter

Date: 2026-10-04 Asia/Shanghai  
Status: `GAPS REGISTERED / SECOND-RUN OBSERVATIONAL CHARTER / EXECUTION NOT AUTHORIZED`  
Redaction rule: monetary values, exact project-internal identifiers, exact physical paths, and exact boundary candidates are not reproduced.

## 1. Purpose

Execution 001 exposed a set of concrete gaps. These gaps were not invented from a schema-first design; they appeared after a real agent completed a real information-retrieval and extraction task.

This record seals the observed gap register and defines the next observational step without authorizing schema design, code changes, or automatic execution.

## 2. Sealed gap register

### G1 — Information depth is insufficient

Execution 001 started from 434 Information rows:

```text
directory-inventory rows = 432
verbatim-text rows       = 2
```

The space was not empty and successfully supplied location-level guidance. However, it mostly answered:

```text
Where might relevant material exist?
```

It did not generally answer:

```text
What is already known inside the material?
```

Current observed form:

```text
logical object → physical-location index
```

Missing richer form:

```text
object
  ↓
content
  ↓
attributes
  ↓
relations
  ↓
historical working results
```

### G2 — Information query capability is insufficient

The real task required direct SQL access to the local Information database. The observed basic access pattern was limited to store/fetch-style operations, while the actual task required:

```text
find related Information;
filter by source;
filter by content or attributes;
combine conditions;
form a candidate set.
```

Observed fact: query capability was needed.

Design boundary: the exact API shape must not be fixed yet.

### G3 — Execution did not become Information₁

Execution 001 produced reusable working information, including source correspondence, extracted facts, a unit-anomaly judgment, and an unresolved evidence question. None of these returned to Information Space.

```text
Write-back to Information Space: NONE
```

Observed lifecycle:

```text
Information₀
      ↓
Execution
      ↓
working facts and judgments
      ✕
Information₁
```

The desired lifecycle remains unverified:

```text
Information₀
      ↓
Execution
      ↓
Information₁
      ↓
next Execution
      ↓
Information₂
```

G3 is the central breakpoint.

### G4 — Working products lack a natural persistence organization

The execution implicitly formed reusable working products:

```text
relevant directories;
relevant physical files;
opened-file reading results;
task facts;
cross-file support relations;
unit anomaly;
uncertainty;
remaining verification work.
```

These did not have a natural destination in the current system. This does not prove that a retrieval table, relation table, summary table, or any other specific schema is required.

### G5 — “Work once, work faster later” is not yet demonstrated

Execution 001 did not visibly reduce the exploration cost of a future run. The system remained effectively at Information₀ after the task completed.

The key future question is therefore:

```text
Does Information Space make a second related task meaningfully cheaper than the first?
```

This is more important than the absolute number of stored Information rows.

## 3. Second-Run observational charter

### Execution 002 — Persistence-gap probe

The next run should repeat the same task family under a controlled no-hint condition.

Input boundary:

```text
fresh execution context;
same task statement;
same Information₀ state;
InformationCore access allowed;
original physical-source access allowed;
no Execution 001 result;
no Execution 001 path summary;
no extracted values;
no file hints beyond Information₀;
no schema or tool enhancement.
```

Required work:

```text
1. snapshot the Information database before execution;
2. let the agent start only from the task and Information₀;
3. record whether it can discover the relevant path independently;
4. record all queries, candidate sets, opened sources, extracted facts, uncertainties, and final conclusions;
5. snapshot the Information database after execution;
6. redact task-specific sensitive values before external preservation.
```

### 3.1 Pre-registered control matrix

```text
condition                  Execution 001       Execution 002
-------------------------  ------------------  ------------------
Information state          Information₀        same Information₀
task statement             same task           same task
agent execution context    experimental        fresh
prior result               produced            forbidden
prior result summary       produced            forbidden
prior path hints           produced            forbidden
schema                     current             unchanged
InformationCore API        current             unchanged
write-back behavior        current             unchanged
physical-source access     allowed             allowed
```

The comparison target is not a precise latency benchmark. It is a qualitative persistence probe: whether the first execution left any reusable trace in the unchanged system state.

## 4. Required observation record

The raw run must preserve:

```text
declared input paths;
Information database hash before and after;
all Information queries, including direct SQL if used;
all source-selection decisions;
all opened physical files;
all retrieval failures;
all produced facts and judgments;
all unresolved questions;
wall-clock duration;
write-back count;
final artifact hashes.
```

The redacted record must preserve only structure, behavior, cost pattern, evidence boundary, and system-level observations.

## 5. Interpretation rules

The second run is especially valuable if it independently shows:

```text
the same information must be rediscovered;
the same physical files must be reopened;
the same ambiguity must be reconstructed;
the agent has no awareness that a prior execution already obtained these results.
```

That would provide a second independent observation of G3 and G4.

If the run reuses prior information, the next question changes:

```text
What was actually persisted?
How was it found?
Why was it useful?
Which representation made reuse effective?
```

If Execution 002 is unexpectedly faster, the result must not be attributed to Information Space before a leakage and confound audit. The audit must check, at minimum:

```text
session or conversation history contamination;
workspace artifacts left by Execution 001;
shell, editor, search, or tool history;
filesystem caches and metadata exposed to the agent;
unexpected copies of prior results;
hidden write-back outside the observed database;
task-input differences;
runtime or model behavioral variance.
```

Only after excluding these paths can faster behavior be treated as evidence of reusable Information persisted by the unchanged mechanism.

Until then, the result must not be interpreted as proof for or against a specific retrieval-set schema.

## 6. Explicit non-goals

```text
No new Information type.
No new Relation type.
No retrieval-set schema.
No summary-table schema.
No write-back mechanism design.
No InformationCore API redesign.
No schema migration.
No gate change.
No contract change.
No hints from Execution 001.
```

## 7. Authorization state

```text
Gap register             = SEALED
Second-run charter       = REGISTERED
Second-run execution     = NOT AUTHORIZED
Schema or API design     = NOT AUTHORIZED
Write-back experiment    = NOT AUTHORIZED
Raw evidence publication = NOT AUTHORIZED
```
