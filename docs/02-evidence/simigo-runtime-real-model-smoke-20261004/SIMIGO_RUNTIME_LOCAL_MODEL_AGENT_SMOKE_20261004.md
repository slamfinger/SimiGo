# SimiGo Runtime Local-Model Agent Smoke Observation

Date: 2026-10-04 Asia/Shanghai  
Status: `EXECUTED / OBSERVATION SEALED / MODEL-RUNTIME SMOKE ONLY`  
Boundary: no SimiGo source, schema, API, or InformationCore code was changed.  
Redaction rule: local absolute paths are not reproduced in this version.

## 1. Running system

```text
application       = SimiGo.app 2.1.0
backend           = Native MLX
local endpoint    = 127.0.0.1:8000
model family      = Qwen3.6 35B A3B MLX
protocol observed = /health, /v1/models, /v1/chat/completions
```

Health returned `status=ok`. The model list identified the backend as Native MLX and reported chat completions, completions, responses, streaming, and tool-calling support.

## 2. Basic real generation

A non-streaming chat completion was sent through SimiGo with explicit agent, session, and request identifiers.

```text
HTTP status          = 200
elapsed              = 35.456 seconds
prompt tokens        = 232
cache hit tokens     = 0
cache mode           = cold
response correctness = correct
```

Runtime trace recorded:

```text
QUEUED → RUNNING;
prefill;
prefix-pool export;
cache save;
completion;
RELEASED.
```

This confirms that SimiGo.app, not a direct external model call, owned the local-model invocation path.

## 1.1 Ownership boundary correction

SimiGo did **not** own the task loop.

The actual ownership was:

```text
external harness selected the task;
external harness created the tool schemas;
external harness sent Chat Completions requests;
SimiGo Runtime performed local-model inference;
SimiGo Protocol observed tool-call events;
external harness executed the tools;
external harness returned tool results;
external harness decided when the task was complete.
```

Therefore this experiment proves:

```text
SimiGo.app → Runtime → Native MLX model invocation = working.
```

It does **not** prove:

```text
SimiGo.app → autonomous task agent → tool execution → completed task = working.
```

The checked app source exposed model-serving protocol behavior and execution/cache/tool-governance traces, but no built-in task orchestrator was invoked. The word “agent” in identifiers and headers marked the external caller's execution identity; it did not mean SimiGo itself became the task agent.

## 3. Session and context behavior

A second request reused the same session headers but sent only a follow-up user message, not full chat history. The model did not know the prior task.

A third request resent the full conversation under the same session identity. The model then answered correctly.

Observed contract:

```text
session headers identify execution/cache context;
Chat Completions request messages remain the caller-owned transcript;
session headers alone do not replace complete chat history.
```

The third call showed Runtime-side prefix reuse:

```text
mode             = restore / extend
cache hit tokens = 238
cache efficiency = 0.52
```

## 4. External-agent tool loop through SimiGo model backend

A small external agent harness used SimiGo as the model endpoint. The external harness, not SimiGo, owned the task loop. The local model completed a three-turn tool-call loop over a synthetic workspace:

```text
turn 1: list workspace;
turn 2: read three text/markdown files;
turn 3: produce final inventory JSON.
```

The final result was correct.

### Context growth

```text
turn 1: history=3, promptTokens=683, cacheEfficiency=0.00, mode=cold
turn 2: history=5, promptTokens=71,  cacheEfficiency=0.91, mode=extend
turn 3: history=9, promptTokens=81,  cacheEfficiency=0.91, mode=extend
```

The third turn TTFT fell to about 331 ms. No compression or eviction occurred in this small run; Runtime used cache extension and its prefix pool.

### Tool governance

SimiGo observed tool calls and externally returned tool results:

```text
1 list_workspace call;
3 read_file calls;
4 TOOL_RESULT events.
```

A concrete issue was also observed: a zero-argument tool request was internally rejected as `invalid_arguments`, and the rejected tool call was not returned to the client. The client saw an empty assistant message with `finish_reason=stop`. Adding a required non-empty argument allowed the same tool pattern to work.

This is a Runtime/protocol compatibility issue to revisit later; no fix was made during this observation.

## 5. Execution and Information state

The persisted reference Execution StateGraph file did not change during any ordinary generation or tool turn.

```text
ExecutionStateGraph before = unchanged
ExecutionStateGraph after  = unchanged
```

Runtime execution was observable only in the trace log:

```text
lifecycle transitions;
prefill/cache mode;
prompt-token counts;
cache efficiency;
tool-call and tool-result governance events.
```

No InformationCore or Information SQLite database appeared in the running SimiGo application-support path. Source inspection also found no InformationCore/SQLiteStore references in the SimiGo app/runtime sources used for this run.

Therefore:

```text
working transcript       = model context / Runtime cache / client transcript;
execution observation    = Runtime trace;
persistent state graph   = unchanged;
Information Space        = not in this call chain;
Execution → Information₁ = not formed.
```

## 6. Interpretation boundary

This run does not prove that SimiGo Runtime is unable to support Information Space. It proves that the current app path does not connect model-call execution to InformationCore.

The corrected research judgment is:

```text
G3 under external-agent path               = observed;
G3 as a SimiGo Runtime defect              = not yet proven;
missing SimiGo → Information link          = observed at model-call boundary;
missing SimiGo-owned task/agent orchestration = observed as the next boundary.
```

## 7. Raw evidence

Raw requests, responses, agent turns, harness, Runtime trace excerpts, and hashes remain local-only in this directory and are ignored by Git.

## 8. Post-observation process-interruption correction

A later monitoring run observed the running SimiGo process disappear while an agent turn was active. A macOS diagnostic report recorded `SIGSEGV`, which was initially interpreted as a Native MLX crash.

The operator corrected this interpretation: the process disappearance was caused by replacing/updating the running SimiGo build, which killed the active process. It was not treated as evidence of a SimiGo Runtime, MLX, Metal, or agent-loop defect.

Therefore:

```text
process interruption cause = build update / process replacement by operator
MLX runtime defect claim   = retracted
StateGraph after run       = unchanged
Information SQLite         = unchanged
```
