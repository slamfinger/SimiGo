# Cloud Backend Agent Smoke Observation

Date: 2026-10-04 Asia/Shanghai  
Status: `EXECUTED / OBSERVATION SEALED`  
Source commit: `ae16763 feat: add replaceable ZAI cloud backend`  
Boundary: no Runtime, schema, InformationCore, RelationCore, PALACE, or API code was changed.

## 1. Running path

```text
external agent harness
      ↓
SimiGo HTTPServer /v1/chat/completions
      ↓
RemoteOpenAIBackend
      ↓
ZAI Cloud API
```

Observed runtime:

```text
installed app = SimiGo 2.1.1 build 11
source commit  = ae16763
endpoint       = 127.0.0.1:8000
upstream       = https://api.z.ai/api/coding/paas/v4
model          = glm-5.3-flash
status         = ok
```

The tool executor was external. SimiGo forwarded the model call and returned tool-call responses; it did not execute `read_file` itself.

## 2. Execution identity

The caller supplied a stable logical identity:

```text
Agent ID  = simigo-cloud-agent-001
Session   = simigo-cloud-session-001
Branch    = main
```

No durable SimiGo Execution ID was exposed. Each HTTP request had a distinct caller-supplied local request ID, while ZAI returned distinct cloud request, log, trace, and response IDs.

## 3. Initial tool task

The task required reading a real workspace file through the `read_file` tool and reporting its first line.

| Step | HTTP | Duration | Result |
|---|---:|---:|---|
| model tool-call turn | 200 | 5.992s | `read_file("real-file.txt")` |
| external execution | local | local | real file was read |
| model final turn | 200 | 4.955s | `MARKER=cloud marker 7f3a-real-file` |

The final answer was correct.

Key identifiers:

```text
turn 1 local request       = simigo-cloud-phase1-turn1-1791091708222
turn 1 cloud response ID   = 2026100413282971fc597dc29f4206
turn 1 cloud request ID    = d7b7cb99-91d9-484d-b20e-2a5786b3b5b7
turn 2 local request       = simigo-cloud-phase1-turn2-1791091714220
turn 2 cloud response ID   = 202610041328358bfde5947b3a4f40
turn 2 cloud request ID    = 72dac732-a71e-433c-a65e-0adbb62387fa
```

## 4. Continuation probe A: full client transcript

The same Agent/Session/Branch headers were reused, and the harness resent the complete prior transcript plus the continuation question.

```text
continuation request     = 200, 7.134s
model behavior           = issued read_file again
external execution       = real file was reread
final request            = 200, 4.813s
final answer             = SECOND_LINE=second line
```

The result was correct, but correctness cannot be attributed to SimiGo Runtime state: the full transcript was supplied by the caller.

## 5. Continuation probe B: same headers only

The same Agent/Session/Branch headers were reused, but the request contained only the new follow-up user message.

```text
continuation request     = 200, 5.570s
model behavior           = issued read_file again
external execution       = real file was reread
final request            = 200, 5.146s
final answer             = SECOND_LINE=second line
```

This does not demonstrate Execution State continuation. The follow-up text itself named the file, so the model could issue the same tool call without prior context. No Runtime cache or server-side conversation state was observed.

## 6. Execution semantics observed

```text
Cloud tool calling                  = worked
stable header identity              = accepted
durable SimiGo Execution ID         = not exposed
Runtime execution lifecycle trace   = absent for Cloud path
Runtime KV cache                    = absent for Cloud path
server-side conversation continuity = not observed
caller-owned full transcript        = required for observed continuation
ExecutionStateGraph                 = unchanged
Information Space                   = unchanged
```

The distinction is therefore:

```text
model conversation could continue
      ≠
Execution State was persisted or restored
```

For the Cloud Backend, SimiGo behaved primarily as a protocol forwarding Runtime. It did not expose the execution-lifecycle, cache, checkpoint, fork, or state semantics observed on the Native MLX path.

## 7. State audit

Before and after the experiment:

```text
ExecutionStateGraph SHA-256 = d8520de2bf05ae56ab455bade7e4f2e1a443f21e92668b357d0cce16956b3eed
Information SQLite SHA-256  = 1029af85915319555ae5c4949d1bfb3afd678c503c2c34c00d65303b56905090
Information count           = 434
SQLite integrity            = ok
```

No Information₁ was formed.

## 8. Raw evidence

Requests, responses, headers, harness code, tool results, and continuation artifacts remain local-only in this directory and are ignored by Git.
