# A 30-Minute Entry Point for External Readers

**Status**: FINAL-REVIEW DRAFT (English). Linked from README as the English entry (owner authorization 2026-11-14). Proactive external publication/sending still requires per-instance owner sign-off — this link is not that authorization.
**Purpose**: Serve **external scrutiny** — the public materials can be read, run, and challenged by anyone. This is **not** an invitation to a formal independent-review process; the project does not currently claim the conditions to convene one. This entry only lowers the cost of forming an outside judgment.
**Audience**: first priority vLLM / SGLang / llama.cpp ecosystems.
**Discipline**: no claim of product maturity, novelty, superiority, or general applicability. Every reading carries its scope; n=1 is labeled as such.

---

## 0. What this entry is for

An external review observed that 156 markdown files are an archive, not an entry point: there is no single path that says "read three things, run one minimal chain, form a judgment in 30 minutes." This document is that path. The other 156 files become an appendix, navigated via [docs/README.md](README.md).

**Promise to the outside reader**: within 30 minutes you can form your own judgment — is the question clear, are the boundaries honest, can it be reproduced, does it overlap with existing techniques. Four outcomes are all valid (no novelty / complementary / reproduced / not adopted); negative conclusions are welcome. The judgment belongs to the reviewer, not the proposer.

---

## 1. Read three things (~20 minutes)

### ① Semantic definitions (~7 min) — judge "are the distinctions discriminative?"

- [B0 glossary](upstream/B0_ESIS_GLOSSARY_20261105.md): 15 terms with positive/negative definitions + three semantic boundaries (ES ≠ Snapshot ≠ Carrier; the Settlement / Settled Result / Settlement Record trichotomy; Carrier Independence split into a semantic-layer principle and an implementation-layer claim). ACCEPTED, frozen.
- [B1 minimal formalization](upstream/B1_ESIS_MINIMAL_FORMALIZATION_20261105.md): skeleton `ES_n ──Settlement──▶ IS ──Admission──▶ ES_{n+1}`; R1–R6; **the two predicates Settled(ρ) and Recoverable(ρ,ctx,t) are separated**. A relational skeleton, not a proven complete formal system; OQ-1/3/8 explicitly OPEN.
- Implementation-side terminology of record: [TERMINOLOGY_V0.1](research/es-is/TERMINOLOGY_V0.1_20261109.md).

**Ask yourself after reading**: are `Settled ≠ Recoverable`, `Refuse ≠ re-execution`, and dependency-closure invalidation touching only the closure — relabelings, or distinctions with discriminative power?

### ② Evidence boundaries (~7 min) — judge "are the boundaries honest?"

- [Research map](research/es-is/ESIS_RESEARCH_MAP_V0.1_20261108.md): each thesis → code anchor → test → reading → gap (G1–G6). Four propositions P1–P4.
- [Open problems](knowledge/open-problems/README.md): each item carries a "boundary" subsection stating what is *not* proven.
- [Experiment index](experiments/README.md) reading principles: a passing experiment supports only its stated scope; different file/directory names ≠ independent evidence; historical experiments do not automatically represent current capability.

**Ask yourself**: does the author actively narrow the scope of their own conclusions? Are n=1, latency contamination, and single-path coverage labeled honestly?

### ③ How to reproduce a minimal chain (~6 min read) — judge "can it be reproduced?"

- [P2 four-stage experiment plan](upstream/P2_EXPERIMENT_PLAN_20261105.md): real-model settlement → release old KV → IS recovery → new ES continuation. Plan G1 CONDITIONAL PASS; **a sound plan ≠ a passing experiment**; the public reproducible main-chain Run has not yet been executed (hard precondition: key experiments must not lag the research description).
- Executed supporting evidence (n=1): [ESIS gap-closure four arms](experiments/ESIS_GAP_CLOSURE_20261110/README.md) (carrier independence: SIGKILL → cold start → zero-call consumption); [C2 Session Readiness matrix results](experiments/C2_SESSION_READINESS_MATRIX_RESULTS_20261113.md) (H1 supported in weak form; C/F recorded N/A-this-build).

**Ask yourself**: are the acceptance conditions of this chain checkable? Which readings already exist, and which are still missing?

---

## 2. Run a minimal chain (hands-on; three tiers, prerequisites verified)

The minimal chain is not one device but three tiers, with rising prerequisites and rising proving power. **The public text must present them by tier; a pass at a low tier must not be passed off as a conclusion at a higher tier.**

### Tier 0 · Probe self-check (zero build / zero model — actually run and verified)

```bash
python3 docs/experiments/ESIS_GAP_CLOSURE_20261110/rig/compose_probe/compose_probe.py --self-check
```

- **Prerequisites**: python3 standard library only (argparse/json/os/shutil/sqlite3/subprocess/sys/tempfile). No third-party dependency, no model, no App build, no running instance. Self-contained in a temp directory.
- **Verified reading (2026-11-14, run on a clean path in this repo)**: `EXIT=0`, final line `SELFCHECK PASS`; all four configurations (epsilon+delta / beta+gamma / epsilon+alpha / blind) classify red/green as expected.
- **What it proves**: the probe's own reading and classification logic can go red and green — including a falsification arm: `blind` (still returns a value after the control file changes) → positive control does not fire → `E2: void`; the probe refuses to count a run that cannot observe withdrawal as a pass.
- **What it does NOT prove (key boundary)**: the self-check uses a **stub CLI**; it validates the **probe**, not SimiGo's real system behavior. It must not be used to claim "ES/IS compositionality has been verified on the real system." This is the only zero-prerequisite reproducible artifact in the 30-minute entry; its role is to let an outside reader confirm with their own hands that this set of criteria self-falsifies — not a product demo.

### Tier 1 · Formal compositionality run (requires building the contract CLI; still no model)

```bash
python3 .../compose_probe/compose_probe.py --cli <path-to-contract-cli-binary> [--work DIR]
```

- **Prerequisites**: a Swift toolchain (macOS Xcode CLT) to build the contract CLI — sources in `rig/baseline/contract_cli{,_v2}.swift` and `rig/compose_probe/product_rig/` (Swift package `turn-cli`). **Still loads no model and needs no full App.**
- **What it proves**: compositionality readings of E1 (one demand, two authorities → one judgment? epsilon/beta) and E2 (does cross-space withdrawal travel by edge or by recompute? delta/gamma/alpha) against the real contract CLI.
- **Status**: the device exists and the self-check is green; the formal `--cli` run requires building the CLI first and was **not** run in this window.

### Tier 2 · Full carrier-independence chain / C2 matrix (heavy prerequisites; not a 30-minute clean checkout)

- Carrier arm `rig/baseline/carrier_driver.py`: SIGKILL the process → cold start → explicit consumption; expected `consumed / model_calls=0 / new objects / value equality`.
- C2 driver `experiments/C2_SESSION_READINESS_MATRIX_RESULTS_20261113_evidence/c2_driver_20261113.py`: `POST 127.0.0.1:8000/v1/chat/completions` + `X-SimiGo-Agent` + reads `~/.simigo/logs/native_mlx_trace.log`.
- **Prerequisites (all required)**: a built product App + user-supplied local model weights + a running instance + isolated `SIMIGO_HOME`/`SIMIGO_CACHE_ROOT`/port/experiment DB. The carrier arm's latency readings are contaminated by a parallel production instance (`contaminated=true`); structural assertions are unaffected.
- **Conclusion**: this tier is **not** a clean-checkout 30-minute demo. Packaging the full chain into a zero-build reproducible artifact is **open work** under the P2 hard precondition, and is not promised by this entry.

**Honest scope (must appear in the public text)**:
- Tier 0 actually run and verified (stub, falsification arm effective); Tier 1 device ready, not run in this window; Tier 2 heavy prerequisites, not a 30-minute demo. **A zero-build full-chain 30-minute demo does not currently exist.**
- Supporting readings are all n=1 (single machine / single build / single model / single day); latency readings are contaminated by memory pressure and make no steady-state performance claim.
- Evidence databases `*.sqlite3` and build artifacts are **not committed**; they are located by ledger + hash. The same-hash binary copy is unique; rebuilding from source does not guarantee the same hash.
- Across engines only values pass; KV representations are not portable. A single-side reading is not extrapolated into a unified conformance.
- Tiers 1/2 require Apple Silicon macOS + Xcode + user-supplied model weights (not distributed by this repo); Tier 0 requires only python3.

---

## 3. Form a judgment (~5 minutes)

Against [route doc §5, four related-work comparisons](upstream/DEEPSEEK_ES_IS_SEMANTIC_ROUTE_20261105.md) (hypothesis status; until the per-system six-question audit is done, do not assert that an existing system "lacks" a capability):

| System compared | What it does | What ES/IS claims is different |
|---|---|---|
| vLLM prefix caching / LMCache / CacheGen / CacheBlend | reuse computed results | does not define an authority for "settlement and validity"; ES/IS uses a settlement ledger to decide when reuse is trustworthy and when re-execution is required |
| checkpoint / durable execution | save state / resume execution | (pending per-system six-question audit; no preset conclusion) |

**Judgment checklist**: Is the question clear and specific enough? Are the boundaries honest? Can the minimal chain be reproduced? Overlap or complementarity with existing techniques? Which application scenario fails? — A negative conclusion is as valid as a successful reproduction.

---

## 4. Appendix and navigation

The other 156 documents are a research archive, not required reading. To go deeper, enter via the Start here and evidence/archival rules in [docs/README.md](README.md). Authority order: frozen contracts and authoritative implementation > B0/B1 frozen artifacts > configuration records > plans > route documents; revise lower layers without altering upper ones.

---

## 5. Pending owner sign-off / completion

1. ~~Clean-checkout runnability of minimal-chain candidates~~ **Verified (2026-11-14)**: Tier 0 `compose_probe.py --self-check` ran zero-build/zero-model to `SELFCHECK PASS` (stub, falsification arm effective); Tier 1 needs the contract CLI built (no model), device ready but not run; Tier 2 heavy prerequisites, not a 30-minute demo. A zero-build full-chain demo does not exist; packaging it is open P2 work.
2. This English final-review draft — **external publication requires owner sign-off**.
3. ~~Link this entry from the README "Research & engineering docs" section~~ **Done (2026-11-14, owner authorized)**; proactive external sending remains separately gated.
4. Until the related-work six-question audit (P3) is complete, the §3 comparison table stays labeled hypothesis and is not upgraded to an assertion.