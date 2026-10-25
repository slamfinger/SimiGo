# SimiGo2 G3 Runtime Isolation — D Authorization Boundary v0.1

> **Status:** DESIGN REVIEW ONLY — D NOT AUTHORIZED
> **Date:** 2026-10-21
> **Scope:** the G3 line — Swift/MLX per-arm KV isolation (`simigo2-experimental`) and the G3/PALACE settlement harness (`execution-information-loop`)
> **Provider trust:** `RuntimeProviderTrustPolicy.registeredLiveProviderTypes = [:]` (unchanged)
> **Model loads / generation:** none
> **Lab commit:** none
> **C closure record:** `docs/06-closure/G3_C_CLOSURE_20261021.md` (`G3-C = CLOSED`)
> **D1 protocol (frozen method, not a grant):** `docs/00-governance/SIMIGO2_G3_D1_EXPERIMENT_PROTOCOL_V0.1_20261021.md`, frozen by its `.sha256` sidecar
> **Supersedes:** nothing. This is the first written D boundary for this line.

This document defines the falsifiable acceptance criteria that must exist
before any request to authorize a real-model G3 run. It does not authorize a
run, does not register a provider, does not load a model, and does not start
generation. Approval of this document, if granted, would authorize only the
preparation of a separate D1 execution package; it would not authorize D1
execution itself.

## 0. 决策摘要（中文）

- **本文性质**：D 的授权边界设计评审，不是执行授权包。D 未授权，provider trust 仍为空，未加载模型，未运行 G3，未提交工作树。
- **C 的收口状态**：生命周期控制流审计通过，附三项限制（release 竞争不等于并发安全；`consumeBinding` → `duringGenerationRegistration` 存在不可回滚窗口；对象析构不等于物理内存归还）。收口记录在 `docs/06-closure/G3_C_CLOSURE_20261021.md`。
- **D 的拆分**：四项最小命题不放进一次运行。D1 验证真实模型下的拒绝传播（P1）与旧 KV 释放（P2）；D2 用确定性 carrier 验证 Information Space 恢复（P3）与非伪造（P4）；D3 才是模型 + PALACE 的端到端。D1 通过不授权 D2/D3。
- **D1 前必须裁决的五件事**：① 关闭或显式排除 `consumeBinding` → 注册窗口；② 两 worker 进程监督结构（进程内 runner 无法满足 `distinct_live_worker_pids`）；③ 受审查的拒绝计划与一次性 marker；④ 内存数字只作描述性观测（不主张页归还）；⑤ D2 保持独立授权、D3 另立包。这五项已按所有者 2026-10-21 的建议记录为 D1 协议基线 D1-D1 … D1-D5；性质是**技术基线，不是执行授权**，仍待逐项签署。
- **D1 协议状态**：方法已冻结（sidecar digest），但纯静态审查未通过（SR1–SR10 中仅 SR7 为完整 PASS），因此 **D1 执行门未通过**；无 marker、无 provider 注册、无模型加载。
- **当前不改变的状态**：registry 为空；无 marker；无模型加载；无 G3 执行；不提交 lab 工作树（HEAD `c0ac9694`）。

## 1. Frozen state baseline

| Item | State |
| --- | --- |
| A: refusal control-flow audit | PASS, limited to the audited path |
| B: model-free fault injection | PASS, limited to current test coverage |
| C: lifecycle audit | PASS, with the limits in section 5 |
| D: real-model validation | NOT ENTERED / NOT AUTHORIZED |
| Provider trust registry | EMPTY |
| Model loaded / G3 executed | NO / NO |
| Lab worktree committed | NO (HEAD `c0ac9694`) |

C is closed at "lifecycle control-flow audit passed", not at "concurrency-safe
lifecycle". A/B/C together support: within the G3 path, a refusal cannot reach
sampling, token commit, ES settlement, or a settled report; release, exception
and cancellation paths fail closed at the measured boundaries. They do not
support any model-level, allocator-level, or PALACE-level claim.

The C closure is registered separately as `G3-C = CLOSED` in
`docs/06-closure/G3_C_CLOSURE_20261021.md`. This document is the D boundary,
not the C record.

## 2. Why D cannot be inferred from A/B/C

A/B/C exercise native `KVCacheSimple` objects and model-free control flow. They
do not exercise a loaded model's real cache topology, its real `newCache`
result, the scheduler that drives it, or the way a real forward propagates a
refusal through every layer and into sampling. Treating A/B/C as D evidence
would be a scope error: the tests prove the wiring, not the loaded behavior.

D also cannot be inferred from the existing G3/PALACE dry run. That harness
uses a stub calculator, records `is_execution_evidence: false`, and explicitly
states that a formal G3 batch requires separate authorization.

## 3. D is three separately gated batches, not one run

The four propositions below have different evidence sources. Running them in one
batch would confound the result: a model-level KV refusal and a PALACE
settlement recovery would each be able to "pass" while the other's artifacts
are misattributed. D is therefore split.

### D1 — model-level refusal propagation and old-KV release

Propositions:

- **P1 (refusal propagation).** A KV write refusal at a planned layer and step
  stops the arm before the refused step's token is read, committed, settled, or
  reused, and does not affect the peer arm.
- **P2 (old-KV release).** After a settled execution releases its cache, no new
  execution state holds, claims, or reads the old KV; a new execution starts
  from a fresh cache and matches a cold control run.

D1 uses one model, two worker processes, one arm per process. It does not make
any PALACE settlement claim.

The frozen method — topology, phases, refusal plan, budget, evidence schema,
static-review gate, non-claims, and the decisions that still need sign-off
(PS1, CA1–CA4, IC1–IC4) — is in
`SIMIGO2_G3_D1_EXPERIMENT_PROTOCOL_V0.1_20261021.md`. That protocol does not
authorize execution and cannot issue a marker while any static-review row is
GAP.

### D2 — settlement and Information Space recovery (deterministic carrier)

Propositions:

- **P3 (IS recovery).** A new execution state restores the already-settled
  results from the sealed PALACE Information Space and continues execution
  without recomputing the settled units.
- **P4 (non-fabrication).** The recovered result is not produced by cache
  residue, a retry, or a silent recomputation; the compute/reuse logs and the
  cold control agree with the pre-registered partition.

D2 reuses the G3/PALACE fixtures, gate process and carrier mechanics, with a
deterministic calculator. It does not use a live LLM and does not inherit the
G3 model-start authorization. It has its own authorization; a D1 PASS does not
authorize D2.

### D3 — model-backed end-to-end

Only after D1 and D2 both PASS. D3 asks whether a real model execution can
settle into the Information Space and whether a later execution can recover
that settlement and continue. D3 requires a new package; it cannot be claimed
from D1 + D2 by composition.

This document defines D1 in detail and the D2 boundary criteria at minimum
observable level (section 4.6), because D1 is the next decision. D2 must freeze
its own thresholds and expected sets in its own package; D3 remains boundary
level until D1 and D2 are decided.

## 4. D1 falsifiable acceptance criteria

Every criterion below must be observable in a write-once evidence record and
must have a declared falsifier. "The run looked correct" is not evidence.

### 4.1 Preconditions that must be true before D1 is requested

1. **Two live workers.** `RuntimeIsolationGate.requiredFieldNames` includes
   `worker_pid`, and the gate checks `distinct_live_worker_pids`. The existing
   in-process `G3DualArmRunner` drives both arms sequentially in one process
   and therefore cannot satisfy this check. D1 needs a supervisor plus two
   child workers. Relaxing the gate to one PID is forbidden. The MLX-free
   `g3-swift-isolation-entry` executable is a gate control point, not a model
   worker; it cannot be counted as one of the two workers. The D1 protocol §3
   fixes the supervisor/W1/W2/W3 split and how the supervisor evidences two live
   PIDs; the gate's own check is only a PID-shape check, not a liveness probe.
2. **Read-only weights, distinct runtime state.** Both workers may map the same
   model artifacts read-only (`same_valid_model_content`, same tokenizer
   content), but must report distinct model, tokenizer, weights-buffer,
   KV-cache, prefix-cache and runtime-buffer instance ids, and disjoint write
   roots.
3. **Reviewed refusal plan.** P1 needs a deliberate, observable refusal. The
   plan must name the arm, layer and step, carry a stable digest, be
   constructible only in the D1 harness, and be inactive unless a one-shot
   marker is consumed. A production binary must not contain an enabled plan.
   The plan must be pre-registered with the expected token prefix and the
   expected gateway reason. The mechanism, its trigger offset, and the one
   production seam it needs (PS1) are in the D1 protocol §5 and Appendix B.
4. **No-injection control.** A control run with the same model and prompt but no
   refusal plan must produce the standard token sequence and a settled report.
   This proves the injection itself did not alter the standard path.
5. **Frozen vendor fork.** The vendored `mlx-swift-lm` commit and the two seam
   definitions (`KVCacheWriteObserver`, `KVCacheIsolationObserving`) are frozen
   for the run and identified by digest. D1 may not add a new seam mid-run.
6. **Irreversible-window decision.** `continueExecutionG3WithPerArmCache`
   consumes the ES binding before `duringGenerationRegistration` runs. A
   registration failure after that point cannot un-consume the binding. D1 must
   either (a) close this ordering in a separately reviewed change before the
   run, or (b) pre-register that a registration failure invalidates the run and
   is excluded from every settlement claim. Option (b) is a limitation, not a
   fix; it must appear in the D1 evidence and report. The D1 protocol adopts
   option (b) as D1-D1 and fixes the invalid-run label
   (`INVALID_IRREVERSIBLE_ES_ADVANCED`).
7. **Serial driver contract.** One task drives one arm. The executor and session
   are not thread-safe by design. Concurrency stress is out of scope for D1 and
   would need its own package.

### 4.2 P1 — refusal propagation

Pre-registered inputs: arm (ES+IS), layer L, step S, prompt tokens, expected
prefix `[t1 … t(S-1)]`, expected refusal reason `R`.

| Observable | PASS | Falsifier |
| --- | --- | --- |
| Generated tokens for the refusing arm | exactly the prefix, no token at S | any token at or after S |
| Sampler invocations | exactly S-1 | >= S |
| `consumeBinding` calls for the refusing arm | 0 | >= 1 |
| Runner record | `settled: false`, `isExecutionEvidence: false` | `settled: true` |
| `fellBackToStandard` / standard-route calls | false / 0 | true / >= 1 |
| Gateway `terminatedReason` | equals `R` | nil or different |
| Later layers in step S | refused with `arm_terminated_after(R)`, window unchanged | any later-layer KV written |
| Peer arm | its own `settled: true`; its cache never refuses | peer terminated or affected |
| A second G3 continuation on the refusing arm | refused before any forward (`armTerminated` / retired slot); no token, no settlement | a second forward or a settled result |
| Cache state of the refusing arm after the run | no readable advance beyond S-1; session terminated | cache readable as a live execution |

The "later layers" and "peer arm" rows are the model-level counterpart of B1
and B2. They must be observed on the real model's per-layer cache array, not on
a test cache.

### 4.3 P2 — old-KV release

Run sequence: (1) settle one D1 execution with cache C_old; (2) call
`releaseG3KVCache()`; (3) start a new execution with a fresh cache C_new and a
different prompt; (4) compare with a cold control process that never saw C_old.

| Observable | PASS | Falsifier |
| --- | --- | --- |
| C_old object graph | weak probes for cache, gateway, observer are nil after release | any non-nil |
| Old session | `abortReason == cache_session_released`; `claimContinuation()` false; `runStep` refused | old session can step or claim |
| Old slot | installed nil, retired true; further install false | install succeeds |
| C_new identity | a different KV-cache instance id from C_old | same instance id |
| New execution output | token-for-token equal to the cold control | any divergence |
| New execution's cache writes | start at offset 0 for the new prompt; no old prefix | old prefix reused |
| Memory observables | `Memory.activeMemory`, `cacheMemory`, `peakMemory` recorded before/after release | not a PASS gate (see R3) |

The cold-control equality is the anti-fabrication check for P2: if any old KV
leaked into C_new, the outputs would differ from a process that never held it.

**R3 limit.** MLX documents `cacheMemory` as memory "not currently used that has
not been returned to the system allocator… kept in a buffer pool". Object
deallocation is therefore not evidence of physical return. D1 records the
memory numbers as descriptive observables and makes no page-return claim. A
separate allocator-level experiment would be required to claim reclamation.

### 4.4 D1 anti-fabrication controls (the D1 portion of P4)

P4 proper — Information Space non-fabrication — belongs to D2. D1 still has to
show that its own observables were not produced by cache residue or a retry:

- The refusal plan digest, layer, step and expected prefix are frozen before the
  run and included in the evidence.
- The generated prefix is compared against an independent, no-cache recompute
  of the same prompt in a control process. The refusing arm's prefix must match
  the control prefix; the refused step must be absent. A "plausible" output is
  not enough.
- The sampler and `consumeBinding` counters are instrumented before the run and
  their instrumentation is itself digest-bound.
- A sentinel token or prompt is included so that a cached continuation from a
  previous execution would produce a detectable wrong token.

### 4.5 P3 (D1 boundary)

D1 does **not** test PALACE recovery. `ExecutionContinuationResult` and
`consumeBinding` are execution-state mechanics, not Information Space
settlement. Any statement about settlement or recovery belongs to D2/D3.

### 4.6 D2 boundary criteria (P3/P4, deterministic carrier)

D2 uses the G3/PALACE fixtures, gate process and carrier mechanics with a
deterministic calculator. It is not the formal G3 model batch and does not
inherit its 20 model-start authorization. The expected sets below come from
`g3/preregistration/G3_PREREGISTRATION.json`; the dry-run numbers are design
counts, not evidence (`is_execution_evidence: false`, `model_starts: 0`).
Thresholds and expected values must be frozen in the D2 package before the run.

| Observable | PASS | Falsifier |
| --- | --- | --- |
| Reused set, per step (`es_reused`) | equals the pre-registered reused set | missing or extra reuse |
| Recomputed set, per step (`es_recomputed`) | equals the pre-registered recomputed set | a settled unit is recomputed |
| Unsettled set, per step (`es_unsettled`) | equals the pre-registered unsettled set | a settled unit is reported unsettled, or the reverse |
| Set partition | reused / recomputed / unsettled are pairwise disjoint and cover the universe | overlap or gap |
| Continuation position (`es_state`, `next_step`) | ADVANCED at every probe; the position comes only from restored settlements | position from a stale basis, or stalled |
| Compute log (`es_compute_log`) | one calculator call per computed unit, in the pre-registered order | extra calls, silent recomputation, or a reused unit in the log |
| Retries | 0; one run under one consumed authorization | any retry or second run |
| Source change | `u1_u2_recomputed_after_source_change` and `free_item_reused_after_source_change` hold | a stale settlement is reused after a source change |
| Negative gates | expired and tampered settlements are refused with `database_unchanged: true` | accepted, or the database is mutated |
| Initial bytes | `initial_is_bytes_identical` before either arm runs | the arms start from different IS bytes |
| Arm isolation | `is_denied_touches == []`; `arm_writes_do_not_cross_to_the_other_arm` | any denied touch or cross-arm write |
| Non-fabrication | every PASS above is re-derived from carrier bytes, not from a pre-filled expected set | a PASS row is only the harness's self-reported verdict, with no independent re-derivation |

P3 is satisfied only if the reused set is restored from the sealed Information
Space and the continuation position follows from it. P4 is satisfied only if the
compute log, the source-change checks and the negative gates rule out cache
residue, retry and silent recomputation.

## 5. C limits carried into D

These are preconditions/limits, not D claims:

1. **R1 — Release does not imply concurrency safety.** The atomic continuation claim,
   cancellation checks and weak-probe release test prove three different
   properties. The executor still assumes one serial driver per arm. D1 must
   preserve that assumption; it may not present the C tests as thread safety.
2. **R2 — The consume/registration window is irreversible.** A registration failure
   after `consumeBinding` cannot be undone. D1 must resolve it or declare it.
3. **R3 — Object deallocation is not physical reclamation.** See 4.3 above.
4. **Forward compute is not cancelled.** After a refusal the remaining forward
   is inert (no KV write, logits unread), not aborted. D1 must use the same
   wording.
5. **Partial KV remains.** Layers that wrote before the refusal keep their
   bytes; termination makes them unreachable, not erased.

## 6. D1 observable evidence record

One write-once JSON record per run, with at least:

```text
schema_id, run_id, started_at_utc, ended_at_utc, outcome
authorization: marker_path, marker_sha256, consumed_at_utc, one_shot
provider: provider_type, provider_id, source_revision, source_sha256
model: model_directory, config_sha256, tokenizer_sha256, weight_sha256[]
workers: [worker_pid, isolation_unit_id, model_instance_id, tokenizer_instance_id,
          weights_buffer_instance_id, kv_cache_instance_id,
          prefix_cache_instance_id, runtime_buffer_instance_id,
          kv_cache_namespace, prefix_cache_namespace, runtime_write_root]
gate: report (all checks), failed_checks, evidence_class,
      eligible_for_runtime_evidence, model_generation_started_by_gate
refusal_plan: digest, arm, layer, step, expected_reason, expected_prefix[]
per_arm: generated_tokens[], sampler_invocations, consume_calls,
         settled, fell_back_to_standard, standard_route_calls,
         gateway_terminated_reason, session_terminated, slot_retired
release: weak_cache_nil, weak_gateway_nil, weak_observer_nil,
         old_session_claim_refused, old_session_step_refused
memory: active_bytes[], cache_bytes[], peak_bytes[]   # descriptive only
control: no_injection_tokens[], cold_control_tokens[],
         prefix_match, cold_match
checks: {name: bool}, failed_checks[]
non_claims: [...]
```

The record must be written in create-exclusive mode and must not be rewritten.
A FAIL record is evidence and must be retained. A run with a missing field, a
type mismatch, or inconsistent PASS/FAIL artifacts is invalid, not passed.

`consume_calls` is amended by CA1 in the D1 protocol: the internal
`consumeBinding` has no counter and no injection point, so the row becomes
`binding_present_after_refusal: true` plus `binding_consumed_on_settle`. The
amendment is effective only after the owner signs CA1; until then this record
keeps the original field and D1 cannot claim the row.

## 7. Cleanup, abort and rollback

| Stage | Required cleanup | Evidence |
| --- | --- | --- |
| Before marker | unload nothing; no model started; registry unchanged | no artifact |
| Marker consumed, gate refused | terminate/release both sessions; kill workers; no generation | refusal record; marker consumed, not reusable |
| Gate cleared, before first forward | release sessions; kill workers; no token | invalid-run record |
| Refusal during D1 step | terminate refusing arm; release both; kill workers; no fallback; no second run under the marker | FAIL/expected-refusal record |
| Registration failure after consume | invalid run; cannot roll back ES; record the consumed binding and the failed hook | `invalid_irreversible_es_advanced` |
| Crash / timeout | process-group kill; write-once partial record; marker consumed; no rerun | crash record; orphan check |
| PASS | release both caches; unload both models; seal evidence; revert the registry diff; no production enablement | PASS record + cleanup record |

No retry is allowed under a consumed marker. A failed D1 run requires a new
authorization package and a new marker; it must not be "rerun until green".

## 8. Untouchable standard paths

The following are out of scope and must not be modified or exercised by D1:

- `MLXPrefixRecomputeExecutor.continueExecution` (the `cache: nil` recompute
  path) and any normal inference path.
- `G3ExecutionDispatch.standard` and any fallback from `.g3`.
- `RuntimeProviderTrustPolicy` beyond the exact reviewed type registration in
  the authorized diff; the registry must remain empty until that authorization.
  After the run, the registration must be reverted.
- Fixture providers, deterministic mocks, and any "live-looking" provider that
  is not the registered concrete type.
- The Python G3 gate, calculator harness, fixtures, and PALACE canonical
  database. D1 does not write to the canonical Information Space.
- Model artifacts: read-only mapping only; no weight rewrite, no tokenizer
  rewrite, no cache-limit tuning that changes the model's standard behavior.
- The vendored fork: frozen commit; no seam changes during the run.
- CLI defaults, production configuration, or any path that could make G3 the
  default.

## 9. Authorization gate

D1 execution requires a separate, one-shot authorization package containing the
frozen D1 protocol (`SIMIGO2_G3_D1_EXPERIMENT_PROTOCOL_V0.1_20261021.md`) and its
`.sha256` sidecar, plus:

1. the frozen D1 acceptance criteria (section 4), with every threshold and
   expected value;
2. the exact provider type to be registered and the exact diff that registers
   it, reviewed by a second person;
3. model identity and hashes, worker count, prompt set, refusal plan, expected
   results, and the control-run definition;
4. a one-shot marker path, a consumed-marker path, atomic-rename-before-launch
   semantics, and a write-once evidence path that must not exist before the run;
5. a budget: model starts, forwards, max tokens, wall clock, process-group
   timeout, and the rule that a consumed marker cannot be reused;
6. the cleanup/abort matrix in section 7, including the irreversible-window
   decision;
7. an explicit list of non-claims (section 10).

The protocol's static-review table must be all PASS before a marker may be
issued. Today only SR7 is a full PASS: SR2/SR5/SR6/SR9/SR10 are full GAPs,
SR1/SR3/SR4/SR8 have implementation or identity GAPs, PS1/CA1–CA4 are unsigned,
and the IC1–IC4 implementation constraints are unmet. A protocol digest alone is
not an execution gate.

Until that package is granted: registry empty, no marker, no model load, no G3
run, no lab commit.

## 10. Non-claims

D1, even if it passes, does not claim:

- that MLX forward execution was cancelled;
- that partial KV was erased;
- that GPU/Metal pages were returned to the OS;
- that the executor is thread-safe or safe under concurrent release;
- that the registration-after-consume window is closed;
- that PALACE Information Space recovery works, or that settled results can be
  restored from the canonical carrier;
- that G3 is a production gate, or that any standard inference path changed;
- that the Python G3 authorization is granted or its dry run is model evidence.

## Appendix A — Symbol map

| Concern | Symbol / file |
| --- | --- |
| Gate entry | `RuntimeIsolationGate.requireIsolation(provider:request:)` |
| Trust registry | `RuntimeProviderTrustPolicy.registeredLiveProviderTypes` |
| Strict gate fields | `RuntimeIsolationGate.requiredFieldNames` (`worker_pid`, …) |
| Gated generation | `G3FirstGenerationEntry.runAsync` |
| Two-arm driver (in-process, sequential) | `G3DualArmRunner.run` |
| Per-arm session | `G3ArmCacheSession`, `G3CacheSessionSlot` |
| Per-arm native cache | `MLXKVCacheBoundary`, `G3KVAllocationGateway` |
| Refusal seam | `KVCacheWriteObserver` in `KVCacheSimple.update` |
| Consumer seam | `KVCacheIsolationObserving.onIsolationAbort` |
| ES consume / registration order | `MLXPrefixRecomputeExecutor.continueExecutionG3WithPerArmCache` |
| Memory observables | `Memory.activeMemory`, `Memory.cacheMemory`, `Memory.peakMemory` |

## Appendix B — Decisions requested before D1 can be packaged

Recorded in the D1 protocol as the owner's 2026-10-21 recommendations
(`D1-D1 … D1-D5`). They are technical baselines, **not execution grants**; each
stays an open decision until it is explicitly signed.

1. R2 — recorded as an **accepted limitation** (D1-D1): the window is not closed;
   a registration failure after `consumeBinding` makes the run
   `INVALID_IRREVERSIBLE_ES_ADVANCED`, never PASS. Still requires sign-off.
2. Two-worker supervisor — recorded as D1-D2: independent supervisor plus two
   worker child processes; the in-process runner is not sufficient for
   `distinct_live_worker_pids`. Still requires sign-off.
3. Refusal plan and one-shot marker — recorded as D1-D3, with the mechanism in
   protocol §5 and the required production seam PS1
   (`G3KVAllocationGateway.terminate(reason:)`). PS1 still requires sign-off.
4. Memory observables descriptive only — recorded as D1-D4; no page-return
   claim, no memory threshold as a PASS condition. Still requires sign-off.
5. D2 separate and deterministic-carrier; D3 a later, separately reviewed
   package — recorded as D1-D5. Still requires sign-off.
