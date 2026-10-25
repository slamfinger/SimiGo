# Actual code-path audit (model / KV ownership, entry, ES, IS, trust material)

Required by the task pack before any source edit: record who really holds the model context and
the KV/cache, where `continueTask` is called, where the Execution State and its checkpoint are
established, where the Information Space is written and read, and where the signing key and the
trust anchor live. Every line below was re-checked in this session against the delivered sources
in `../source/files/`; nothing here is inferred from names. Disclosure: the path audit was done
before the source edits, but it was not persisted as a document at that time; this file is a
re-verification of the same facts in the closing pass, and it is the record. Where an earlier
summary and the current code disagree, the current code wins and is what is written here.

## 1. Model loading and the real holder of the model context

| fact | where |
| --- | --- |
| the only model load in the experiment path is one `loadContainer` per process, from the existing Hugging Face snapshot directory | `Sources/SimiGoTaskRun/main.swift:347` (`LLMModelFactory.shared.loadContainer(from: options.modelDir, …)`) |
| the loaded container is held by exactly one object per process: `MLXPrefixRecomputeExecutor.container` (`ModelContainer`) | `Sources/SimiGo2Experimental/MLXPrefixRecomputeExecutor.swift:45`, init at `:118-121` |
| tokenize / generate / decode all run inside `container.perform { (context: ModelContext) in … }` — the `ModelContext` (model + tokenizer) is the real owner, borrowed per call, never copied into the Execution State | `MLXPrefixRecomputeExecutor.swift:125`, `:133`, `:150`, `:173` |
| the runner wraps that executor in a counting adapter, so model-call counters sit on the real call sites | `Sources/SimiGoTaskRun/main.swift:352-353` (`MLXExecutionStateBackend()` then `CountingModelExecutor(base: MLXPrefixRecomputeExecutor(...))`), counters recorded in `ProductionRuntimeInformationIntegration.continueTask` |

Consequence for this round: the model context has exactly one owner per OS process and no shared
long-lived holder above it, so "the producer's context is gone" is equivalent to "the producer
process exited", and nothing in the consumer path can reach it.

## 2. Where the KV / cache actually lives

* The ordinary production path used by this round **passes no KV cache at all**:
  `MLXPrefixRecomputeExecutor.continueExecution` forwards with `context.model(running, cache: nil)`
  (`MLXPrefixRecomputeExecutor.swift:155`) and re-feeds the whole token list each step
  (`tokens = tokens + [nextToken]`, `:161-162`). This is the recompute path; `carrier_loop`'s
  recompute semantics were not touched.
* Per-layer `KVCacheSimple` arrays exist only on the G3 arm path, owned by
  `G3ArmCacheSession` / `MLXKVCacheBoundary` / `G3KVAllocationGateway` and installed into
  `g3CacheSlot` by `G3DualArmRunner` (`MLXPrefixRecomputeExecutor.swift:64-84`, `:431`). The code
  itself states that `nil` there means "no KV observed", never "verified isolated" (`:70-71`).
  The F round does not use that path, so it cannot and does not claim an observed KV deallocation.
* What does persist across a call is the **token prefix**, owned by `MLXExecutionStateBackend`:
  `prefixes: [ExecutionID: [Int]]`, `boundPositions`, `retiredCarriers`
  (`MLXExecutionStateBackend.swift:30-36`), plus its durable form written by
  `DurableExecutionStateStore` (`DurableExecutionStateStore.swift:26`) rooted at the instance's
  `semanticStateDirectory` (`ProductionRuntimeInformationIntegration.swift:417-419`).
  A backend instance is created per process (`Sources/SimiGoTaskRun/main.swift:352`), and the
  consumer's state directory is provably empty before it starts.

So the only "old context" a detached consumer could inherit is a persisted prefix in the state
directory or a bound entry in a live backend. The F evidence closes both: empty consumer directory
before start, and the producer process exited and was reaped (`PROCESS_ADDRESS_SPACE_DESTROYED_ONLY`,
which is exactly what §4 of the report is allowed to claim).

## 3. `continueTask` call sites and its internal order

* Single production call site used by both processes: `Sources/SimiGoTaskRun/main.swift:383`
  (`integration.continueTask(database:, handle: nil, …)`), i.e. the ordinary task entry, no
  handoff-specific orchestration.
* Inside `continueTask` (`ProductionRuntimeInformationIntegration.swift:1110`):
  1. `resolveTaskInput` admission **before anything else** (`:1122`, defined `:1491`);
  2. fail-closed ES↔IS checkpoint cross-check (`:1126-1141`, `validateSettlementAgainstInformationSpace` `:666`);
  3. tokenize the admitted input text (`:1151`);
  4. create-or-attach: with `handle == nil` it tokenizes the seed and **creates** the state under
     `self.taskExecutionID` at `ExecutionPosition(0)` and binds the seed prefix (`:1211-1230`);
  5. model call (`:1240`), value + provenance files (`:1248-1265`);
  6. IS settle (`:1268`), logical advance (`:1335`), rebind of the advanced representation
     (`:1347`), carrier confirmation (`:1355`), ES↔IS settlement checkpoint (`:1397`).
* A failure after the model boundary records a blocked state (`failPending`, `:1171`) and restores
  the pre-model representation (`:1363-1378`); a failure at admission happens before any of that.

## 4. Information Space write / read paths

* Read (model input): `resolveTaskInput` → bridge `resolve-model-input`
  (`ProductionRuntimeInformationIntegration.swift:1491`), whose Python side is
  `production_runtime_bridge.py` opened with `require_provenance=True` (`execute()` at `:225`) and
  which expands the item's own `{placeholder}` template from verified settlements only.
* Write: `runBridge("execute-with-model-result", …)` (`:1268`) then
  `confirm-runtime-application` (`:1355`); `runBridge` is defined at `:447` and launches
  `/usr/bin/python3 production_runtime_bridge.py` with the configuration environment merged over
  the inherited one.
* `readItem` (`:1717`) is used only to fetch the task item's own prompt seed and result contract
  (`Sources/SimiGoTaskRun/main.swift:370` and `:377`); no settlement is read by the harness, and the
  driver never builds a model input.

## 5. Signing key and trust anchor

* Deployment trust anchor and signing key are **environment-supplied paths outside the database**:
  `SIMIGO_SETTLEMENT_TRUST_ANCHOR`, `SIMIGO_SETTLEMENT_SIGNING_KEY`; the policy is read by
  `execution-information-loop/settlement_provenance.py:load_policy()` (`required` needs both and a
  matching `key_id`, `verify` needs the anchor only, default `off`).
* The launch configuration exports the anchor to the bridge child
  (`ProductionRuntimeInformationIntegration.swift:314-323`); the key must come from the inherited
  process environment, so `run_phase_f.py` provisions the two files under `trust/` and exports both.
* The consumer admits under `verify` and produces under `required`
  (`Sources/SimiGoDetachedDriver/main.swift:263-275`). Swift-side Ed25519 verification of the
  dependency settlement is in `Sources/SimiGo2Experimental/SettlementProvenanceVerification.swift`
  with the anchor fallback resolution at `ProductionRuntimeInformationIntegration.swift:1651`.
* Because both processes can sign their own output, "the consumer did not re-mint the dependency"
  is proven by settlement **object-address equality** (`consumer_did_not_remint_u1_object`), not by
  key withholding; the aborted attempt `attempts/aborted-20261022-073059Z` is the preserved evidence
  that a signing-incapable consumer cannot settle at all.

## 6. What the audit ruled out

* No long-lived parent object holds the producer's engine/context/cache: the driver is a separate
  process that only `waitUntilExit()`s on its children
  (`Sources/SimiGoDetachedDriver/main.swift:160-210`, the wait at `:197`), and it refuses to start if the consumer
  state directory is not empty (`:245-261`).
* No bypass channel: nothing reads a settlement to build the U2 prompt; the only channel into the
  model input is step 1 of §3.
* `executionID` is not being used as "proof of a new ES": the static default identity
  (`ProductionRuntimeInformationIntegration.swift:332`) stays what it was, and the per-instance
  `taskExecutionID` (`:336`) is what advances, which is what
  `DetachedContinuationEntryTests.testPerInstanceIdentityCreatesItsOwnColdStateFromInformationSpaceInput`
  now pins down with a stub recorder.
