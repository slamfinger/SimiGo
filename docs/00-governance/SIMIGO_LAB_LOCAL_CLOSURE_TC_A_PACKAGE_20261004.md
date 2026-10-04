# Local Closure TC-A Task Package Registration

Date: 2026-10-04  
Status: `TASK PACKAGE FROZEN / RUNNER HARNESS PREPARED / EXECUTION NOT AUTHORIZED`

## 1. Frozen carrier

```text
Carrier   = TC-A — Configuration compatibility audit → Release gate
Backend   = SimiGo HTTPServer → NativeMLX
Route fix = SimiGo source commit 82b57f6
```

## 2. Frozen package

Package root:

```text
docs/02-evidence/local-execution-information-closure/task-carrier-tc-a/
```

Frozen contents:

```text
sources/platform-baseline.json;
sources/service-alpha.json;
sources/service-beta.json;
sources/service-gamma.json;
instructions/execution-a.md;
instructions/execution-b-template.md;
observer/selection-rules.md;
runner/isolation-and-recording.md;
runner/expected-register.json;
runner/semantic-evaluation-rules.md;
runner/harness.py;
runner/RUNBOOK.md;
MANIFEST.sha256.
```

Manifest SHA-256:

```text
1920f30ba830c22239851b76eb751901b718f27663f02d8a521783a4aea8f95b
```

## 3. Agent-facing boundary

Execution A may use only:

```text
read_file
```

Execution B may use only:

```text
fetch_stored_information
```

B must not reread Phase A source files. The expected register and evaluator
are runner-side only and must not enter either Agent workspace.

## 4. Observer boundary

After Execution A, the observer may only:

```text
preserve A residue;
select the structurally complete final answer;
copy those exact bytes to candidate-information.json;
store it through existing t4ctl store / InformationCore.store();
record the resulting identity;
give only that identity to Execution B.
```

The observer may not repair JSON, summarize, add facts, create a new schema,
promote Runtime trace/cache into Information, or alter the expected register.

## 5. Isolation boundary

Between A and B, inference state must be isolated by:

```text
stop/reload NativeMLX;
fresh isolated backend process;
or recorded cache/prefix-pool eviction.
```

B's trace must show a cold path with no inherited A cache bind, prefix hit,
checkpoint load, or execution-state reuse.

## 6. Authorization state

```text
Task package               = FROZEN
Runner harness             = PREPARED / PACKAGE VERIFIED
Observer rules             = FROZEN
Expected register          = RUNNER-SIDE ONLY
Observer residue selection = NOT AUTHORIZED
InformationCore store      = NOT AUTHORIZED
Execution A                = NOT AUTHORIZED
Execution B                = NOT AUTHORIZED
Schema / Runtime change    = NOT AUTHORIZED
```
