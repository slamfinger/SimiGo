# Runner Isolation and Recording Rules

## 1. Frozen inputs

Before Execution A:

```text
hash all files under sources/, instructions/, observer/, and runner/;
create a fresh copy of the sealed Information₀ SQLite database;
record the copy hash.
```

The sealed Information₀ itself must not be written.

## 2. Execution A

Run Execution A with a fresh Agent/Session and the fixed Local path:

```text
SimiGo HTTPServer → NativeMLX
```

Capture every request, response, tool call, tool result, Runtime trace, and
timing record.

## 3. Observer phase

After A stops, apply `observer/selection-rules.md`.

If Candidate Information is eligible, store it only through the existing
`t4ctl store` boundary into the Information₀ copy. Record the identity.

## 4. Runtime isolation before B

Between A and B, isolate NativeMLX inference state by one of:

```text
stop and reload NativeMLX;
use a fresh isolated backend process;
or clear/evict all relevant cache and prefix-pool entries with before/after
evidence.
```

Record the method and before/after evidence. Unique Agent/Session IDs are not
sufficient.

## 5. Execution B

Render `execution-b-template.md` by substituting only the Stored Information
identity. Run B with a fresh Agent/Session. B has only
`fetch_stored_information`; it has no `read_file` and must not reread A source
files.

Capture every request, response, tool call, tool result, Runtime trace, and
timing record. The B Runtime trace must show a cold path with no inherited A
cache bind, prefix hit, checkpoint load, or execution-state reuse.

## 6. Required outcome records

Preserve:

```text
A final answer and candidate bytes;
Stored Information identity;
B fetch output;
B final answer;
A/B Runtime traces;
all database hashes;
all instruction/package hashes;
explicit readings R-A0 through R-B4.
```
