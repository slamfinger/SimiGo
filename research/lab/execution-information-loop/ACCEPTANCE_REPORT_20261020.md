# Acceptance report — ES→IS code advancement, 2026-10-20

This report states the state of the repository **at the moment it was written**.
It does not inherit the 2026-10-09 tag's PASS, and it does not assert that any
earlier PASS is still valid. Every number below was produced by a command run
against the working tree described in §1.

The claim being audited is the completion definition D1–D4 from the approved
plan. §4 answers them one by one with the evidence that produced the answer.
§6 reconciles the G3 budget, and §8 separates four kinds of evidence that are
easy to merge into one sentence and must not be.

## 0 Report identity

| item | value |
| --- | --- |
| report file | `ACCEPTANCE_REPORT_20261020.md` |
| written on | 2026-10-20. Its own mtime is **not** quoted as a fixed value here: editing this file moves it forward, so §10 gives the command that reads it, and the artefact mtimes below are the ones that matter |
| earlier draft name | `ACCEPTANCE_REPORT_20261022.md` — a naming mistake, corrected here |
| where `20261022` comes from | it is the harness constant `EVALUATED_AT = "2026-10-22T00:00:00Z"`, a synthetic evaluation instant chosen inside the G3 window. It is not the date of any run in this report |
| this file's own sha256 | deliberately **not** written into this file. A summary or sidecar that quotes a hash of the acceptance report must recompute it against the file's bytes after every edit; embedding it here would make the value wrong the moment this file changes again, which is a self-reference problem, not a check |

The date claim does not rest on this file's mtime, which is self-referential, nor
on any single second of an artefact's mtime, which moves every time a suite is
re-run. It rests on the produced artefacts all carrying the same **day**:
`g3_harness.py`, `G3_PREREGISTRATION.json`, `G3_DRY_RUN_RESULT.json` and
`G2_CORE_API_REPLAY_RESULT.json` each read 2026-10-20 under the `stat` command
in §10. The only `2026-10-22` anywhere is the evaluated-at constant inside the
records, which is a designed instant rather than a run date.

The earlier draft's filename was later than the day it was written. Nothing in
its content depended on that date, but a future audit could not have told a real
execution date from a hand-written one, so the name now matches the day, and the
constant it was confused with is named above.

## 1 Repository state

Three different questions, three different answers. The earlier draft merged the
first two and read as a self-contradiction.

| question | command | answer |
| --- | --- | --- |
| is the whole worktree clean? | `git status --porcelain` | **no** — 10 modified, 13 untracked |
| are the five frozen assets identical to `HEAD`? | see §2 | **yes** — zero diff, zero untracked |
| is `g2/evidence/` exempt from `git diff`? | `git check-ignore -v …` | **no** — it is tracked, 98 files |
| is this round's work committed? | `git rev-parse HEAD` | **no** — `HEAD` is still `c0ac9694…`, the commit the round started from |

`git diff --stat HEAD` over the whole tree reports **10 files changed, 860
insertions(+), 119 deletions(-)**. That is the deliverable of this round, and it
is uncommitted on purpose: the round's output is a working tree, not a commit.

```
 M execution-information-loop/carrier_loop.py
 M execution-information-loop/carrier_selftest.py
 M .../model-level-validation/.carrier-arm3.sqlite
 M .../model-level-validation/.carrier-arm4.sqlite
 M .../model-level-validation/.last_judgment.json
 M .../model-level-validation/selftest.py
 M execution-information-loop/real_palace_integrated_selftest.py
 M execution-information-loop/real_palace_loop.py
 M execution-information-loop/real_palace_selftest.py
 M execution-information-loop/real_palace_source_change_selftest.py
?? execution-information-loop/ACCEPTANCE_REPORT_20261020.md
?? execution-information-loop/SETTLEMENT_CONTRACT_CHANGELOG.md
?? .../model-level-validation/.carrier-arm2.sqlite
?? .../model-level-validation/g2/G2_CORE_API_REPLAY_20261020.md
?? .../model-level-validation/g2/G2_CORE_API_REPLAY_RESULT.json
?? .../model-level-validation/g2/batch/carrier_gate_v2.py
?? .../model-level-validation/g2/batch/replay_g2_as_core_api.py
?? .../model-level-validation/g2/batch/test_carrier_gate_v2.py
?? .../model-level-validation/g3/
?? .../model-level-validation/logs/arm{1,2,3,4}.jsonl
```

`HEAD` is `c0ac969427facecd35aae476a08ab3b54855671f`.

Nothing here is submitted as a clean tree. An acceptance reader who needs a
clean tree has to commit first; this report deliberately does not claim one.

## 2 Frozen bytes

Five frozen assets, checked with two independent instruments.

The first is `git`, with the paths spelled out (run from the repository root):

```bash
cd /Users/mr.simi/Documents/SimiGo-Lab
git diff --stat HEAD -- \
  execution-information-loop/experiment/continuous-calc-verification/model-level-validation/g2/manifest/G2_MANIFEST.json \
  execution-information-loop/experiment/continuous-calc-verification/model-level-validation/g2/batch/run_batch.py \
  execution-information-loop/experiment/continuous-calc-verification/model-level-validation/g2/batch/carrier_gate.py \
  execution-information-loop/experiment/continuous-calc-verification/model-level-validation/g2/batch/checker.py \
  execution-information-loop/experiment/continuous-calc-verification/model-level-validation/g2/evidence
# → 0 lines

git status --porcelain --untracked-files=all -- \
  execution-information-loop/experiment/continuous-calc-verification/model-level-validation/g2/manifest \
  execution-information-loop/experiment/continuous-calc-verification/model-level-validation/g2/evidence
# → 0 lines
```

Both commands are path-scoped. They say **these five paths** have no difference
from `HEAD` and no untracked members; they say nothing about the rest of the
tree, which does differ (§1). Because the paths are tracked, a byte-level change
would appear in `git status` — the check does not rely on an ignore rule.
`g2/evidence/` is **not** ignored: `git check-ignore -v` exits 1 for a file
inside it, and `git ls-files … | wc -l` returns **98**, so all 98 evidence files
are tracked and any edit would be visible.

The second instrument is the hash itself, compared with the value recorded in
`SETTLEMENT_CONTRACT_CHANGELOG.md` when the V2 contract landed:

| asset | sha256 (on disk now) | matches changelog | matches HEAD |
| --- | --- | --- | --- |
| `g2/manifest/G2_MANIFEST.json` | `fd5146968f01a8b2014a288519dbec022af2abb533c3b38613fce5b622798ec0` | yes | yes |
| `g2/batch/run_batch.py` | `6cd580cda4235e50bb01464bff4c398dc76b49aa0b48eff181a052dbde3644ac` | yes | yes |
| `g2/batch/carrier_gate.py` | `a791de301283f21d26ecfa92bcd17dfbe1e20e0cb963ba93f763af052aaaa99d` | yes | yes |
| `g2/batch/checker.py` | `bc453515789a432d88c80af6c6fb2a8f82a7b8fd8cfdd274b21660fecefaff32` | yes | yes |
| `g2/evidence/` (98 files, tracked) | tree unchanged | n/a | yes |

The manifest binds `checker.py` at `bc453515789a432d…`, which is what is on
disk, so the manifest is still self-consistent with the frozen checker. The only
new files under `g2/batch/` are `carrier_gate_v2.py`, `replay_g2_as_core_api.py`
and `test_carrier_gate_v2.py`; no frozen file was edited in place.

### 2.5 Commit state

Nothing in this round is committed. `HEAD` is still
`c0ac969427facecd35aae476a08ab3b54855671f`, the value §1 records; the ten
modified files and thirteen
new paths are working-tree state, and the tracked ones diff against `HEAD` at
`10 files changed, 860 insertions(+), 119 deletions(-)`.

The honest name for this deliverable is therefore **local implementation and
local acceptance**: the code exists, the checks run green in this checkout, and
the artefacts are reproducible here. It is not merged, and it is not frozen in
version control. The G3 pre-registration is frozen as a *document* — a hashed
artefact awaiting an authorisation decision — which is a different sense of
"frozen" from a committed branch, and §6 uses the word only in the first sense.

## 3 On-the-spot test results

All commands were run inside this round against the tree in §1. "Checks" is the
number of boolean assertions the script itself reports, not a count of things
that "looked fine".

| script | result | exit | checks / scenarios |
| --- | --- | --- | --- |
| `carrier_selftest.py` | `PASS` | 0 | **47 checks, 0 false** |
| `real_palace_selftest.py` | `PASS` | 0 | 13 checks, 0 false |
| `real_palace_source_change_selftest.py` | `PASS` | 0 | 14 checks, 0 false |
| `real_palace_integrated_selftest.py` | `PASS` | 0 | 21 checks, 0 false |
| `g2/batch/test_carrier_gate_v2.py` | `PASS` | 0 | 12 scenarios, 65 checks, `database_mutations_by_gate: false` |
| `g2/batch/replay_g2_as_core_api.py` (3 fixtures) | `PASS` | 0 | 31 `evidence_checks` + 12 `replay_checks` per fixture, all true |
| `g3/harness/g3_harness.py` (stub) | `PASS` | 0 | 26 checks per fixture + 3 run-level dependency-graph checks; 20 calculator slots, 0 model starts, 4 gate processes |
| `selftest.py --arm all` (mlv) | 14 judgments, 0 tracebacks | **1** | see below |

`selftest.py --arm all` exits 1 by design. The harness ends with
`sys.exit(1 if bad else 0)` and `bad` includes any `NOT VERIFIED` judgment. The
only such judgment is `H_选择性失效-Executor(真Calculator)` with
`status=NOT_INSTRUMENTED` (the real Swift Calculator is not wired into that
harness). That condition predates this round; the 14 judgments are unchanged,
and the run produced no traceback. It is reported here as `exit=1, honest gate`,
not as a regression and not as a pass. §8 states what that means for the model
layer.

The 14 judgments as printed:

```
A_真实模型路径                          PASS-部分
G_正确性(arm2=baseline prefix 级等价)    PASS
B_持久结算(IS sha256 恢复成功)           PASS
C_旧缓存隔离(新阶段 handle)               PASS-部分
D_结果恢复(IS 提供有效结果)               PASS
F_新阶段执行(新增单元由新阶段实跑)         PASS
E_避免重复计算                           PASS-部分
H_选择性失效-Carrier                     PASS-部分
H_选择性失效-Executor                    NOT VERIFIED   (NOT_INSTRUMENTED)
H_选择性失效-整体                        PASS-部分
H_选择性失效-Diamond-Carrier             PASS
H/E/I_证据结构一致性                     PASS-部分
I_工作量收益                             PASS-部分
J_可复现性(logs/*.jsonl 完整)            PASS
```

`carrier_selftest.py` reports 47 checks with 0 false. 31 of those names already
exist at `HEAD`; 16 are new this round, and the split is exact:

- 8 contract checks — `settlement_contract_rejects_missing_field`,
  `…_malformed_digest`, `…_cross_domain_digest`, `…_cross_scope_source_version`,
  `…_cross_scope_evaluated_at`, `settlement_contract_violation_writes_nothing`,
  `opaque_settlement_is_not_reused`, `contract_audit_classifies_legacy_opaque`;
- 8 invalidation checks — `basis_only_dependency_propagates`,
  `declared_and_transitive_dependencies_propagate`,
  `invalidation_scope_is_exactly_the_closure`, `non_strict_preserves_legacy_shape`,
  `non_strict_writes_nothing`, `unknown_target_raises_missing_logical_entry`,
  `unknown_target_writes_nothing`, `unrelated_item_not_invalidated`.

`invalidation_checks` occurs 0 times at `HEAD`.

Two reproducibility checks were run against the records on disk, not just against
the scripts. Re-running the replay produced bytes identical to the committed
record (`sha256 d119efb90f31eed4cd5c3e5498cfcd5eacd1e718607e67e9eaaa4215b6f61b6d`
in both cases), because that record contains no process identifiers. Re-running
the G3 harness differs in exactly four values, all of them
`gate_processes[*].pid` (§6.2); everything else, including every check, is
identical.

## 4 D1–D4

### D1 — one contract, explicit dual digest domain, zero writes on violation, history opaque

| requirement | evidence | verdict |
| --- | --- | --- |
| single contract | `SETTLEMENT_CONTRACT = "EINFO-SETTLEMENT-CONTRACT-V1"` (`carrier_loop.py:54`), `CARRIER_LOOP_CONTRACT_VERSION = "2"` (`:55`), marker at envelope top level | met |
| dual digest domains explicit | `source_payload_sha256` and `result_value_sha256` are separate fields in both `result` and `basis`; `payload_digest` is gone | met |
| missing field rejected | `settlement_contract_rejects_missing_field: true` | met |
| malformed digest rejected | `settlement_contract_rejects_malformed_digest: true` | met |
| cross-domain comparison rejected | `settlement_contract_rejects_cross_domain_digest: true` | met |
| **`result.source_version == basis.source_version`** | `carrier_loop.py:165-166`; test `settlement_contract_rejects_cross_scope_source_version: true` | met |
| **`result.evaluated_at_utc == basis.evaluated_at_utc`** | `carrier_loop.py:169-170`; test `settlement_contract_rejects_cross_scope_evaluated_at: true` | met |
| violation writes nothing | `settlement_contract_violation_writes_nothing: true`; independently re-measured this round on a fresh carrier: three rejected attempts, `is_objects 2→2`, `is_index_entries 2→2`, `dependency_entries 1→1` | met |
| history opaque and non-reusable | `opaque_settlement_is_not_reused: true`, `contract_audit_classifies_legacy_opaque: true`; the replay audit over the frozen G2 carriers reports `counts {OPAQUE: 3}`, `all_opaque: true`, 1 per fixture | met |
| frozen V1 writer fails loudly rather than silently | a reproduction of `run_batch.py`'s exact V1 `result`/`basis` shape raises `SettlementContractViolation` with 13 missing fields (`result.value`, both digests in both scopes, both windows, both policies, `result.source_version`, `result.dependency_object_ids`) and 0 mismatched | met |

The last row is a design consequence, not a defect: `run_batch.py` is
byte-frozen, still writes V1, and is not re-run. See §5.

The two cross-scope rows were missing from the earlier draft. The check existed
in `validate_settlement_payload` but had no test named after it, so a regression
could have removed it silently; both cases are now exercised, each injecting a
one-field mismatch into an otherwise valid envelope and asserting the exact
rejection label.

### D2 — gate and loop agree on all four window states

`test_carrier_gate_v2.py` records the cross-check itself:

| window state | gate | loop | same verdict |
| --- | --- | --- | --- |
| missing (`--require-validity`) | `REFUSED / VALIDITY_MISSING` | `BLOCKED_MISSING_VALIDITY` | yes, both refuse |
| malformed timestamp | `REFUSED / VALIDITY_MALFORMED` | `BLOCKED_INVALID_VALIDITY` | yes, both refuse |
| expired | `REFUSED / VALIDITY_EXPIRED` | `BLOCKED_STALE_VALIDITY` | yes, both refuse |
| valid | `RESTORED` | `ADVANCED` | yes, both proceed |

Every scenario also asserts `database_unchanged: true` and
`model_not_loaded: true`, and the run-level `database_mutations_by_gate` is
`false`.

No v1 check was dropped. The frozen v1 gate emits 24 named checks (the plan
estimated 17 from a partial read); `carrier_gate_v2.py` retains all 24 names and
adds 7 window/contract checks — `settlement_contract_known`,
`validity_window_present`, `validity_window_parseable`, `validity_window_current`,
`evaluated_at_utc_parseable`, `contract_source_payload_digest_agrees`,
`contract_result_value_digest_matches` — plus 3 dialect-envelope checks added
after review (see below). The frozen refusal codes `SETTLEMENT_MISSING` and
`OBJECT_DIGEST_MISMATCH` are still emitted, alongside the new `VALIDITY_MISSING`,
`VALIDITY_MALFORMED`, `VALIDITY_EXPIRED`, `EVALUATED_AT_MALFORMED`,
`SETTLEMENT_CONTRACT_UNKNOWN` and `SETTLEMENT_CONTRACT_MALFORMED`.

`evaluate(db_path, item_id, evaluated_at_utc, …)` takes the instant as a required
argument; the file contains zero occurrences of `now(`, `utcnow` or
`datetime.now`, so the gate cannot silently evaluate against wall-clock time.

Two scenarios prove the gate understands the dialect the loop actually writes:
`contract_valid` → `RESTORED` with `dialect_is_conforming: true`, and
`contract_expired` → `REFUSED / VALIDITY_EXPIRED`, also conforming. Before this
round the gate rejected every conforming settlement with
`OBJECT_DIGEST_MISMATCH`, because it inherited the V1 gate's
`r1_digest_matches_payload` check, which reads a G2-only field. That gap is
closed in `carrier_gate_v2.py` only; the frozen V1 gate is unchanged and remains
a historical-dialect gate.

**Dialect selection is now checked, not inferred.** The marker picks the reading;
the field shape is then verified against the marker. Four negative scenarios were
added, each built as a one-step mutation of an otherwise valid conforming
envelope and appended byte-for-byte (no conforming writer would emit them):

| scenario | mutation | refusal |
| --- | --- | --- |
| `unknown_marker` | marker `EINFO-SETTLEMENT-CONTRACT-V9` | `REFUSED / SETTLEMENT_CONTRACT_UNKNOWN` |
| `marker_shape_conflict` | conforming marker, historical `result` shape | `REFUSED / SETTLEMENT_CONTRACT_MALFORMED` |
| `mixed_dialect` | `result` carries `value` **and** `r1_canonical` | `REFUSED / SETTLEMENT_CONTRACT_MALFORMED` |
| `marker_absent_conforming_shape` | `result.value` present, marker absent | `REFUSED / SETTLEMENT_CONTRACT_MALFORMED` |

The last row is the one W1 requires: a payload with no contract identity is not
"probably compatible". An absent marker is still read as V1 *only* when the shape
is V1; the gate no longer derives the dialect from whichever keys happen to be
present. `settlement_contract_shape_complete` additionally refuses a partial
shape in either dialect.

`missing_window_optional` (no `--require-validity`) records
`absent_window_recorded: true` and still `RESTORED`, which is the documented
behaviour needed to audit historical carriers.

### D3 — core API can restore and reuse; replay separates rebinding from execution

| field | value |
| --- | --- |
| `result` | `PASS` (3/3 fixtures) |
| `core_api_restore` | `PASS` |
| `core_api_reuse` | `PASS` |
| `new_model_starts` | `0` |
| `is_new_execution_evidence` | `false` |
| `runtime_application_semantics` | `REBINDS_RECORDED_EVENT` |
| `legacy_settlements_classification` | `OPAQUE`, 3 total (1 per fixture) |

Per fixture: `u1_action == "REUSE"` and `u1_settlement_object_id` is the
settlement created in the replay carrier
(`fixture-1 5611b62b…`, `fixture-2 4ace8986…`, `fixture-3 59935a28…`), so the
reuse was decided by the core predicate, not pre-filled by the script. The state
chain has five records per fixture
(`u1-settled → u1-settled:runtime-applied → u2-restored → u2-advanced →
u2-advanced:runtime-applied`). All `evidence_checks` (31) and all
`replay_checks` (12) are true for every fixture.

**Where `APPLIED_SWIFT` comes from.** `confirm_runtime_application(state_id)`
takes no evidence: it accepts a state id, requires the state to be
`PENDING_SWIFT` and the latest one, and records `APPLIED_SWIFT`. It is a gate on
state shape, not a verifier of execution. The evidence that an application
happened is therefore carried by a five-link chain the script verifies *before*
it creates a carrier, and the values are copied into
`evidence_provenance` in the result JSON:

| link | frozen source | value (fixture-1; same checks per fixture) |
| --- | --- | --- |
| event identity | `B1/host_record.json` | `pid 51607`, `parent_pid 51216`, `process_group 51607`, `mode phase1`, `08:21:43Z → 08:21:56Z` |
| terminal state | `B1/host_record.json`, `terminal.json` | `exit_code 0`, both host checks true, arm claim `G2-B: PASS`, `halted: false` |
| executable hash | `manifest/G2_MANIFEST.json` | host build product `9eee4bc3…99a75217`; four frozen tools; `terminal.manifest_sha256` equals the on-disk manifest hash |
| entry identity | `B1/host_record.json`, `model_binding` | model dir `artifact-model-…-6e302ea6`, revision prefix `6e302ea6`, engine triple `bb0b2711…` / `9bada7c8…` / `d1f01c0c…` |
| result binding | `B1/host_record.json`, `B1/r1.json` | `u1.r1_sha256` equals the frozen `r1_sha256`, and `u1.r1_canonical` is byte-equal to it |

**Scope of the reuse claim.** The reuse proved here is the reuse of a settlement
*this script wrote under the current contract*, in a carrier created for the
replay. It does not say the historical G2 settlement objects became reusable;
those stay `OPAQUE`, as the same run's audit reports. Rebuilding a conforming
settlement from recorded bytes and reusing the rebuild is a weaker, different
claim than reusing the original object, and the result JSON states both
(`reuse_scope_note`, `legacy_settlements_classification`).

The binding record is the first record in each replay carrier and states
`scope: SYNTHETIC_REPLAY`, `model_starts: 0`, `is_new_execution_evidence: false`.
The script's own `non_claims` block repeats that it produces no G2-A/B/C
evidence, does not replace the 98 frozen files, claims no new Swift application,
and does not make the historical settlements reusable.

### D4 — three `real_palace_*` green on the positive path, negative paths retained

| script | result | checks | negative paths still exercised |
| --- | --- | --- | --- |
| `real_palace_selftest.py` | `PASS` | 13 | none by design; the positive path reports `state` and `failure_reason` instead of raising `KeyError` |
| `real_palace_source_change_selftest.py` | `PASS` | 14 | none by design; source change before and after both carry policy and window |
| `real_palace_integrated_selftest.py` | `PASS` | 21 | `expired_source_blocks_without_guess`, `malformed_observation_blocks_same_real_loop`, `integrated_missing_information_blocks`, `mid_demand_failure_rolls_back_atomically`, `process_crash_leaves_no_partial_settlement`, `ambiguous_source_fails_closed`, `blocked_state_blocks_restore_until_repaired`, `restored_demand_contract_drift_rejected` — all true |

Every `BLOCKED` carries its original reason. The blocked run in the integrated
script reports:

```
state          = BLOCKED_STALE_VALIDITY
failure_reason = source validity expired without refreshed authorization
```

The remaining five runs in that script are `ADVANCED` with
`failure_reason: null`, which is the expected positive-path state.

The blocked run does not abort the chain. After the `BLOCKED` state is recorded,
the script asserts that `restore_continuation` is refused while the state is
blocked, then appends `state-006-recovered` (`APPLIED_SWIFT`) and asserts that
`restore_continuation` returns exactly that state. The six recorded states are
`state-001-initial`, `state-002-reuse`, `state-003-invalidation`,
`state-004-source-change`, `state-005-expiration`, `state-006-recovered`.

None of the three depends on the working directory: each was also executed from
`/tmp` using only an absolute script path, and returned the same `result: PASS`
with exit 0.

## 5 Contract drift

`carrier_loop.py` is **not** frozen this round, and its hash is reported so that
nobody has to infer it:

| point | sha256 |
| --- | --- |
| HEAD (`git show HEAD:…/carrier_loop.py \| shasum -a 256`) | `d3fb317ad9588eed84b0f7e10ef751f477cbbdeb4fd1b13ba6082ac4450fc2a3` |
| working tree | `464e5c557275417a6724f1d96baa0dd7323a5a691bbfb0205d1f29f3f6db5b4f` |

The HEAD value is byte-identical to the hash bound by
`ACTUAL_MLX_SMOKE_MANIFEST_V6`. V6 is closed and not re-runnable; that binding
remains a historical record, and **HEAD is not claimed to satisfy V6**.

`SETTLEMENT_CONTRACT_CHANGELOG.md` records V1 (implicit, no marker) → V2
(`EINFO-SETTLEMENT-CONTRACT-V1`, dual digest domain), the field table, the write
rule, the read rule, the audit classification, the fact that G2's bytes are
untouched and opaque, and the same-version changes made after V2 landed: W4
invalidation tightening, gate-v2 dialect coverage, dialect selection by marker
rather than by shape, and cross-scope equality inside one envelope. It also
states the forward rule: any future freeze record must bind both the
`carrier_loop.py` hash and `CARRIER_LOOP_CONTRACT_VERSION`.

Because `run_batch.py` is frozen and V1-shaped, re-running it against this
module raises `SettlementContractViolation`. That is documented in the changelog
and reproduced in §4/D1. G2 is closed; the V2 replacements are
`carrier_gate_v2.py` and `replay_g2_as_core_api.py`.

## 6 W6 — G3: budget, units, and what the dry run measured

### 6.1 The dispute, stated exactly

The review quotes a frozen budget table of **12 model starts / 8 negative-control
processes / 20 total processes**. That table is not in the approved plan. §7.4
of the plan says, in one sentence:

> `2 fixtures × 2 arms × 5 = 20` 次模型启动；负向控制 `2 fixtures × 2 = 4` 个 gate 进程；总进程上限 24，0 重试。

So the plan's own numbers are **20 start slots, 4 gate processes, cap 24** — not
12 / 8 / 20. Either way, the earlier report's sentence "20 次模型启动" was
wrong, and it was wrong in the way that matters: it used the plan's design-unit
name as if it were an execution count.

The quotation above is checked rather than retyped: `preregistration.budget.plan_quote_verbatim`
is compared byte-for-byte against the plan file, and the comparison is exact
(`EXACT_MATCH`, including the backticks and the `×` characters). A first draft of
that field had replaced `×` with `x` while still calling itself verbatim; that is
the same class of error as the one this section is about, and it was corrected
before the freeze.

### 6.2 What actually ran

The harness starts **no model**. It injects a deterministic Python stub
(`StubCalculator`) that reproduces the frozen unit rule and checks its own answer
with the frozen checker. `subprocess` occurs exactly once in the harness, inside
the gate-control helper, so the only child processes are the four
`carrier_gate_v2.py` runs for the negative controls.

A second run of the harness reproduced the record byte-for-byte except for four
values: `fixtures[*].gate_processes[*].pid` (one observed pair was
`47423-47426` against a later run's four pids). Those numbers change on every
run, which is exactly why they are the only field that differs, and why the four
gate controls can be called processes rather than simulated events. Every other
value in the two records — including all 26 checks per fixture and the three
dependency-graph checks — is identical.

| quantity | predicted | measured |
| --- | --- | --- |
| calculator invocation slots (design unit) | 20 | **20** |
| **actual model starts** | 0 | **0** |
| gate processes | 4 | **4** |
| retries | 0 | **0** |
| `is_execution_evidence` | `false` | `false` |

The earlier record was regenerated so that the two quantities are named apart in
the artifact itself: `measured_calculator_invocations: 20`,
`actual_model_starts: 0`. Under the review's table *and* under the plan's table,
zero executed starts is within every stated cap, so no authorization was
consumed and none is claimed. The 20 slots remain a pre-execution design count;
converting them into 20 model starts needs the separate grant.

### 6.3 What the dry run is and is not

| field | value |
| --- | --- |
| preregistration status | `FROZEN_PENDING_EXECUTION_AUTHORIZATION` |
| `model_execution_authorized` | `false` |
| preregistration revision | 4 |
| preregistration sha256 | `30f977cc4def7d3951b78f2df209454916fca4884a19877d702180283b486972` |
| harness sha256 | `1953dc75be4a199b1e1bf157145de020ec7ce9bf202beea2f396c12e67d464f1` |
| dry-run record sha256 | `96e2a30fd87035dd2a82c61bc480836d7da2f5a3528de76686ddb333d7c4f879` |
| dry-run schema | `SIMIGO-G3-DRY-RUN-V1`, `dry_run: true` |
| fixture-level checks | 26 per fixture, 0 false |
| run-level checks | 3 dependency-graph checks, 0 false (`dependency_edges_declared`, `dependency_graph_matches_harness`, `independent_sibling_has_no_edges`) |
| **total checks in the dry-run record** | **55, not 52.** The three run-level checks are a separate object (`dependency_graph.checks`) from the per-fixture `fixtures[*].checks` object; recomputing both sets from `G3_DRY_RUN_RESULT.json` and intersecting their names returns the empty set, so none of the three is already counted inside 26 × 2 = 52. A summary that writes "26 checks × 2 = 52" and separately lists "依赖图 3/3" is describing the same 55 total across two lines, not two different run totals |

Revision 4 is a content change to a frozen plan, so the revision number, the hash
embedded in the human-readable pre-registration and the dry-run record were
advanced together rather than patched in place. Within revision 4, two
overlapping clauses about model runtime resources were merged into
`arm_isolation.model_resources`, leaving eight isolation clauses; each one either
names the check that enforces it or states explicitly that no dry-run check can.

The record now carries its own `provenance` block — `preregistration_sha256`,
`harness_sha256` and `preregistration_revision` — written by the harness at run
time. Both embedded values were compared with the bytes on disk after the run
and match, so the dry-run record states which frozen plan it checked itself
against instead of asking the reader to assume it.

The dry run's verdict is `DIVERGENCE_OBSERVED`, and the divergence is exactly the
one the pre-registration wrote down in advance: `final_result` and
`open_obligations` agree at all four probes on both fixtures, `next_step`
diverges at the `d2` probe only (ES says `d3`, IS-only says `d4`), because IS
alone cannot tell a declared step boundary from a satisfied one. This is recorded
as an observation, not as a proof of independent ES value.

### 6.4 The frozen sets, and the sibling

Every step is checked against four sets declared on an arm-independent basis (the
current settlement object id of each item), and the harness asserts that the sets
partition the universe:

| step | recomputed | reused | unsettled | blocked |
| --- | --- | --- | --- | --- |
| `d1` | `U1` | `U_free` | `U2`, `U3` | — |
| `d2` | `U2` | `U1`, `U_free` | `U3` | — |
| `d3` (source change on `U1`) | `U1`, `U2` | `U_free` | `U3` | — |
| `d4` | `U3` | `U1`, `U2`, `U_free` | — | — |

The `unsettled` bucket did not exist in the earlier draft and its absence was a
real defect in the frozen plan: `U3` appeared in the "unchanged" set for `d1`–`d3`
only because it had no settlement on either side, so a reuse expectation could
have been satisfied by nothing happening. It is now a separate set, and
`three_sets_partition_the_universe` asserts the split.

The dependency graph is frozen in the pre-registration as
`task_graph.dependency_edges` — `U2 ← U1`, `U3 ← U2`, `U1` and `U_free` with no
edges. The harness does not carry its own private copy of that table: it reads
the pre-registration on every run and asserts `dependency_graph_matches_harness`
and `independent_sibling_has_no_edges`. Removing `U2`'s edge from a copy of the
plan turns the first check false and fails the run, so the comparison is
falsifiable rather than decorative. This matters for `d3`: the prediction that
`U2` recomputes is only meaningful if the edge by which `U1`'s new settlement id
enters `U2`'s basis is the frozen one.

The `blocked` column is empty by design, and the assertion is stronger than an
empty set: `blocked_set_is_empty_on_the_formal_arms` requires both arms to report
`state == ADVANCED` at every formal step, so an unplanned block fails the step
rather than leaving a set quietly empty. Blocking is measured by the negative
controls on their own copies.

`U_free` is the independent sibling. `U1` is the source-change target, so it
cannot play that role, and `U3` is downstream of `U2`. `U_free` is settled once
in the prefix carrier and never again; `unrelated_settlement_survives_source_change`
asserts exactly one settlement revision in both arms, and
`free_item_reused_after_source_change` asserts it is in the reused set at the
final probe.

### 6.5 Arm isolation

The review asked whether the two arms have separate state stores, separate
settlement objects and separate runtime resources, sharing nothing but the
immutable input the pre-registration allows. That is a design question with a
checking answer, and answering it turned up a real defect.

`ISOnlyView` is the IS arm's only handle on its carrier, and it first ran its
whitelist in `__getattr__`. That hook fires only **after** normal attribute
lookup fails, so instance attributes were handed out unguarded: `view._loop`
returned the wrapped `CarrierInformationLoop`, `restore_continuation` and every
other ES entry point were reachable through it, and `denied` stayed empty. The
existing invariant `is_arm_touched_no_es_entry_point` would have reported a clean
run for an arm that was never restricted. The whitelist now runs in
`__getattribute__`, and `__setattr__` / `__delattr__` are refused.

Isolation is measured, not asserted. Seven per-fixture checks carry the claim,
listed in one table with the two proxy checks sharing a row; three of the seven
(`arms_use_distinct_carriers`, `es_records_land_only_in_the_es_carrier`,
`arms_use_distinct_calculator_instances`) existed before this revision, the
other four are new:

| invariant | check | what would fail it |
| --- | --- | --- |
| separate carriers | `arms_use_distinct_carriers` | the two paths resolving to one database |
| ES records land only in the ES carrier | `es_records_land_only_in_the_es_carrier` (`es_execution_state_count` > 0, `is_execution_state_count` = 0) | one carrier shared by both arms |
| separate calculator instances | `arms_use_distinct_calculator_instances` | a mixed call log |
| the proxy cannot be pierced | `proxy_refuses_inner_loop_and_es_entries`, `proxy_refuses_attribute_write` | `view._loop` returning the carrier, as it did before the fix |
| writes do not cross | `arm_writes_do_not_cross_to_the_other_arm` | a probe item and settlement written to the ES carrier and visible in the IS carrier |
| shared input stays input | `shared_fixture_inputs_not_mutated_by_either_arm` | either arm mutating the fixture it reads |

Two negative controls were run, so these are not checks that cannot fail:
reinstating a `__getattr__`-based proxy makes `view._loop` return the carrier
with an empty `denied`; writing the probe item into **both** carriers turns
`arm_writes_do_not_cross_to_the_other_arm` false, while writing it to one leaves
it true.

The model prefix cache is **not** covered by the dry run, because the dry run
starts no model: a shared KV/prefix cache can only appear when real instances
exist. The pre-registration states it as a hard precondition for the formal run
(`arm_isolation.model_resources`, the single clause after the revision-4 merge),
not something this harness can demonstrate.

Frozen pre-registration is not execution authorization. The 20 slots have not
been converted into model starts and remain a separate grant.

## 7 Position of ES

This round did not change what counts as a legal continuation, and did not move
the decision algorithm into the ES data structure. The operative split, in the
terms the code actually implements:

- **ES is the state authority.** The continuation position, the open
  obligations, the continuation conditions and the bound demand contract are
  definable only by execution-state records. `restore_continuation()` is the
  only reader of that authority, and it refuses `BLOCKED`, refuses
  `PENDING_SWIFT`, refuses a missing `APPLIED_SWIFT`, and refuses a
  demand-digest mismatch.
- **`execute_demand` is the decision mechanism.** It reads ES and IS, chooses
  reuse, compute, block or advance under the validity and dependency rules, and
  writes the new ES record. None of those choices are stored in ES as an action
  list.

Whether an action list or a closure digest should be written into ES is left
open on purpose: the G3 IS-only comparison is the measurement that should decide
it, and that comparison has been dry-run only (see §6).

## 8 Four kinds of evidence

The review's closing point is that these four are related but not
interchangeable. Kept apart:

| kind | what it establishes | where it stands |
| --- | --- | --- |
| code tests | the implementation does what the contract says, in-process | §3–§4, D1/D2/D4: green — 47 carrier checks, 65 gate checks over 12 scenarios, 13 + 14 + 21 real-palace checks |
| offline semantic replay | the core API can express the recorded continuation and reuse a settlement it wrote | §4/D3: `PASS` 3/3, `new_model_starts: 0` |
| historical execution evidence | a host process really produced the recorded `R1` | §4/D3 provenance chain: five links verified against the frozen bytes; the original G2 run remains the only execution evidence |
| real model experiment | the designed comparison actually ran and produced a measurement | **not obtained.** No model was started; G3 is frozen and dry-run only |

Two consequences that follow from keeping them apart:

- The three `real_palace_*` suites passing does **not** extend to the model
  layer. `H_选择性失效-Executor` is still `NOT_INSTRUMENTED`: a model-layer
  ability this round did not instrument. §3 reports that as an open condition,
  not as a regression and not as a pass.
- The replay's `APPLIED_SWIFT` does not add execution evidence. It is a state
  transition over bytes that already existed, and the semantics are recorded as
  `REBINDS_RECORDED_EVENT`.

## 9 What this report does not claim

- It does not claim a clean worktree; the round's deliverable is uncommitted.
- It does not carry forward the 2026-10-09 tag's PASS or any earlier PASS.
- It does not claim HEAD satisfies `ACTUAL_MLX_SMOKE_MANIFEST_V6`.
- It does not claim G2 is reproducible under V2; G2 is closed and opaque.
- It does not claim the G3 comparison ran. It was pre-registered and dry-run with
  a stub only, and `actual_model_starts` is `0`.
- It does not claim 20 model starts were executed, under either budget table.
- It does not claim ES has an independent contribution; the dry run records a
  divergence at one probe and leaves interpretation to the reviewer.
- It does not claim the model layer is fully instrumented; one mlv judgment is
  still `NOT_INSTRUMENTED`.
- It does not claim the historical G2 settlement objects are reusable.
- It does not claim G3 execution authorization.
- It does not claim the two arms are isolated *at the model layer*. What is
  measured in §6.5 is carrier, settlement-object, calculator and shared-input
  isolation under the stub. No model instance, KV cache, prefix cache, tokenizer
  handle or weight buffer existed during the dry run, so their non-sharing is a
  precondition the formal run must satisfy, not a result this report can show.
- It does not claim anything was committed or merged. `HEAD` is unchanged from
  the start of the round (§2.5); the deliverable is local implementation and
  local acceptance.
- It does not record its own SHA-256 inside the report body; a hash of this file
  quoted anywhere else (a summary, a canvas, an authorization submission) is
  computed from outside and has to be refreshed after every further edit to this
  file, rather than corrected by editing a field inside it.
- It did not, in its first revision of §2.5, state `HEAD` correctly: the section
  was written with a 40-character value that no commit has. §10's hash sweep
  catches file digests, not a commit id typed from memory, so the mistake
  survived until the final git reconciliation. It is corrected above rather than
  quietly overwritten — the same failure mode §6.1 describes for the `×`/`x`
  substitution, reached from the other side: a value that looks checked because
  it is written out in full.

## 10 Reproduction

```bash
cd execution-information-loop
python3 carrier_selftest.py
python3 real_palace_selftest.py
python3 real_palace_source_change_selftest.py
python3 real_palace_integrated_selftest.py

cd experiment/continuous-calc-verification/model-level-validation
python3 g2/batch/test_carrier_gate_v2.py
python3 g2/batch/replay_g2_as_core_api.py --fixtures fixture-1 fixture-2 fixture-3 \
    --out g2/G2_CORE_API_REPLAY_RESULT.json
python3 g3/harness/g3_harness.py          # add --out only if you intend to
                                          # replace the dry-run record
python3 selftest.py --arm all             # exits 1 by design; see §3
```

Timestamp check behind §0 (run from `model-level-validation`), and the isolation
re-check behind §6.5:

```bash
stat -f "%Sm  %N" -t "%Y-%m-%dT%H:%M:%S%z" \
  ../../../ACCEPTANCE_REPORT_20261020.md \
  g3/harness/g3_harness.py \
  g3/preregistration/G3_PREREGISTRATION.json \
  g3/G3_DRY_RUN_RESULT.json \
  g2/G2_CORE_API_REPLAY_RESULT.json

python3 g3/harness/g3_harness.py | python3 -c "
import sys, json
d = json.load(sys.stdin)
for fid, f in d['fixtures'].items():
    print(fid, len(f['checks']),
          [k for k, v in f['checks'].items() if v is not True],
          'denied', f['is_denied_touches'])
    for k in ('proxy_refuses_inner_loop_and_es_entries',
              'proxy_refuses_attribute_write',
              'arm_writes_do_not_cross_to_the_other_arm',
              'shared_fixture_inputs_not_mutated_by_either_arm',
              'arms_use_distinct_carriers',
              'arms_use_distinct_calculator_instances',
              'es_records_land_only_in_the_es_carrier'):
        print('   ', k, f['checks'][k])
print('model_starts', d['budget']['actual_model_starts'],
      '| graph', d['dependency_graph']['checks'])
"
```

The record's own provenance block can be re-checked without trusting this
report (same directory):

```bash
python3 - <<'PY'
import json, hashlib, pathlib
rec = json.load(open('g3/G3_DRY_RUN_RESULT.json'))
p = rec['provenance']
disk = lambda x: hashlib.sha256(pathlib.Path(x).read_bytes()).hexdigest()
assert p['preregistration_sha256'] == disk('g3/preregistration/G3_PREREGISTRATION.json')
assert p['harness_sha256'] == disk('g3/harness/g3_harness.py')
print('record provenance self-consistent | revision', p['preregistration_revision'],
      '| result', rec['result'], '| model starts', rec['budget']['actual_model_starts'])
PY
```

The report's own mtime is deliberately excluded from the date argument in §0; it
is listed here only so a reader can see how stale a quoted value of it becomes
after one editing session.

Frozen-asset check (from the repository root), copied from §2:

```bash
git diff --stat HEAD -- \
  execution-information-loop/experiment/continuous-calc-verification/model-level-validation/g2/manifest/G2_MANIFEST.json \
  execution-information-loop/experiment/continuous-calc-verification/model-level-validation/g2/batch/run_batch.py \
  execution-information-loop/experiment/continuous-calc-verification/model-level-validation/g2/batch/carrier_gate.py \
  execution-information-loop/experiment/continuous-calc-verification/model-level-validation/g2/batch/checker.py \
  execution-information-loop/experiment/continuous-calc-verification/model-level-validation/g2/evidence
```

Every sha256 printed in this report was resolved against the tree, not copied
from an earlier draft: nine of the ten values match the bytes of a file under
`execution-information-loop/`, and the tenth (`d3fb317a…`) is the `HEAD` revision
of `carrier_loop.py`, resolved by `git show HEAD:… | shasum -a 256`. The
`plan_quote_verbatim` field in the pre-registration was likewise compared
byte-for-byte with the plan file and matched exactly. Re-running any command
above reproduces the numbers in §3; the only expected variation is the four
`gate_processes[*].pid` values in the G3 record (§6.2).
