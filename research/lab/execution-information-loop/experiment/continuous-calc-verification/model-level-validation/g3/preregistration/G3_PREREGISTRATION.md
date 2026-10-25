# G3 Pre-registration — ES+IS vs IS-only, one variable

Status: **FROZEN, not executed.** Model execution is **not** authorized by this
document. Frozen machine record: `preregistration/G3_PREREGISTRATION.json`
(sha256 `30f977cc4def7d3951b78f2df209454916fca4884a19877d702180283b486972`).

## 1 The question

Everything up to W3 answers "can the core API run the loop". G3 asks the
different question the plan forbids pre-deciding:

> On a controlled multi-step task, does the *persisted execution state* add
> anything to what the *information space alone* can express?

It is a comparison, not a demonstration. The harness reports what each arm
answered; it does not decide that a divergence is a proof of anything.

## 2 Common conditions (held identical)

Same model copy, same frozen checker (`g2/batch/checker.py`, sha256
`bc453515789a432d`), same task goal, same declared unit rule, same source
version, same sealed validity policy, same validity window, same
`evaluated_at_utc`.

The initial IS is identical *by construction*: one prefix carrier is built once,
copied twice, and the two copies are hash-compared before either arm runs
(`initial_is_bytes_identical`). No arm starts from a hand-built approximation of
the other.

## 3 The only difference

| | ES+IS | IS-only |
| --- | --- | --- |
| continuation position | `restore_continuation()` on persisted execution states | derived from items and settlements only |
| obligation text | the restored demand's declared `pending_obligations` | derived from the declared obligation→item mapping |
| ES access | full | **none** |

`ISOnlyView` is a whitelist proxy: every attribute outside the IS surface raises
`AssertionError` and is recorded. `is_denied_touches` must stay empty, and the
dry run shows that it does.

The restriction is enforced rather than promised, but it took a revision to make
that sentence true. The whitelist first ran in `__getattr__`, which fires only
after normal attribute lookup fails — so `view._loop` returned the wrapped
carrier directly, `restore_continuation` and every other ES entry point were
reachable through it, and `denied` stayed empty. The isolation assertion would
have passed against an arm that was never restricted. The hook is now
`__getattribute__`, attribute writes are refused too, and the four measurements
below hold the guarantee:

| check | what it measures |
| --- | --- |
| `proxy_refuses_inner_loop_and_es_entries` | `_loop`, `carrier`, `restore_continuation`, `define_demand` all raise |
| `proxy_refuses_attribute_write` | the arm cannot replace a whitelisted method |
| `arm_writes_do_not_cross_to_the_other_arm` | a probe item and settlement written to the ES carrier are invisible to the IS carrier — separate files, measured rather than asserted |
| `shared_fixture_inputs_not_mutated_by_either_arm` | the fixture, the one legitimately shared object, is fingerprinted before and after both arms |

A formal run adds one precondition the stub cannot demonstrate: each arm gets its
own model instance, and no KV cache, prefix cache, tokenizer handle or weight
buffer may be reachable from both. Warming the other arm through a shared cache
would be a hard precondition failure, not a retry.

The IS-only arm *is* given the task specification (the declared obligation list
and its discharging items). Denying it the question would make the comparison
rigged in the other direction; the interesting variable is where the arm learns
its **position**, not whether it was told what the task is.

## 4 Unit chain

`U1 → U2 → U3`, plus `U_free` as unrelated information:

```
d1  [U_free, U1]      U_free REUSE, U1 COMPUTE        U2, U3 still UNSETTLED
d2  [U2]              U2 COMPUTE                      U3 still UNSETTLED
    --- update_source(U1, v2): an IS mutation, not an ES transition ---
d3  [U1, U2]          U1 and U2 COMPUTE               U3 still UNSETTLED
d4  [U3, U_free]      U3 COMPUTE, U_free REUSE
```

The edge set is frozen here, not chosen by the harness:

| item | depends on |
| --- | --- |
| `U1` | — (it is the source-change target) |
| `U2` | `U1` |
| `U3` | `U2` |
| `U_free` | — |

An edge `X ← Y` means X's settlement records Y's settlement object id in
`result.dependency_object_ids` and its value is a function of Y's settled value.
That is what makes the `d3` prediction falsifiable: changing `U1`'s source
changes `U1`'s settlement id, which is recorded inside `U2`'s basis, so `U2`
must recompute, and `U3` follows through `U2`. `U_free` has no edge, which is
exactly why it can serve as the independent sibling.

The harness reads this table from `G3_PREREGISTRATION.json` on every run and
refuses to run if its own `UNIT_INPUTS` disagree
(`dependency_graph_matches_harness`, `independent_sibling_has_no_edges`). A
harness that quietly used other edges would be measuring a different plan than
the frozen one, so the comparison is part of the run rather than a convention.

Every step is checked against four frozen sets, declared on a basis that does
not depend on which arm runs: the current settlement object id of each item in
`[U1, U2, U3, U_free]`.

| set | definition |
| --- | --- |
| recomputed | the id differs after the step |
| reused | the id is unchanged **and non-empty** |
| unsettled | there is no settlement on either side |
| blocked | the step refuses |

The `blocked` column is empty by design, and the assertion is stronger than an
empty set: both arms must report `state == ADVANCED` at every formal step
(`blocked_set_is_empty_on_the_formal_arms`), so an unplanned block fails the
step instead of leaving a set quietly empty. Blocking is measured by the
negative controls, each on its own copy, not by the formal arms.

The `unsettled` bucket is not bookkeeping. Without it, `U3` in `d1`–`d3` would
sit in the reuse set purely because it has no settlement on either side, and a
plan could satisfy a reuse expectation by having nothing happen. The four sets
must partition the universe after every step, and the harness asserts that too.

Frozen unit rule: each unit carries the upstream `secret`/`site`, relabels
itself, and emits `ANSWER=<secret>-sha256(site.lower())[:8]`. The answer line is
checked by the frozen G2 checker **verbatim**; the settled value differs per unit
only through its `unit` label, so recomputation is observable by settlement
object id and action, never by value drift.

Selective propagation is what `d3`/`d4` prove: `update_source` invalidates U1,
U1's new settlement id invalidates U2, and `U_free` keeps exactly one settlement
revision across the whole run. `U_free` is the independent sibling: `U1` is the
source-change target, so it cannot play that role, and `U3` is downstream of U2.
Without `U_free` the design would only show that an unaffected *upstream* item
stays reused, which is a weaker claim.

## 5 Negative controls

Each control uses its own copy and never shares state with a formal arm.

| case | mechanism | expected |
| --- | --- | --- |
| expired settlement | gate subprocess | `REFUSED / VALIDITY_EXPIRED` |
| tampered settlement | gate subprocess | `REFUSED / OBJECT_DIGEST_MISMATCH` |
| missing settlement | in-process reuse predicate | `not reusable`, `MISSING_OR_SUPERSEDED_SETTLEMENT` |
| blocked state | in-process | `BLOCKED_STALE_VALIDITY`, then `restore_continuation` refused |

Only two controls per fixture are processes, which is why the budget below counts
`2 fixtures × 2 = 4` gate processes rather than four per fixture.

## 6 Budget, computed before authorization

| stage | slots per arm |
| --- | --- |
| U1 initial | 1 |
| U2 | 1 |
| U1 + U2 after the source change | 2 |
| U3 terminal | 1 |
| **subtotal** | **5** |

`2 fixtures × 2 arms × 5 = 20` model-start **slots** (design units); `4` gate
processes; cap `24`; **0 retries**. Any identity or precondition failure
invalidates the whole batch — it is never retried. A formal run converts each of
the 20 slots into one model start.

The approved plan states this in one sentence, quoted verbatim:

> `2 fixtures × 2 arms × 5 = 20` 次模型启动；负向控制 `2 fixtures × 2 = 4` 个 gate 进程；总进程上限 24，0 重试。

The word "start" in that sentence names a **design slot**, not an executed model
process. In the dry run the same slot is counted as one calculator invocation,
and no model is loaded, so the two numbers must never be conflated: 20 is the
slot count, 0 is the executed-start count. A formal run converts each slot into
one model start under a separate authorization. The plan contains no 12-start
table; its three numbers are 20 slots, 4 gate processes and a cap of 24.

**Measured with the stub calculator, before freezing:**

| quantity | predicted | measured |
| --- | --- | --- |
| calculator invocation slots (design unit) | 20 | 20 |
| **actual model starts** | **0** | **0** |
| gate processes | 4 | 4 |
| retries | 0 | 0 |
| initial IS bytes identical | true | true |
| ES-arm slots per fixture | 5 | 5 |
| IS-arm slots per fixture | 5 | 5 |

Record: `G3_DRY_RUN_RESULT.json`. The measurement matches the arithmetic, so the
budget is frozen as written. The dry run starts no model: `actual_model_starts:
0`, `is_execution_evidence: false`; the record names the two quantities apart
(`measured_calculator_invocations` / `actual_model_starts`) so that no reader can
mistake a slot for an execution.

## 7 Decision rules (fixed before any run)

1. All three outputs agree on every probe → record
   `ES_INDEPENDENT_CONTRIBUTION_NOT_PROVEN`. It is not rewritten as
   "mechanism works".
2. Any output diverges → record the divergence verbatim. A divergence is an
   observation, not a proof; the interpretation stays with the reviewer.
3. The IS arm must be as well instrumented as the ES arm. If its per-step compute
   counts differ from the ES arm's, the comparison is `INCONCLUSIVE`, not a win
   for ES.
4. A fixture that fails an evidence-identity, prefix-byte or window check is
   `INVALID` and contributes no comparison.

Pre-registered expectation, recorded so it can be checked rather than assumed:
`final_result` and `open_obligations` should agree at every probe;
`next_step` **may** diverge where a declared step exists whose required items are
already settled, because IS alone cannot tell a declared step boundary from a
satisfied one. The dry run in fact shows exactly that: agreement everywhere
except the `d2` probe, where the ES arm's next step is `d3` and the IS arm's is
`d4`.

## 8 What a G3 result would and would not mean

Would mean: on this task graph, with these two arms, these three answers, one
arm needed persisted execution state and one did not — stated per output, not as
a verdict on the architecture.

Would not mean: that the core API is unnecessary if the answers match; that ES is
independently valuable if they differ; that G2 is reproducible; that any execution
evidence was produced by the dry run.

## 9 Authorization boundary

Frozen pre-registration ≠ execution authorization. Starting the 20 model
processes requires a separate, explicit authorization. The harness ships with the
stub calculator only; a real model runner is deliberately absent from this round.
