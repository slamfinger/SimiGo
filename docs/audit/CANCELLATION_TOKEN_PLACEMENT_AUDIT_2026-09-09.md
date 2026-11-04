# CancellationCommitToken Placement Audit — 2026-09-09

## Scope

Audit the exact lifetime and insertion points for the proposed request-scoped `CancellationCommitToken`.

**Runtime code is intentionally unchanged.**

## Executive conclusion

The previously documented rule "create Token before request Task creation" is stronger than necessary and should **not** be treated as a mandatory placement rule.

The cleaner ownership boundary is:

```text
requestTask
  ↓
SessionGenerationGate
  ↓
generateAfterGate
  ↓
create request-local Token
  ↓
install Task cancellation handler around the generation lifetime
  ↓
MLX generationTask becomes available
  ↓
install generation cancellation hook
  ↓
activeGenerationTasks registration
  ↓
stream / value / commit
  ↓
clear hook
```

The reason is that cancellation before `generateAfterGate()` starts cannot have a generation task to cancel. `SessionGenerationGate` already checks cancellation before and after acquisition, so no generation-task ownership exists at that point.

The Token therefore needs to exist **before the first operation that can create an independent generation task**, not necessarily before request-task creation.

## 1. Existing request ownership is already sufficient before generation

Current `generate()` atomically creates and registers `activeRequestTasks[requestId]` under `NativeMLX.State`.

The request task then enters `SessionGenerationGate.withExclusive(executionKey)`.

`SessionGenerationGate` checks `Task.isCancelled` before acquisition and again after the gate is acquired. Its waiter cancellation path is also cancellation-safe.

Therefore this sequence is already safe without a Token:

```text
request registered
→ request cancelled
→ gate waiter removed / acquisition rejected
→ generateAfterGate never creates generationTask
```

No generation ownership exists that requires Token intervention.

## 2. Correct Token creation boundary

Recommended conceptual placement:

```swift
private func generateAfterGate(...) async throws -> String {
    let token = CancellationCommitToken()

    return try await withTaskCancellationHandler(
        operation: {
            // existing generation body
        },
        onCancel: {
            token.cancel()
        }
    )
}
```

The exact implementation may use a local helper to keep the existing function body readable.

The critical invariant is not the exact line where `token` is allocated. It is:

> The cancellation handler observing cancellation must be installed before `container.perform` can create the independent MLX generation task.

This closes the only meaningful pre-handoff window.

## 3. Why Token should not be stored in NativeMLX.State

Do not add:

```text
state.cancellationTokens[requestId]
state.requestCancellationState[requestId]
state.isCancelling
state.generationStarting
state.commitInProgress
```

The request task itself is already the request ownership ledger. The Token is a short-lived synchronization object whose lifetime follows `generateAfterGate()`.

A State registry would create another cancellation authority and would require its own cleanup, shutdown snapshot semantics, and stale-entry handling.

The preferred model is therefore:

```text
activeRequestTasks
    = request ownership / stop drain

activeGenerationTasks
    = generation ownership / stop drain / observability

CancellationCommitToken
    = request-local cancellation ↔ generation handoff ↔ KV publication ordering
```

These are three different responsibilities.

## 4. Critical cancellation-handler placement

The Token cancellation handler must cover the whole generation lifetime, not merely the stream loop.

It must be active while all of the following can happen:

```text
container.perform
prefill / MLX generation setup after permit
MLX generationTask creation
handoff to activeGenerationTasks
stream consumption
generationTask.value
ledger snapshot
tool processing
Physical KV eligibility
Physical KV commit
```

Most importantly, it must already be active when `container.perform` can return a generation task.

Otherwise this race remains:

```text
generationTask created
        ↓
cancel arrives
        ↓
Token cancellation handler not installed yet
        ↓
no generationTask cancellation hook
```

## 5. Generation-task hook installation

Once the tuple is extracted:

```text
(stream, generationTask, generationKVCache, promptPrefillTime)
```

the first relevant operation should be Token hook installation.

Required order:

```text
generationTask extraction
        ↓
token.installCancellationHook {
    generationTask.cancel()
}
        ↓
defer { token.clearCancellationHook() }
        ↓
activeGenerationTasks[requestId] = generationTask
```

Do not put asynchronous work, logging, MainActor work, or unrelated State mutations between extraction and hook installation.

## 6. Why the hook and request cancellation handler are both needed

They solve different races.

### Request cancellation handler

```text
requestTask.cancel()
    ↓
token.cancel()
```

This converts cancellation of the request owner into cancellation of the request-local synchronization primitive.

### Generation cancellation hook

```text
token.cancel()
    ↓
generationTask.cancel()
```

This converts Token cancellation into cancellation of the independently created MLX generation task.

Together:

```text
HTTP / API / stop
       ↓
requestTask.cancel()
       ↓
Task cancellation handler
       ↓
Token.cancel()
       ↓
┌──────────────────────────┐
│ if generationTask exists  │ → generationTask.cancel()
│ else cancelled=true       │
└──────────────────────────┘
```

If cancellation wins before generation-task creation, later hook installation must immediately invoke the hook.

## 7. `cancel → install` is the essential handoff guarantee

The Token must make this sequence safe:

```text
cancel()
  ↓
cancelled = true
  ↓
MLX generationTask becomes available
  ↓
install(hook)
  ↓
hook executes immediately
```

No timing assumption is allowed.

This is why merely checking `Task.isCancelled` after generation-task creation is insufficient: it creates a polling race rather than an ownership guarantee.

## 8. Commit placement

The final Physical KV publication must use the same Token, but only at the publication boundary.

Conceptual sequence:

```text
ordinary eligibility checks
        ↓
token.withCommitLock {
    guard !token.cancelled else { reject }

    state.withLock {
        publish PhysicalKVRevision
    }
}
```

The token lock therefore establishes the order between:

```text
cancel
vs
publish
```

It does not replace:

```text
ledgerSynced
prompt non-empty
KV cache non-empty
agentOutputCommitAllowed
```

Those remain ordinary eligibility checks.

## 9. Important stop interaction

`stop()` does not need direct access to the Token.

Its existing ownership chain is sufficient:

```text
stop
  ↓
state lock
  ├─ isRunning = false
  └─ snapshot activeRequestTasks
  ↓
requestTask.cancel()
  ↓
request Task cancellation handler
  ↓
Token.cancel()
  ↓
generationTask.cancel() if already installed
```

If generationTask does not yet exist, Token remains cancelled. If generationTask appears later, `install()` observes the cancelled state and invokes the hook.

Thus stop does not require a Token registry in State.

The independent `activeGenerationTasks` snapshot remains useful because it provides an additional direct cancellation/drain handle when already registered.

## 10. Lock ordering

The Token lock may precede State lock only for the short publication decision:

```text
Token lock
    ↓
State lock
```

No State critical section may acquire the Token lock.

No await or task value wait may occur under either combined critical section.

Physical release remains after State unlock.

## 11. Hook clearing boundary

The hook must be cleared by one dominating `defer` established immediately after successful installation.

Required lifetime:

```text
install
  ↓
activeGenerationTasks registration
  ↓
all generation work
  ↓
KV commit or rejection
  ↓
activeGenerationTasks removal
  ↓
clear
```

If the outer generation scope exits before the ledger removal due to a future code change, the cleanup must still dominate that exit. The exact local placement should be chosen so the hook cannot survive generation lifetime.

`clear()` must serialize with `cancel()` so that:

```text
cancel → clear
```

executes the hook once, while:

```text
clear → cancel
```

leaves no stale hook.

## 12. Deletion implications

No new deletion candidate is justified by this placement audit.

Keep:

- `activeRequestTasks`
- `activeGenerationTasks`
- `SessionGenerationGate`
- `RuntimeLifecycleGate`
- `stop()` task snapshots

Do not introduce a Token registry merely to make stop() reach the Token.

The existing task ownership chain is sufficient.

## 13. Corrected design rule

Replace the earlier broad rule:

> Create Token before request Task creation.

with the narrower architectural rule:

> Create the request-local `CancellationCommitToken` before the first independent generation-task creation point, and install its task-cancellation handler before that point can execute.

This keeps the Token local, avoids State ownership, and still closes both required races:

```text
cancel ↔ generation-task handoff
cancel ↔ Physical KV publication
```

## Final classification

**P1 design placement is now resolved.**

The Token should be local to the generation lifetime, cancellation-aware before MLX generation-task creation, and reused only for generation-task handoff and final Physical KV publication.

No runtime code is changed by this audit commit.
