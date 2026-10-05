# IPAC Instantiate Runtime Realization & Verification — Conceptual Design v0.2 (Gate I-1d)

Date: 2026-10-05
Branch: `codex/execution-state-research-20260929`
Status: `REVISED DRAFT v0.2 · INCORPORATES THE HUMAN REVIEW VERDICT ON V0.1 · FREEZE NOT YET · IMPLEMENTATION / EXPERIMENT / PALACE / BACKEND BLOCKED · PENDING HUMAN REVIEW`
Revision lineage: v0.1 (`4b2f42d`) → Human Review verdict (2026-10-05: direction ACCEPT; central deliverable stands; design REVISE — four mandatory fixes; constraint: no VV expansion, no M-table expansion, no new runtime ontology) → v0.2 (this document).

---

## 0. What changed from v0.1 — and what did not

**Human review of v0.1 (registered):** direction ACCEPT; the central deliverable (the auditable three-way mapping) **stands**; and one structural achievement is named for keeps — the **CR/IR pairing turns the loop into an auditable object chain**:

```text
CR(E1) → resolve → R2 → instantiate → IR(S2) → execute → CR(E2)
```

which makes "Information Space → Execution State → Information Space" auditable as a chain of objects rather than a runtime log.

**Four mandatory fixes (applied here):**

1. **IR records the τ2 identity** (§1.1, §1.2): a **TaskRecord** {task-ref / task-content-digest, declaration source, version} is added to the IR, so SC-5 truly enters the three-way mapping — from the IR one can mechanically answer *which externally declared T2 this S2 was created for*. (IR field addition only — no VV row added; the task-digest check folds into VV-1's precondition definition.)
2. **Check verdicts formalized in three levels** (§3): **VERIFIED** (mechanical check actually passed) / **COVENANTED** (the check cannot observe the property; an explicit trust boundary is recorded) / **FAILED** (mechanical check observed violation). Applies to the covenant-class checks (VV-2, VV-4). **COVENANTED never masquerades as VERIFIED**; whether continuation is allowed under COVENANTED is a later implementation policy. Compliance now records the *tier* of every check.
3. **Anti-drift guarantee narrowed to the provable scope** (§5): I-1d mechanically detects (missing contract mapping / weakened declared verification / altered failure semantics / undeclared decision inputs entering the recorded verification path). I-1d alone does **not** prove the absence of arbitrary hidden semantic logic — code-level static audit is a separate future evidence layer, not smuggled in here.
4. **Idempotence withdrawn** (§2): POST-CREATION-ANOMALY's default recovery remains *conservative re-instantiation from the same RESOLVED R2* — **"idempotent" is not claimed at conceptual level** (a real substrate may allocate, create contexts, write runtime state, seed randomness, emit traces).

**Also registered (non-blocking, from the review):** the creation point is defined *operationally* — "successful materialization, subject to the runtime object exposing a newly **addressable** continuation object" — so no future backend's function name becomes a theory requirement (open item, §7).

**Unchanged:** the pipeline order (bind → restore(opt) → materialize[creation] → attach → record); the mapping table's coverage rule; the three disposition classes; the no-oracle discipline; the storage-agnostic, no-PALACE, no-implementation, no-experiment boundaries; the frozen M-table and edge vocabulary.

---

## 1. Contract → runtime object

### 1.1 The runtime objects (TaskRecord added)

```text
TaskRecord        the τ2 identity, recorded: { task-ref / task-content-digest,
                  declaration source, version (if applicable) } — answers,
                  mechanically and from the IR alone, WHICH externally declared
                  T2 this S2 was created for.
BindingRecord     { state: BOUND | UNBOUND | MISMATCH, predecessor-weights-id?,
                  declared-weights-id?, decision inputs }
ExecutionEnvelope the ε2 object as declared: { policy, limits, tool-availability }
SubstrateManifest { engine-id, weights-id (as bound), tokenizer-id }
PositionRecord    { method: derived, tokenizer-id, surface-length-units } (PD-6)
Instantiate Record (IR)   { CR_ref resolved, R2 digest, TaskRecord, BindingRecord,
                  ExecutionEnvelope, SubstrateManifest, PositionRecord, attached
                  segment provenance (E1.seg ids), verification results
                  (VV-1..VV-7 with per-check verdict tiers), timestamp, actor }
```

### 1.2 The mapping table (updated: SC-5 mapped; verdict tiers marked)

| Frozen clause | Runtime object / field / operation | Mechanical verification | Verdict tier | Failure signature |
|---|---|---|---|---|
| IC-1 information completeness | surface handed to substrate as bytes; used-item identities in IR | surface byte-faithfulness (VV-2); used-item pins (inherited V-2) | VERIFIED / COVENANTED / FAILED | SURFACE-INFIDELITY / I-MISMATCH |
| IC-2 binding | BindingRecord | three-state decision from (R2 provenance, τ2★ declaration) | VERIFIED (decision is always mechanically computable) | — (states → §4 taxonomy) |
| IC-3 envelope | ExecutionEnvelope captured; readback where available | declared ≡ effective | VERIFIED (readback) / COVENANTED (constructor-capture only) / FAILED | ENVELOPE-DRIFT |
| IC-4 lineage | segment provenance + A-chain bound into S2's context; IR references CR(R1) and parent chain | attachment completeness | VERIFIED / FAILED | LINEAGE-ATTACH-FAIL |
| IC-5 position | PositionRecord: tokenize(R2.surface) under bound tokenizer | derivation recorded; tokenizer-id ∈ manifest | VERIFIED / FAILED | POSITION-DERIV-FAIL |
| IC-6 no-oracle | realized by the *absence* of semantic checks in VV-1..VV-7 **plus** the narrowed guarantee (§5) | mapping coverage + declared-check audit | — (structural) | — |
| IC-7 efficiency (optional) | substrate.restore(carrier-state) → consumed-prefix metrics | metrics recorded when the path is taken | VERIFIED / FAILED / NOT-TAKEN | RESTORE-FAIL (non-fatal) |
| SC-1 surface integrity | VV-2 | byte equality | VERIFIED / COVENANTED / FAILED | SURFACE-INFIDELITY |
| SC-2 substrate bound | BindingRecord | IC-2 three-state decision | VERIFIED | — (→ §4) |
| SC-3 envelope active | VV-4 | declared ≡ effective | VERIFIED / COVENANTED / FAILED | ENVELOPE-DRIFT |
| SC-4 lineage attached | VV-6 | attachment completeness | VERIFIED / FAILED | LINEAGE-ATTACH-FAIL |
| SC-5 task declared | **TaskRecord in the IR** | TaskRecord present; task-digest matches the supplied τ2★ | VERIFIED / FAILED | TASK-MISSING / TASK-RECORD-INCOMPLETE (audit finding) |
| SC-6 position derivable | VV-5 | derivation under bound tokenizer | VERIFIED / FAILED | POSITION-DERIV-FAIL |

Coverage rule unchanged: I-1d compliance = every row realized, every check result recorded in the IR at its verdict tier.

---

## 2. The instantiate boundary (retained; idempotence withdrawn)

Pipeline order unchanged:

```text
 0. precondition    R2 = RESOLVED (clean); τ2★ present; TaskRecord written
                    (task-digest over the supplied τ2★)     — else REFUSE
 1. bind            substrate.bind(weights-identity, ε2)    → BindingRecord
 2. restore (opt)   substrate.restore(carrier-state)        → consumed-prefix metrics
 3. materialize     substrate.materialize(R2.surface)       → **CREATION POINT** —
                    defined operationally: successful materialization, subject to
                    the runtime object exposing a newly ADDRESSABLE continuation
                    object (no backend's function name is a theory requirement)
 4. attach          lineage/segment provenance bound into S2's context
 5. record          IR written; VV-1..VV-7 executed → Instantiate Verdict
```

**POST-CREATION-ANOMALY disposition (fix 4):** S2 exists but its record is incomplete — the default recovery candidate is **conservative re-instantiation from the same RESOLVED R2**. **Idempotence is NOT claimed at conceptual level**: a real substrate may allocate resources, create backend contexts, write runtime state, seed randomness, emit traces, or otherwise act non-purely; whether re-instantiation is idempotent is a per-substrate property to be established at implementation, never assumed here.

---

## 3. Check verdict tiers (new — fix 2)

Every check in the Verification Surface emits one of three verdict tiers:

```text
VERIFIED    the mechanical check actually ran and passed
COVENANTED  the check cannot observe the property on this substrate; an explicit
            trust boundary is recorded (covenant class: surface fidelity under
            opaque engines, envelope under constructor-capture-only)
FAILED      the mechanical check observed a violation
```

Rules:

```text
COVENANTED never masquerades as VERIFIED — the IR records the tier per check,
and compliance statements must cite the tier profile (which checks were
VERIFIED vs COVENANTED), not a bare "compliant".
Whether continuation is ALLOWED under COVENANTED checks is a later
implementation policy — I-1d only makes the tier visible and non-forgeable.
```

This preserves the opaque-substrate route (v0.1's fidelity covenant) without diluting the mechanical-verification standard: a readback substrate and a covenant substrate are both I-1d-*mappable*, but they carry **different recorded claim strengths** — and the difference is machine-readable.

---

## 4. Runtime failure taxonomy (retained; covenant tiers and POST-CREATION wording updated)

| Failure / state | Stage | Runtime-visible | Disposition class |
|---|---|---|---|
| PRECONDITION-FAIL (R2 not RESOLVED; τ2★/TaskRecord missing or digest mismatch) | 0 | yes | **PRECONDITION-BLOCK** (resolve-side signatures carry: CR-ID-MISMATCH, I-NF, I-MISMATCH, A-SUB, A-CYCLE, P-VIOLATION, FORM-DRIFT) |
| BINDING = BOUND | 1 | yes | **PROCEED** — lineage-strict claim available |
| BINDING = UNBOUND | 1 | yes | **PROCEED-WITH-ANNOTATION** — lineage-strict status UNDECIDABLE (recorded, never inferred) |
| BINDING = MISMATCH | 1 | yes | **DECLARED-ALTERNATIVE** — proceeds only as declared cross-model continuation; blocks iff the envelope declares `lineage-strict: required` |
| carrier absent | 2 | yes | **PROCEED-WITH-ANNOTATION** (document-form trace provenance unaffected) |
| RESTORE-FAIL | 2 | yes | **PROCEED-WITH-ANNOTATION** |
| substrate bind/materialize error | 1/3 | yes | **CREATE-BLOCK** — no S2 exists |
| SURFACE-INFIDELITY (VV-2 = FAILED) | 3/5 | yes | **CREATE-BLOCK** (a covenant can only be COVENANTED, never quietly FAILED-avoidant) |
| ENVELOPE-DRIFT (VV-4 = FAILED) | 5 | yes | **CREATE-BLOCK** where readback exists; constructor-capture-only substrates surface the drift as COVENANTED-class audit findings, never as silence |
| POSITION-DERIV-FAIL | 5 | yes | **CREATE-BLOCK** (no silent fallback to a stored position — PD-6's alternative requires a revision) |
| LINEAGE-ATTACH-FAIL | 4/5 | yes | **CREATE-BLOCK** (continuing without inherited provenance silently breaks C-CAP(c)) |
| MANIFEST-INCOMPLETE | 5 | yes | **PROCEED-WITH-ANNOTATION** at most; audit finding regardless |
| IR write failure | 5 | yes — post-creation | **POST-CREATION-ANOMALY** — default recovery: conservative re-instantiation (§2); idempotence not claimed |

---

## 5. The anti-drift guarantee — narrowed to the provable scope (fix 3)

An implementation **claims I-1d compliance** iff:

```text
(a) the IR exists for every instantiate attempt, with exactly the §1.1 fields
    (including TaskRecord) at their verdict tiers;
(b) the verification results VV-1..VV-7 (with tiers) appear in the runtime trace;
(c) the mapping table (§1.2) is fully covered — no clause without object+check;
(d) the failure taxonomy (§4) is honored — no failure class silently reclassified;
(e) the mapping table carries this design's freeze lineage.
```

**What I-1d mechanically detects:**

```text
missing contract mapping          (a clause with no object/check)
weakened declared verification    (a check demoted, widened, or made vacuous)
altered failure semantics         (a signature renamed, swallowed, or reclassified)
undeclared decision inputs        (inputs affecting the recorded verification path
                                   without a declared source)
```

**What I-1d alone does NOT prove:**

```text
that arbitrary hidden code contains no semantic judgment. IR completeness is
necessary for auditability, not sufficient for purity: an implementation could
perform unrecorded semantic operations without touching any mapped field.
```

That universal negative is **not claimed and must not be claimed**. Code-level static audit may later become a separate evidence layer; it is deliberately not part of I-1d. The frozen boundary stands: no-oracle = *no semantic check inside the declared Verification Surface*, enforced by the narrowed guarantee above.

---

## 6. What this design does not do

No substrate/backend implementation or selection; no carrier choice (PALACE untouched); no storage-format binding for the IR; no experiment; no M-table, VV-numbering, or edge-vocabulary expansion; no new claim strength for UNBOUND/MISMATCH/COVENANTED continuations; no semantic judgment in the Verification Surface.

## 7. Open items for Human Review

1. **TaskRecord** — accept the field shape (task-ref/digest, declaration source, version).
2. **The verdict tiers** (VERIFIED / COVENANTED / FAILED) and the rule that compliance statements must cite the tier profile — confirm.
3. **The narrowed anti-drift guarantee** (four detectable classes; the universal negative explicitly not claimed) — confirm as the frozen methodological boundary.
4. **The creation-point operational wording** ("newly addressable continuation object") — confirm at freeze.
5. **POST-CREATION-ANOMALY default** (conservative re-instantiation, idempotence not claimed) — confirm.
6. **The three disposition classes** — confirm exhaustiveness.

## 8. Non-claims

No substrate/backend implementation or selection; no carrier choice (PALACE untouched); nothing implemented or run; no idempotence claim; no claim that mapping coverage proves the absence of hidden semantic logic (§5 — the universal negative is explicitly not claimed); no claim that COVENANTED checks verify anything (they record trust boundaries); no expansion of the M-table, VV numbering, edge vocabulary, or the frozen R2/CR contracts; no semantic judgment in the Verification Surface; the Implementation gate remains closed behind Human Review of this design and a subsequent ruling.
