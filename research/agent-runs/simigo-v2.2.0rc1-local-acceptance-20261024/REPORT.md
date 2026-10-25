# SimiGo v2.2.0rc1 — local acceptance report (batch simigo-v2.2.0rc1-local-acceptance-20261024)

Everything below is derived from files in this batch. `driver/verify_batch.py`
re-derives every gate from raw data (logs, sqlite, bundle bytes, Keychain
metadata deltas); no verdict is typed by hand. Batch exit code: **2** =
no FAIL, at least one BLOCKED (see `acceptance_report.json`).

## 1. What was built, and from what

| item | value |
|---|---|
| product repo / branch | `Documents/SimiGo` / `localb-b3-closure-20261016` |
| product HEAD | `f18d65f8f312ffbb837fdf5e07125af044833854` |
| working tree | dirty by design: 13 changed paths + 2 untracked (see `RC_SOURCE_FREEZE.json`) |
| Lab repo | `Documents/SimiGo-Lab` (read only; evidence untouched) |
| candidate | `v2.2.0rc1`, `CFBundleShortVersionString 2.2.0`, `CFBundleVersion 26` |
| build | `xcodebuild -project SimiGo.xcodeproj -scheme SimiGo -configuration Release -derivedDataPath build/release-v2.1 build` → `** BUILD SUCCEEDED **` |
| package | `bash tools/package_dmg.sh 2.2.0rc1` → `SimiGo-v2.2.0rc1.dmg` |
| toolchain | Xcode 27.1 (27A9275), Apple Swift 6.4, SDK 27.0, macOS 27.0.1 (26A434) |

Treated as the installed candidate (bytes on disk, not "same source"):

| identity | value |
|---|---|
| executable sha256 | `cc6fe63c20d52637d6a220a0230b0a9ac7ecc33457437b48eba254f0c2a6659f` |
| executable UUID | `5AAD0DF1-3860-3B16-B25F-A6C4AD4AF9E4` |
| bundle tree digest | `25b6a2f41946e14b52ea325fc7e1912a73ad2953d27879fe289ef02e18e3b608` (19 files) |
| dmg sha256 / bytes | `e3c9f077d8423a9235e4be4b335f3fa01def12b0ce20f21db037221d26712319` / 31,984,457 |
| install path | `<batch>/install/SimiGo.app` (`codesign --verify`: valid on disk, satisfies its DR) |
| model | `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit` @ `6e302ea604ad9ab206367e2c501d1571023e7b6d`, 17 files re-hashed |

`evidence/recheck_artifacts.json` recomputes exe size / exe digest / UUID / dmg
digest / Info.plist digest / model file digests from disk and PASSes.

## 2. Code that changed for this round (all source-verified, nothing committed)

1. **LOCALB Keychain scoping** (rounds 3): `LOCALBTransportIdentityStore` and
   `LOCALBKeychainSignerStore` resolve a dedicated keychain file under
   `<SIMIGO_HOME>/localb/` and scope every `SecItem` call (`kSecUseKeychain` for
   adds, `kSecMatchSearchList` for copy/update/delete,
   `SecIdentityCreateWithCertificate(keychain,)` for the TLS identity). Shared
   helper: `public struct LOCALBKeychainScope`.
2. **CloudKeychain isolation** (round 4): `Service.init()` called
   `CloudKeychain.readAPIKey()`, which read the *real* login Keychain even with
   `SIMIGO_HOME` set. On this host the item's ACL answered the freshly built
   binary with an interactive SecurityAgent prompt, so the process blocked for
   ever inside `SecItemCopyMatching`
   (`sample` stack: `SecItemCopyMatching → SSDbUniqueRecordImpl::get → mach_msg`;
   `log show` at the exact launch second: `securityd` `client is not Apple-signed`
   → `sending UI event for LegacyAPICounts: SimiGo QueryKeychainUse::queryUser`).
   Bootstrap therefore never ran in round 3 (`bootstrap-report.json ABSENT`).
   Fix: `CloudKeychain` is inert while `SIMIGO_HOME` is non-empty — no read, no
   write, so no user secret enters the candidate's window and no prompt can
   block an unattended run. Covered by
   `SimiGoTests.CloudBackendTests.testIsolatedManagedRootNeverReadsOrWritesTheLoginKeychain`.

Round 1/2 evidence, and the round-3 binary/evidence taken before this fix, are
preserved under `round3_archive/` and `evidence/round2/`; nothing was deleted or
rewritten.

## 3. Test gates

| suite | executed | skipped | failures | log |
|---|---|---|---|---|
| `Packages/LOCALBCore` | 41 | 0 | 0 | `logs/localbcore_tests.log` |
| `Packages/SimiGoRuntime` (incl. the 8 `SimiGoRuntimeContractTests` files) | 85 | 0 | 0 | `logs/simigoruntime_tests.log` |
| App target via `tools/run_isolated_tests.sh` | 208 | 14 | 0 | `run_isolated_r4/isolated_tests_r4.log` |

The App suite grew from 207 to 208 executed with the same 14 skips (one new
test, none lost). Its isolation audit reports
`real_user_state_write_count=0`, `violation_events=0`, `xctestrun_only_three_roots=true`.
Package runs used dedicated `swift test --scratch-path` trees and their own
`SIMIGO_HOME` roots, so both scoped keychain files land inside the batch.

## 4. Install, launch, chain (stage A)

`evidence/m3_stage_a_process.txt`: the running image is `install/SimiGo.app`
(sha256 `cc6fe63c…`), the process sees all three isolated roots, bootstrap
completes (**20 models, schema v3, 0 issues**), `simigo.sqlite3` (+wal/shm) is
created inside the isolated home, the app quits on SIGTERM and restarts from the
same bundle (pid 43872 → 43934). `evidence/noninterference_bracket.txt` repeats
the launch between two snapshots: 0 real-user writes, `.DS_Store` byte-identical.

## 5. Research chain (M4) against this binary

Both runs executed `install/SimiGo.app` (sha256 `cc6fe63c…`, UUID `5AAD0DF1…`):

| check | m4a (`hello`) | m4b (`delta9`) |
|---|---|---|
| ES1 status / generated text | OK / `RESULT=hello` | OK / `RESULT=delta9` |
| ES1 settled + read back from IS | yes | yes |
| ES1 exited before ES2 | yes | yes |
| ES2 new PID, fresh cache identity | yes | yes |
| ES2 value recovered from IS | `hello` | `delta9` |
| ES2 digest + validity + binding | verified / valid / ok | verified / valid / ok |
| ES2 value-carrying env channels | `[]` | `[]` |
| ES2 real model continuation / U2 output | yes / `RESULT=hello-U2` | yes / `RESULT=delta9-U2` |

Controlled difference: the only input that changed is the ES1 settlement value
(`hello` → `delta9`); ES2's recovered value and its model output followed
(`RESULT=hello-U2` → `RESULT=delta9-U2`) with the counterfactual baseline held at
`world` in both runs. Negative controls refuse before generation:
NC1 missing settlement rc=6, NC2 payload tamper rc=6, NC3 invalidated rc=6,
NC4 model identity mismatch rc=6, NC5 invalid role rc=2, NC6 missing parameter
rc=2, NC7 value leaked into the consume env rc=7 — each `status=BLOCKED`,
`generation_call_count=0`, at the expected stage.

Resource lifecycle (`m4/m4a|m4b/memprobe_*_mem.json`): the Release binary has no
idle-timing seam, so the probe waits out the production floor
(`observed_idle_wait_seconds=240`, `suspend_attempts=17`), `suspendIfIdle()`
returns true, model container present→absent, lifecycle suspend/resume delta
1/1, `sessions_released=1`, `post_resume_generated=RESULT=<value>`.
`footprint_delta_bytes≈17.3 GB` is recorded as supporting evidence only.

## 6. Non-interference

* Whole-window snapshot diff (`evidence/noninterference_diff_m4.json`): `~/.simigo`,
  `~/Library/Application Support/SimiGo` and the HF reference root all report
  0 unexpected new / deleted / modified, 0 expected self-writes, 0 reference changes.
* Bracket around one launch: `real_user_state_write_count=0`, `violation_events=0`.
* Login Keychain (`evidence/keychain_noninterference.json`): metadata delta
  against a baseline taken before the runs — `new_item_count=0`,
  `removed_items_since_baseline=0`, production credentials
  (`com.simigo.localb-*`) untouched, 21 scoped keychain files created inside the
  batch. The 45 items leaked by rounds 1/2 are **left in place** as evidence.
  The 3 items leaked by the pre-signer-fix round-3 binary are preserved in
  `evidence/keychain_round3_intermediate_leak.json`.

## 7. Gate ledger (`acceptance_report.json`)

| gate | verdict |
|---|---|
| source_and_model_frozen | PASS |
| build_and_package | PASS |
| install_and_operate | BLOCKED |
| product_service_http | BLOCKED |
| research_chain_primary | PASS |
| research_chain_negative_controls | PASS |
| negative_controls_refuse_before_generation | PASS |
| research_chain_controlled_difference | PASS |
| app_suite_and_isolation | PASS |
| package_suite | PASS |
| resource_lifecycle | PASS |
| physical_page_return | BLOCKED |
| per_layer_forward_calls | NOT_INSTRUMENTED |
| experiment_non_interference | PASS |
| keychain_non_interference | PASS |
| artifact_identity_recomputed | PASS |

### Why the three BLOCKED gates are BLOCKED (minimum unblock)

1. **install_and_operate** — the installed app launches, bootstraps and restarts,
   but the *user-visible prompt* leg cannot be driven from this host: the driver
   has no Screen Recording permission (`screencapture: could not create image
   from display`), the 8 scripted attempts reach the AX tree (2 menu bars,
   6 items) yet no window/pop-up window is exposed (`windowsAfterPress=0`), and
   `CGWindowListCopyWindowInfo` returns no window for the process. Unblock: grant
   Screen Recording + Accessibility to the driving terminal, then repeat
   `driver/run_stage_b.py` and capture the prompt/answer and
   `home/logs/native_mlx_trace.log`.
2. **product_service_http** — the installed candidate bound **no TCP listener**
   within the 180 s window (`probe_result=NO_SOCKET_WINDOW OBSERVED`), so no
   authorized request could even be attempted; `authorization_relaxed=0` and no
   proof was fabricated. The guard itself is intact (`localbAuthorizationUnavailable`
   at `HTTPServer.swift:1333/1435`; activation is only reachable from a verified
   LOCALB host context at `LOCALBHostRuntime.swift:191`, `OversizedRuntime.swift:129`,
   `NativeMLX.swift:497`). Unblock: a shipped activation surface (or a driven,
   authorized GUI session) that starts the product server and performs the LOCALB
   ceremony, then the same probe can record a real 200 and an IS admission result.
3. **physical_page_return** — no OS-level page-return evidence was collected;
   footprint/RSS deltas are explicitly not accepted as proof.
4. **per_layer_forward_calls** — the product has no per-layer forward-count
   instrumentation.

## 8. Direct answers to the acceptance questions

* **Can it be built from the recorded source + dependencies?** Yes — Release
  build succeeded from `f18d65f` + the 13 changed paths; `RC_IDENTITY.json`
  records revisions for every resolved package (mlx-swift `ef5f1b6b…`,
  mlx-swift-lm `bc64ee69…`).
* **Which binary was installed?** `cc6fe63c20d52637…`, UUID `5AAD0DF1-3860-3B16-B25F-A6C4AD4AF9E4`,
  bundle tree `25b6a2f4…`, taken from `SimiGo-v2.2.0rc1.dmg` (`e3c9f077…`).
* **Did the GUI and ordinary inference really run in the installed bundle?** The
  installed bundle runs, generates 20-model bootstrap, persists state, quits and
  restarts — proven. The *typed prompt* leg is BLOCKED (no Screen Recording).
* **Does Service/HTTP use a normal, authorized product path?** Not proven this
  round: no listener window was observed; the authorized lane was never
  attempted, and nothing was relaxed to make it pass.
* **Is the IS-recovered value causally used by ES2's real generation?** Yes —
  two runs differing only in the settled value produce correspondingly different
  ES2 prompts and outputs, with the value arriving through IS, not env.
* **Were tests and experiments non-interfering with real user state?** Yes by
  snapshot diff and by Keychain metadata delta (0 new items, 0 removals).
* **Which thresholds pass / fail / block?** 12 PASS, 3 BLOCKED, 1 NOT_INSTRUMENTED,
  0 FAIL.
* **Is this enough for an rc1 candidate?** It is a buildable, installable,
  auditable candidate whose research chain and isolation are evidenced end to
  end. It is **not** a demonstration of the complete product HTTP path or of
  typed GUI inference; both stay BLOCKED with the minimum unblock listed above.

## 9. Governance

No `git commit`, `git push`, tag, remote merge, branch rewrite, `reset --hard`,
or `git clean` was performed. Lab evidence was read only. Real user state
(`~/.simigo`, Application Support, Keychain) was neither modified nor cleaned;
the only artefacts written outside the batch are the repo's own build outputs.

## 10. Correction record — round-2 Service/HTTP note (2026-10-24)

**更正原因.** `acceptance_report.json` 的 `product_service_http.note` 由
`driver/verify_batch.py` 生成。该注记原先断言 round 2 期间在运行 pid 上用 lsof 观测到
了 ephemeral 监听端口、拿到 TLS-only 行为、以及伪造 LOCALB proof 的 POST 返回 503。
本轮复核该批次留存文件时发现上述三条观测都没有对应的留存记录：唯一留存的 stage-C
记录 `evidence/m3_stage_c_probe.txt` 写的是 `listening_socket_found=0`、
`authorized_request_completed=0`、`probe_result=NO_SOCKET_WINDOW OBSERVED`，且批次内
不存在任何 `bound_port=`／`tls_verify=`／`http_status=` 行。因此该注记属于“凭记忆写出、
无留存证据支持”的断言。经操作者授权，本次只更正注记的措辞与生成逻辑，不更改 round-2
的原始日志、原始快照或任何已封存的证据。

**原注记（逐字保留，仅作对照）.**

> Round 2 reached the installed app's real HTTPServer (ephemeral port observed via
> lsof on the running pid, TLS-only: plaintext gets an empty reply) and its
> authorized lane is refused exactly as designed: a POST carrying a fabricated
> LOCALB proof returns 503 'LOCALB request authorization is not configured'
> because this build ships no surface that performs the activation ceremony
> (app_target_call_sites=0 in evidence/localb_authorization_path.txt), so the
> guard fires before any proof is evaluated. The same product code does serve
> authorized requests once activated - proven by the product's own tests in the
> round-2 test binary. Closing this gate needs a shipped activation surface, not
> a weakened guard.

**更正后的措辞（由 `service_http_note()` 从留存记录生成，不再是手写文本）.**

> CORRECTED 2026-10-24: no retained evidence supports (无留存证据支持) the earlier
> round-2 note — 'Round 2 reached the installed app's real HTTPServer (ephemeral
> port observed via lsof on the running pid, TLS-only: plaintext gets an empty
> reply)' and 'a POST carrying a fabricated LOCALB proof returns 503'. The
> retained stage-C record reads: listening_socket_found=0;
> authorized_request_completed=0; probe_result=NO_SOCKET_WINDOW OBSERVED. … The
> correction does not flip this gate: an absence of evidence is not evidence that
> the server never listened, so product_service_http stays BLOCKED until a
> rebuilt candidate that ships the activation path is observed end-to-end.

**所依据的证据缺口.**

1. 无监听证据：批次内没有 round 2 的 `lsof` 输出、`listening_socket_found=1` 或
   `bound_port=` 记录；留存的 stage-C 探测结果恰恰是 `listening_socket_found=0`。
2. 无 TLS 行为证据：不存在 `tls_verify=18` 或任何等价握手记录。
3. 无 503 响应证据：不存在对安装二进制发起受保护路由请求的 `http_status=503` 记录。
   503 与 `localbAuthorizationUnavailable` 的对应关系来自源码
   （`SimiGo/Protocol/HTTPServer.swift:1333`、`:1435`），是代码事实，不是运行观测。
4. 仍然成立的部分：`app_target_call_sites=0`（`evidence/localb_authorization_path.txt`）
   与 round-2 测试二进制内授权通道的 10 个 PASS 用例。

**判定影响.** 无。`product_service_http` 仍为 `BLOCKED`；本次更正只把“无证据的观测”
降级为“无留存证据支持”，不等于证明其反面（不主张服务端从未监听）。批量总体判定仍为
`BLOCKED`，`counts` 不变。本次更正改动的文件与摘要变化记录在
`simigo-v2.2.0rc1-service-http-20261024/evidence/round2_note_correction_{before,after}.json`，
并已按 `driver/make_manifest.py` 重新生成 `MANIFEST_SHA256.txt`、用
`driver/verify_manifest.sh` 复验。
