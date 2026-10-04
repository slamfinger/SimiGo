# Information Reduction Round 1 Result

Date: 2026-10-05<br>
Status: `17 / 17 CONDITIONS EXECUTED / RAW OUTPUTS SEALED / BEHAVIOR ADJUDICATED / OBSERVER NOT RUN / STORE NOT RUN`

## 1. Execution

Run root:

```text
docs/02-evidence/local-execution-information-closure/task-carrier-tc-a/runs/20261004-210000-round1
```

The original run completed 14 of 17 arms. It was interrupted after external
NativeMLX unload/restart prevented the next expected idle-suspend observation.
The remaining three `RD9-*` arms were resumed under separately authorized
180-second intervals. Every arm returned HTTP 200 and recorded a cold path with
`cacheHitTokens=0` and `reuse=false`.

The resumed outputs were initially written one directory above the canonical
task-carrier root because of a runner path-resolution error, then moved
unmodified into the canonical Round 1 run root. The relocation is recorded in
`resume-record.json`.

## 2. Frozen PASS criterion

PASS required all of:

```text
valid minified JSON;
release_decision = blocked;
deployment_order = [alpha,beta];
blocked_services = gamma.
```

## 3. Results

| Design | Conditions | Result |
|---|---|---|
| R-D2 representation | RAW / DECODED-TEXT / SEMANTIC-OBJECT | PASS / PASS / PASS |
| R-D5 explanation | ABSENT / PRESENT | PASS / FAIL |
| R-D1A aggregation | WHOLE-REGISTER / STRUCTURED-FACTS | PASS / PASS |
| R-D3 M2 deletion | M2-DELETED | FAIL |
| R-D4 M1 factorial | ALL / GAMMA-ONLY / ABSENT | PASS / PASS / FAIL |
| R-D8 source hashes | VALID / STALE / ABSENT | FAIL / FAIL / PASS |
| R-D9 tool evidence | PRESENT / ABSENT / SUMMARY | FAIL / PASS / PASS |

All 17 final answers were directly valid JSON. Failures were continuation
failures, not JSON parse failures.

## 4. Bounded readings

```text
R-D2: raw, decoded-text, and semantic-object representations
      all supported the same bounded continuation.

R-D5: explanation absence PASS;
      explanation presence was followed by empty deployment order.

R-D1A: whole-register and structured-facts packaging both PASS.

R-D3: M1.b alone failed; M2.b pair decisions are required.

R-D4: all-M1 and gamma-only M1 PASS when M2.b is present;
      M1 absent FAIL.

R-D8: valid/stale hashes produced empty order while absent hashes passed;
      hash validity/staleness had no stable protective effect in this run.

R-D9: full tool evidence failed while absent/summary evidence passed;
      tool evidence was not required in this frame.
```

The Round-1 evidence formally places the earlier M1.b finding into a wider
factorial frame: `gamma-only M1.b + M2.b` PASS, while `M1.b without M2.b`
FAIL and `M2.b without M1.b` FAIL in the tested arms. Thus the successful
narrow core is the conjunction, not either field alone.

## 5. Interpretation boundary

PASS/FAIL readings are bounded to:

```text
this exact prompt set;
this model;
this TC-A release-gate frame;
the direct-inline delivery surface;
single-run observations.
```

Differences such as explanation-present failure, valid/stale hash failure, and
full-tool-evidence failure must not yet be promoted to stable causal laws. They
require repetition and counterfactual controls before such a claim.

## 6. Boundary

```text
Observer                 = NOT RUN;
InformationCore store    = NOT RUN;
schema/API change        = NOT MADE;
raw outputs              = UNMODIFIED;
universal minimality     = NOT CLAIMED;
experimental irreducibility = NOT CLAIMED.
```
