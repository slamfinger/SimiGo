# K2 Evidence Report — Native `digest_equals_binding` Aligned to Production and Landed

Run label: `es-is-native-result-contract-20261023k2`
Date: 2026-10-23 (local macOS, Swift 6.x toolchain, MLX Qwen3-Coder-30B-A3B-Instruct-4bit)
HEAD under test: `e7f63856298390deb8596a4a30e173d3fb466eaa` (unchanged; staged = 0)

## 1. Research question this increment serves

How does an already-settled semantic result leave its old execution context, be
restored in a new Execution State through the Information Space, and continue
incrementally — rather than bolting on yet another verification framework. K2
narrows one concrete Python/Swift capability gap found in K: the native
result-contract engine did not implement `digest_equals_binding`.

## 2. Claim tiers

- **Fact (measured on this machine, re-verifiable from on-disk evidence):**
  the items in section 4 and the verifier result in section 5.
- **Conclusion (follows from the facts):** the native engine now performs the
  `digest_equals_binding` check with the same canonical-JSON SHA-256 convention
  and the same *direction* as the production Python gate; the K2 change did not
  weaken any prior gate.
- **Assumption:** the delivered ZIP/patch was authored against a Linux Swift
  6.2.1 environment; the pure-Swift SHA-256 fallback and the CryptoKit path were
  both exercised here on macOS (see §4.2).
- **Authorization boundaries respected:** no `git add`, no commit, no change to
  `carrier_loop.py` recompute semantics, no touch to prior-round run roots
  (`…20261023k` left intact; K2 uses a new `…20261023k2` root).

## 3. What the delivered patch actually was, and the one correction

The ZIP applied cleanly and supplied correct **infrastructure**:
`canonicalJSONData()` (JSONSerialization `.sortedKeys/.withoutEscapingSlashes/
.fragmentsAllowed`), a portable `NativeSHA256`, a CryptoKit-first digest path, and
`digest_equals_binding` acceptance in `validateDefinition`.

But its **constraint direction was inverted** relative to production. The patch
implemented `field == SHA256(canonical(binding))` (binding holds the raw value).
The real production bridge (`production_runtime_bridge.py`, secret/commitment
contract, lines ~681–696) and the Python gate (`declarative_result_contract.py`
lines 252–265) both mean **`SHA256(canonical(field)) == binding`** — the extracted
field is the raw value and the IS-verified binding carries the *committed digest*
(e.g. a dependency's `secret_sha256`). Shipping the patch as-is would have
rejected the real production contract. Per the integration guide's hard
prerequisite, the direction was corrected to the production/Python semantics
before landing, and the direction-sensitive native unit tests were rewritten to
match. This correction is why the patch was **not** shipped verbatim.

Digest byte-parity was verified independently:
`SHA256(canonical("NORTH>EAST")) = 2b1a5d9f0a1183c966ce8325a252424579a625c1b2314654dd6aaebaf9c334a8`
and `SHA256(canonical("café")) = 28380feb8724d669bc8d4cf5b5a5bb1adbdc61b81ebd06f3fabc567b4f3b0fc5`
match between the Python helper and the native engine.

## 4. What actually ran on this machine

| # | Action | Evidence |
|---|--------|----------|
| 4.1 | `git apply` of the digest patch onto the current engine + tests | engine defines `digest_equals_binding`; 21 native tests present |
| 4.2 | Native direction corrected to `SHA256(canonical(field)) == binding` + tests flipped | `NativeDeclarativeResultContract.swift:437-458`; `swift test` 21/21, exit 0 (macOS, CryptoKit + portable SHA-256) |
| 4.3 | 4 new cross-language parity cases (string VALID, non-ASCII VALID, digest-mismatch REJECT, missing-binding REJECT); expanded fixture 32 → 36 | `compare_native_python_parity.py` issue_count **0** over `cases_sha256 = 68dab430…` |
| 4.4 | N2 counterfactual re-pointed from `digest_equals_binding` to `equals_binding_segment` (Python implements, native does not) | native refuses `CONTRACT_UNKNOWN_CONSTRAINT` at `PRODUCER_RESULT_CONTRACT`; Python returns VALID for the same kind |
| 4.5 | Stale notes updated (bridge `--u1-constraint-kind` docstring, parity fixture `applies_to` / `declared_divergences`, driver docstring) | digest now listed in the shared family; `equals_binding_segment` is the sole Python-only declared divergence |
| 4.6 | Regression + verifier made robust to the suite growing 16 → 21 (derive expected count from the test file, not a magic number) | driver records `expected_tests/executed/failures`; verifier re-derives on-disk count independently |
| 4.7 | Driver now persists the RAW comparator output to `parity/parity_verify.json` so the verifier re-reads it, not the narration | file present with issue_count 0 |
| 4.8 | Fresh relink of `SimiGoTaskRun` with the digest-capable engine | `binary_sha256 = f88e866e9da8674826a3ce099a01b3335349c7cd95fbe64f3ea461fb4b0556d7` |
| 4.9 | Real-model K0: three fresh processes | run token `86281eba`, items `J-86281eba-U1/U2/U3` |

### K0 per-stage (native gate as pre-settlement authority)

| Stage | Item | native_status | bindings from IS | native==python | native==settled | IS bindings | settled | signed |
|-------|------|---------------|------------------|----------------|-----------------|-------------|---------|--------|
| P1 | J-86281eba-U1 | VALID | True | True | True | 3 | True | True |
| P2 | J-86281eba-U2 | VALID | True | True | True | 1 | True | True |
| P3 | J-86281eba-U3 | VALID | True | True | True | 1 | True | True |

K0 exercises the native `concat` route-synthesis family (the ordinary production
contract). `digest_equals_binding` parity is proven by the cross-language gate
(§4.3) and the native unit suite (4.2), not by a real-model K0 stage — stated
plainly to avoid over-claiming.

### N2 counterfactual (native fail-closed on a genuinely unsupported kind)

- Declared kind: `equals_binding_segment`
- Native: `CONTRACT_UNKNOWN_CONSTRAINT` / stage `PRODUCER_RESULT_CONTRACT`, field
  `route_key`, detail `… unsupported constraint kind equals_binding_segment`
- `model_continuation_calls = 1` (a real generation ran **before** the refusal)
- `valid_settlement_created = False`, `signature_created = False`
- Python gate for the same kind: `VALID` (so the refusal is native-authority, not
  a shared "unknown" verdict)

## 5. Independent acceptance

`validate_k_evidence.py` re-derives acceptance from raw on-disk artifacts
(re-hashes the binary vs recorded `binary_sha256`; re-hashes the expanded fixture
vs recorded `cases_sha256`; re-reads `parity_verify.json`; re-parses the N2
failure string; re-derives the native test count from the test file; checks K0
each stage VALID + bindings-from-IS + both agreements + settle+sign and N2
refusal/derivation). Result:

```
{ "result": "PASS", "issue_count": 0, "issues": [] }
```

## 6. Conclusion

The K2 increment is proven on production integration and a real run, not only on
standalone Swift tests: the native engine now enforces `digest_equals_binding`
with the same canonical-JSON SHA-256 convention and the **same direction** as the
production Python gate (36-case parity issue_count = 0 including digest and
non-ASCII vectors), while remaining fail-closed on a kind it genuinely does not
implement (`equals_binding_segment`, exercised end-to-end through the real
three-process model run). The native pre-settlement authority path is unchanged
and still agrees with Python and the settled IS value across all three stages.

## 7. Honest limits

- **Not staged, not committed.** HEAD `e7f63856` unchanged; staged = 0.
- **The delivered patch was not shipped verbatim** — its digest direction was
  inverted vs production and had to be corrected first. A reader comparing the
  ZIP to the worktree will see that intentional divergence.
- **Native is still narrower than Python.** `equals_binding_segment` remains
  Python-only (now the N2 demonstrator). Retiring the parallel Python gate still
  requires porting it (and any other Python-only kinds) first.
- **Digest parity scope.** String and non-ASCII digests are covered by
  cross-language parity through real field extraction; the nested-object digest
  case is covered by the native unit suite (`hexDigest`), because a nested object
  is not a value a regex field can extract from result text.
- **Single model snapshot** (Qwen3-Coder-30B-A3B-Instruct-4bit, snapshot
  `6e302ea6…`), `match_policy = "first"`.
- **Release-mode 21/21 not reproducible on this macOS box, for an unrelated
  pre-existing reason.** `swift test -c release` fails to compile the whole test
  target because `OversizedSegmentedEngineRestoreAtomicityTests.swift` calls
  `OversizedSegmentedEngine.makeRestoreAtomicityTestFixture`, which is confined
  to `#if DEBUG` in the source (lines 223–317) and thus absent in a release
  build. That file has **zero** digest / native-contract references and is
  outside K2's authorized scope, so it was left untouched. The native contract
  suite itself runs green in debug here (`swift test --filter
  DeclarativeNativeResultContractTests` = 21/21, exit 0), which is the build the
  parity harness, K gate and regressions all use.
- **Re-running the model-free H/I/J/admission selftests refreshed some experiment
  data artifacts** (`.carrier-arm*.sqlite`, `arm*.jsonl`, `.last_judgment.json`).
  Those are run state, not frozen source; `carrier_loop.py` was not modified by
  K2 (its mtime precedes every K2 edit) and the prior `…20261023k` evidence root
  was left untouched.
