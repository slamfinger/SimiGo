# Swift Calculator Bridge Spike — G1.0 Read-Only Confirmation

> **Gate:** G1.0 of the Swift Reference Calculator gate (see §6 of this record for
> what G1.1/G1.2 must build).
> **Date:** 2026-10-20
> **Nature:** read-only inspection of the existing Swift surface. No code changed,
> no contract edited, no experiment re-run. Every claim below cites the symbol and
> file it was read from.
> **Question:** can an existing Swift entry point fulfill the frozen formulas A–E in
> `calculator-contract-freeze.jsonl` (contract `SIMIGO-REFERENCE-CALCULATOR-V1`, v1.0.0)?

---

## 1. What the frozen contract requires

| Dimension | Requirement (verbatim basis) |
|---|---|
| Entry | `Callable[[str, dict, dict], dict]` — `calculator(item_id, source_payload, dependency_values)` |
| Output | JSON object, stored verbatim as `settlement.result.value`; v1 domain is exactly `{"swift_value": "<canonical signed base-10 integer>"}` |
| Failure | five stable codes only: `UNSUPPORTED_UNIT_ID`, `INVALID_PAYLOAD`, `DEPENDENCY_SET_MISMATCH`, `INVALID_DEPENDENCY_VALUE`, `ARITHMETIC_OVERFLOW` |
| Numeric domain | signed 64-bit integers; overflow rejected, never wrapped/saturated/truncated |
| Side effects | none: the calculator must not mutate Carrier, IS, sources, dependencies or settlements |
| Events | exactly one `started` then one terminal `completed`/`failed` per invocation; on failure, no successful stdout and nonzero exit |

## 2. What the Swift project actually provides

Three symbols exist; none is a calculator.

| Symbol | Location | Signature | What it does |
|---|---|---|---|
| `MLXPrefixRecomputeExecutor.continueExecution` | `simigo2-experimental/Sources/SimiGo2Experimental/MLXPrefixRecomputeExecutor.swift:72` | `(_ state: ExecutionStateHandle, nextInputTokens: [Int], maxTokens: Int) async throws -> ExecutionContinuationResult` | runs MLX forward over `boundPrefix + nextInputTokens`, greedily generates up to `maxTokens`, invalidates the physical binding, returns token IDs + decoded text |
| `ExecutionContinuityCoordinator.continueExecution` | `.../ExecutionContinuityCoordinator.swift:344` | `(_ state: ExecutionStateHandle, continuation: ExecutionContinuation) async throws -> ExecutionStateHandle` | logical commit only: appends a `continued` record and advances the position; performs no computation |
| `ProductionRuntimeModelContinuationExecutor` | `.../ProductionRuntimeInformationIntegration.swift` (protocol, ~l.21) | `tokenizeText` / `tokenizeSeedText` / `continueExecution` | protocol over the above; `MLXPrefixRecomputeExecutor` conforms |

Exhaustive symbol checks (run 2026-10-20, repository root, `.build` excluded):

```
grep -rn "protocol .*Calculator" --include='*.swift' .        -> 0 hits
grep -rn "Calculator"            --include='*.swift' simigo2-experimental/Sources trackD-memory/Sources -> 0 hits
grep -rn "source_payload|dependency_values|item_id" --include='*.swift' simigo2-experimental/Sources -> only carrier JSON passthrough fields (computed_item_ids, reused_item_ids, validity_failure_item_ids)
grep -rln "ReferenceEchoCalculator" .                          -> 0 hits
```

**There is no Swift `Calculator` type, and no `ReferenceEchoCalculator` symbol in
this repository.** The behaviour that name describes does exist, but in Python:

- `model-level-validation/swift_proxy.py` — a token-prefix echo that *models* a Swift forward (`unit_id -> h<hash>`); its own docstring states it is a faithful model, not the real calculator.
- `model-level-validation/selftest.py` — `unit_real_prefix`, the injected calculator whose physical quantity is token-prefix length.

## 3. Semantic comparison

| Dimension | Frozen contract (A–E) | Real Swift entry (`continueExecution`) | Equivalent? |
|---|---|---|---|
| Input | `item_id` + per-unit payload + named dependency results | opaque `ExecutionStateHandle` + `[Int]` tokens + `maxTokens` | No — no unit identity, no payload, no dependency map |
| Output | `{"swift_value": "<i64>"}` | `ExecutionContinuationResult` (token IDs, text, prefix length) | No — no integer result channel |
| Formula authority | frozen per-unit formulas checked against `calculation_rules` | model weights / MLX forward | No — non-deterministic, no formula at all |
| Failure surface | 5 stable codes | `CoordinatorError` / MLX/IO throws, no code mapping | No |
| Side effects | none permitted | advances physical binding, generates tokens, consumes state | **Directly contradicts** "must not mutate" |
| Determinism | byte-identical canonical result for identical input | sampling-dependent | No |

The mismatch is not cosmetic. `continueExecution` is a *model continuation
executor*; the frozen contract is a *deterministic integer oracle*. Wrapping one as
the other would manufacture an equivalence claim that no evidence supports.

## 4. Verdict

1. **No existing Swift entry can serve as the frozen calculator.** G1 must not wrap
   `ExecutionContinuityCoordinator` or `MLXPrefixRecomputeExecutor` as "the Swift
   Calculator".
2. **The project Calculator remains unidentified.** Nothing in the Swift sources
   implements the A–E formulas, so "Swift 端执行了这份合同" and "项目实际计算器
   被执行了" are two different claims. G1 only targets the first.
3. **A test-only Swift Reference Calculator must be built** — a separate,
   self-contained executable that implements the frozen contract, emits its own
   events, and is addressed over a fail-closed subprocess boundary. It is a test
   oracle, not a production component and not evidence about the project Calculator.
4. Any earlier probe result (`swift_proxy.py`, `unit_real_prefix`, an echo-style
   fixture) is **transport evidence only** and must not be cited as calculator
   evidence.

## 5. What G1 will and will not prove

| Claim | G1 status |
|---|---|
| The frozen contract can be implemented in Swift and produces the frozen vectors | G1.1 target |
| The Python Carrier can call a Swift process through a fail-closed adapter and keep its recompute/reuse/settlement semantics | G1.2 target |
| Swift failed calls propagate and the Carrier transaction rolls back | G1.2 negative test |
| The project's real Calculator is equivalent to the frozen contract | **Out of scope** — no such Calculator exists in the repo |
| Old KV cache released; IS restores a new Execution State; real model continues incrementally | **Out of scope** — this is G2 |

## 6. Interface fixed for G1.1 / G1.2

Decisions taken here so the implementation needs no further design:

- **Form:** standalone SwiftPM executable, `g1-swift-reference-calculator/`, no
  dependency on `simigo2-experimental` (no manifest change to an existing package).
- **Transport:** one process per call. Request JSON on stdin, response JSON on
  stdout, events appended to a JSONL file passed with `--events`.
- **Request:** `{"mode":"compute","invocation_id":...,"item_id":...,"source_payload":...,"dependency_values":...}`
  and `{"mode":"canonicalize","invocation_id":...,"value":...}` for the single
  canonicalization vector.
- **Exit codes:** `0` success, `2` contract error (stable code in stderr JSON),
  `3` malformed request, `4` internal failure. Never a successful stdout on error.
- **Identity:** the executable computes its own SHA-256 at runtime and emits it in
  every event, alongside a compile-time `build_id`; the harness pins the same hash
  independently before the run.
- **Adapter:** Python side raises on any non-zero exit; there is no Python fallback,
  no retry-with-oracle, and no default result.
