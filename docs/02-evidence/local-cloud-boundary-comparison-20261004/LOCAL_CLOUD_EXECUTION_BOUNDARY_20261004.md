# Local / Cloud Execution Boundary Comparison

Date: 2026-10-04 Asia/Shanghai  
Status: `EXECUTED / OBSERVATION SEALED`  
Boundary: same external harness, same synthetic task, same file content, same `read_file` tool schema, and same continuation probes on both backends. No InformationCore, RelationCore, PALACE, schema, or write-back mechanism was added.

## 1. Backend paths

### Local

```text
external harness
      ↓
SimiGo HTTPServer /v1/chat/completions
      ↓
NativeMLX
      ↓
Qwen3.6 35B A3B MLX
```

### Cloud

```text
external harness
      ↓
SimiGo HTTPServer /v1/chat/completions
      ↓
RemoteOpenAIBackend
      ↓
ZAI glm-5.3-flash
```

## 2. Route fix required before comparison

The first Local attempt failed before inference:

```text
HTTP 503
Remote backend unavailable
```

Root cause was the Cloud route guard introduced in `ae16763`. The guard applied only to the second `/chat/completions` pattern, leaving `/v1/chat/completions` unconditionally routed to the remote branch.

Minimal fix:

```text
SimiGo source commit = 82b57f6
change               = guard both Chat Completions remote patterns
validation           = fixed Release build reached NativeMLX
pushed               = codex/v2.1
```

The 503 artifacts are retained separately and are not counted as a Local execution result.

## 3. Initial tool task

Both runs read the same real file through an external harness:

```text
cloud marker 7f3a-real-file
second line
```

| Dimension | Local MLX | Cloud ZAI |
|---|---|---|
| first model turn | 200 / 10.907s | 200 / 5.992s |
| tool call | `read_file("real-file.txt")` | `read_file("real-file.txt")` |
| tool executor | external harness | external harness |
| final answer | correct first line | correct first line |

Cloud did not expose a Runtime lifecycle event for this work. Local did.

Local initial-turn Runtime trace:

```text
request             = req-5478b6ae
runtime session      = simigo-local-agent-001/001/main
lifecycle            = QUEUED → RUNNING → RELEASED
cache mode           = cold
prompt tokens        = 570
cache hit tokens     = 0
tool calls           = 1
cache save history   = 3
```

Cloud initial-turn identifiers:

```text
client request ID    = simigo-cloud-phase1-turn1-1791091708222
cloud request ID     = d7b7cb99-91d9-484d-b20e-2a5786b3b5b7
cloud response ID    = 2026100413282971fc597dc29f4206
```

## 4. Final-answer turns

After the harness supplied the tool result, both backends produced the correct first line.

| Dimension | Local MLX | Cloud ZAI |
|---|---|---|
| HTTP | 200 | 200 |
| duration | 1.000s | 4.955s |
| answer | `MARKER=cloud marker 7f3a-real-file` | `MARKER=cloud marker 7f3a-real-file` |

Local Runtime trace:

```text
request              = req-571fb6c5
tool result observed  = read_file
cache load history    = 3
cache mode            = extend
cache hit tokens      = 597
cache efficiency      = 0.93
cache save history    = 5
```

Cloud showed no equivalent Runtime cache event.

## 5. Continuation probe A: full caller transcript

The harness reused the same Agent/Session/Branch headers and resent the complete transcript with a follow-up question about the second line.

| Dimension | Local MLX | Cloud ZAI |
|---|---|---|
| model behavior | answered directly | reissued `read_file` |
| tool execution | none | external harness reread file |
| final answer | correct second line | correct second line |
| duration | 0.935s direct | 7.134s + 4.813s |

Local Runtime trace:

```text
request              = req-64c2f0cf
pool hit             = yes
cache mode           = restore
cache hit tokens     = 597
cache efficiency     = 0.51
cache save history   = 6
```

Cloud had no corresponding Runtime cache semantics.

Interpretation: the Cloud model succeeded because the caller supplied full context and the tool was available again. This is model conversation continuation, not evidence of SimiGo-owned Execution State continuation.

## 6. Continuation probe B: same headers only

The harness reused the same Agent/Session/Branch headers but sent only the follow-up message.

| Dimension | Local MLX | Cloud ZAI |
|---|---|---|
| first model turn | issued `read_file` | issued `read_file` |
| tool execution | external harness reread file | external harness reread file |
| final answer | correct second line | correct second line |
| duration | 1.380s + 0.463s | 5.570s + 5.146s |

Success here does not prove Execution State reuse. The follow-up text named `real-file.txt`, so each backend could solve it by issuing the tool again without prior conversation state.

Local Runtime trace:

```text
first request        = req-08a3a755
cache mode           = cold
cache hit tokens     = 0
cache save history   = 2
tool result observed = read_file

final request        = req-320b3ac8
cache mode           = extend
cache hit tokens     = 560
cache efficiency     = 0.93
cache save history   = 4
```

Cloud again showed no equivalent Runtime cache events.

## 7. Boundary table

| Dimension | Local MLX | Cloud ZAI |
|---|---|---|
| Agent / Session / Branch accepted | yes | yes |
| durable Execution ID exposed | no | no |
| per-request execution identifier | local `req-*` | cloud request/log/response IDs |
| lifecycle `QUEUED → RUNNING → RELEASED` | observed | not observed |
| Runtime KV cache | observed | not observed |
| cache save / load | observed | not observed |
| continuation via full caller transcript | yes | yes |
| continuation via headers alone | not proven | not proven |
| checkpoint / restore in this harness | not exercised | not exercised |
| StateGraph | unchanged | unchanged |
| backend internal state visibility | partial | not visible |
| transcript supplied by caller | yes | yes |

## 8. Research conclusion

Both backends can execute the same tool-calling task and produce the same task answer.

Only Local MLX exposed SimiGo Runtime execution semantics:

```text
lifecycle transitions;
session-scoped cache;
cache save / load;
cache efficiency;
tool-result observation;
runtime request identifiers.
```

Cloud behaved as a model-forwarding backend:

```text
HTTP / tool-call protocol worked;
provider request and response IDs were distinct;
no Runtime lifecycle or cache state was visible;
continuation depended on caller-owned transcript or a self-recovering tool call.
```

Therefore:

```text
Model Backend ≠ Execution State Backend
```

SimiGo can drive both backends, but Execution State semantics currently depend on the concrete backend's observability and controllability. Cloud forwarding alone does not turn the external provider into a SimiGo Execution State carrier.

## 9. State audit

Across both Local and Cloud runs:

```text
ExecutionStateGraph SHA-256 = d8520de2bf05ae56ab455bade7e4f2e1a443f21e92668b357d0cce16956b3eed
Information SQLite SHA-256  = 1029af85915319555ae5c4949d1bfb3afd678c503c2c34c00d65303b56905090
Information count           = 434
SQLite integrity            = ok
Information₁                = not formed
```

## 10. Raw evidence

Requests, responses, headers, harness code, Runtime trace excerpts, StateGraph snapshots, and Information snapshots remain local-only in this directory and are ignored by Git.
