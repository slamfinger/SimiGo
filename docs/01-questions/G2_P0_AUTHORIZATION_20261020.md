# G2 P0 — Model Load and Observation Capability Probe: Authorization Record

> **Status:** `AUTHORIZED — ONE MODEL START · NO RETRY` (issued 2026-10-20)
> **Parent design:** `docs/01-questions/G2_PREREGISTRATION_20261020.md` (`FROZEN — EXECUTION NOT AUTHORIZED`)
> **Artifact binding:** `docs/01-questions/G2_MODEL_BINDING_20261020.json`
> **What this record authorizes:** P0 only. It does not authorize P1, P2, P3, any fixture run, the 3 × 3 matrix, or a batch manifest.

## 1. Authorized acts

P0 may do exactly these four things, and nothing else:

1. Load the frozen artifact named by the binding, once, through the target `ChatSession` stack, under the pinned backend revisions. No retry, no model substitution, no silent fallback to another directory.
2. Establish whether the `ChatSession` path and the cache-observation hook G2 depends on are really available: load, render the chat prompt, generate, install `MLXPrefixCrossSessionCache` on an empty store base, and read `observations`.
3. Record load result, runtime environment, actual artifact identity, observation capability and any error as a named terminal state.
4. Stop there. No `U1`, no `U2`, no fixture payload, no arm, no batch authorization, no completion marker.

## 2. Budget: two separate ledgers

| Ledger | Amount | Transferable? |
|---|---|---|
| **P0 model starts** | **1** | no |
| P0 retries | 0 | — |
| P0 generations inside that one process | 2 (declared: (a) baseline generation without a hook, (b) one generation under the installed hook on an empty store) | no |
| **G2 batch model starts** | 9 planned / 15 hard cap, per §5 of the design | not affected by P0 |

The P0 start is not drawn from, and does not enlarge, the batch cap. A failed P0 does not license a second P0 start under this record; it returns the design for amendment and needs a new authorization. `P0` producing `PASS` also does not issue a batch authorization — that remains a separate act (§9).

## 3. Terminal states

The probe writes `terminal.json` with exactly one of:

- **`PASS`** — artifact rows match the binding (17/17 files, bytes and SHA-256, aggregate `4c1bd759…`), engine content identity was read and its weights digest equals the value derivable from the binding rows, the container loaded, the chat prompt rendered, both generations produced a chunk sequence and a completion token count, the hook installed, and on the hooked generation `observations.calls > 0` with `hits == 0`.
- **`FAIL`** — the artifact mismatched, loading raised, prompt rendering raised, a generation raised, hook install raised, or the observed counts contradict the empty store. `FAIL` is a statement about the capability, not about the run's cleanliness.
- **`INCONCLUSIVE`** — the run left no usable verdict: the child died without writing a record (external kill, OOM, crash) or evidence is incomplete. Only the parent runner may write this, and only when `terminal.json` is absent.

State rules that carry over unchanged from the design: no retry, no substitution, no matrix expansion. Evidence is write-once; a later disagreement is appended as an adjudication record, never written back into the run facts.

## 4. Evidence

```text
execution-information-loop/experiment/continuous-calc-verification/model-level-validation/g2/
  p0/<run-id>/
    AUTHORIZATION.json          # digest of this record + scope actually exercised
    AUTHORIZATION.consumed      # atomic rename immediately before the child launch
    artifact_check.json         # per-file rows vs binding, aggregate recomputation
    build.json                  # product SHA-256, Package.resolved pins, revision, clean flag
    P0_PROBE.json               # facts written by the probe (write-once)
    terminal.json               # PASS | FAIL | INCONCLUSIVE (write-once)
    RUN_VERIFICATION.json       # parent's independent recheck of the probe facts
    run.log                     # child stdout + stderr, unmodified
```

`AUTHORIZATION.consumed` existing means the P0 start is spent. The evidence root is created already-populated-by-nothing: it must not exist before the runner creates it.

## 5. Prohibitions carried into this authorization

- No change to any Frozen Contract, to `calculator-contract-freeze.jsonl`, or to the Carrier.
- No change to G1's `CLOSED` record; G2 evidence never enters `g1-evidence/`.
- No signer movement, no R27 change, no production claim.
- No model download path: the artifact is read from the local cache only; network access during the run is false.
- No push of local commits.

## 6. Source touched by P0

The probe is a **new, separate SwiftPM package** under the experiment tree. `simigo2-experimental` is consumed as a path dependency; its `Package.swift`, its sources and its existing products are not modified. The engine identity reading is obtained through the already-public `MLXPrefixCrossSessionCache.contentIdentity(modelDirectory:)`, which delegates to `EngineModelIdentity.compute` — so the probe records the engine's own digest without adding an accessor to the library.

Order of operations: commit probe and this record → build `-c release` → verify artifact and pins → consume authorization → one model start → record → human audit → commit run evidence.
