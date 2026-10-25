# SimiGo2 G3 — D1 Frozen Experiment Protocol v0.1

> **Status:** PROTOCOL FROZEN — D1 NOT AUTHORIZED
> **Date:** 2026-10-21
> **Normative companion:** this file (frozen by its `.sha256` sidecar)
> **D boundary:** `docs/00-governance/SIMIGO2_G3_RUNTIME_ISOLATION_D_AUTHORIZATION_BOUNDARY_V0.1_20261021.md`
> **C closure:** `docs/06-closure/G3_C_CLOSURE_20261021.md` (`G3-C = CLOSED`)
> **Provider trust:** `RuntimeProviderTrustPolicy.registeredLiveProviderTypes = [:]` (unchanged)
> **Marker:** none
> **Model loads / generation:** none at freeze time
> **Lab commit:** none (HEAD `c0ac9694`, worktree uncommitted)

This document freezes the **method** by which D1 would be run. It does not
authorize D1, does not create a marker, does not register a provider, does not
load a model, and does not start generation. A frozen protocol is a prerequisite
for an authorization package, not a substitute for one.

The five owner recommendations of 2026-10-21 are recorded as protocol decisions
D1-D1 … D1-D5. They are technical baselines for review, not execution grants.

## 0. 决策摘要（中文）

- **本文性质**：D1 实验协议冻结稿。它把五项裁决落成可执行条款，并记录一次
  纯静态审查的结果；它不授权执行，不生成 marker，不注册 provider，不加载模型。
- **五项裁决已写入**：R2 窗口显式接受为已知限制；独立 supervisor + 两个独立
  worker 子进程；先冻结拒绝计划再发一次性 marker；内存只作描述性观测；D2/D3
  完全独立授权。对应 D1-D1 … D1-D5。
- **静态审查的新发现**（不是文档措辞问题，是架构约束）：
  1. 进程内 `G3DualArmRunner` 在 dispatch 前调用 `G3OwnershipIsolation.check`
     并把两个 owner 互相 `seal(against:)`；两个进程各持一个 owner，无法复用这条
     路径。D1 需要一个由对端 attestation 构造的 **peer-snapshot owner**，或一个
     受审查的跨进程 seal API。
  2. `G3KVAllocationGateway` 是 `final`，`handleCacheWrite` 是 `internal`，
     `G3AllocationRegistrar` 也是 `final`；D1 没有任何公开入口把一个“计划拒绝”
     注入生产 gateway 的不可复位锁存。要么增加一个一行的 `terminate(reason:)`
     seam，要么把级联锁存降级到 harness，并修改 P1 的一行判据。
  3. `consumeBinding` 没有注入点或计数器；可观察的后置条件是拒绝后
     `boundPrefix` 仍然返回原前缀（消费会删除绑定）。因此 `consume_calls: 0`
     必须改为 `binding_present_after_refusal: true`。
  4. gate 是每次进程内的首次生成门；同一进程的第二次 continuation 会被
     `generation_invocations_before_gate != 0` 拒绝，无法用来测 P2 的“新执行”。
     P2 的新执行必须改为**同进程 fresh-cache step probe**（cache 级，不是 ES 级）。
  5. 真实 provider 类型必须位于 `SimiGoRuntimeContract`（registry 在该模块），
     不能位于 worker 可执行文件；注册是一个受审查的 diff，跑完必须回退。
- **状态**：协议文本已冻结（sidecar digest），但 **D1 执行门未通过**。静态审查
  的 SR1–SR10 中，仅 SR7 为完整 PASS；SR2/SR5/SR6/SR9/SR10 为完整 GAP；
  SR1/SR3/SR4/SR8 为“设计或候选 PASS、实现或身份半边 GAP”。CA1–CA4 与 PS1
  需要所有者书面裁决。
- **现在不允许**：生成 marker、注册 provider、加载模型、运行 worker、提交工作树。

## 1. Claim scope

D1 may claim only P1 and P2, and only for the frozen model, prompts, refusal plan,
and process topology in this protocol.

| In scope | Out of scope |
| --- | --- |
| Real-model refusal propagation inside one arm (P1) | PALACE settlement recovery (P3) |
| Peer-arm/control non-interference at process level | Information Space non-fabrication (P4) |
| Old-cache release and same-process fresh-cache reuse (P2) | End-to-end model + PALACE (D3) |
| Two live worker PIDs, inspected by the gate | Thread safety, concurrent driver safety |
| Descriptive memory observables | GPU/Metal page return to the OS |
| One-shot authorization and no-retry semantics | Production readiness or a G3 default route |

A D1 PASS does not authorize D2 or D3. A D1 PASS does not turn the C tests into
a concurrency proof, and does not close the R2 window.

Untouched by this protocol, and re-checked as SR7 before a marker:
`MLXPrefixRecomputeExecutor.continueExecution` (the `cache: nil` recompute path),
`G3ExecutionDispatch.standard`, and any fallback from `.g3`.
`RuntimeProviderTrustPolicy.registeredLiveProviderTypes` stays empty until the
single authorized registration diff, and is reverted after the run. D1 does not
make G3 a default route and does not pre-register provider trust as preparation.

## 2. Owner decisions recorded

### D1-D1 — R2 irreversible window: accepted limitation

`MLXPrefixRecomputeExecutor.continueExecutionG3WithPerArmCache` calls
`backend.consumeBinding(for: state)` (line 404) before the gated method returns;
`duringGenerationRegistration` runs only after that return (the wrapper's hook
call is at line 251).
A registration failure after that point cannot un-consume the binding.

D1 accepts this window and does not modify ES commit semantics. If the
registration hook throws after `consumeBinding`, the run is recorded as
`INVALID_IRREVERSIBLE_ES_ADVANCED`: not PASS, not FAIL, no settlement claim, the
consumed binding and the hook error are recorded, and the consumed marker is not
reused. W2 installs the hook precisely so this branch is observable.

Falsifier of this decision: a report that labels a registration-failure run as
PASS, or that claims the binding was restored.

### D1-D2 — Independent supervisor plus two worker processes

The in-process `G3DualArmRunner` drives both arms sequentially in one process
(`let a = await drive(first, …); let b = await drive(second, …)`, lines 224–225)
and cannot satisfy `distinct_live_worker_pids` (`observations.count == 2` and two
distinct positive PIDs, `RuntimeIsolationGate.swift:323,331`). Relaxing the gate
to one PID is forbidden. The MLX-free `g3-swift-isolation-entry` executable is a
gate control point, not a model worker, and is not counted as a D1 worker.

D1 uses one supervisor process plus two worker child processes, one arm per
worker, each in its own process group. The supervisor starts, coordinates,
terminates, reaps, and assembles evidence; it does not forward.

Falsifier: a D1 run whose gate observations contain one PID, a reused PID, or a
worker that is the MLX-free entry.

### D1-D3 — Freeze the plan, then issue one one-shot marker

The refusal plan, model identity, runner manifest, expected results, budget, and
cleanup matrix are frozen before any marker exists. The marker binds their
digests and is consumed by an atomic rename **before** the workers are spawned.
A missing/mismatched field, an existing evidence root, a consumed marker, or a
budget overrun is fail-closed. No implicit retry; no second run under a consumed
marker.

Falsifier: a run that starts without a consumed marker, or a second run that
reuses a consumed marker.

### D1-D4 — Memory observables are descriptive only

Record `Memory.activeMemory`, `Memory.cacheMemory`, `Memory.peakMemory`, cache
object lifetime, and process liveness. No memory threshold is a PASS condition,
and no result claims pages were returned to the OS. MLX documents `cacheMemory`
as memory retained in a buffer pool, not as proof of release.

Falsifier: a PASS row whose truth depends on a memory decrease, or a claim of
physical reclamation.

### D1-D5 — D2 and D3 are separately authorized

D1 does not inherit the G3/PALACE 20 model-start authorization, does not use the
stub calculator, and does not write to the canonical Information Space. D2 stays
a deterministic-carrier package with its own marker. D3 requires a new package
after D1 and D2 both pass.

Falsifier: a D1 report that cites P3/P4, or a D1 run that touches PALACE.

## 3. Topology

| Role | Process | Responsibility | Never does |
| --- | --- | --- | --- |
| Supervisor | `G3D1SupervisorTests.testSingleAuthorizedRun` (XCTest, marker-gated, skipped without a marker) | Preflight, marker consumption, spawn, PID/liveness checks, preflight gate, `go`/`abort`, reaping, evidence assembly | Load a model, forward, write a worker result |
| W1 | `G3D1Worker --arm es` | Refusing arm: load model, build per-layer caches, gate, refuse at plan point, second-attempt probes | Settle a result, touch the peer's files |
| W2 | `G3D1Worker --arm is` | Settling arm: load model, settle 4 tokens, release, weak probes, fresh-cache probe | Refuse, read W1's cache |
| W3 | `G3D1Worker --mode control` | Cold reference: three no-cache greedy loops, no gate, no ES | Use a G3 cache session, write a settlement |

W1 and W2 run **concurrently** so the gate sees two live worker PIDs during the
same run. W3 starts only after both W1 and W2 have exited and been reaped. The
supervisor is not a worker and never appears in `worker_pid`.

The two workers share read-only model/tokenizer artifacts but have distinct
model, tokenizer, weights-buffer, KV-cache, prefix-cache, and runtime-buffer
instance ids, disjoint namespaces, and disjoint `runtime_write_root`s.

Process groups: `posix_spawn` with `POSIX_SPAWN_SETPGROUP`, pgroup 0, as in the
proven smoke harness (`ActualMLXSmokeValidation.swift:672–713`). Timeout and
cleanup use `kill(-pgid, SIGTERM)`, then `kill(-pgid, SIGKILL)`, then `waitpid`.

PID evidence: each worker writes `worker_pid = getpid()` in its prepared record;
the supervisor checks `kill(pid, 0) == 0` and `Set(pids).count == 2` before
writing `go`, and re-checks after the run; the gate independently checks
`distinct_live_worker_pids`. That gate check is a PID-shape check — two distinct
positive integers (`RuntimeIsolationGate.swift:330–333`) — not a liveness probe.
Liveness is evidenced by the supervisor's `kill(pid, 0)` observations and by both
workers' concurrent prepared/result records. This is recorded as a limitation of
the gate, not as a claim that the gate proves liveness.

## 4. Phase protocol

### Phase 0 — Supervisor preflight (no process, no model)

1. Marker exists, is readable, has `schema_id = G3-D1-AUTHORIZATION-V1`, and its
   `protocol_sha256` equals the frozen sidecar digest.
2. No `G3_D1_AUTHORIZATION_CONSUMED` exists; the evidence root does not exist.
3. Model manifest: every file digest matches the frozen manifest; the manifest
   digest equals the marker's `model_manifest_sha256`.
4. Runner manifest: worker binary, supervisor test binary, library source digest,
   and vendor seam digests match the marker.
5. The provider registry diff is exactly the one authorized entry; no other live
   provider is registered.
6. Free unified memory is at least 48 GiB (two concurrent 16 GiB models plus
   overhead), or the owner has signed a sequential-fallback amendment (not
   granted in v0.1).
7. No `G3D1PlannedRefusal` symbol is present in `simigo2ctl`, `SimiGo2App`, or the
   library binary; the plan type is linked only into `G3D1Worker`.

Any failure aborts **without consuming the marker** and writes a refusal record
under `refusals/` (create-exclusive, outside the run evidence root).

### Phase 1 — Consume, spawn, prepare

1. Atomically rename the marker to `G3_D1_AUTHORIZATION_CONSUMED`; record the
   marker digest and consumption time.
2. Create the evidence root with `O_CREAT | O_EXCL` (must not pre-exist).
3. Spawn W1 and W2 with `posix_spawn` in separate process groups; stdout/stderr
   to create-exclusive files under the evidence root.
4. Each worker loads the model and performs this exact composition, in order:
   a. `let caches = context.model.newCache(parameters: nil)`; validate every
      layer is exactly `KVCacheSimple`, one distinct instance per layer.
   b. Create a stable per-arm `D1CacheHolder` that owns the `[KVCache]` array.
      Pass that holder as the probe's `kvCache` object and supply an
      `opaqueMutableIdentity` fold that returns a confirmed id for it. A nil
      fold is a fail-closed refusal, not a pass; the pre-run cache holder must
      not be `.indeterminate`. The holder is built before the session because
      the owner/registrar are needed to build the session; the holder and the
      session share the same cache array.
   c. `let execution = executor.g3ArmExecution(armID:probe:provider:request:
      state:nextInputTokens:maxTokens:)`; this builds the owner and binds the
      probe's registration channel.
   d. `execution.owner.seal(against: peerSnapshotOwner)`; the peer snapshot is
      built from the other worker's attested mutable ids (IC2).
   e. `guard let registrar = execution.owner.makeRegistrar() else { fail closed }`;
      the accessor returns `nil` unless the owner is `.sealed`, so a nil registrar
      is a precondition failure, not a reason to continue. Build the session with
      `MLXPerArmKVCacheFactory.makeSession(armID:registrar:caches:)` over the
      same array the holder owns, then wrap layer 24's observer with the D1
      decorator, then `executor.installG3CacheSession(session)`.
   f. Write `prepared-<arm>.json` with `worker_pid`, `pgid`, `binary_sha256`,
      `model_manifest_sha256`, all sixteen `RuntimeResourceObservation` fields,
      `cache_layer_count`, `cache_types`, `cache_offsets` (all zero),
      `model_load_started_at`, `forward_count = 0`.
5. Bind each worker's state before `go`:
   `backend.bind(executionID: state.id, position: state.position, tokenPrefix: [])`
   with `state.position = ExecutionPosition(0)` and `lifecycle = .active`; record
   `bound_prefix_length = 0` and `bound_position`. The worker keeps its own
   reference to the backend (`MLXPrefixRecomputeExecutor.init(container:backend:)`
   takes it; the executor's property is private). Without this binding the gated
   call would refuse at `boundPrefix(for:)` for a reason unrelated to the
   experiment. With an empty bound prefix, W1's plan offset is
   `len(nextInputTokens) + 6`.
6. No forward runs in this phase. Building empty caches allocates no KV bytes.

### Phase 2 — Preflight gate and `go`

1. The supervisor waits for both prepared records within `prepare_timeout = 600 s`.
2. It verifies both workers are alive (`kill(pid, 0)`), the PIDs are distinct, the
   write roots are disjoint, the model manifest digests are equal, and every
   required field is non-empty and well-typed.
3. It writes `attestation-bundle.json` containing both attestations and the
   supervisor's liveness observations.
4. It evaluates `RuntimeIsolationGate.requireIsolation` once with
   `D1AttestationProvider(bundle:)` and records `gate-supervisor.json` (all
   checks, failed checks, `eligible_for_runtime_evidence`,
   `modelGenerationStartedByGate = false`).
5. If the gate refuses, it writes `abort`, goes to cleanup, and no worker
   forwards. If it passes, it writes `go`.
6. The supervisor's gate is a preflight. Each worker's in-executor gate remains
   authoritative and runs immediately before that worker's first forward.

Envelope requirements, enforced by `RuntimeIsolationGate.validateBatch`
(`RuntimeIsolationGate.swift:495–555`): exactly two attestations in
`expectedArms` order `[ES+IS, IS-only]` (W1 first, W2 second); both carry the same
`providerID`/`providerKind`, the same `run_id` and `challenge_nonce`, a non-empty
`source_revision`, a 64-lowercase-hex `source_sha256`, and a UTC ISO-8601
`captured_at_utc`. The gate derives `observedFields = requiredFieldNames` from
the validated envelope; that provenance item is not a per-field sampling audit —
the individual predicates and the workers' prepared records are what actually
check the values.

### Phase 3 — Execute

W1:
1. On `go`, call `executor.continueExecutionG3(state, nextInputTokens: …,
   maxTokens: 8, provider: D1AttestationProvider(bundle:), request: …)`. The
   in-executor gate runs inside `G3FirstGenerationEntry.runAsync` (line 219).
2. The generate closure sets `generation_started = true` before the first
   forward. On a gate refusal the closure never runs and `generation_started`
   stays false.
3. The refusal plan fires at layer 24, step 8 (section 5). The arm terminates;
   no token at step 8 is committed; `consumeBinding` is not reached.
4. Second-attempt probes (both required):
   a. `session.runStep(forward:candidateToken:)` with a forward closure that
      increments `probe_forward_count`; expect `.refusedAfterTermination(R)` and
      `probe_forward_count == 0`.
   b. A second `executor.continueExecutionG3` reusing the same provider, whose
      `generationInvocationsBeforeGate` closure reads the worker's
      `generation_started` flag (now true, because step 8's forward was entered).
      The gate must fail `zero_generation_invocations_before_gate` and refuse;
      `probe_forward_count == 0`. Record `second_attempt_refusal_layer = gate`.
      The count is the live flag, not a hand-set constant.
5. Record `binding_present_after_refusal` by calling `backend.boundPrefix(for:)`:
   it must return the original prefix. If it throws `noBoundRepresentation`, the
   binding was consumed and P1 fails.

W2:
1. On `go`, call `executor.continueExecutionG3(..., maxTokens: 4, registrar:)`
   with `probe.bind(to: executor)` installed, so the registration hook runs after
   `consumeBinding`. It settles 4 tokens.
2. On success, record `binding_consumed_on_settle = true` (`boundPrefix` throws
   `noBoundRepresentation`) and `settled = true`.
3. Drop every harness-side strong reference to the probe, execution, owner,
   `D1CacheHolder`, and cache array (section 6). Then call
   `executor.releaseG3KVCache()`.
4. Run the old-session tombstone probe with a temporary strong reference, drop
   it, then sample the weak probes.
5. Run the fresh-cache probe on a new executor/session (section 6).

### Phase 4 — Control

After W1 and W2 exit and are reaped, the supervisor spawns W3. W3 loads the same
model and runs three greedy **no-cache** reference loops (one per prompt:
W1 prompt, W2 prompt, P2 prompt), each stepping `context.model(_, cache: nil)`
directly. It does not call `MLXPrefixRecomputeExecutor.continueExecution`, does
not use a cache session, and does not settle ES.

### Phase 5 — Seal

The supervisor reaps all workers, checks `kill(-pgid, 0) == ESRCH` for each group,
assembles `run.json`, derives every PASS/FAIL row from the records (never from a
pre-filled verdict), writes `cleanup.json`, and seals the evidence root
read-only. Evidence is never deleted, including a FAIL record.

## 5. P1 — refusal plan

### Plan

| Field | Value |
| --- | --- |
| plan id | `D1-ES-L24-S8` |
| arm | `es` (W1) |
| layer | 24 (0-based, of 48) |
| step | 8 (1-based; steps 1–7 commit) |
| absolute position | `len(bound.prefix) + len(nextInputTokens) + 6` (runtime) |
| reason | `d1_planned_kv_refusal` |
| expected prefix | the 7 tokens committed at steps 1–7 |
| expected later layers | 25–47, each `.refuse("arm_terminated_after(R)")` |
| armed by | `marker_sha256`; inactive without it |

The position formula follows the executor loop: step 1 writes the whole input at
offset 0; step `S ≥ 2` writes one token at `len(inputTokens) + S - 2`. The plan
is computed from the live `inputTokens.count`, not from a hard-coded prompt
length.

### Mechanism

A D1-only `KVCacheWriteObserver` decorator is installed on layer 24 **after** the
production `MLXKVCacheBoundary` has installed its observers. Its trigger is
`range.lowerBound == L0 + 6` on layer 24 — the step-8 token's pre-write offset;
no other step writes that offset. The `range` comes from the seam's own
signature (`kvCache(_:willWriteKeys:values:range:freshStorage:)`), so the trigger
does not depend on a harness-side step counter. On trigger the decorator calls
`gateway.terminate(reason: R)` and returns `.refuse(reason: R)`. Every other
write delegates to the production observer. Layers 25–47 then hit the gateway's
existing irreversible latch (`G3KVAllocationGateway.handleCacheWrite`, line 175)
and return `arm_terminated_after(R)`; their cache offsets do not advance.

`gateway.terminate(reason:)` does not exist yet. It is the one production seam
required by this protocol (PS1, Appendix B): a one-method, no-call-site addition
that reuses the private `refuse(_:)` latch. Without it, the refusal cannot enter
the real gateway and the P1 gateway rows cannot be observed.

### PASS / falsifier

| Observable | PASS | Falsifier |
| --- | --- | --- |
| Generated tokens | exactly the 7-token prefix | any token at or after 8 |
| Sampler invocations | 7 | ≥ 8 |
| Binding after refusal | `boundPrefix` returns the original prefix | `noBoundRepresentation` (consumed) |
| Runner record | `settled: false`, `isExecutionEvidence: false` | `settled: true` |
| Fallback | `fellBackToStandard: false`, standard calls 0 | any fallback or standard call |
| Gateway reason | `terminatedReason == R` | nil or different |
| Layers 0–23 at step 8 | offset `L0 + 7` (wrote) | offset unchanged (unexpected) |
| Layers 25–47 at step 8 | refused, offset `L0 + 6` | any offset advance or write |
| Peer/control | W2 settles its 4 tokens; W3 reference matches | W2 terminated or divergent |
| Second attempt (session) | `.refusedAfterTermination(R)`, forward 0 | any forward or commit |
| Second attempt (executor) | gate refusal, `zero_generation_invocations_before_gate` in `failed_checks`, forward 0 | any forward |
| Cache after the run | layer 24+ `isolationAborted`, session terminated | cache readable as live |

The "remaining forward is inert" wording is required: after the refusal the
forward continues through later layers with no KV writes, and the logits are
never read. Partial KV from layers 0–23 remains and is made unreachable, not
erased.

Evidence channel for a refused arm: the executor throws
`G3PerArmCacheError.armTerminated(reason:)` and never returns its local
`generated` array, so the token rows are read from the session ledger —
`session.committedTokens` (the partial prefix, deliberately not a settled
result; `G3ArmCacheSession.swift` doc on `committedTokens`), `session.stepCount`
(forwards entered, including the refused one), and `session.abortReason`. Each
entry in `committedTokens` is one `candidateToken()` call, so
`committedTokens.count` is the sampler-invocation count. No harness-side sampler
injection is required or allowed.

## 6. P2 — release and fresh-cache probe

### Sequence

1. W2 settles 4 tokens with `C_old`; `consumeBinding` removes the binding.
2. Drop harness references: `execution`, `probe`, `owner`, `D1CacheHolder`, and
   any local cache array. The executor's `g3CacheSlot` is then the only holder of
   the session.
3. `executor.releaseG3KVCache()`: terminates with `cache_session_released`, drops
   the per-layer caches, gateway, and observers, retires the slot.
4. Old-session tombstone: hold a temporary strong reference, call
   `session.runStep` with a forward closure that increments `probe_forward_count`;
   expect `.refusedAfterTermination("cache_session_released")` and count 0; drop
   the reference.
5. Old-slot check: `executor.installG3CacheSession(newSession)` returns `false`.
6. Weak probes: cache[0], gateway, observer are `nil`.
7. Fresh-cache probe: new executor + new owner + new boundary + new session, new
   8-token prompt. The new owner is sealed against the same peer snapshot and
   `makeRegistrar()` must be non-nil before the probe starts; otherwise every KV
   write is refused `owner_not_sealed` and the probe would fail for a setup
   reason, not a cache-residue reason. Build caches, assert every layer is
   `KVCacheSimple` with `offset == 0`, prefill the 8-token prompt (step 1), then
   run 7 one-token steps through `session.runStep` — 8 forwards, 8 committed
   tokens, final offset 15. Record tokens, offsets, admitted count, and
   `binding_consumed: false`.

### PASS / falsifier

| Observable | PASS | Falsifier |
| --- | --- | --- |
| C_old weak probes | all nil after step 2–3 | any non-nil |
| Old session | terminated; `runStep` refused; claim false | steps or claims |
| Old slot | retired; install false | install succeeds |
| C_new identity | different cache instance id | same id |
| C_new offsets | start at 0; after 8 steps offset = prompt length + 7 (15 for the 8-token prompt: 8 prefill + 7 decode) | old prefix or a non-zero start |
| C_new tokens | token-for-token equal to W3 for the same prompt | any divergence |
| C_new gating | gateway admitted > 0; later step reuses registered buffer | zero admitted or refusal |
| ES | no binding consumed by the probe | a settlement claim |
| Memory | four timestamped samples recorded | a PASS row that depends on them |

The fresh-cache probe is **cache-level**, not ES-level. The gate is a first-
generation gate; a second gated continuation in the same process legitimately
fails `generation_invocations_before_gate != 0`, so it cannot be used to create
"a new execution state" here. This is criterion amendment CA2.

## 7. R2, memory, cleanup

### R2

W2 installs `duringGenerationRegistration` via `probe.bind(to: executor)`. If it
throws after line 404's `consumeBinding`, the worker records:

```text
run_outcome: INVALID_IRREVERSIBLE_ES_ADVANCED
registration_error: <error>
binding_consumed: true
settlement_claim: none
```

This is an invalid run, not a FAIL and not a PASS. The consumed binding is
recorded as irreversibly advanced. No retry.

### Memory

Samples at: after model load, before release, after release, after the fresh-cache
probe. Each sample records `activeMemory`, `cacheMemory`, `peakMemory`, the four
weak-probe results, and process liveness. `descriptive_only: true` is written in
the record. No threshold, no page-return claim, no allocator claim.

### Cleanup order

1. Worker writes its result record create-exclusive, fsyncs, closes.
2. Supervisor writes `supervisor-terminal.json` create-exclusive with the outcome
   and PIDs.
3. `SIGTERM` the process group; wait 2 s; `SIGKILL`; `waitpid`; check
   `kill(-pgid, 0) == ESRCH`.
4. Seal evidence. Never delete a FAIL or invalid record.
5. Marker stays consumed; a new run needs a new marker and a new run id.

| Stage | Cleanup | Evidence |
| --- | --- | --- |
| Preflight refusal | no spawn, marker intact | `refusals/<id>.json` |
| Marker consumed, spawn failed | kill any child, reap, no model | `supervisor-terminal.json` |
| Gate refused (supervisor) | `abort`, workers exit before forward | gate report, `forward_count = 0` |
| Worker gate refused | no forward, exit | worker `gate` record |
| Refusal during W1 | terminate W1 arm, release, exit; W2 unaffected | P1 record |
| Registration failure in W2 | invalid run; binding consumed | `INVALID_IRREVERSIBLE_ES_ADVANCED` |
| Crash/timeout | group kill, partial record, marker consumed | crash record, orphan check |
| PASS | release, exit, seal, revert registry diff | PASS + cleanup records |

## 8. Evidence record

One write-once `run.json` per run, plus per-worker records. All writes use
`O_CREAT | O_EXCL`; no file is rewritten. A missing field, a type mismatch, or a
PASS/FAIL inconsistency makes the run invalid.

```text
schema_id, protocol_sha256, run_id, marker_sha256, started_at_utc, ended_at_utc, outcome
supervisor: supervisor_pid, worker_pids[], pids_distinct, both_alive_at_go,
            orphan_check, exit_codes[], preflight_gate_report
workers: [{arm, worker_pid, pgid, binary_sha256, model_manifest_sha256,
           prepared, gate, result, forward_count, generation_started}]
gate: supervisor_report{passed, failed_checks, eligible_for_runtime_evidence,
      model_generation_started_by_gate}, worker_reports[]
refusal_plan: digest, arm, layer, step, position, reason, expected_prefix[]
per_arm: arm, generated_tokens[], sampler_invocations, settled,
         fell_back_to_standard, standard_route_calls, gateway_terminated_reason,
         session_terminated, slot_retired, binding_present_after_refusal,
         binding_consumed_on_settle
release: weak_cache_nil, weak_gateway_nil, weak_observer_nil,
         old_session_claim_refused, old_session_step_refused, old_slot_retired
probe: fresh_cache_instance_id, start_offsets[], tokens[], admitted_count,
       binding_consumed
control: tokens_by_prompt{}, matches{}
memory: [{phase, active_bytes, cache_bytes, peak_bytes, descriptive_only}]
budget: {model_processes, model_loads, gated_generations, control_loops,
         gate_evaluations, forwards, retries}
checks: {name: bool}, failed_checks[]
non_claims[]
```

Workers may write only `prepared-*.json`, `gate-*.json`, and `result-*.json` in
their own write root. Only the supervisor writes `run.json` and the final
`checks`. A worker cannot self-certify a PASS.

`generated_tokens` for a refused arm is the session ledger
(`G3ArmCacheSession.committedTokens`), not the executor's return value: the
executor throws on abort and never returns its local array. `sampler_invocations`
is `committedTokens.count`; `stepCount` is recorded separately so the
entered-but-refused step stays visible. `session_terminated` is
`session.abortReason != nil`, and that reason must equal the planned `R` for W1.

## 9. Budget and marker

### Frozen budget

| Item | Limit |
| --- | --- |
| Model processes | 3 (W1, W2, W3) |
| Model loads | 3 |
| Gated generations | 2 (W1, W2) |
| Control loops | 3 (W1 prompt, W2 prompt, P2 prompt) |
| Gate evaluations | 4 (1 supervisor + 2 executor + 1 second attempt) |
| Second-attempt probes | 2 (session, executor) |
| Forwards | 39 (W1 8, W2 12, W3 19) |
| Retries | 0 |
| Wall clock | 20 min; worker 10 min; control 5 min |
| Concurrent free memory | ≥ 48 GiB |

Forward counts are exact, not estimates. `continueExecutionG3WithPerArmCache`
runs exactly `maxTokens` forwards (`for _ in 0..<maxTokens`; step 1 is the
prefill): W1 `maxTokens: 8` = 8 forwards, and step 8's refusal happens inside its
forward (later layers run inertly, no KV write). W2 = 4 settle forwards + 8
fresh-probe forwards (8-token prompt prefill + 7 decode steps). W3 = 7 + 4 + 8
no-cache control forwards, one per generated token per prompt. Both
second-attempt probes must forward zero times. Any change to prompts, steps, or
model invalidates the budget and requires a new protocol revision and a new
marker.

### Marker

`G3_D1_AUTHORIZATION` is a JSON file with:

```text
schema_id, run_id, challenge_nonce, issued_at_utc, expires_at_utc
protocol_sha256, plan_sha256, package_sha256
model_manifest_sha256, runner_manifest_sha256
gate_provider_id, gate_provider_type
max_model_processes, max_model_loads, max_gated_generations,
max_control_loops, max_gate_evaluations, max_forwards, max_retries = 0
refusal_plan_digest, evidence_root, consumed_path
```

The supervisor verifies every field, then atomically renames the marker to the
consumed path before spawning. A consumed marker is never valid again. An expired
or mismatched marker is refused without consumption.

## 10. Static review

The review is performed before any model load. "GAP" means the artifact needed to
satisfy the item does not exist yet, so the execution gate is not passed.

| ID | Item | Evidence in current tree | Status |
| --- | --- | --- | --- |
| SR1 | Two distinct live worker PIDs; no in-process runner | Gate requires exactly two observations and two distinct positive PIDs (`RuntimeIsolationGate.swift:323,331`); runner drives both arms in one process (`G3DualArmRunner.swift:224–225`); spawn/process-group helper exists (`ActualMLXSmokeValidation.swift:672`) | PASS (design), GAP (D1 targets) |
| SR2 | Planned refusal enters the real gateway and latches | Gateway is `final` (`G3KVAllocationGateway.swift:54`); `handleCacheWrite` is `internal` (line 175); registrar is `final` (`G3ArmResourceOwnership.swift:356`); no terminate API | GAP (requires PS1) |
| SR3 | Two-process ownership sealing | `seal(against:)` takes a live owner (`G3ArmResourceOwnership.swift:231`); `OwnedResource` and `.confirmed` are public (`G3ArmResourceOwnership.swift:82,106`); a peer-snapshot owner can be built by the harness from the attestation bundle | PASS (design), GAP (implementation) |
| SR4 | Marker, write-once evidence, no retry | V6 smoke pattern: digest-bound marker, atomic rename before spawn, create-exclusive evidence root, timeout kill (`ActualMLXSmokeValidation.swift:263–298`) | PASS (pattern), GAP (D1 supervisor) |
| SR5 | Live provider type is registrable | Registry is in `SimiGoRuntimeContract` (`RuntimeIsolationGate.swift`); provider type must live in the same module to match `Swift.type(of:)`; registry empty today | GAP (provider + reviewed diff) |
| SR6 | `consumeBinding` observable | `consumeBinding` is internal (`MLXExecutionStateBackend.swift:67`); `boundPrefix` is public and throws after consume (line 48) | GAP; substitution CA1 |
| SR7 | Standard path and registry unchanged | Worktree diff for `MLXPrefixRecomputeExecutor.swift` is 308 insertions, 0 deletions; `continueExecution` body unchanged; `G3ExecutionDispatch.standard` untouched; registry empty | PASS |
| SR8 | Model topology fits the seam | Qwen3-MoE: 48 layers, no `sliding_window`, no `layer_types`; no `newCache` override; default builder returns `KVCacheSimple()` per layer (`LanguageModel.swift:421–432`, `CacheConfiguration.swift:289`) | PASS (candidate), identity GAP |
| SR9 | Evidence/cleanup implementation | Schema and order are frozen here; no D1 worker/supervisor code exists | GAP |
| SR10 | Field semantics and reference discipline | `model_content_sha256` must be a manifest digest, not a 16 GiB blob; `kv_cache_instance_id` must identify the arm's cache holder, not an empty buffer; probe/owner strong refs must be dropped before weak probes | GAP; amendments CA3/IC4 |

Execution gate: **NOT PASSED**. SR2, SR5, SR6, SR9, SR10, and the implementation
half of SR1/SR3/SR4 plus SR8's identity half remain open. A marker may not be
issued while any row is GAP.

## 11. Authorization package checklist

Before a marker can be issued, the package must contain:

1. This protocol and its `.sha256` sidecar, unmodified.
2. The exact source diff: `G3D1Worker` target, supervisor test, `G3KVAllocationGateway.terminate(reason:)`, `D1AttestationProvider`, and the one-entry registry registration.
3. The peer-snapshot owner construction and the proof that it uses the peer's
   attested mutable ids, not placeholders.
4. The refusal plan JSON with digest, layer 24, step 8, position formula, reason,
   and expected prefix.
5. The model manifest (config + every safetensors + tokenizer) and the runner
   manifest (worker/supervisor binaries, library and vendor seam digests).
6. The marker JSON with the frozen budget and no-retry fields.
7. The evidence schema and the cleanup/abort matrix from this document.
8. A completed static review: every SR row PASS, with command output.
9. Signed decisions for PS1 and CA1–CA4.
10. The non-claims list, unchanged.

## 12. Non-claims

D1, even if it passes, does not claim:

- that MLX forward execution was cancelled;
- that partial KV was erased;
- that GPU/Metal pages were returned to the OS;
- that the executor is thread-safe or safe under concurrent release;
- that the R2 window is closed;
- that the two-process peer snapshot proves live cross-process aliasing safety
  beyond the gate's reported ids;
- that the gate's `live_attestation_provenance_complete` is a per-field sampling
  audit; the gate derives `observedFields` from the validated envelope, and the
  values are checked only by the individual predicates;
- that provider trust is bound to a process role; the registry binds a concrete
  Swift type, so the supervisor's preflight instantiation of the same type is
  not live-worker evidence (IC1);
- that the pre-run holder id proves allocator-level KV isolation before the first
  forward; allocator-level identity exists only after the first write and is
  supplied by the sealed registration (CA3);
- that PALACE Information Space recovery works, or that P3/P4 hold;
- that G3 is a production gate, or that any standard inference path changed;
- that the G3/PALACE dry run is model evidence or that its 20-start budget is
  inherited.

## Appendix A — Symbol map

| Concern | Symbol / file |
| --- | --- |
| Gate entry | `RuntimeIsolationGate.requireIsolation(provider:request:)` |
| Trust registry | `RuntimeProviderTrustPolicy.registeredLiveProviderTypes` |
| Two-PID check | `RuntimeIsolationGate.swift:323,331` |
| In-process two-arm driver | `G3DualArmRunner.run`, lines 168–230 |
| Gated first generation | `G3FirstGenerationEntry.runAsync`, line 258 |
| Executor per-arm loop | `MLXPrefixRecomputeExecutor.continueExecutionG3WithPerArmCache`, line 276 |
| Consume site | same file, line 404 |
| Registration hook | `MLXPrefixRecomputeExecutor.swift:251` |
| Single-arm composition | `G3MLXRuntimeResourceProbe.g3ArmExecution`, line 413 |
| Owner / registrar | `G3ArmResourceOwnership.swift:231,356` |
| KV boundary / observer install | `G3PerArmKVCache.swift:97–234` |
| Gateway / write boundary | `G3KVAllocationGateway.swift:54,175,244` |
| Consume / bound prefix | `MLXExecutionStateBackend.swift:48,67` |
| Spawn / group kill | `ActualMLXSmokeValidation.swift:641,672` |
| Model cache builder | `MLXPerArmKVCacheFactory.modelCacheBuilder` |
| Memory observables | `Memory.activeMemory`, `.cacheMemory`, `.peakMemory` |

## Appendix B — Decisions requiring owner sign-off

### PS1 — Gateway terminate seam (production, one method)

Add to `G3KVAllocationGateway`:

```swift
/// Terminate this arm's gateway with a fixed reason. Idempotent; the first
/// reason wins. No production call site installs or invokes this; the D1
/// harness calls it at the frozen refusal point so the real latch and cascade
/// are exercised.
public func terminate(reason: String) { _ = refuse(reason) }
```

Rationale: without it, the planned refusal cannot enter the real gateway; the
P1 rows `gateway.terminatedReason == R` and the `arm_terminated_after(R)` cascade
would have to be re-implemented in the harness, which is a weaker claim.

Alternative (not recommended): harness-local latch plus a P1 criterion amendment.
Requires rejecting PS1 and revising the boundary.

### CA1 — Replace `consume_calls: 0`

`consumeBinding` has no injection point or counter. Replace the row with
`binding_present_after_refusal: true` (the prefix is still returned) and
`binding_consumed_on_settle: true` for W2. A `noBoundRepresentation` throw after
the refusal is the falsifier.

### CA2 — P2 fresh-cache probe is cache-level

The gate is one-shot per process. A second gated continuation cannot represent
"a new execution state". P2's new execution is a same-process, fresh-cache,
gated step loop with no ES settlement. The P2 claim remains KV-level; no ES or
PALACE claim is added.

### CA3 — Field semantics

`model_content_sha256` and `tokenizer_content_sha256` are the digests of the
canonical manifests (small files), not a 16 GiB weight blob and not a directory
read; both must be 64 lowercase hex. The probe's own
`sha256(of: artifactURL)` reads a file with `Data(contentsOf:)`, so a directory
URL would yield an empty string and fail envelope validation — the D1 provider
must supply the manifest digests explicitly. `kv_cache_instance_id` identifies
the arm's cache holder; per-buffer KV ids are post-generation evidence.
`mutable_resource_ids` are holder-level ids, not every admitted buffer. The
holder is folded to a confirmed id through the probe's `opaqueMutableIdentity`;
returning nil is a fail-closed refusal.

The holder fold is object-level, not allocator-level: before the first forward
the layer caches are empty and expose no materialized storage, so no allocator id
exists yet (`G3MLXRuntimeResourceProbe.identity(of:)` returns `.indeterminate` for
an unmaterialized array). `D1CacheHolder` therefore returns a confirmed id
derived from its own object identity plus the arm label. Consequence, recorded as
a limitation: the gate's `distinct_kv_cache_instances` proves two distinct holder
objects, not two distinct KV allocations. Allocator-level per-buffer isolation is
evidenced only after the first write, by the gateway's sealed registration
(`G3KVAllocationGateway.handleCacheWrite` → `admit`). The individual
`KVCacheSimple` objects must NOT be listed in `mutableResources`: they would
resolve to `.indeterminate` and fail the gate before any forward.

### CA4 — Second-attempt refusal layer

A second `continueExecutionG3` is refused at the gate because the provider's live
`generation_started` counter is 1 (the refused step 8 still entered a forward),
not at the executor tombstone. PASS requires `forward_count == 0` and records
`refusal_layer = gate` and the failed check
`zero_generation_invocations_before_gate`; the executor tombstone is separately
tested through `session.runStep`.

### IC1 — Provider module and registry

`D1AttestationProvider` must live in `SimiGoRuntimeContract` (the registry's
module) and be registered by one reviewed diff with
`providerKind = .swiftMLXLiveWorker`. Its initializer takes the self observation
as a `@Sendable () -> RuntimeResourceObservation` closure (evaluated inside
`collect`, so `generationInvocationsBeforeGate` is read live — a frozen struct
would make the second attempt look like a first one) and the peer observation as
a frozen value from the bundle. It returns both in `expectedArms` order, with the
same `run_id` and `challenge_nonce` as the request, and throws if the self PID
differs from the bundle or the peer is not alive. Because the provider lives in
the contract module, the closure that reads the probe is defined by the worker
and passed in; the provider itself never imports MLX. The registration is
reverted after the run; the type remains inert and unregistered.

Limitation of type-identity trust: the registry binds a concrete Swift type, not
a process role, so the supervisor can instantiate the same registered type for
its preflight gate. The supervisor's gate report is therefore written with
`role = preflight` and is never used as the authoritative gate; only the two
in-executor reports are. This is recorded as a trust-model limitation, not as
evidence that the supervisor is a live worker.

### IC2 — Peer-snapshot owner

The worker builds a peer `G3ArmResourceOwner` from the peer's attested mutable
ids (public `OwnedResource` and `.confirmed`), seals against it, and records
`peer_snapshot_source = attestation_bundle`. This is a harness construction, not
a production change. The harness must hold a **strong** reference to the
peer-snapshot owner for the whole gated run: `seal(against:)` stores the peer
weakly (`private weak var peerRef`), so dropping it silently disables the
cross-arm registration check while leaving every call looking successful.
Limitation: the peer ids are self-reported; the gate's
`distinct_live_worker_pids` and `mutable_resource_ids` checks are the cross-process
evidence.

### IC3 — Model and memory

Candidate: `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit` (16 GiB, 48 layers,
full attention, default `KVCacheSimple`). Concurrent W1/W2 require ≥ 48 GiB free.
The marker binds the model manifest digest; the package must re-verify topology.
A sequential fallback is not authorized in v0.1 because it weakens the
simultaneous-liveness claim.

### IC4 — Reference discipline for weak probes

Before release, the worker must drop `execution`, `probe`, `owner`, the
`D1CacheHolder`, and local cache arrays. Otherwise `OwnedResource.backing`, the
probe, or the holder retains the caches and the weak probes stay non-nil for the
wrong reason. The evidence records `harness_refs_dropped_before_release: true`.

## Appendix C — Static review commands

Run from the lab root; all are read-only and must be recorded verbatim.

```bash
git rev-parse HEAD
git status --short
grep -n "distinct_live_worker_pids" simigo2-experimental/Sources/SimiGoRuntimeContract/RuntimeIsolationGate.swift
grep -n "let a = await drive\|let b = await drive" simigo2-experimental/Sources/SimiGoRuntimeContract/G3DualArmRunner.swift
grep -n "backend.consumeBinding" simigo2-experimental/Sources/SimiGo2Experimental/MLXPrefixRecomputeExecutor.swift
grep -n "public final class G3KVAllocationGateway\|func handleCacheWrite" simigo2-experimental/Sources/SimiGo2Experimental/G3KVAllocationGateway.swift
grep -n "registeredLiveProviderTypes" simigo2-experimental/Sources/SimiGoRuntimeContract/RuntimeIsolationGate.swift
git diff --stat simigo2-experimental/Sources/SimiGo2Experimental/MLXPrefixRecomputeExecutor.swift
python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.cache/huggingface/hub/models--mlx-community--Qwen3-Coder-30B-A3B-Instruct-4bit/snapshots")
s = sorted(os.listdir(p))[-1]
d = json.load(open(os.path.join(p, s, "config.json")))
print("layers", d.get("num_hidden_layers"), "sliding", d.get("sliding_window"),
      "layer_types", d.get("layer_types"), "arch", d.get("architectures"))
PY
```

## Appendix D — Relation to the D boundary v0.1

This protocol does not rewrite the D boundary. It:

- adds the two-process topology that the boundary's §4.1.1 requires;
- turns the boundary's §4.2–4.3 tables into the observables in sections 5–6;
- records the five owner decisions as D1-D1 … D1-D5;
- lists the substitutions (CA1–CA4) that would amend specific boundary rows **only
  if the owner signs them**;
- leaves the boundary's R1–R3 limits, non-claims, and D2/D3 separation intact.

Until PS1 and CA1–CA4 are signed, the D boundary remains as written and D1
remains not authorized.
