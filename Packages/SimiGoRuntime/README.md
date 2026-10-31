# SimiGoRuntime

Standalone Apache-2.0 runtime package consumed by the public SimiGo app. It
contains the Execution/Runtime Contract, Runtime/Backend implementation, and
the isolated Qoder transcript collection component.

## Products

- `SimiGoRuntimeContract` — execution and information-space runtime contracts.
- `SimiGo2Experimental` — MLX-backed experimental runtime implementation.
- `SimiGoCollection` — read-only Qoder transcript tailing, turn reconstruction,
  durable candidate inbox, and process-level runner lifecycle.

## Qoder collection bridge

The collector reads Qoder transcript files beneath
`~/.qoder-cn/projects` (overridable with `QODER_PROJECTS_DIR`). Its durable
state lives beneath `$SIMIGO_HOME/collectors/qoder`, or
`~/.simigo/collectors/qoder` when `SIMIGO_HOME` is unset. It does not write
to the Qoder transcript tree.

The SQLite inbox commits candidate payloads and transcript cursors in one
transaction. A process-level `flock` lease admits one Runner owner for that
state directory. On normal app termination the lifecycle owner calls
`stop()`; after an abnormal process exit the operating system releases the
lock, and a new process rebuilds open-turn state from the persisted replay
anchor and resumes from the durable inbox.

**Collection is not settlement.** The normal GUI app currently uses
collection-only mode: candidates remain pending in the inbox and are not
written to Information Space. No RULED_ALLOW, WA, or C-policy activation is
performed by this component.

The optional delivery Sink has **at-least-once** semantics. A candidate already
marked delivered is not delivered again after a normal restart. If the Sink
accepted a candidate but the `markDelivered` transaction did not commit before
a crash, it may be delivered again with the same durable candidate key. Sinks
must use that key as their idempotency key; this is not exactly-once delivery.

Before a pending candidate can reach the Sink, its SHA-256 digest is checked
against the exact payload BLOB bytes read from SQLite. A mismatch is treated as
corrupt durable state and fails closed.

## Tests

Run the dependency-isolated collection package tests on macOS:

```bash
swift test --package-path Packages/SimiGoRuntime --filter SimiGoCollectionTests
```

These tests exercise the package boundary and do not launch the GUI App or
write to the user's Information Space. Passing them is not a substitute for
the separate real-Qoder/App quit-and-relaunch lifecycle acceptance.

## Package boundary

This package deliberately excludes research documents, experiment executables,
model weights, and research-only harnesses.
