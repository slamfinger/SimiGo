# IPAC Instantiate Runtime Realization & Verification — Conceptual Design v0.3 (Gate I-1d)

Date: 2026-10-05
Branch: `codex/execution-state-research-20260929`
Status: `READY FOR FREEZE DECISION (final classification patch applied: POST-CREATION-ANOMALY primary disposition = PROCEED-WITH-ANNOTATION; recovery attempt independently dispositioned) · IMPLEMENTATION / EXPERIMENT / PALACE / BACKEND REMAIN BLOCKED`
Revision lineage: v0.1 (`4b2f42d`) → review (four mandatory fixes) → v0.2 (`6590dd6`, TaskRecord + verdict tiers + narrowed anti-drift + idempotence withdrawn) → review (fixes confirmed; three local consistency patches before freeze) → v0.3 (this document) → **final classification patch** (2026-10-05: POST-CREATION-ANOMALY's primary disposition = PROCEED-WITH-ANNOTATION, annotation = IR-INCOMPLETE/POST-CREATION-ANOMALY; recovery attempt independently dispositioned — orthogonality now formal) — freeze-ready.

---

## 0. What changed from v0.2 — and what did not

**Human review of v0.2 (registered):** the four v0.1 fixes are confirmed landed — TaskRecord→SC-5→IR closure holds; **VERIFIED ≠ COVENANTED ≠ FAILED** is now the line's evidence discipline; the narrowed anti-drift correctly demotes hidden-code purity to a future static-audit layer; idempotence is withdrawn. Direction ACCEPT.

**Changed — the three consistency patches (applied here):**

1. **IR lifecycle** (§2, §3.1): the IR is established at **step 0** as a minimal *instantiate-attempt* record and completed at step 5 on success — on successful instantiation it simultaneously becomes **S2's birth record**. This resolves the conflict between "step-0 REFUSE produces no IR" and the compliance clause "an IR exists for every instantiate attempt". New definition: **IR = the instantiate-attempt / instantiate-result record.** Step-0 failure → IR closed with the failure disposition; step-3 success → IR marks S2's creation; step-5 → IR completed with VV results.
2. **COVENANTED is a verification state, never a failure signature** (§3, §4): "not knowing whether there is a violation" ≠ "discovering a violation". ENVELOPE-DRIFT exists **only** where readback makes the mismatch observable; a constructor-capture-only substrate yields the check state **COVENANTED (effective envelope unobservable)** — never ENVELOPE-DRIFT. The conflation sentence from v0.2 is corrected.
3. **Disposition classes layered** (§4): the three disposition classes are retained and made formally exhaustive — **BLOCK** with concrete subtypes {PRECONDITION-BLOCK, CREATE-BLOCK}; **PROCEED-WITH-ANNOTATION** (annotation set possibly empty — the clean BOUND case is its zero-annotation member); **DECLARED-ALTERNATIVE** (policy-declared cross-model path). **POST-CREATION-ANOMALY is a lifecycle/recovery state, not a fourth disposition class** — it records where in the lifecycle the attempt stands and may accompany recovery; it does not compete with the disposition vocabulary.

**Unchanged (review-confirmed):** the three-axis frozen stack behind this gate; TaskRecord→SC-5→IR closure; the verdict tiers VERIFIED/COVENANTED/FAILED; the narrowed anti-drift guarantee; the idempotence withdrawal; the creation-point operational definition (open item); the pipeline order; the storage-agnostic, no-PALACE, no-implementation, no-experiment boundaries; **the M-table and VV numbering remain frozen — no expansion.**

---

## 1. Contract → runtime object

### 1.1 The runtime objects (IR lifecycle now defined)

```text
Instantiate Record (IR)   the instantiate-ATTEMPT / instantiate-RESULT record:
                          established at step 0 (attempt identity, precondition
                          inputs: R2 digest, TaskRecord), completed at step 5 on
                          success (BindingRecord, ExecutionEnvelope,
                          SubstrateManifest, PositionRecord, attached segment
                          provenance (E1.seg ids), verification results VV-1..VV-7
                          with per-check verdict tiers, timestamp, actor) — or
                          closed earlier with the failure disposition. On successful
                          instantiation the completed IR is simultaneously S2's birth
                          record.
TaskRecord                { task-ref / task-content-digest, declaration source,
                          version } — the τ2 identity, written at step 0.
BindingRecord             { state: BOUND | UNBOUND | MISMATCH, predecessor-weights-id?,
                          declared-weights-id?, decision inputs } — computed at step 1.
ExecutionEnvelope         ε2 as declared: { policy, limits, tool-availability }.
SubstrateManifest         { engine-id, weights-id (as bound), tokenizer-id }.
PositionRecord            { method: derived, tokenizer-id, surface-length-units } (PD-6).
```

**Lifecycle (fix 1):**

```text
step 0   IR established (attempt record; precondition inputs; TaskRecord)
         ├─ precondition fail → IR closed with BLOCK / PRECONDITION-BLOCK
         └─ proceed
step 1   BindingRecord appended
step 2   restore metrics appended (if taken)
step 3   materialize success → IR marks S2's creation (birth record)
step 4   attachment evidence appended
step 5   IR completed with VV-1..VV-7 results → Instantiate Verdict
         (an IR completion failure here = POST-CREATION-ANOMALY, §4)
```

Compliance clause (a) now reads: **an IR exists for every instantiate attempt — established at step 0, completed at step 5 on success, or closed with the failure disposition otherwise.** The v0.2 contradiction is gone.

### 1.2 The mapping table (retained; SC-5 row carries TaskRecord)

Unchanged from v0.2 §1.2, including the coverage rule (every row realized, every check result recorded in the IR at its verdict tier) — with the ENVELOPE-DRIFT row's failure signature now readback-scoped per §4, and the IR-column interpreted under the new lifecycle.

---

## 2. The instantiate boundary (retained; creation point operational definition noted)

```text
 0. precondition    R2 = RESOLVED (clean); τ2★ present; TaskRecord written — else
                    IR closed with BLOCK / PRECONDITION-BLOCK
 1. bind            substrate.bind(weights-identity, ε2) → BindingRecord
 2. restore (opt)   substrate.restore(carrier-state) → consumed-prefix metrics
 3. materialize     substrate.materialize(R2.surface) → **CREATION POINT** —
                    defined operationally: successful materialization, subject to
                    the runtime object exposing a newly ADDRESSABLE continuation
                    object (no backend's function name is a theory requirement)
 4. attach          lineage/segment provenance bound into S2's context
 5. record          IR completed with VV-1..VV-7 → Instantiate Verdict
```

POST-CREATION-ANOMALY default recovery: conservative re-instantiation from the same RESOLVED R2; **idempotence not claimed** (per the frozen v0.2 fix). The original attempt's primary disposition is PROCEED-WITH-ANNOTATION (annotation: IR-INCOMPLETE / POST-CREATION-ANOMALY); the recovery attempt independently receives its own disposition.

---

## 3. Check verdict tiers and the state/signature boundary (fix 2)

Every Verification Surface check emits a verdict **state**:

```text
VERIFIED    the mechanical check actually ran and passed
COVENANTED  the check cannot observe the property on this substrate; an explicit
            trust boundary is recorded
FAILED      the mechanical check observed a violation
```

**Frozen boundary (Human review, verbatim in substance):**

> **"不知道有没有违规" ≠ "发现违规"。**
> *(Not knowing whether there is a violation ≠ discovering a violation.)*

**COVENANTED is a verification state, never a failure signature.** Failure signatures exist only under FAILED. Concrete case: with readback, a declared/effective envelope mismatch is **observed** → the check is FAILED with signature ENVELOPE-DRIFT; without readback, the effective envelope is **unobservable** → the check is COVENANTED — and ENVELOPE-DRIFT is not claimable. The v0.2 sentence that surfaced drift "as COVENANTED-class audit findings" is corrected accordingly: what the audit finds there is the *covenant*, not the drift.

---

## 4. Runtime failure taxonomy (layered — fix 3)

**Three disposition classes, formally exhaustive over instantiate outcomes; failure subtypes and lifecycle states are layered beneath them:**

```text
DISPOSITION CLASS 1 — BLOCK
    ├─ subtype PRECONDITION-BLOCK   (step 0: R2 not RESOLVED; τ2★/TaskRecord
    │                                missing or digest mismatch — resolve-side
    │                                signatures carry: CR-ID-MISMATCH, I-NF,
    │                                I-MISMATCH, A-SUB, A-CYCLE, P-VIOLATION,
    │                                FORM-DRIFT, TASK-MISSING)
    └─ subtype CREATE-BLOCK         (substrate bind/materialize error;
                                     VV-2 FAILED = SURFACE-INFIDELITY;
                                     VV-4 FAILED = ENVELOPE-DRIFT [readback];
                                     VV-5 FAILED = POSITION-DERIV-FAIL;
                                     VV-6 FAILED = LINEAGE-ATTACH-FAIL)

DISPOSITION CLASS 2 — PROCEED-WITH-ANNOTATION
    (the proceed family; the annotation set may be EMPTY — the clean BOUND
     case is its zero-annotation member)
    ├─ BINDING = BOUND              → empty set (lineage-strict claim available)
    ├─ BINDING = UNBOUND            → annotation: lineage-strict UNDECIDABLE
    │                                (recorded, never inferred)
    ├─ carrier absent               → annotation: no carrier-form no-recompute
    │                                evidence (document-form unaffected)
    ├─ RESTORE-FAIL                 → annotation: efficiency path forfeited
    └─ MANIFEST-INCOMPLETE          → annotation + audit finding

DISPOSITION CLASS 3 — DECLARED-ALTERNATIVE
    └─ BINDING = MISMATCH           → declared cross-model continuation
                                     (per PD-7 policy); blocks iff the envelope
                                     declares `lineage-strict: required`

LIFECYCLE STATE (orthogonal to the disposition classes)
    └─ POST-CREATION-ANOMALY        S2 exists but the IR is not completed.
         primary disposition        = PROCEED-WITH-ANNOTATION — the object
                                      lifecycle continues, with this attempt's
                                      auditability degraded (not BLOCK: S2
                                      exists; not DECLARED-ALTERNATIVE: no
                                      alternative semantics was declared)
         annotation                 = IR-INCOMPLETE / POST-CREATION-ANOMALY
         recovery                   = conservative re-instantiation from the same
                                      RESOLVED R2 (idempotence not claimed); the
                                      recovery attempt independently receives its
                                      own disposition (BLOCK /
                                      PROCEED-WITH-ANNOTATION /
                                      DECLARED-ALTERNATIVE)
```

**Forbidden everywhere: silent degradation** — every deviation is a recorded annotation, a declared alternative, or a block; nothing is unrecorded convenience. **Exhaustiveness now holds formally, including the anomalous path**: every instantiate outcome maps to exactly one primary disposition class (with subtype) — the POST-CREATION-ANOMALY outcome's primary disposition is PROCEED-WITH-ANNOTATION (annotation: IR-INCOMPLETE / POST-CREATION-ANOMALY), with POST-CREATION-ANOMALY recorded as its orthogonal lifecycle state; recovery attempts are independent attempts and receive their own dispositions.

---

## 5. The anti-drift guarantee (retained at the v0.2 narrowed scope)

An implementation claims I-1d compliance iff:

```text
(a) an IR exists for every instantiate attempt (established at step 0; completed
    at step 5 on success; closed with its failure disposition on earlier failure;
    or — under POST-CREATION-ANOMALY — left incomplete with that annotation and
    the primary disposition PROCEED-WITH-ANNOTATION) with exactly the §1.1 fields
    at their verdict tiers;
(b) the verification results VV-1..VV-7 (with tiers) appear in the runtime trace;
(c) the mapping table is fully covered — no clause without object+check;
(d) the failure taxonomy is honored — no failure class silently reclassified;
(e) the mapping table carries this design's freeze lineage.
```

I-1d mechanically detects: missing contract mapping; weakened declared verification; altered failure semantics; undeclared decision inputs entering the recorded verification path. I-1d alone does **not** prove the absence of arbitrary hidden semantic logic — code-level static audit is a separate future evidence layer. (Frozen methodological boundary, v0.2 §5.)

## 6. What this design does not do

No substrate/backend implementation or selection; no carrier choice (PALACE untouched); no storage-format binding for the IR; no experiment; no M-table, VV-numbering, edge-vocabulary, or runtime-ontology expansion; no new claim strength for UNBOUND/MISMATCH/COVENANTED continuations; no semantic judgment in the Verification Surface.

## 7. Open items for Human Review

1. **IR lifecycle** — accept the attempt-record scheme (fix 1).
2. **The state/signature boundary** — accept COVENANTED as a verification state, never a failure signature (fix 2).
3. **The layered disposition taxonomy** — accept the three classes with subtypes and POST-CREATION-ANOMALY as lifecycle state (fix 3).
4. **The creation-point operational wording** — confirm at freeze ("newly addressable continuation object").
5. POST-CREATION default recovery — confirm.
6. PD-5/6/7 — confirm (carried).

## 8. Non-claims

No substrate/backend implementation or selection; no carrier choice (PALACE untouched); nothing implemented or run; no idempotence claim; no claim that mapping coverage proves the absence of hidden semantic logic; no claim that COVENANTED checks verify anything; no expansion of the M-table, VV numbering, edge vocabulary, or runtime ontology; no semantic judgment in the Verification Surface; the Implementation gate remains closed behind Human Review of this design and a subsequent ruling.
