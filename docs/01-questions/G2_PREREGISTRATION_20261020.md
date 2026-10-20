# G2 Pre-registration — Real-Model Cache Release, Information-Space Restoration, Incremental Continuation

> **Status:** `FROZEN — EXECUTION NOT AUTHORIZED` (ruling 2026-10-20: D1 conditional, D2–D5 accepted)
> **Date:** 2026-10-20
> **Research line:** Execution–Information closed loop (E-I)
> **Model binding:** `docs/01-questions/G2_MODEL_BINDING_20261020.json` — 17 files, aggregate SHA-256 `4c1bd7596b9480864ca7c5ac949fbb051c47b182b853a8219c80a171b22f6678`
> **Relation to G1:** independent gate. G1 is `CLOSED` (`docs/06-closure/G1_CLOSURE_20261020.md`); nothing here reopens it or extends the calculator work.
> **Authority of this file:** the normative G2 design text. `FROZEN` binds the matrix, the evidence gates and the authorization scope below; changing any of them requires a recorded amendment. It does **not** authorize P0 or any G2 run, does not modify any Frozen Contract, does not alter the G1 `CLOSED` terminal state, and does not touch the signer line or R27 STOP.

**Ruling basis.** The 2026-10-20 ruling was issued against the capability audit and the D1–D5 summary, because `ad47898e` was not pushed and could not be read remotely. This revision is the text that meets the ruling's three pre-freeze conditions — full model artifact identity (§2.3), a fixed matrix with a hard start budget and stop rules (§5, §9), and negative-control paths that structurally forbid automatic recompute (§7). A discrepancy found at first full read is corrected by an appended amendment record, never by a silent edit.

**Why this path.** `docs/01-questions/README.md` reserves this directory for research objects, questions, boundaries, qualification gates and **design pre-registration records**; `docs/05-architecture` is for consequences already constrained by findings, not unverified designs. The suggested `docs/05-research/` directory does not exist in the current layout, so the pre-registration is placed here.

---

## 1. What G2 must decide

G1 established cross-language consistency for a test-only integer oracle. G2 asks the research question the loop exists for:

> After a unit of work has been settled, can the dependency on the producing execution stage's KV cache be released, can the PALACE Information Space restore the settled result into a new Execution State, and can a real model continue the downstream task without re-executing the settled unit?

Three claims are separated because each can fail alone and none substitutes for another.

| Claim | Statement | Falsified if |
|---|---|---|
| **G2-A** | After settlement, the old stage's KV cache has no accessible reference, handle or lookup path usable by the new stage | the new host hits an old-stage artifact or prefix, or a phase-1 KV artifact is reachable and used |
| **G2-B** | A new Execution State restores the correct settled result, version, dependency identity and validity basis from the Information Space, and refuses missing/invalid/inconsistent state | restored value, identity or closure differs from the settled record, or a negative control continues anyway |
| **G2-C** | With the restored state, a real model completes the downstream unit, and the settled upstream unit was not scheduled or executed again | U2 fails its pre-registered checker, or U1 is re-scheduled / re-executed, or the original source is re-injected to redo U1 |

**G1 ⇒ G2 remains guarded** (2026-10-18 formalization, `REVIEW-SR-P3-G1G2-20261018`). A G2 PASS does not retroactively strengthen G1, and G1 PASS grants nothing here.

---

## 2. Capability audit (read-only, 2026-10-20)

These are facts about the current tree, not plans. They determine which parts of the design are executable today and which would force `INCONCLUSIVE`.

### 2.1 What exists

| Capability | Where | Note |
|---|---|---|
| Real local model backend | `simigo2-experimental/Package.swift` (MLXLLM / MLXLMCommon / MLXHuggingFace); `LLMModelFactory.loadContainer` + `ChatSession` | Swift, in-process; MLX pinned in `Package.resolved` (`mlx-swift ef5f1b6b…`, `mlx-swift-lm eab6895…`) |
| Separate-process model host | `simigo2-experimental/Sources/ActualMLXSmokeChild/main.swift` | child launched by parent; pid written to `child.pgid`; parent uses process-group `SIGKILL` |
| Write-once evidence root | `ActualMLXSmokeValidation.swift` | `create-exclusive` root, terminal record `O_CREAT|O_EXCL`, manifest-digest binding |
| Explicit KV cache objects | `MLXLLM` `model.newCache(parameters:)`; `ChatSession` | KV is a hand-managed, serializable object in this stack |
| Durable KV snapshots | `PrefixSnapshotStore.export/load/rescan`; `ChatSession.savePrefixSnapshot(to:upTo:)` | artifacts survive process exit; sidecar carries `snapshotSHA256`, `chainHash`, `tokenCount` |
| Cross-session adoption + audit hook | `MLXPrefixCrossSessionCache` (`install`, `namespace(modelID:contentIdentity:profile:)`, `hostRoot`, `observations`) | process-global hook; `install` fails closed if another owner; `observations` records `calls`, `hits`, `matchedTokenCounts` |
| Content model identity | `EngineModelIdentity.compute(modelDirectory:)` (`EngineSessionBaseline.swift:246`) | SHA-256 over weight file list + tokenizer bytes |
| Information Space | `execution-information-loop/carrier_loop.py` (D002 append-only carrier, SQLite) | `object_id` content addressing, dependency materialization, validity policy |
| Accepted bridge pattern | `execution-information-loop/production_runtime_bridge.py` | Swift host → bounded JSON → Python carrier + read-only PALACE adapter |

The existence of rows 4–6 is what makes G2-A instrumentable at all. The 2026-10-18 formalization described KV as "not a hand-managed object"; that statement is superseded by this stack, where caches are explicit, snapshot files are explicit, and adoption is hooked and counted.

### 2.2 What is missing or risky

| Gap | Consequence for G2 |
|---|---|
| `MLXPrefixRecomputeExecutor.continueExecution` forwards the full token prefix with `cache: nil` on **every** step (`MLXPrefixRecomputeExecutor.swift:85`) | this path re-does all prefill work continuously. It is disqualified as evidence for "no rework"; G2 must use the `ChatSession` path or an equivalent KV-consuming path |
| `ChatSession` does not expose generated token IDs | generation evidence is chunk sequence + `GenerateCompletionInfo` counts (already registered as a fork API gap in `CanonicalPrefillAcceptance`) |
| The hook observes only lookups that flow through `ChatSession`'s installed hook | a direct filesystem read of a snapshot is not observed. G2-A must therefore combine hook evidence with artifact unavailability, and must not claim coverage of arbitrary reads |
| No instrumentation of cache identity outside the hook | G2-A cannot be claimed on "new session" alone; the store root, namespace and observations must all be recorded |
| No physical-erasure / RAM-remnant instrumentation | out of scope by construction; G2-A is an accessibility claim, not a memory-sanitization claim |

### 2.3 Model binding (frozen)

`docs/01-questions/G2_MODEL_BINDING_20261020.json` is the normative record. It pins the artifact, not the name: 17 files, 17,197,118,924 bytes, aggregate SHA-256 `4c1bd7596b9480864ca7c5ac949fbb051c47b182b853a8219c80a171b22f6678`, computed as SHA-256 over the canonically serialized `{path, bytes, sha256}` list sorted by path.

| Item | Frozen value |
|---|---|
| Model | `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit` @ `6e302ea604ad9ab206367e2c501d1571023e7b6d` |
| Weights | `model-00001-of-00004` `25c6d0a62e02224605774ce2e9dc9a8c95910cde33557b938e55a368da1b5212`; `00002` `7007ce495b063155207c3e8b4038771d0d751655274cb6b76c42b8d9c0624412`; `00003` `a14f5bfdd0cd72ee6e71e7f0bc72f6fcde4d78a2da7ee0665f8cf071ac7d2675`; `00004` `0ea3484a221d674b60c604ea20cb5e5418a2cfd9e61df72c0d7fb5b1622ff5b4` |
| Tokenizer / config | `tokenizer.json`, `tokenizer_config.json`, `vocab.json`, `merges.txt`, `added_tokens.json`, `special_tokens_map.json`, `chat_template.jinja`, `config.json`, `generation_config.json` — each with its own full digest in the binding file |
| Backend | `mlx-swift ef5f1b6b…`, `mlx-swift-lm eab6895…`, `swift-transformers c21fdcde…` (`Package.resolved`); Swift 6.4; Apple M5, 32 GB |
| Generation | greedy (`temperature = 0`), U1 ≤ 256 tokens, U2 ≤ 128 tokens, `canonical-remainder-v1` prefill profile (`.remainder`, step 256), identical across arms |

The binding file carries the full 64-hex digest of every file; this table is a reading aid and does not replace it. Two consequences are binding: a same-name model with a different aggregate digest is a different artifact and inadmissible; any file whose digest differs stops the run.

The model pinned by `ACTUAL_MLX_SMOKE_MANIFEST_V6` (`gemma-4-12b-…` @ `6b82053f…`) is no longer on disk. V6 stays `CLOSED`, cannot be re-executed, and is not a fallback. `Qwen3-Coder-Next-4bit` (≈42 GB) is excluded by the 32 GB host; the two ≈20 GB community builds are not admitted, because the freeze admits exactly one artifact.

---

## 3. Work definition (what "redo" means)

The claim is only testable if the units are defined before the run.

- **U1**: one model call whose input is the fixture source `S1` and whose output is the settled result `R1` (a canonical JSON object).
- **U2**: one model call whose input is `R1` plus the downstream instruction, and whose output is checked by a pre-registered checker.
- **"U1 was re-executed"** means: a model call was issued whose input is `S1` (or any hash-equal copy), **or** the carrier scheduled U1 for compute in phase 2. It does **not** mean "the tokens of `R1` were prefilled". Prefilling `R1` is new work for U2 and is expected; `R1` is orders of magnitude smaller than `S1` by fixture construction.
- **"The old KV was used"** means: a cross-session lookup returned a hit, or a snapshot artifact from phase 1 was opened by phase 2.

This distinction is binding on how a pass may be cited.

---

## 4. Fixtures

Three independent fixtures, each with a unique source and an independently checkable outcome. Content is synthetic; no production data.

Each fixture provides:

| Element | Requirement |
|---|---|
| `S1` | ≈300–600 tokens of synthetic material containing a random `transfer_secret` (12 hex chars) and distractor facts |
| `transfer_secret` | appears only in `S1`; must appear in `R1` and be required by U2's checker |
| `context_canary` | random 16-hex token placed **only** in the phase-1 system prompt; never in `S1`, `R1`, the Information Space, or any phase-2 input |
| U1 task | extract a fixed JSON object `{secret, facts…}` — deterministic schema, model-generated content |
| U2 task | produce `ANSWER=<secret>-<checksum>` where `checksum` is derived from a field of `R1`; the checker recomputes it independently |
| Checker | parses U2 output, verifies format, secret equality with the settled `R1`, and checksum; returns PASS/FAIL — not exact-string equality |

Fixture 2 and 3 vary the structure (one longer source, one with a distractor that looks like a secret) so that a pass cannot come from a single template artifact.

**Canary placement and scan (D4).** The canary belongs to the old-stage context only. Scan scope: rendered phase-1 and phase-2 prompts, the actual model request records, outputs, stdout/stderr, tool-call records, cache observation logs and all evidence artifacts. A canary found in `R1` voids the fixture and stops the batch — a rebuilt fixture needs a new manifest, and the void run is not counted. A canary found on any phase-2 surface is a leak and fails G2-A. Absence of the canary is corroborating evidence only and never replaces the lifecycle or lookup rows.

---

## 5. Matrix and start budget

`Model start` = one process that loads the model. Everything else (cache cleanup, database preparation, digesting, negative-control execution) is listed but not counted as a model start.

| Arm | Treatment | Model starts per fixture |
|---|---|---|
| **A — continuous baseline** | one process: U1 settles `R1`, the same session continues to U2 | 1 |
| **B — G2 main, phase 1** | U1 settles `R1`; no snapshot export | 1 |
| **B — G2 main, phase 2** | cold host restores `R1` from the carrier and runs U2 | 1 |
| **C-missing** | restore-eligibility gate on a copy with the settlement object removed; no model load | 0 |
| **C-tampered** | restore-eligibility gate on a copy with the payload replaced; no model load | 0 |

Per fixture: 3 model starts and 2 non-model validation processes. Three fixtures: **9 model starts, hard cap 15**. The cap is a ceiling, not a retry allowance.

Arm C never loads the model. Refusal happens in the restore-eligibility gate before any model load, so "no downstream call happened" is observable without inference. For each fixture the canonical phase-1 carrier is preserved unmodified with its SHA-256 recorded; `C-missing` and `C-tampered` each derive from an independent byte-copy of it, never share a copy, and never touch the canonical file.

Non-model steps, listed so the budget is auditable: 6 carrier copies (2 per fixture), 6 eligibility-gate processes, artifact-root digesting, store-inventory checks, and the P3 scans.

**Stop rule.** No retry, no model substitution, no fixture substitution, no matrix expansion under one authorization. A failure ends the batch and returns to review; any further run needs a new manifest and a new authorization.

---

## 6. Protocol

### P0 — capability probe (separate authorization, budget 1 model start)

P0 is its own gate and is **not** covered by the G2 batch authorization. Its purposes, in order:

1. Load the frozen artifact from `G2_MODEL_BINDING_20261020.json`; record `EngineModelIdentity.compute` output and compare it against the binding. A mismatch stops P0.
2. Run one short `ChatSession` generation under the frozen parameters; record chunk sequence and completion token count.
3. Install `MLXPrefixCrossSessionCache` on an empty store base and confirm `observations.calls > 0` with `hits == 0` on a lookup.
4. Record build identity: `swift build -c release` product hash, `Package.resolved` digests, source revision, clean-tree flag.

P0 has 1 model start and no retry. If loading, the real `ChatSession` path, or the observation hook fails, P0 ends `FAIL` and the design returns for amendment; substitution is not permitted. P0 must be authorized explicitly, and the batch manifest cannot be issued until P0's terminal record exists.

### P1 — phase 1 (old stage)

1. Fresh process; fresh per-run store base; **no snapshot export is performed**.
2. Record: process id / group, start time, model identity, prompt hash and token count, `transfer_secret` / `context_canary` (in the evidence root only), generation record (chunk sequence + completion token count), `R1` and its canonical digest.
3. Settle `R1` into the isolated carrier with source identity, version, dependency closure and validity policy; record `object_id` and settlement record.
4. Record store inventory: **zero artifacts** (this is what makes "old KV unavailable" non-vacuous in the main arm).

### Gap — old stage exits

1. Terminate the phase-1 host (SIGTERM, then SIGKILL on timeout) and record exit status.
2. Verify `kill(pid, 0)` returns `ESRCH`; verify the process group is empty.
3. Compute the artifact-root digest and record it; the root is then made unreadable (`chmod 000`) for the remainder of the run and restored only after evidence capture.

### P2 — phase 2 (new stage)

1. New process; new store base (fresh, empty); install `MLXPrefixCrossSessionCache` on that empty base with the model-content namespace, so every lookup is **counted** and must miss.
2. Restore `R1` from the carrier: value, `object_id`, source identity, dependency closure, validity basis. Re-hash and compare against the phase-1 record.
3. Build the U2 prompt from `R1` + downstream instruction only. `S1`, the phase-1 prompt and the canary are not available to this process (not in env, not in files it is given).
4. Run U2; record hook observations (`calls`, `hits`, `matchedTokenCounts`), prompt token count, generation record, output.

### P3 — verification

1. Run the frozen checker on U2 output.
2. Scan phase-2 prompt, output, logs and artifacts for `context_canary` and for `S1` markers (e.g. a rare token from `S1`).
3. Read the carrier: confirm no U1 compute in phase 2, `R1` still `SETTLED` with unchanged `object_id`.
4. Compare the artifact root digest with the value recorded before phase 2 (unchanged), and confirm the phase-2 store inventory is still empty (no writes, no adoption).

---

## 7. Evidence gates

### G2-A — old KV accessibility

| Required evidence | Pass standard | Fail / inconclusive |
|---|---|---|
| Old host lifecycle | exit record + `ESRCH` + empty process group | host alive or exit unverifiable → `INCONCLUSIVE` |
| New execution identity | new pid/pgid, new start time, new store base, new cache instance | reused process or inherited store base → `FAIL` |
| Cache isolation | phase-1 store inventory empty; old root unreadable and digest-unchanged; new base distinct | any phase-1 artifact exists and is reachable → `FAIL` |
| Cache lookup record | hook installed in phase 2; `calls > 0`; `hits == 0`; no `matchedTokenCount` equal to any phase-1 prefix length | hook absent or observations unavailable → `INCONCLUSIVE` |
| Canary | `context_canary` absent from phase-2 prompt, output, logs and artifacts | present anywhere → `FAIL` |

**Evidence boundary (frozen).** `observations` counts only lookups routed through `ChatSession`'s installed hook. It does not observe direct filesystem reads, OS page-cache or swap state, or any model-internal reuse that bypasses the hook. G2-A therefore rests on the conjunction of the five rows above — process death, new identity, empty and unreadable old store, counted misses, canary — and never on any single one. If the hook cannot be installed, or `observations` is unavailable, G2-A is `INCONCLUSIVE` regardless of how clean the output looks. The claim is accessibility, not physical erasure.

### G2-B — Information-Space restoration

| Required evidence | Pass standard |
|---|---|
| Result identity | restored `object_id` equals the phase-1 settlement `object_id`; re-hash equals |
| Source and version | restored source identity and version equal the phase-1 record |
| Dependency closure | closure complete; every dependency id and digest equals |
| Validity basis | validity policy digest equals; validation returns valid |
| Negative control · C-missing | settlement object and index entry for `R1` removed from an independent copy; gate refuses with the frozen code `SETTLEMENT_MISSING` before any model load; copy digest unchanged after refusal |
| Negative control · C-tampered | stored payload replaced with different bytes while the index pointer is kept; re-hash mismatch refuses with the frozen code `OBJECT_DIGEST_MISMATCH` before any model load; copy digest unchanged after refusal |
| No recompute path | the phase-2 host has no U1 calculator wired and does not call `execute_demand`; "recompute, then report success" is structurally unavailable, not merely discouraged |
| No silent repair | blocked runs leave the carrier copy byte-identical; no settlement is written |

### G2-C — real-model continuation

| Required evidence | Pass standard |
|---|---|
| U2 really ran | phase-2 model events with model identity, prompt token count, completion count, chunk sequence |
| Upstream came from IS | U2 output contains the `transfer_secret`, which exists only in `S1` and in the restored `R1` from the carrier |
| U1 not re-executed | no phase-2 model call with input hash equal to the `S1` prompt; no U1 compute in the phase-2 carrier log; `S1` absent from phase-2 inputs |
| Source not re-injected | `S1` markers absent from phase-2 prompt and logs |
| Semantic criterion | frozen checker PASS on all three fixtures |
| Honest boundary | prefilling `R1` is recorded and is explicitly not counted as redoing U1 |

---

## 8. Verdict rules

**PASS** — A, B and both negative-control variants meet every row above on all three fixtures; the negative controls block as designed; model identity, host lifecycle and event provenance are traceable; no old-KV access, no wrong restoration, no U1 re-execution. P0 is a separate gate and is not part of this verdict.

**FAIL** — any counterexample: an old-stage artifact hit, an identity or closure mismatch, a negative control that continued, a re-scheduled U1, or a checker failure.

**INCONCLUSIVE / STOP** — the mechanism evidence is missing even if outputs look correct: model failed its load probe or identity is unpinned, host lifecycle is unclear, the hook is absent so lookups cannot be counted, events were not produced by the execution side, or a fixture was re-fed to the model. Correct output never substitutes for a missing mechanism row.

**Stop rule.** One authorization, one run set. A failure is located and fixed by amending the design, not by repeating until green. Any rerun requires a new manifest and a new human authorization.

---

## 9. Execution control and authorization scope

- **Phase separation.** `P0 probe` → `batch manifest` → `batch authorization` are three distinct acts. A batch authorization may not be issued before P0's terminal record exists.
- **Manifest.** Fixes source revision and clean-tree flag, build product hash, `Package.resolved` digests, model aggregate digest and file manifest, fixture digests, checker digests, evidence root, the 9-start planned budget with a 15-start hard cap, and terminal states.
- **Authorization.** A marker file whose content is the manifest's SHA-256; consumed atomically (rename) before the first child launch. Consumed means no second run.
- **Scope.** One authorization covers exactly: 3 fixtures × (A, B phase 1, B phase 2) plus 6 negative-control validations. It does not cover retries, a different model, different fixtures, or additional arms.
- **Write-once.** Evidence root `create-exclusive`; terminal record `O_CREAT|O_EXCL`; raw outputs are preserved unmodified and digested before any derived report is written.
- **Isolation.** Child processes run in their own process group; timeout kills the group with SIGKILL.
- **Separation from G1.** G2 evidence never enters `g1-evidence/` and never modifies the G1 closure record.

---

## 10. Non-claims (binding)

1. **Not a physical-erasure proof.** G2-A tests accessibility, not RAM remanence, swap or page-cache sanitization.
2. **Not a token-level KV-reuse proof.** The claim is that U1 is not re-executed; prefilling `R1` is expected and measured.
3. **Not a general model capability claim.** Three synthetic fixtures with a frozen checker; nothing about arbitrary tasks or long chains.
4. **Not a production authorization.** No deployment, no traffic, no signer movement, no R27 change.
5. **Not G1 evidence.** G1 stays `CLOSED` on its own record; this gate neither extends nor reinterprets it.
6. **Not an adversarial-resistance claim.** Phase 1 deliberately exports no snapshot, so G2-A shows that the new stage has no accessible path and needs none. It does not show resistance to an actor that deliberately re-adopts a retained artifact.

---

## 11. Ruling record (2026-10-20)

| ID | Ruling | Condition carried into this revision |
|---|---|---|
| D1 | Conditional accept | full 64-hex artifact identity, file manifest and backend/config/tokenizer pins (§2.3, binding file); P0 probe mandatory; no substitution |
| D2 | Accept with cap | matrix fixed with per-arm start counts; 9 planned, 15 hard cap; P0 separate; no retry, substitution or expansion |
| D3 | Accept with injection rules | independent copies; `C-missing` and `C-tampered` defined by operation and expected refusal code; refusal before model load; no recompute path |
| D4 | Accept with placement rules | canary confined to the old-stage context; scan extended to requests, rendered prompts, tool-call and cache logs; `R1` contamination invalidates the fixture |
| D5 | Accept | design and manifest committed first; run evidence only after human audit; raw output is never rewritten |

`FROZEN` here means these are the terms that would be executed. It is not an execution authorization.

---

## 12. Artifacts (if and when authorized)

```text
docs/01-questions/G2_MODEL_BINDING_20261020.json      # frozen artifact identity (committed with this design)
docs/01-questions/G2_PREREGISTRATION_20261020.md      # this file

execution-information-loop/experiment/continuous-calc-verification/
  model-level-validation/g2/
    manifest/G2_MANIFEST.json (+ .sha256)
    p0/<run-id>/terminal.json + probe records
    evidence/<run-id>/phase1/ phase2/ phase3/ termination.json
```

Design records stay in `docs/01-questions/`; run evidence stays with the experiment. No run path is created by this freeze.
