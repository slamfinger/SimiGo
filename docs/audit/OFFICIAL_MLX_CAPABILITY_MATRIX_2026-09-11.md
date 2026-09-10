# SimiGo / Official MLX Capability Matrix — 2026-09-11

## Scope

Repository baseline: `audit-simplify-2026-09-11`.

Pinned dependencies in the SimiGo baseline remain official `mlx-swift` / `mlx-swift-lm` packages. This audit compares the inference responsibilities SimiGo actually uses with the corresponding official APIs in the pinned upstream line (`mlx-swift` 0.31.6, `mlx-swift-lm` 3.31.4).

## Decision rule

1. If official MLX/MLXLMCommon already owns the inference behavior, SimiGo must call the official API rather than reproduce that behavior.
2. SimiGo may retain application responsibilities that official MLX does not own: HTTP/OpenAI protocol, request lifecycle, service lifecycle, policy/observability, and application-specific tool dispatch.
3. A custom implementation is not justified merely because it can expose more internal telemetry. Telemetry must not become a second inference state machine.

## Capability mapping

| Capability SimiGo needs | Official capability | Current SimiGo implementation | Decision |
|---|---|---|---|
| Model loading / model container | `LLMModelFactory` + `ModelContainer` | Uses official `ModelContainer` | KEEP OFFICIAL |
| Prompt preparation / chat template | `ModelContainer.prepare` / official processor/tokenizer | Uses official `container.prepare` | KEEP OFFICIAL |
| Token generation + streaming | `MLXLMCommon.generateTask` / generation stream | Uses official generation task, but wraps it in custom iterator/ledger plumbing | MIGRATE TO DIRECT OFFICIAL |
| KV cache creation / retention across turns | `ChatSession` owns session cache and reuses it; `ChatSession` supports pre-built KV cache | SimiGo owns `sessionCaches` + global `PhysicalKVRevision` + manual `KVCache.copy/trim` reuse catalog | DELETE CUSTOM KV CATALOG; USE OFFICIAL SESSION/CACHE |
| Prefix / prompt cache | Official `ChatSession` supports pre-built cache and prompt-cache restore APIs in the official stack | Reimplemented as global physical revision selection | DELETE REIMPLEMENTATION |
| Tool calling | Official `ToolSpec`, `ToolCall`, model-specific `ToolCallFormat`, streaming tool-call handling | Uses official structured `.toolCall`, but also has custom `<tool_call>` raw parser and custom duplicate/degeneration logic | DELETE RAW PARSER; KEEP APP DISPATCH |
| Tool-call format detection | Official model configuration includes `toolCallFormat`; official tool parser infrastructure supports model-specific formats | SimiGo manually searches for `<tool_call>` and reparses streamed text | USE OFFICIAL |
| Generation cancellation / early-stop cleanup | Official `generateTask` returns task handle; upstream explicitly manages cancellation when streaming ends early | SimiGo tracks and cancels official generation task, which is useful at app boundary | KEEP THIN APP CANCELLATION; DELETE CUSTOM TOKEN/LEDGER STATE |
| Generation parameters / prefill step | Official `GenerateParameters` includes generation controls and prefill configuration | SimiGo creates official `GenerateParameters`; this is correct | KEEP OFFICIAL |
| Speculative decoding | Official `ChatSession` `SpeculativeDecodingConfig` | Not required by current SimiGo flow | DO NOT BUILD CUSTOM; OPTIONAL FUTURE OFFICIAL |
| Memory allocator / MLX cache | Official `Memory.snapshot`, `cacheLimit`, `memoryLimit`, `clearCache` | SimiGo calls official APIs, but also maintains an estimated KV byte ledger and custom admission/eviction | REDUCE; OFFICIAL MEMORY OBSERVABILITY IS TRUE SOURCE |
| Wired-memory coordination | Official MLX has wired-memory management in newer upstream; pinned version must be verified before use | No direct SimiGo replacement wired policy currently established | VERIFY PINNED API BEFORE ADDING ANYTHING |
| Session serialization | `ChatSession` is explicitly single-session/single-task; `ModelContainer` provides protected model access | `SessionGenerationGate` duplicates per-session generation exclusion | DELETE AFTER CHATSESSION MIGRATION |
| HTTP / OpenAI-compatible service | Not owned by MLX | SimiGo HTTP server and protocol adaptation | KEEP CUSTOM |
| Service start/stop/suspend/resume policy | Not owned by MLX | SimiGo lifecycle coordinator/gates | KEEP APP POLICY, MINIMIZE |
| Runtime metrics / trace logging | Not owned by MLX | SimiGo observability | KEEP, but observability must not own inference semantics |
| Context-budget / admission policy | Not a ChatSession semantic; application can impose policy | Custom `projectedMemory` + eviction/reject policy | KEEP ONLY AS OUTER POLICY; remove duplicate KV truth |

## The most important finding

The biggest duplication is not model loading or generation. It is **session/KV ownership**.

Official `ChatSession` already owns a persistent per-session cache, converts history to KV state, carries the cache across turns, and supports pre-built KV caches for prefix reuse. SimiGo currently builds a second global KV subsystem around the same underlying `KVCache` objects. That creates two truths for residency, ownership, reuse, and lifecycle.

The second major duplication is **tool parsing**. The official generation stream already exposes structured tool calls and the official stack supports model-specific formats. SimiGo's `RawToolCallStreamParser` therefore represents a parallel parser path that should disappear after direct official tool handling is wired through.

The third duplication is **session generation locking**. `ChatSession` documents single-task/session use as its own contract. A service may still serialize access to a session at its boundary, but SimiGo should not maintain a second inference-specific gate whose semantics overlap the session object.

## Required migration order

### 1. Introduce official `ChatSession` ownership per SimiGo logical session/branch

The application may keep a small registry from SimiGo's `(agent, session, branch)` identity to `ChatSession`. The registry is application state; the KV cache must belong to `ChatSession`, not to a parallel `PhysicalKVRevision` catalog.

### 2. Route normal generation through `ChatSession`

Use the official session generation/stream APIs for prompt preparation, KV retention, and tool-call production. Keep only the HTTP callback/response adaptation in SimiGo.

### 3. Delete the global physical KV layer

Delete:

- `PhysicalKVRevision`
- `state.physicalRevisions`
- global prefix selection / common-prefix matching
- manual `KVCache.copy()` / `trim()` reuse catalog logic
- `PhysicalTokenRecorder`
- `PhysicalLedgerTokenIterator`
- `ledgerSynced`
- physical-KV commit logic

### 4. Delete the raw tool parser path

After the official tool-call stream is the sole source of tool calls, delete:

- `RawToolCallStreamParser`
- raw `<tool_call>` reparse logic
- raw-tool-specific failure state

Keep only SimiGo's application-level `ParsedToolCall` adaptation and actual tool dispatch if the HTTP API requires that shape.

### 5. Delete `SessionGenerationGate`

Do this only after `ChatSession` objects are the session cache owners. Do not merely remove the gate while leaving concurrent writes against shared session state.

### 6. Re-evaluate admission

Admission may remain as an outer service policy, but it must use official MLX memory observations as the ground truth. A hand-maintained byte estimate must not become a second definition of physical KV residency.

## Non-goals

- Do not vendor `mlx-swift-lm` into SimiGo.
- Do not invent a custom batch scheduler to replace official generation.
- Do not add another cache abstraction on top of `ChatSession`.
- Do not preserve custom inference mechanisms solely because they have richer logs.

## Upstream evidence

Pinned-line official sources used for this audit:

- `mlx-swift-lm` 3.31.4 `ChatSession.swift`: session-owned cache, persistent multi-turn KV state, tool configuration, and official streaming generation.
- `mlx-swift` 0.31.6 `Memory.swift`: official memory snapshots, allocator/cache limits, and cache clearing.
- Current official tool-calling documentation: structured `ToolCall`, `ToolSpec`, model-specific `ToolCallFormat`, and `ToolCallProcessor`.

The current SimiGo branch still contains the duplicated physical/session inference layer. This document therefore records the target architecture, not a claim that the migration is already complete.
