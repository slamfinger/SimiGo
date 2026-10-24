# SimiGo2 G3 — D1 Entry Boundary Decision v0.1

> **Status:** DECISION RECORD + FIRST ENFORCEMENT LAYER — D1 NOT AUTHORIZED
> **Revision:** 5 — Phase 1 (G6/G7a/G7b/G8a) landed: a real `G3D1Worker` now exists, is built from the frozen snapshot, self-verifies its executable identity before the first forward, and is bound via `tools/g3_execution_identity.py` to `status: bound` (stand-in = false). Builds on Revision 4 (G5 closed WITHIN the reviewed execution paths). **This is execution-infrastructure binding, not a real-model ES+IS closure. D1 still NO-GO.**
> **Date:** 2026-10-21
> **Scope:** G8a (sessionless `.g3` execution), G8b (entry boundary between normal inference and D1-authorized execution), G7b (source and execution identity), G3/G4/G5 (settlement axes, cancellation positions, terminal ordering)
> **Model loads / generation / provider trust:** none / none / registry empty
> **Lab worktree:** not committed (HEAD `c0ac9694`)
> **Evidence:** `docs/02-evidence/g3-d1-source-freeze/runner-manifest.json`

This record answers the four questions the independent review raised for G8b. It
does not close G8b. It also records the G8a refusal implementation and the
entry-level evidence for it; the full runner-to-executor entry chain still needs
its own acceptance. The machine-checkable boundary now enters the frozen runner
manifest. Revision 2 added the G3/G4/G5 implementation and its runtime evidence.
Revision 3 replaces Revision 2's pre-commit check with a single adjudication
domain for settlement, termination and commit, defines the cancellation cutoff,
and closes a `--verify` gate that silently passed an unbound execution identity.
Revision 4 does not change that mechanism; it consolidates the evidence the
fourth review asked to see INTO this record — the method-B exhaustive reachability
audit (every termination write and the single commit-success write are domain-
guarded), the production executor path trace (the real gated run, not a test
double, enters the same domain), and the scenario-3 total assertion — and re-runs
the freeze/identity chain against the current tree so the recorded counts, the
manifest digest, the artifact identity and the execution binding all come from
one round of final products.
**No real model was loaded anywhere in this record; nothing here is G3 execution
evidence.**

## 0. 决策摘要（中文）

- **G8a 的拒绝路径已实现，但 G8a 仍是 OPEN**：`G3DualArmRunner.run` 不再接受“没有 per-arm session factory”的调用（参数由可选改为必填）；执行器 `.g3` 路径中的 recompute 回退分支已被删除，缺少 session 时在 `continueExecution`、`context.model`、`consumeBinding` 之前抛出 `missingCacheSession`。generation body 的拒绝顺序已有运行时证据；runner 到 executor 的全部入口约束仍需独立验收（见第 4 节的两个证据等级）。
- **G8b 只做了部分实现，仍是 OPEN**。本轮明确选择 **情况 A（信任经过审查的合作 worker）** 作为 D1 v0.1 的威胁模型；**情况 B（抵抗主动绕过）不在进程内声称成立**，它需要 G6 的两进程结构（supervisor 持有授权，worker 只收到一次性计划）。
- **当前真正强制的边界有三层**：① SwiftPM target 依赖图（`g3-swift-isolation-entry` 只能到达 `SimiGoRuntimeContract`，无法 import 执行器）；② runner 的编译期必填 session 参数；③ 执行器 `.g3` 路径没有 recompute 分支（源码结构上不可达）。
- **证据类别必须分开陈述**：依赖图证明“模块级代码不可达”；runner 参数证明“调用约定被类型强制”；两个新测试证明“运行时拒绝”。三者都不等于“抵抗恶意调用者的运行时封闭”。
- **G8b 分成两项**：**G8b-A（合作 worker 的依赖集、调用约定、源码审查与产物身份）是 D1 必须闭合项**；**G8b-B（抵抗主动绕过）明确不声明**，不再是 D1 的“待办硬阻断”。双进程与 supervisor 本身不闭合 B：worker 仍链接执行器模块，除非另有 facade/可见性机制被证明。
- **G7b 分三层**：源码内容载体（195 文件 tar + 3 bundle + 1 diff）、构建产物身份（`artifact_stamp`，构建与读取同一 `.build/out`）、执行身份（`tools/g3_execution_identity.py`：sealed copy + 一次性 marker + 运行中 PID 的 `proc_pidpath` 复核）。**第三层本轮只做到机制与 control-only 演示**；真实 `G3D1Worker` 不存在，记录显式为 `unclosed`。
- **G8a 的证据分两层**：第一层是 generation body 的拒绝（weightless model，`forwardCalls == 0`、binding 保留）；第二层是生产入口——public `continueExecutionG3` 有独立运行时拒绝测试（在 `provider_trust` 处拒绝，未进入模型），runner 入口有“不 dispatch”测试。但“gate 通过后到达 body guard”的路径仍只有结构证据，因为 trusted registry 为空。
- **G3 / G4 / G5 本轮推进**：G3 的三轴（`settleEntered` / `bindingConsumed` / `delivery`）由每个 run 的 `G3RunLedger` 分别记录，runner 的 `settled` 只从 ledger 推导（派生规则：`settled = isFullyDelivered`，见 6.1），不再读 `!session.isTerminated`；G4 的取消按观察位置裁决（`duringGeneration` / `beforeSettlement` / `afterSettlement` / `afterDecode` / `atCommitCutoff`），截止点即提交域，截止后只记录不撤销；G5 不再依赖“提交前再读一次”，而是由每 arm 一个的 `G3Adjudication` 共同裁决域把结算门、终止锁存与提交转换串行化（见 6.3）。**证据等级：生产 executor body + weightless model 的模型无关运行时证据；未运行真实模型。**
- **G5 线性化的验收口径**（三轮审查要求确认的实现细节）：读取终止状态与写提交状态使用**同一把锁**；未参与裁决域的 boundary 由 `commitDelivery` fail-closed 拒绝；晚到终止由 latch 自身写入 ledger（不靠事后采样）。四场景（终止先于提交 / 提交先于终止 / 并发 / 截止后取消）均有运行时测试，含 240 轮真并发与互斥探针。
- **工具门修复**：`g3_runner_manifest.py --verify` 之前忽略 `--require-*` 三个旗标，会对 `control-only`/`unclosed` 返回 0（沉默通过）。本轮修复为：verify 通过后仍按记录的最终状态执行 `requirement_checks`，`--require-execution-binding` 对非 `bound` 如实返回 2 并打印 `UNBOUND EXECUTION IDENTITY`。
- **测试措辞**：已运行**模型无关**测试套件（swift-testing 75 tests / 11 suites + XCTest 513 tests（RuntimeContract 130 + Experimental 383，5 skipped）/ 0 failures）；**未运行真实模型 G3 实验**。
- **仍未闭合的硬阻断**：G6（没有 `G3D1Worker` target）、G7a（没有一次性计划/marker 签发链）、G7b 的真实 worker 产物绑定（当前为 control-only），以及 G3 的真实模型运行证据。
- **Revision 4 的范围裁决**（第四轮审查接受）：G3 三轴闭合、G4 已覆盖取消时序闭合、G5 **在接受范围内闭合**——以本轮所述的终止/提交排序实现、方案 B 穷举可达性审计、生产路径可达与场景三全断言为据；**G5 闭合 ≠ D1 放行**。线性化保证只覆盖通过契约 API 的转换与本轮审计到的可达写入点，不外推为对所有并发行为（如 `MLXArray` 层别名、gateway 之下的指令级竞争）的承诺。真实 D1 worker、supervisor 与跨进程授权链为独立后续目标，未纳入本轮授权，D1 维持 NO-GO。
- **状态不变**：不签发 D1 marker、不注册 provider、不加载模型、不运行 G3、不提交工作树。
- **Revision 5 的第一阶段验收（本轮范围裁决「选择 B」）**：建立可绑定身份的 D1 执行链，把执行身份从 `control-only` 推进到有证据支持的 `bound`。**G6**：`G3D1Supervisor` 双臂武装一次性授权、拉起两个**独立 worker 进程**（实测 PID 39129/39130，`distinctPIDs=true`），生命周期管理（挂起 worker 超时 `terminate` 回收）与可审计执行记录（每 worker 一份 audit）。**G7a**：`G3D1Authorization` 用 `O_CREAT|O_EXCL` 签发一次性 marker、绑定 run/slot/期望执行哈希、`rename(2)` 原子消费、拒绝重放（supervisor 消费后再 `consume` 返回 `missingOrReplayed`；两 slot `replayRefused=true`），身份失败或授权缺失时 fail-closed（不消费 marker，退出码 10/11）。**G7b**：真实 `G3D1Worker` 存在并进入 `ARTIFACTS`（`PENDING` 现为空），worker 自校验可执行文件 SHA256（实测 `1f9baa57…`，`identity.status=verified`）在首个 forward 之前，经 `g3_execution_identity.py --launch`（**非 `--stand-in`**）得 `status=bound`、`launch.match=true`、marker 已消费，manifest 内嵌 `d1_execution_binding` 亦刷新为 `bound`，`--require-execution-binding` 退出 0。**G8a**：worker 执行必须经 `G3FirstGenerationEntry.runAsync` 受约束入口，在空 provider-trust 注册表下于 `provider_trust` 阶段拒绝——`generationCallCount=0`、`settleEntered=false`、`bindingConsumed=false`、`generateBodyRuns=0`，`claimsSettledDelivery=false`。测试替身仅用于验证机制，**真实 worker 的 `bound` 来自实际产物**。**边界**：4 项 G8b-A 模块检查 + 5 项 G8a 入口守卫 PASS；G8b-B 仍为明确非声明。本轮同轮产物：`ROUNDTRIP PASS 204/204`、`G3D1SupervisorTests` 12 项（含真实双 PID 子进程与回收）全绿；`source_sha256`/`runner_sha256` 的权威值只记在 `runner-manifest.json` 并被 bound marker 在 `execution-identity.json` 消费——本文件自身处于 `source_sha256` 之内，故正文不钉任何摘要值（否则编辑本文必改摘要）。**D1 仍 NO-GO**：这不等于第二阶段（真实模型 ES→IS→新 ES 续跑）已放行，后者需单独判断。

## 1. Threat model selected for D1 v0.1

D1 v0.1 adopts **Case A**: the worker is reviewed source, built from the frozen
manifest, and follows the calling convention. The boundary is enforced by
construction where SwiftPM can enforce it, and by reviewed code otherwise. The
claim is:

> A D1 run cannot execute through the ungated surface **without modifying the
> frozen package manifest or the frozen sources**, and any such modification
> changes `source_sha256`.

The claim is **not**:

> An arbitrary in-process caller is prevented from calling `continueExecution`.

That second claim cannot be made in-process: `continueExecution` is public on the
MLX executor and must stay public for normal inference (`simigo2ctl`,
`SimiGo2App`). Case B is deferred to the two-process D1 architecture (G6), where
the worker has no authority to mint a D1 result and the supervisor accepts only
gate-bound evidence.

### 1.1 Why Case B is not claimed now

| Requirement for Case B | Current state |
| --- | --- |
| Separate trust domain for the authorized entry | Not built (no `G3D1Worker`, no supervisor) |
| Runtime capability that a linked caller cannot forge | Not expressible in-process: any public mint function is callable by the same process |
| Evidence acceptance that rejects ungated runs | Not built (G7a plan/marker absent; `isExecutionEvidence` is hard-coded `false`) |

Any statement stronger than Case A today would be a claim about intent, not about
mechanism.

## 2. The boundary that actually exists

### 2.1 Layer 1 — module unreachability (machine-checked)

`swift package dump-package` reports:

```text
G3SwiftIsolationEntry -> [SimiGoRuntimeContract]
SimiGo2Experimental   -> [MLX, MLXHuggingFace, MLXLLM, MLXLMCommon, MLXNN,
                          SimiGoRuntimeContract, Tokenizers]
```

The gate control-point executable cannot import the module that owns
`continueExecution`, `runStep` or the model container. SwiftPM refuses that
import at compile time. The check is recorded in the runner manifest as:

```text
G8b-A.entry_dependency_set              PASS
G8b-A.entry_excludes.SimiGo2Experimental PASS
G8b-A.worker_dependency_set             PASS (not applicable: target absent)
```

and `--require-boundary` fails closed if any check fails. Because the dependency
edges come from `Package.swift`, which is hashed into `source_sha256`, adding an
edge changes the frozen digest.

**What this proves:** module-level code unreachability for the gate binary.
**What it does not prove:** that a future worker will not depend on the executor.
That check (`G8b-A.worker_dependency_set`) is recorded as `applicable: false` and
becomes binding the moment `G3D1Worker` exists.

### 2.2 Layer 2 — the authorized entry cannot be expressed without a session

`G3DualArmRunner.run(_:_:makeCacheSession:)` now takes a **non-optional**
`G3PerArmCacheSessionFactory`. The previous signature allowed `= nil`, which
dispatched both arms into the recompute path. That state is no longer
expressible at the only dual-arm G3 entry: omitting the argument is a compile
error, and a factory that throws is a `cacheWiringRefused` before either arm is
dispatched.

### 2.3 Layer 3 — the gated executor path has no recompute fallback

Inside `MLXPrefixRecomputeExecutor.continueExecutionG3`, the `else` branch that
called `continueExecution` has been deleted. The public gated entry delegates to
the post-gate body, and only that body owns the admission guard:

```swift
// public entry: the delegate call sits inside runAsync's closure
let run = try await G3FirstGenerationEntry.runAsync(...) {
    try await self.runGatedGeneration(...)
}

// runGatedGeneration (internal; production's only call site is above)
guard !self.g3CacheSlot.isRetired else { throw .armTerminated(...) }
guard let session = self.g3CacheSession else {
    throw G3PerArmCacheError.missingCacheSession(...)
}
let result = try await self.continueExecutionG3WithPerArmCache(...)
```

The `internal` visibility is a test seam, not a public bypass: external modules
cannot call it, and the only production call site is inside the cleared-gate
closure. A source scan of the guarded body finds only two call forms: the public
gated overload (outside the body) and `continueExecutionG3WithPerArmCache`.
`continueExecution` appears only in comments. The guard sits before the per-arm
path, so it precedes `backend.boundPrefix(for:)`, `context.model(...)`,
`claimContinuation()`, `G3RunSettlement.settle(...)` and `consumeBinding(for:)`.

## 3. What each test proves

| Evidence | Class | Proves | Does not prove |
| --- | --- | --- | --- |
| `G8b-A.entry_dependency_set` / `--require-boundary` | module unreachability | The gate binary cannot import the executor | A future worker's dependency set |
| Non-optional `makeCacheSession` | type-enforced convention | A G3 run cannot be expressed without session wiring | That a throwing factory cannot be supplied (runtime refusal covers that) |
| `testExecutorWithoutPerArmSessionWiringIsRefusedBeforeDispatch` | runtime refusal | An executor that cannot install a session is refused before dispatch; neither forward runs | That a real MLX executor was exercised |
| `testThrowingSessionFactoryRefusesBeforeDispatch` | runtime refusal | A failed session build refuses before dispatch; gated calls stay 0; no session installed | Artifact/binary identity (G7b) |
| `missingSessionRefusesBeforeModelOrBindingConsumption` (`G3GatedEntryAdmissionTests`) | runtime refusal over the production body + weightless model | Driving `runGatedGeneration` raises `missingCacheSession`; the counting model's forward count stays 0; a pre-bound prefix survives (no consume); there is no session to claim | The public gate path (registry is empty) and a loaded model |
| `publicEntryRefusesAtGateBeforeModelOrBindingConsumption` (`G3GatedEntryAdmissionTests`) | runtime refusal at the public entry | `continueExecutionG3` refuses at `provider_trust` (`generationCallCount == 0`, `isExecutionEvidence == false`); forward count 0; prefix still bound | That a cleared gate reaches the body guard (source order + body test cover that) |
| Source scan of `runGatedGeneration` + the public entry | code structure | The public entry delegates only inside `runAsync`; the guarded body has no `context.model` / `consumeBinding` / claim / settlement, no recompute call, no `#if` branch | Runtime behaviour of a loaded model |
| `swift test --scratch-path .build/out` (XCTest 512 + swift-testing 75, 5 pre-existing skips) | model-independent regression | The per-arm path, gateway, native cache, admission body, public-entry refusal, the G3/G4/G5 axes and the G5 commit/termination linearization still pass; the tested bundles are the stamped ones | A real-model run |

## 4. G8a acceptance mapping

Two evidence levels are kept separate. **Level 1** is the executed generation
body. **Level 2** is the production entry chain (raw runner to executor, public
`continueExecutionG3` to the same body). Structural checks support Level 2 but
are not an end-to-end run.

| Requirement | Evidence | Level | State |
| --- | --- | --- | --- |
| Runner cannot dispatch without a session factory | `testExecutorWithoutPerArmSessionWiringIsRefusedBeforeDispatch`, `testThrowingSessionFactoryRefusesBeforeDispatch`; non-optional `makeCacheSession` | L2 (runtime, stub arms) | PASS |
| Public `continueExecutionG3` cannot bypass the precondition | `publicEntryRefusesAtGateBeforeModelOrBindingConsumption`: `provider_trust` refusal, `generationCallCount == 0`, `isExecutionEvidence == false`, forward count 0, prefix still bound | L2 (runtime, empty registry) | PASS for the gate refusal; a cleared gate is not exercised |
| Reject before `context.model` | `missingSessionRefusesBeforeModelOrBindingConsumption`: forward count 0; guard precedes the per-arm call | L1 (runtime) + structural | PASS |
| Reject before `consumeBinding` | Pre-bound prefix still resolvable after the refusal; `consumeBinding` remains only inside `settlement.settle` after a successful per-arm generation | L1 (runtime) + structural | PASS |
| Generation did not happen | `forwardCalls == 0`; `aGen == 0`, `bGen == 0`; `gatedCalls == 0` | L1 (weightless model) | PASS |
| Consumption did not happen | `boundPrefix` returns the original `[1, 2]` after the refusal; no dispatch/record exists | L1 (runtime) + structural | PASS |
| Claim did not happen | No session exists to claim; `claimContinuation()` is inside the per-arm method after the guard | L1 (runtime precondition) + structural | PASS |
| Settlement did not happen | `G3RunSettlement` is created inside the per-arm method after the guard | structural | PASS (structural only) |
| The tested body is the production body | The only production call site of `runGatedGeneration` is inside `runAsync`; the body has no `#if` branch | structural | PASS (structural) |

What this proves: with no session, the runner refuses before dispatch, the public
entry refuses at `provider_trust`, and the executed body refuses before
`context.model`, claiming or consuming.

What it does not prove: a run that clears the gate and then reaches the body
guard (the trusted registry is empty, so no test clears it), or a real loaded
model. Those remain D1-level checks.

## 5. Build binding and execution identity (G7b)

### 5.1 Digest definitions

`source_sha256` is not the manifest file's hash and not a hash of the tar. It is
computed from a named payload with fixed rules, and the rules themselves are a
field (`digest_rules`) inside that payload, so editing a rule changes the digest.
Both digests use the same encoding:

```text
SHA-256 over UTF-8 bytes of
json.dumps(payload, sort_keys=True, separators=(',', ':'), ensure_ascii=False)
```

`source_sha256` covers content identity only:

| Included | Excluded (why) |
| --- | --- |
| `schema_id`, `digest_rules` | `generated_at_utc` (time) |
| `scope` | `toolchain` (environment, not source) |
| `files[]`: `path, type, sha256, size, mode, link_target`, sorted by path | `boundary`, `entry_guards` (derived checks, recomputed on verify) |
| `vendor_repos[]`: head, tree, dirty files, tracked diff hash, submodules | `artifact_stamp`, `artifacts[]`, `runner_sha256` |
| `build_inputs`: package/resolved hashes, path roots, pin count | `d1_execution_binding` (a status, not source) |
| `archives[]`: kind, repo, path, sha256, size, prerequisite, history | branch/remote/tracking state, `files[].git_state` |

`runner_sha256` covers all of the above plus artifact bytes and the stamp, where
the stamp contributes only `source_sha256`, `artifacts_sha256`, `toolchain` and
`commands` reduced to `command + exit`. `built_at_utc`, `source_sha256_matches`
and the build-log tails are excluded, so rebuilding identical sources and
artifacts yields the same `runner_sha256`.

Self-reference is excluded by construction: neither digest contains itself,
`source_sha256` does not contain `runner_sha256`, and `runner-manifest.json`, its
sidecar and `archives/` are not in `files[]`.

### 5.2 Stamping the artifacts the build actually produced

`tools/g3_build_stamped.py`:

1. computes the manifest and records `source_sha256` **before** the build;
2. runs `swift build --scratch-path .build/out` and the same with `--build-tests`;
3. recomputes the manifest and refuses if `source_sha256` moved during the build;
4. attaches `artifact_stamp` and writes the manifest plus its `.sha256` sidecar.

The scratch path is not cosmetic. Before this change the build wrote
`.build/debug` while the manifest named `.build/out/...`, so the stamp could
bind a same-named binary the build command never produced. Pinning both the
build and the test run (`swift test --scratch-path .build/out --filter G3`) to
the manifest's `ARTIFACTS` paths makes "the artifact that exists", "the artifact
that was tested" and "the artifact that was hashed" the same file.

The stamp is content-based, not mtime-based: saving a file without changing a
byte no longer invalidates a correctly built binary.

### 5.3 What carries the snapshot

The manifest is an index, not a carrier. Four carriers make the reviewed
sources obtainable without the local worktree:

| Carrier | Content |
| --- | --- |
| `archives/outer_worktree.tar` | the bytes of all 195 in-scope files (tracked, untracked, both package manifests, governance text, this tool), with type, mode and symlink target; deterministic tar: sorted entries, mtime/uid/gid zeroed |
| `archives/vendor_*.bundle` | the local-only commits of `vendor/mlx-swift`, `vendor/mlx-swift-lm` and the `mlx-c` submodule |
| `archives/vendor_mlx-swift-lm.worktree.diff` | the uncommitted `KVCache.swift` observer fix; applying it to the bundled HEAD reproduces the file, and `vendor_repos[].dirty_files[].sha256` verifies the result |

Extraction is checkable: every file SHA256 is in `files`, the tar hash is in
`archives`, and `--verify` recomputes both. A bundle whose creation failed used
to be recorded with `sha256: null`; `--require-artifacts` now fails on any
unbound archive instead of treating a null as success (observed as
`UNBOUND ARCHIVES`, exit 2).

The outer `.gitignore` ignores `/vendor/`. That is not a freeze gap: vendor
content is frozen by its own repositories (bundle + diff), never by an outer
commit.

### 5.4 Real extraction roundtrip

`--verify` does not trust the archive hash alone. It extracts the tar into a
temporary directory and compares, per path, the type (file vs symlink), the
permission bits, the link target and the bytes against `files[]`, and fails on
any extra path. The last run restored 195/195 entries with `symlinks=0` and
`executable=0`; because mode is compared, a lost exec bit would surface as a
mode mismatch. An archive SHA-256 proves the archive bytes did not change; it
does not prove the restored tree kept the same types and permissions.

Both package manifests are in the snapshot, but only
`simigo2-experimental/Package.swift` is a build input of the stamped binaries.
The root `Package.swift` pins the REMOTE forks, so a build through it would NOT
contain the vendor `KVCache` observer fix. A D1 worker must therefore be built
from the experimental package; the root manifest's hashes are recorded so that
difference is visible rather than assumed away.

### 5.5 Execution identity

`tools/g3_execution_identity.py` is the third layer. It does not hash "some
binary in the build directory"; it binds the bytes that will be `exec`'d and
then re-hashes the executable of the process that actually started.

- `--bind` copies the worker into `execution/stage/` (0700 directory), writing a
  0500 file while hashing, fsyncs, renames, then re-opens with `O_NOFOLLOW` and
  re-hashes. It refuses if the write hash and the read hash disagree.
- A marker is
  `sha256("G3-D1-AUTHORIZATION-MARKER-V1|source_sha256|runner_sha256|staged_sha256")`,
  written with `O_CREAT|O_EXCL` under `execution/consumed/`, so one
  authorization cannot launch twice. The child receives
  `G3_EXPECT_EXEC_SHA256`, `G3_AUTHORIZATION_MARKER` and both manifest digests.
- `--launch` resolves the running PID's executable with `libproc.proc_pidpath`
  after spawn and hashes that path, recording PID, path, hash and `match`. The
  verified object is the launched process, not a name under `.build`.
- `--verify` re-derives the status from the current manifest, the staged bytes
  and the marker. A record whose digests no longer match is `stale` and must be
  re-bound; a consumed marker is never reused.

Three statuses are kept distinct:

| Status | Meaning | Exit |
| --- | --- | --- |
| `bound` | real D1 worker bytes staged; launch observed with `match: true` | 0 |
| `control-only` | a stand-in binary demonstrated the mechanism; explicitly not a D1 worker | 0 (2 with `--require-execution-binding`) |
| `unclosed` | the worker artifact is absent (today's state); no launch is claimed | 2 |

Observed with `/bin/sleep` as the stand-in: the running executable resolved to
the staged path with `match: true`, the marker was consumed, a second launch was
refused (exit 3), and tampering the staged bytes made `--verify` fail. With the real
worker path absent, the tool wrote `execution/worker-absent.json` with
`status: unclosed` and exit 2, and `--require-execution-binding` printed
`UNBOUND EXECUTION IDENTITY`.

**Revision 3 gate fix.** The requirement flags were only honored on the stamp
path. `--verify <manifest> --require-execution-binding` returned 0 on a
`control-only` record, because `verify()` ended at its digest comparison and
never reached `requirement_checks`. That is the exact failure mode the third
review warned about — an updated record and an unverified claim being mixed in
one report — so `verify()` now takes the three flags and, after the digest and
roundtrip checks pass, runs `requirement_checks` against the manifest under
review. The verdict therefore reads the RECORDED final state of the same round
of products it just validated. Observed at this revision: `ROUNDTRIP PASS
195/195`, `VERIFY PASS`, `EXECUTION BINDING control-only`, then
`UNBOUND EXECUTION IDENTITY` with exit 2.

Residual window: `proc_pidpath` is read after `exec`, so a same-uid writer could
replace the staged file between the re-hash and `exec`. D1 closes this by the
child hashing its own executable (`G3_EXPECT_EXEC_SHA256`) before the first
forward and refusing on mismatch. That child check is a contract, not evidence:
the worker does not exist. Code-signature identity is recorded for the stand-in
but is not yet a condition for `bound`.

### 5.6 Negative controls

| Control | Result |
| --- | --- |
| Change one artifact hash in a manifest copy | `artifact drift: .../g3-swift-isolation-entry`, exit 1 |
| Append one byte to `outer_worktree.tar` | `outer archive digest drift`, `archive bytes drifted`, exit 1 |
| Delete an archive | `archive absent on disk`, exit 1 |
| Tamper the staged worker | `--verify` re-derives a mismatch and fails |
| Launch a consumed marker again | exit 3 |
| `--require-artifacts` with a null archive hash | `UNBOUND ARCHIVES`, exit 2 |
| Run without the real worker | `unclosed`, exit 2 |

### 5.7 What is still open in G7b

> **Revision 5 supersedes this subsection's worker-absence claims.** A real
> `G3D1Worker` now exists and is promoted into `ARTIFACTS`; the execution
> identity is `bound` (stand-in = false), the child-side self-check is
> implemented and enforced, and `--require-execution-binding` exits 0. See §10.
> What remains open at Revision 5 is a *real-model* run and a protocol marker
> that consumes `runner_sha256` — not the worker artifact.

- No `G3D1Worker` artifact exists (G6), so the binding is `control-only` and
  `worker-absent.json` is `unclosed`.
- No D1 marker consumes `runner_sha256` in the protocol sense; the marker here
  binds this tool's staged bytes, and plan/marker issuance is G7a.
- No code-signature requirement for `bound`.
- The child-side self-check is not implemented (no worker).
- `--require-execution-binding` still fails for the current tree.

The source snapshot is now carried, not merely indexed: the outer tar holds
every in-scope file's bytes with type/mode/link target, the vendor bundles and
diff hold the vendor state, and the stamp binds today's artifacts to that
content digest. The execution-identity mechanism exists and is demonstrated,
but the executed D1 worker does not, so G7b remains open.

## 6. G3 / G4 / G5 — three axes, one cancellation cutoff, one adjudication domain

The second review kept these three items separate and named the reason for each:
`settled` could not express "consumed but not delivered" (G3), cancellation was
adjudicated by one final `Task.isCancelled` (G4), and the report read only
`session.isTerminated` while an independent gateway latch could exist (G5). The
third review then refused to accept G5 on the strength of a pre-commit check:
`guard terminal == nil else { throw }` followed by `commit()` is two statements,
and if the two use different synchronization, a termination may land between
them. That objection was correct against Revision 2, and Revision 3 implements
the reviewer's option A — one shared adjudication mechanism — instead of asking
tests to cover a window that cannot be covered. **No real model was loaded;
nothing here is a G3 execution experiment.**

### 6.1 G3 — the three axes are independent facts

Every run attempt owns a `G3RunLedger` (`Sources/SimiGoRuntimeContract/G3PerArmKVCache.swift`).
`G3ArmCacheSession.beginRunLedger()` is called by `G3DualArmRunner.run` before
either arm is dispatched, so a refused attempt reports `notEntered` axes instead
of the previous attempt's facts.

| Axis | Field | Written by | Means |
| --- | --- | --- | --- |
| settlement gate | `settleEntered` | `G3RunSettlement.settle` after the single-use check succeeds | the consume body was ENTERED; it may still throw |
| binding removal | `bindingConsumed` | `G3RunSettlement.settle` after `consume()` returns | the bound prefix was actually removed |
| delivery | `delivery.generation/registration/decode/commit` | the production executor body | each stage's own result (`succeeded` / `failed` / `skipped` / `notEntered`) |

```text
isFullyDelivered = settleEntered && bindingConsumed
                && delivery.completed && postSettlementTermination == nil
```

The runner's `settled` is exactly this value; it no longer reads
`session.isTerminated`. `delivery.completed` requires generation, decode and
commit to succeed plus registration succeeded-or-skipped. Two cases the old
Boolean could not express are now distinct and tested:

| Case | Axes |
| --- | --- |
| consume body was entered but threw | `settleEntered=true`, `bindingConsumed=false`, `settlementPhase=bindingConsumeFailed` |
| delivery failed after a successful consume | `settleEntered=true`, `bindingConsumed=true`, `commit=failed` or `registration=failed` |

`consumeBinding` removes the prefix and the bound position only; no axis is named
after ES advancement, and no claim is made that the ES position advanced.

**The legacy `settled` field has a derivation rule, not an independent life.**
`G3ArmRunRecord.settled` is assigned exactly `ledger.snapshot.isFullyDelivered`
(`G3DualArmRunner.G3ArmRunRecord` construction in `G3DualArmRunner.run`); nothing writes it from `session.isTerminated`,
from the gate outcome, or from any single axis. It is kept as a compatibility
report field, and the three axes are printed next to it, so a reader who wants
the underlying facts never has to invert the Boolean. The five fault positions
the third review listed are each pinned by a test:

| Fault position | Facts that must survive | Test |
| --- | --- | --- |
| fails before entering the gate | `settleEntered=false`, `bindingConsumed=false`, `delivery=notEntered` | `testRefusedSettlementLeavesBothAxesFalse`, `testPreSettlementCancellationLeavesBothAxesFalse` |
| gate entered, consume not completed | `settleEntered=true`, `bindingConsumed=false`, `settlementPhase=bindingConsumeFailed` | `testThrowingConsumeRecordsEnteredWithoutConsumed`, `testThrowingConsumeInsideTheDomainKeepsTheAxesDistinct` |
| consumed, registration failed | `bindingConsumed=true` (never rolled back), `registration=failed`, `commit=notEntered` | `testPostConsumeRegistrationFailureLeavesConsumedAndDeliveryFailed` |
| consumed, decode failed | `bindingConsumed=true`, `decode=failed`, `commit=notEntered` | `testPostConsumeDecodeFailureKeepsConsumedAndMarksDecodeFailed` |
| delivery completed | consumption and every stage independently auditable | `testConsumedIsIndependentOfDelivery` |

### 6.2 G4 — cancellation is adjudicated by position

The production executor consults one predicate (`isCancelled`; production
default `Task.isCancelled`) at every stage boundary. The ledger records the FIRST
position where cancellation was observed and keeps it even when the consume has
already happened.

| Position | Observed at | Axes after the throw | Binding |
| --- | --- | --- | --- |
| `duringGeneration` | step start; inside the step; after a `task_cancelled` abort | both false, `generation=failed` | survives |
| `beforeSettlement` | entry to the gated body; again after generation, before the gate | both false, generation may be `succeeded` | survives |
| `afterSettlement` | immediately after the gate returns | both true, `commit=failed`, decode `notEntered` | consumed, not rolled back |
| `afterDecode` | after decode succeeded, at the decode boundary | both true, `decode=succeeded`, `commit=failed` | consumed, not rolled back |
| `atCommitCutoff` | inside the commit region, sampled under the domain | both true, `commit=failed`, detail `cancelled_at_commit_cutoff` | consumed, not rolled back |
| `afterCommitCutoff` | after the commit region returned, recorded only | unchanged; a committed delivery stays committed | consumed, delivery committed |

Decode is synchronous and non-interruptible, so "cancellation during decode" is
observed at its boundary, not inside it; the decode record stays `succeeded`
because it did complete.

**The cutoff is defined by the mechanism, not by a sample.** Revision 2 said
"commit is the last observation point" without naming what happens to a
cancellation that arrives after it. Revision 3 names it: the run's cancellation
cutoff IS the commit region. `commitDelivery` samples the cancellation predicate
inside the domain, so a cancellation observable at all before that sample refuses
the commit (`atCommitCutoff`); anything observed after the region closed is
recorded as `afterCommitCutoff` for audit and does NOT undo the delivery. One
sample behind the cutoff is an observation, never an atomic cancellation
guarantee — which is exactly why it may not be reported as a refusal.

### 6.3 G5 — one adjudication domain linearizes settlement, termination and commit

Revision 2's mechanism was: read the three terminal sources at the gate, read
them again before commit, and report `gateway latch > session tombstone >
settlement`. The reads are still there and still matter for the REPORT, but they
are not what orders the transitions, and Revision 2 claimed they were. Two
statements under two different locks leave a real window.

Revision 3 moves the ordering into one object. Each arm owns a
`G3Adjudication` (`Sources/SimiGoRuntimeContract/G3PerArmKVCache.swift`), a named
domain around a single `NSRecursiveLock`. Every participant that can change or
read the terminal state while a transition is in flight enters that domain, and
the participants' own locks were removed rather than layered on:

| Participant | Region entered under the domain | What the region does |
| --- | --- | --- |
| `G3RunSettlement.settle(terminalReason:_:)` | the whole gate | reads every terminal source → single-use `settleEntered` transition → the consume body → `bindingConsumed` |
| `G3ArmCacheSession.terminate(reason:)` | the tombstone write | writes the tombstone and, if `bindingConsumed` is already true, files the ledger's `postSettlementTermination` itself |
| `G3ArmCacheSession.commitDelivery(isCancelled:finalize:)` | the commit | reads the terminal snapshot and the boundary abort flag → samples cancellation → `finalize()` → `commit=succeeded` → records the domain name |
| `G3RunLedger` | every transition | its `lock` IS the domain's lock (`private var lock: NSRecursiveLock { adjudication.lock }`); it no longer owns an `NSLock` |
| `MLXKVCacheBoundary` / `G3KVAllocationGateway` | the latch | `adoptTerminationAdjudication(_:report:)` registers the domain; `terminate(reason:grant:)` and `refuse(_:)` latch inside it and report the reason back into the ledger from inside it |

Consequences that are now structural rather than hoped for:

- **Mutual exclusion is the mechanism, not a favourable schedule.** The commit
  region and a latch cannot overlap. A termination either happened-before the
  region (the commit sees it and refuses) or happens-after it (the commit stands
  and the latch records the late termination through its own report sink).
- **A late termination is filed by the mechanism.** `markPostSettlementTermination`
  is written by `terminate()` and by the gateway's report callback when the
  binding is already consumed. No pass re-reads the ledger to "notice" it.
- **A boundary that does not adopt the domain cannot commit.** The protocol's
  default `adoptTerminationAdjudication` returns `false`, and `commitDelivery`
  then returns `.refusedBoundaryNotAdjudicating` with `commit=failed(
  boundary_not_adjudicating)`. Fail-closed, because a latch outside the domain
  would not be serialized against the commit and the run could not claim a
  linearization.
- **Lock order is one-directional**: domain → boundary/gateway latch lock, never
  the reverse. The recursion is confined to same-thread read-modify-write
  helpers; no region performs I/O or awaits while holding the domain.

The four scenarios the third review asked to be checked, and what the mechanism
now guarantees:

| Scenario | Accepted outcome | Pin |
| --- | --- | --- |
| termination before commit | commit refused, reason preserved, consume NOT rolled back | `testTerminationBeforeCommitRefusesAndPreservesReason` |
| commit before termination | commit stands; the latch itself files the late termination; the consumed fact stands | `testTerminationAfterCommitKeepsTheCommittedFactAndIsFiledByTheLatchItself` |
| termination concurrent with commit | exactly one winner every round, every result classified, no termination lost | `testConcurrentTerminationAndCommitIsAlwaysClassified` (240 rounds), `testDomainHeldByOneParticipantBlocksTheOther` (mutual-exclusion probe), `testSettlementGateAndLatchRaceIsAlwaysClassified` (160 rounds) |
| cancellation after the final check | the cutoff IS the commit region; behind it a sample is recorded as `afterCommitCutoff` and changes nothing | `testCancellationAtTheCommitCutoffRefusesTheCommit`, `testCancellationObservedAfterTheCutoffDoesNotUndoTheDelivery` |

**Protocol rule for a termination that lands after a successful commit.** The
commit fact and the consumed fact are both kept — neither is disguised as
"never happened". The run is nevertheless **not clean evidence**: the
`isFullyDelivered` predicate ends with `postSettlementTermination == nil`, so
`settled` goes false and the report carries the reason. This is the rule the
third review asked the protocol to state explicitly, and it is now encoded in
the derived field rather than left to the reader.

### 6.4 Evidence (model-independent)

| Suite | Count | What it pins |
| --- | --- | --- |
| `G3SettlementAxesTests` | 11 | refused gate; gateway-only termination; precedence with both sources; throwing consume; consumed vs delivered; post-settlement termination; post-settlement cancel; pre-settlement cancel; decode-boundary cancel; post-consume registration failure; post-consume decode failure |
| `G3SettlementAxesReportTests` | 4 | the REAL `G3DualArmRunner`: delivered axes; pre-settlement refusal; consumed-then-cancelled is still not a settled delivery; gateway latch reported separately from the tombstone |
| `G3CommitLinearizationTests` | 9 | the four scenarios above against the production domain; the mutual-exclusion probe; the fail-closed non-adopting boundary; the cutoff semantics; the gate-vs-latch race; a throwing consume keeping entered ≠ consumed |
| `G3CancellationPointTests` | 9 | the REAL `runGatedGeneration` body over a real per-arm MLX boundary and a weightless model: cancel at entry, step start, pre-settle, post-settle, decode boundary, at the commit cutoff; a gateway latch during registration blocks delivery; the real run commits under the arm domain; a gateway latch racing the real run never becomes clean evidence |

Full suite at this revision: `swift test --scratch-path .build/out` → XCTest 513
tests (SimiGoRuntimeContract 130 + SimiGo2Experimental 383, 5 skipped:
pre-existing authorization-gated runs) plus swift-testing 75 tests / 11 suites, 0
failures. No live model, no provider, no D1 marker and no G3 execution evidence is
claimed.

**Count reconciliation.** The fourth review carried provisional figures of 120
RuntimeContract / 71 swift-testing / a `7/7` pre-commit-check line, taken from
the Revision-2-era report. Those were the counts BEFORE the tests added while
answering this review. Constraint 1 of the review ("test results must correspond
to the code version actually run") overrides the provisional numbers, so this
record reports the live full-suite totals — RuntimeContract 130 (+10),
swift-testing 75 (+4) — and does not restate 120/71 as if they were current. The
Revision-2 `7/7` pre-commit-check tests are superseded, not deleted: the
mechanism they exercised (a read before commit) was replaced by the adjudicated
commit region, and its coverage now lives in `G3CommitLinearizationTests` (9).
The five skipped Experimental tests are the pre-existing authorization-gated
runs; none was executed here.

**Model-free vs real model.** Every number above is model-independent runtime
evidence (production control flow driven over a weightless stand-in model on the
CPU device). It supports "broad model-free verification" only. It is NOT
D1 real-model execution acceptance, and this record draws that line explicitly
wherever a count or a PASS is cited.

### 6.5 What is still not claimed here

- No real-model G3 run. The executor body is exercised with a weightless model
  that emits logits, so the domain is proven for the production control flow, not
  for a loaded model's numerics.
- The domain serializes the transitions that pass through the contract API. A
  caller that builds its own `G3Adjudication` per object instead of sharing the
  arm's, or a boundary that never adopts, does not get a linearization: the first
  is a construction error outside this mechanism's reach, the second is refused
  fail-closed and tested.
- `MLXArray`-level aliasing and the native cache's own locking are covered by
  their suites; nothing here claims instruction-level race injection below the
  gateway entry.
- Termination still has an independent execution-time entry
  (`G3KVAllocationGateway.terminate(reason:)`, `G3ArmCacheSession.terminate(reason:)`).
  Option B (removing the capability) was therefore NOT the route taken; the
  reviewer's option A was. The D1 worker does not yet exist, so this stays a
  contract-level guarantee exercised by the model-free suites.

### 6.6 Revision 4 — exhaustive reachability, production path, and assertion strength

The fourth review accepted G5 as closed within the reviewed paths on three
source-level grounds that go beyond "the tests are green." They are recorded
here because the document under review must carry its own strongest evidence; the
full line-by-line citations live in
`docs/02-evidence/g3-d1-source-freeze/G5_LINEARIZATION_SOURCE_EVIDENCE_20261021.md`
(out of the frozen scope, so adding it does not move `source_sha256`).

**(a) Method-B burden — no reachable entry mutates shared state outside the
domain.** A sweep of every termination/commit write site shows they are all
domain-guarded. `G3RunLedger.lock`, `G3ArmCacheSession.lock` and
`G3RunSettlement.lock` are the SAME `adjudication.lock` (`private var lock:
NSRecursiveLock { adjudication.lock }`) — the ledger holds no second lock, so a
ledger write cannot slip beside a commit. `terminate`,
`noteExternallyLatchedTermination`, the commit-region writes, `settle`,
`concurrent_runStep`, every ledger `mark*/record*`, the gateway
`latchTerminationLocked`/refuse-write latch, and the MLX `latchBindingViolation`
each enter the domain (or, pre-adoption, are reported into the ledger at
`adoptTerminationAdjudication` so none is lost). Across all production
`Sources/` there is exactly ONE `.commit.succeeded` write — inside the
`commitDelivery` region — so no fallback can record a delivery as committed
outside the domain. The forbidden `guard terminal == nil; commit()` two-statement
sequence exists in no reachable production path; `terminalAbortReason` is read in
the commit path only via `terminalSnapshot()` inside the region.

**(b) Production path, not a test double.** The real composition root builds the
session over the real MLX boundary, which adopts the arm's domain and forwards it
to the gateway; the production executor calls `session.commitDelivery(...)` (the
adjudicated region), maps `.refusedBoundaryNotAdjudicating`/`.refusedTermination`/
`.refusedCancellation` to throws, and only `.committed` proceeds. This is confirmed
at runtime on the real `runGatedGeneration` body by
`G3CancellationPointTests.realGatedRunCommitsUnderTheArmDomain` (asserts
`boundaryAdoptsAdjudication` and the `commit.adjudicated_under=arm:` transition)
and `gatewayLatchRacingTheRealRunNeverBecomesCleanEvidence`; the suite runs 9/9
clean on the current tree.

**(c) Scenario 3 is a TOTAL assertion.**
`testConcurrentTerminationAndCommitIsAlwaysClassified` (240 rounds, both
interleavings biased to occur) is not a smoke test: every round's `outcome` passes
through a `switch` whose `default` is `XCTFail("unclassified commit outcome")`; the
aggregate `committed + refused == 240` forbids any fall-through to a third state;
and a happens-before journal asserts that whenever `latch:exit` precedes
`commit:enter` the outcome MUST be `.refusedTermination`, while `.committed` may
never follow a completed prior latch. A lost termination is a hard failure, not a
tolerated race.

**Closure scope (what this does NOT extend to).** The linearization covers the
transitions that pass through the contract API and the reachable write sites
audited above. It makes no claim about a caller that builds its own
`G3Adjudication` per object (a construction error outside the mechanism), about
`MLXArray`-level aliasing or the native cache's internal locking (covered
separately, not instruction-level race-injected here), or about below-gateway
timing. G5 closing within this scope is not D1 release; the D1 worker does not
exist, so the domain remains a contract-level guarantee exercised by model-free
suites, and execution identity stays `control-only` / `unclosed`.

## 7. Residual gaps and what they block

| Gap | Blocking fact | Blocks D1 |
| --- | --- | --- |
| G6 | **Rev 5: mechanism closed.** Two independent worker processes with distinct PIDs, lifecycle mgmt and reclaim are demonstrated by `G3D1Supervisor` and the subprocess tests against the real binary. What remains for D1 is a real-model ES→IS→new-ES run, not the two-process structure | Yes (evidence scope) |
| G7a | **Rev 5: mechanism closed.** One-shot marker issuance, execution-input binding, atomic consumption, replay refusal and fail-closed on identity/authorization failure are implemented and tested. What remains is integration into a real-model authorization chain | Yes (evidence scope) |
| G7b | **Rev 5: identity `bound`.** Real `G3D1Worker` in `ARTIFACTS`; source snapshot + `artifact_stamp` + running-PID/executable identity mutually verified (`--launch` no stand-in → `bound`, `match=true`, self-hash verified); `--require-execution-binding` exit 0. Still open: a real-model run and a protocol marker consuming `runner_sha256` | Yes (real-model evidence) |
| G8b-A | **Rev 5: binding active.** Worker artifact exists; dependency set, calling convention and transitive closure excluding the ungated surface are machine-checked (4 + 5 guards PASS). Full entry review against a live model still pending | Yes (evidence scope) |
| G8b-B | In-process bypass is not prevented; this is an explicit non-claim, not a D1 hard blocker | No, unless the protocol requires Case B |
| G3 | **Accepted closed within the reviewed execution paths (Rev 4).** The axes and the post-consume classification are implemented and tested against the production body; the remaining evidence gap is a real-model G3 run, not the classification | Yes (evidence scope) |
| G4 | **Accepted closed for the covered cancellation positions (Rev 4).** Cancellation is defined and tested at the production body, with the cutoff named (the commit region); no extrapolation to uncovered concurrent behaviour; what remains is a real-model run, not the definition | Yes (evidence scope) |
| G5 | **Accepted closed within the reviewed paths (Rev 4).** Settlement, every termination latch and the commit transition share ONE `G3Adjudication` domain; the four scenarios are pinned by 9 linearization tests including a 240-round TOTAL assertion (`default=XCTFail`, `committed+refused==240`, happens-before journal) and a mutual-exclusion probe, plus a method-B exhaustive write-site audit and a production-path runtime test against the real gated body. What remains is a real-model run, not the ordering mechanism | Yes (evidence scope) |
| G1 / G2 | Threat model for copy/offset paths and model identity | Yes |

## 8. Note on the frozen protocol text

The D1 protocol (`SIMIGO2_G3_D1_EXPERIMENT_PROTOCOL_V0.1_20261021.md`) is frozen
by a `.sha256` sidecar and is not edited here. Two of its static-review rows are
now stale against the tree:

- SR2 says "no terminate API". The tree has `G3KVAllocationGateway.terminate(reason:)`
  and `G3ArmCacheSession.terminate(reason:)`; the gateway latch is what
  `terminalAbortReason` reads.
- SR7 says the executor diff is 308 insertions / 0 deletions. The G8a guard,
  the G3 ledger writes, the G4 cancellation points and the G5 adjudication
  domain (including `commitDelivery`) all changed that diff, so SR7 is stale.

A marker may not be issued against the frozen protocol until a new revision
re-states SR2/SR7 and is re-frozen with a new sidecar.

## 9. Non-claims

- This record does not authorize D1, D2 or D3.
- It does not claim that a malicious in-process caller cannot call
  `continueExecution`. That is G8b-B and it is an explicit non-claim; a
  supervisor or two-process layout does not close it by itself while the worker
  still links the executor module.
- It does not claim G8a is end-to-end closed. The cleared-gate path (trusted
  registry non-empty) and a loaded model are not exercised; only the gate
  refusal, the runner refusal and the executed body refusal are.
- It does not claim that `G3D1Worker` will respect the dependency boundary; that
  check becomes binding only when the target exists.
- It does not claim `runGatedGeneration` is unreachable to code inside this
  reviewed module. It is `internal` and exists so the admission test can drive
  the exact production body; external modules cannot call it.
- It does not claim that the existing `g3-swift-isolation-entry` binary is a D1
  worker. It is the gate control point, and it is MLX-free by construction.
- It does not claim a real-model G3 execution. The G3/G4/G5 evidence is
  model-independent (weightless logits model, real production executor body).
- It does not claim instruction-level race freedom below the adjudication
  domain. The domain serializes the settlement, termination and commit
  transitions that go through the contract API, and it makes the gateway latch
  enter that same region; it does not serialize MLX-level storage mutation that
  never touches the gateway or the session, and it is not a verified lock
  discipline for code that constructs its own domain instead of the arm's.
- It does not claim G7b closure: the stamp binds today's three artifacts, not a
  D1 worker, and no protocol marker consumes the manifest digest.
- It does not claim an execution identity for a D1 worker: the demonstrated
  binding is `control-only` (a stand-in binary), the worker record is
  `unclosed`, no code-signature requirement is enforced for `bound`, and the
  child-side self-check exists only as an environment-variable contract.

> **Revision 5 supersedes the last three non-claim bullets.** A real `G3D1Worker`
> now exists; the child-side self-check is implemented and enforced (the worker
> refuses before the first forward when `G3_EXPECT_EXEC_SHA256` does not match
> its own executable hash); and the recorded execution identity is `bound`, not
> `control-only`. Code-signature identity is still recorded but is NOT yet a
> condition for `bound`. `--require-execution-binding` no longer fails for the
> current tree. The claims that a D1 *worker will respect the boundary* and that
> *G8a is end-to-end closed* are NOT superseded: the cleared-gate path and a
> loaded model remain unexercised, and the bound run's evidence is the gate
> refusal, not a real-model ES+IS continuation.

## 10. Revision 5 — Phase 1: a bindable, gated D1 execution chain (G6 / G7a / G7b / G8a)

The scope ruling for this round ("选择 B，推进 D1 worker 主链") authorizes moving
the execution identity from `control-only` to an evidence-backed `bound` and
standing up a runnable execution base — WITHOUT declaring the broader ES+IS goal
complete and WITHOUT reopening the closed G3/G4/G5 review. Phase 1 does not load
a real model, does not register live provider trust, and does not change D1 to
GO. The second phase (real-model ES → IS → new-ES continuation) is gated on this
phase passing review and requires a separate release decision.

### 10.1 What was built

New SPM targets, all contract-only (dependency closure reaches
`SimiGoRuntimeContract` and NOTHING that can run a model or the ungated
continuation — see 10.4):

- `G3D1WorkerCore` (library): identity self-check (`G3D1Identity`), one-shot
  authorization (`G3D1Authorization`), the gated run path
  (`G3D1GatedRun`), the auditable record (`G3D1Audit`) and the worker/supervisor
  orchestration (`G3D1WorkerCore`, `G3D1SupervisorCore`).
- `G3D1Worker` (executable): self-verifies identity, consumes its marker,
  drives the gated `.g3` run, writes an audit, exits 0 (gate-refused) /
  10 (identity) / 11 (authorization) / 12 (run error) / 13 (hang-test hook).
- `G3D1Supervisor` (executable): arms two one-shot authorizations, launches two
  independent worker processes, reclaims on hang, demonstrates replay refusal,
  aggregates audits.
- `G3D1SupervisorTests` (12 tests): mechanism doubles for G7a/G7b/G8a plus two
  subprocess tests gated on `G3D1_RUN_SUBPROCESS_TESTS=1` + `G3D1_WORKER_BINARY`.

### 10.2 Acceptance against the Phase 1 delivery table

| Work item | Delivered | Evidence (this round) |
| --- | --- | --- |
| G6 worker / supervisor | Two independent worker processes, distinct PIDs, lifecycle mgmt, failure reclaim, auditable records | Supervisor run `supervisor-run-rev5-1792581978.json`: `distinctPIDs=true`, PIDs 39129 / 39130, each worker emits a `worker-audit/v1`; `testSupervisorReclaimsHungWorker` passes against the real binary |
| G7a authorization | One-shot marker, execution-input binding, atomic consumption, replay refusal, fail-closed | Both slots `authorization.status=accepted`, `consumedPathExists=true`, `replayRefused=true`; wrong-binding and identity-failure tests assert the marker is NOT consumed; exit 11 on authorization failure |
| G7b real identity binding | Real D1 worker's source snapshot, build artifact, running PID and executable identity mutually verifiable | Worker self-hash `identity.status=verified` `1f9baa57…` before the first forward; `g3_execution_identity.py --launch` (no `--stand-in`) → `status=bound`, `launch.match=true`, running PID recorded in `execution-identity.json`, marker consumed; manifest `d1_execution_binding.status=bound`, `stand_in=false`; `--require-execution-binding` exit 0 |
| G8a entry constraint | Worker runs only through the constrained entry; missing session/auth/binding rejected before model call and before binding consumption | Bound + supervisor audits: `gatePassed=false` at `gateStage=provider_trust`, `generationCallCount=0`, `esGenerateBodyRuns=0`, `settleEntered=false`, `bindingConsumed=false`, `claimsSettledDelivery=false` |

Honesty of the Phase 1 result: `G3D1ArmExecutor.continueExecutionG3` calls the
real public gate `G3FirstGenerationEntry.runAsync`. Under the empty trust
registry the gate refuses BEFORE `generate`, so the model body never runs and the
binding is never consumed. That refusal — not a fabricated success — is what
`exit 0` reports here, and no stand-in double's green result is recorded as a
real worker's `bound`.

### 10.3 Same-round freeze chain

`tools/g3_runner_manifest.py` promotes `G3D1Worker`, `G3D1Supervisor` and
`G3D1SupervisorTests.xctest` from `PENDING_ARTIFACTS` into `ARTIFACTS` (the
pending list is now `[]`), adds the worker-core target to the closure check, and
re-stamps. `g3_build_stamped.py --require-artifacts --require-boundary
--require-execution-binding` exits 0:

- deterministic build: the artifact bytes (and therefore `runner_sha256`) depend
  only on the sources, not on wall-clock, and do not move across pre-/post-build
  (the stamp refuses if `source_sha256` drifts during the build); the authoritative
  `source_sha256` / `runner_sha256` are recorded in `runner-manifest.json` — this
  document is itself inside `source_sha256`, so its prose names no digest value
  (a recorded digest would be invalidated by editing the sentence that records it);
- `ROUNDTRIP PASS 204/204 files`, `VERIFY PASS`, binding recomputed from the
  bound record (excluded from both digests, so re-stamping cannot move them);
- the bound worker is re-launched against the manifest produced from the FINAL
  document (stamp → `g3_execution_identity.py --bind --launch` → re-stamp), so the
  digests the marker names equal the digests of the tree this record ships in;
- all test results above were produced against this same `.build/out` snapshot.

### 10.4 Boundary status after Phase 1

G8b-A: 4 module checks (entry dependency set, exclusion of the ungated surface,
worker dependency set, worker **transitive closure** excluding the ungated
surface) + 5 G8a entry guards PASS. G8b-B remains an explicit non-claim: a
second PID and a supervisor do not, by themselves, prevent an actively hostile
in-process caller from reaching the linked executor module's public API.

### 10.5 What is still NOT claimed after Revision 5

- D1 is not authorized and remains NO-GO.
- No real model was loaded; this is not G3 execution evidence and does not prove
  that a settled computation can be resumed through IS into a new ES — that is
  the Phase 2 research question.
- The cleared-gate path (non-empty trusted registry) is still unexercised, so
  G8a is not end-to-end closed.
- No protocol marker consumes the manifest `runner_sha256` in the D1 protocol
  sense; the marker here binds the staged bytes of this tool.
- Code-signature identity is recorded but is not enforced as a `bound`
  precondition.

## 11. Revision 5 review adjudication (G5 source review + Phase 1 delivery)

The reviewer ruled on the latest execution record as the G5 source-review and the
Phase 1 delivery report. Two goals are held distinct: the **G5 review sub-goal is
complete**; the **overall SimiGo ES + PALACE IS research goal remains active**.

- **G5 — accepted closed within scope**, upgraded from "awaiting source
  confirmation" to "Option A source-level closure, limited to the reviewed
  execution path". The seven acceptance points are covered: the shared
  adjudication domain (session / ledger / settlement resolve to one
  `G3Adjudication` lock); `commitDelivery` completing the terminal read,
  cancellation sampling, commit and state transition inside ONE region; the
  audited termination-write paths entering that domain; the single commit-success
  write point inside the region; the 240-round commit/termination contention
  carrying a total classification assertion plus a happens-before check; the
  production executor actually calling `session.commitDelivery` rather than a
  test double; and a late termination preserving the committed fact while NOT
  qualifying as clean evidence.
- **Guarantee boundary unchanged.** No additional guarantee is made for
  low-level store rewrites that bypass the shared adjudication API, arbitrary
  MLXArray aliasing, or actively hostile bypass. G8b-B stays an explicit
  non-claim. G3 / G4 / G5 remain closed within their reviewed scope and are not
  reopened or extended.
- **Phase 1 — accepted complete, with `bound` read narrowly.** `bound` means the
  Phase 1 worker execution-identity binding holds; it does NOT mean a live
  provider is trusted, and it does NOT mean a model executed. The entry still
  refuses at `gateStage=provider_trust` with `generationCallCount == 0`, never
  reaching generation or settlement. Test counts (RuntimeContract 130,
  Experimental 383 with 5 skips, G3D1Supervisor 12 with 2 skips in the default
  full run, Swift Testing 75 / 11 suites, and the 12/12 supervisor run with
  subprocess tests enabled) are recorded from the report's runs, not an
  independent reviewer re-run.
- **D1 — remains NO-GO.** Settled execution-infrastructure success is not to be
  reported as the real-model research question having run.
- **Next research milestone — requires a SEPARATE release decision.** The
  real-model ES → IS → new-ES continuation:
  1. a real model completes an identifiable computation in an old ES and settles
     the valid result plus its dependencies to IS;
  2. release the old carrier and prove recovery no longer depends on the old KV
     or the old session;
  3. a new ES restores the valid result from IS and continues the unfinished
     computation;
  4. the execution trace shows the settled work was reused, not recomputed;
  5. changing one dependency shows the invalidation scope and the necessary
     recompute scope are correct.
  This is the direct evidence for the SimiGo core research proposition and is not
  authorized by this adjudication.

## 12. Locked final status (口径 fixed on the accepted G5 source review)

The reviewer accepted the supplemented G5 source-review and fixed the final
status to the following口径. This table is the authoritative, quotable state; it
adds no new G5 evidence — the reviewer's standing instruction is to stop
supplementing G5 and move to the real-model experiment.

| Item | Ruling | Boundary |
| --- | --- | --- |
| G3 / G4 | closed within scope | not reopened, original guarantee not widened |
| G5 | Option A source-level closure | limited to the reviewed production path and reachable write sites |
| Phase 1 | complete | `bound` means execution-identity binding only |
| D1 real-model experiment | NO-GO | real-model generation and IS-restore-continuation not yet verified |
| Overall ES + PALACE IS research goal | active | the core research proposition lacks end-to-end proof |

Two standing qualifications on Phase 1:

1. `bound` ≠ the model ran. The execution entry refuses at `provider_trust` and
   `generationCallCount == 0`; this matches Phase 1's goal and is not a failure.
2. Test reporting keeps two runs distinct: the default supervisor run is 12 tests
   with 2 skipped, while the subprocess-enabled run is recorded as 12/12. They
   are not contradictory but must not be merged into one run's result.

Honesty caveat: the G5 acceptance rests on the submitted source-review record and
this worktree's same-round runs, NOT on a fresh independent re-run performed in
the reviewer's own session.

The next REAL research acceptance — the one that decides whether the whole study
holds — is the real-model chain (requires a SEPARATE release; not authorized here):
`old-ES settle → IS save & verify → release the old KV carrier → new-ES restore →
incremental continuation → selective invalidation after a dependency change`.
Identity binding, gate refusal, and model-free tests are not to be upgraded into
evidence that the real-model research has succeeded.
