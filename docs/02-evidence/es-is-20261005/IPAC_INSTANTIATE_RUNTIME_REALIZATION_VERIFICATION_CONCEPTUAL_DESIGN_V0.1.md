# IPAC Instantiate Runtime Realization & Verification — Conceptual Design v0.1 (Gate I-1d)

Date: 2026-10-05
Branch: `codex/execution-state-research-20260929`
Status: `CONCEPTUAL DESIGN · I-1d COMMISSIONED (HUMAN RULING 2026-10-05) · NO IMPLEMENTATION · NO EXPERIMENT · NO PALACE / NO BACKEND SELECTION · PENDING HUMAN REVIEW`
Directive: Human commissioning 2026-10-05 — Gate I-1d opened per the registered proposal (Stage Synthesis, `9382435`). The design answers exactly four things: contract→runtime-object mapping; the instantiate boundary; mechanical verification; the runtime failure taxonomy. Purely conceptual: **no implementation, no experiment, no carrier/backend selection.**
Predecessors: `IPAC_PERSISTENCE_RESOLVE_CONCEPTUAL_DESIGN_V0.3.md` (**FROZEN**, main `2b2e2ef`) + `IPAC_INSTANTIATE_COMPLETENESS_CONCEPTUAL_DESIGN_V0.3.md` (**FROZEN**, main `6c3cf6a`). All frozen boundaries inherited and load-bearing.

Session header (Constitution Article 6):

```text
Core target:               I-1d — runtime realization & verification of the frozen Instantiate Contract
Affected closure edge:     I→S (realization half) + S→S (trace mechanics)
Real system object:        the Instantiate Record (IR) and the Verification Surface — CANDIDATE objects;
                           no runtime artifact may be built before Human Review
Expected capability delta: any future implementation can be audited against the frozen contract
                           mechanically — silent semantic drift becomes a detectable missing/failed check
Stop condition:            if any IC/SC clause cannot be mapped to a runtime object + mechanical check
                           without a semantic oracle, that clause is escalated (not silently weakened)
```

---

## 0. Scope and the anti-drift criterion

**What this design is**: the realization-and-verification layer between the two frozen anchors. Its single deliverable is the **auditable three-way mapping**:

```text
FROZEN CONTRACT (IC-1..7, SC-1..6)
        ↕  every clause maps to a named runtime object/field/operation
RUNTIME TRACE / OBJECT (the Instantiate Record, IR)
        ↕  every object/field maps to a named mechanical check
MECHANICAL VERIFICATION (the Verification Surface, VV-1..VV-7)
```

**The anti-drift criterion (the gate's reason to exist, Human-worded in substance):** I-1d must make it provable not that *"instantiate can run"* but that **"the runtime realization has not silently changed the frozen instantiate semantics."** The mechanism: compliance with I-1d is defined as *full mapping coverage* — every frozen clause has its named object and named check, the IR carries exactly those fields, and the check results appear in the runtime trace. A clause whose object is missing, whose check is weakened, or whose failure signature is renamed is **detectable by auditing the IR against this table** — not by reading code. The mapping table is frozen with this design; changing it requires the same revision discipline (G-2 lineage) as changing the contract itself.

**What this design is not**: not an implementation; not a substrate/carrier/backend choice (PALACE untouched); not an experiment; not an expansion of the frozen M-table or edge vocabulary. Where a substrate is opaque (no readback interface), the design marks a **fidelity covenant** (§4.2) — a recorded trust boundary of the same class as PD-2, never passed off as a verification.

---

## 1. Contract → runtime object (Question 1)

### 1.1 The runtime objects

```text
BindingRecord     the IC-2 decision, computed and recorded:
                  { state: BOUND | UNBOUND | MISMATCH,
                    predecessor-weights-id (if present in R2 provenance),
                    declared-weights-id (from τ2★),
                    decision inputs }
ExecutionEnvelope the ε2 object as declared: { policy, limits, tool-availability }
                  — constructor-captured; readback-compared where the substrate
                  exposes configuration readback
SubstrateManifest { engine-id, weights-id (as bound), tokenizer-id } — what the
                  substrate says it is (recorded; fidelity-covenant class where
                  unverified)
PositionRecord    the derived decode position: { method: derived,
                  tokenizer-id, surface-length-units } (PD-6)
Instantiate Record (IR)   the birth certificate of S2 — the aggregate of everything
                  above plus: { CR_ref resolved, R2 digest, attached segment
                  provenance (E1.seg ids), verification results (VV-1..VV-7),
                  timestamp, actor }
```

The IR parallels the CR: **CR = the persist-time record of E1; IR = the instantiate-time record of S2.** The IR is the object the three-way mapping audits.

### 1.2 The mapping table (the centerpiece — full coverage required)

| Frozen clause | Runtime object / field / operation | Mechanical verification | Failure signature |
|---|---|---|---|
| IC-1 information completeness | surface handed to substrate as bytes; used-item identities recorded in IR | surface byte-faithfulness (VV-2); used-item pins re-verified at resolve (inherited V-2) | SURFACE-INFIDELITY / I-MISMATCH |
| IC-2 binding | BindingRecord | three-state decision computed from (R2 provenance, τ2★ declaration) | — (states, not failures: BOUND/UNBOUND/MISMATCH → taxonomy §4) |
| IC-3 envelope | ExecutionEnvelope captured at substrate configuration; readback where available | declared ≡ effective (byte/field equality) | ENVELOPE-DRIFT |
| IC-4 lineage | segment provenance (E1.seg ids) + A-chain bound into S2's execution context; IR references CR(R1) and parent chain | attachment completeness: every inherited id present in the context record | LINEAGE-ATTACH-FAIL |
| IC-5 position | PositionRecord: tokenize(R2.surface) under the bound tokenizer | derivation recorded; tokenizer-id ∈ SubstrateManifest | POSITION-DERIV-FAIL |
| IC-6 no-oracle | — realized by the *absence* of any semantic check in VV-1..VV-7; the mapping table is the audit | audit = mapping coverage itself | — |
| IC-7 efficiency (optional) | substrate.restore(carrier-state) → consumed-prefix metrics | metrics recorded in IR when the path is taken | RESTORE-FAIL (non-fatal — forfeits only the efficiency realization) |
| SC-1 surface integrity | VV-2 | byte equality | SURFACE-INFIDELITY |
| SC-2 substrate bound | BindingRecord (three-state) | IC-2 decision recorded | see §4 taxonomy |
| SC-3 envelope active | VV-4 | declared ≡ effective | ENVELOPE-DRIFT |
| SC-4 lineage attached | VV-6 | attachment completeness | LINEAGE-ATTACH-FAIL |
| SC-5 task declared | τ2 presence check (precondition) | τ2★ present and well-formed | TASK-MISSING |
| SC-6 position derivable | VV-5 | derivation succeeds under bound tokenizer | POSITION-DERIV-FAIL |

**Coverage rule**: an implementation claims I-1d compliance iff every row above has a realized object and a recorded check result in the IR. Missing rows, weakened checks, or renamed signatures = audit findings, by construction.

---

## 2. The instantiate boundary (Question 2 — where S2 is truly created)

The runtime pipeline, in canonical order:

```text
 0. precondition    R2 status = RESOLVED (clean)          — else REFUSE (precondition block;
                                                           RESOLVED-WITH-VIOLATIONS input
                                                           requires the external acceptance branch —
                                                           registered extension point, not defined here)
 1. bind            substrate.bind(weights-identity, ε2)  → BindingRecord
                    [MISMATCH → disposition per declared envelope policy, §4]
 2. restore (opt)   substrate.restore(carrier-state)      → consumed-prefix metrics   [IC-7]
 3. materialize     substrate.materialize(R2.surface)     → **CREATION POINT**
 4. attach          lineage/segment provenance bound into S2's execution context     [IC-4]
 5. record          IR written; verification surface VV-1..VV-7 executed
                    → Instantiate Verdict
```

**The creation point is step 3**: S2 comes into existence when the substrate accepts the continuation surface as its context — bind alone is a configured-but-empty substrate; materialize success is the substrate's acknowledgment that the continuation context is live. Failures at steps 0–2 are **CREATE-BLOCK** (no S2 exists; nothing to clean up beyond the substrate itself). Failures after step 3 are **POST-CREATION anomalies** — S2 exists but its record may be incomplete; the canonical disposition is conservative **re-instantiation** from the same RESOLVED R2 (idempotent — nothing semantic is consumed by instantiating), with the anomaly recorded.

Operation classes along the pipeline, per the Human's question: **bind** = configuration (steps 1); **materialize** = creation (step 3); **restore** = optional efficiency preload (step 2); **attach** = bookkeeping (step 4). Only materialize is existential.

---

## 3. Mechanical verification (Question 3 — the Verification Surface)

**VV-1..VV-7** (executed at step 5, recorded in the IR):

```text
VV-1  input precondition      R2 status = RESOLVED; R2 digest matches the resolve record
                              else PRECONDITION-FAIL
VV-2  surface faithfulness    the context handed to the substrate is byte-identical to
                              R2.surface — readback-verified where the substrate exposes
                              it; otherwise input-recorded under the substrate's fidelity
                              covenant (marked, never claimed as verified)
                              else SURFACE-INFIDELITY
VV-3  binding state           BindingRecord computed and recorded (BOUND/UNBOUND/MISMATCH)
                              else BINDING-UNDECIDED-UNRECORDED (an audit finding in itself)
VV-4  envelope equality       effective configuration ≡ declared ε2 (readback or
                              constructor-capture)                      else ENVELOPE-DRIFT
VV-5  position derivation     decode position derived under the bound tokenizer, recorded
                              else POSITION-DERIV-FAIL
VV-6  lineage attachment      every inherited identifier (A-chain, E1.seg ids) present
                              in S2's execution context record      else LINEAGE-ATTACH-FAIL
VV-7  substrate manifest      engine-id / weights-id / tokenizer-id recorded
                              else MANIFEST-INCOMPLETE
```

**No-oracle discipline (retained)**: every check is byte-equality, hash-equality, configuration-equality, or a recorded derivation. Nothing in VV asks whether R1 was correct, whether the information is right, or whether T2 should proceed. **What the Verification Surface does not cover** (registered boundary): the substrate's internal honesty beyond its interface (fidelity covenants marked, never claimed as verified), and behavioral continuity (C-CAP's post-execution jurisdiction).

---

## 4. Runtime failure taxonomy (Question 4)

| Failure / state | Stage | Runtime-visible | Disposition class |
|---|---|---|---|
| PRECONDITION-FAIL (R2 not RESOLVED) | 0 | yes — refuse before bind | **PRECONDITION-BLOCK** (upstream; resolve-side signatures carry: CR-ID-MISMATCH, I-NF, I-MISMATCH, A-SUB, A-CYCLE, P-VIOLATION, FORM-DRIFT) |
| TASK-MISSING (no τ2★) | 0 | yes | **PRECONDITION-BLOCK** (τ2 is external; instantiate never infers it) |
| BINDING = BOUND | 1 | yes — BindingRecord | **PROCEED** — lineage-strict claim available |
| BINDING = UNBOUND | 1 | yes — BindingRecord | **PROCEED-WITH-ANNOTATION** — continuable; lineage-strict status UNDECIDABLE (recorded, never inferred) |
| BINDING = MISMATCH | 1 | yes — BindingRecord | **DECLARED-ALTERNATIVE** — proceeds only as a declared cross-model continuation; blocks iff the envelope declares `lineage-strict: required` (disposition is envelope policy, mechanical) |
| carrier absent | 2 | yes — annotation | **PROCEED-WITH-ANNOTATION** — forfeits only the no-recompute carrier-form evidence; document-form trace provenance unaffected |
| RESTORE-FAIL | 2 | yes — non-fatal | **PROCEED-WITH-ANNOTATION** (same forfeit) |
| substrate bind/materialize error | 1/3 | yes — substrate error signature | **CREATE-BLOCK** — no S2 exists |
| SURFACE-INFIDELITY | 3/5 | yes — VV-2 | **CREATE-BLOCK** (SC-1/IC-1 broken; a fidelity-covenant substrate cannot hide this — the covenant covers only what it cannot see) |
| ENVELOPE-DRIFT | 5 | yes — VV-4 | **CREATE-BLOCK** where readback exists; where constructor-capture only, recorded as covenant class |
| POSITION-DERIV-FAIL | 5 | yes — VV-5 | **CREATE-BLOCK** (no silent fallback to a stored position — PD-6's alternative requires a revision, not a whim) |
| LINEAGE-ATTACH-FAIL | 4/5 | yes — VV-6 | **CREATE-BLOCK** (SC-4 broken; continuing without inherited provenance would silently break C-CAP(c)) |
| MANIFEST-INCOMPLETE | 5 | yes — VV-7 | **PROCEED-WITH-ANNOTATION** at most; audit finding regardless |
| IR write failure | 5 | yes — post-creation | **POST-CREATION-ANOMALY** — S2 exists but unverifiable; canonical disposition: conservative re-instantiation from the same RESOLVED R2, anomaly recorded |

Three disposition classes cover everything: **BLOCK** (no S2, or S2 that would break a frozen clause), **PROCEED-WITH-ANNOTATION** (continuable; claim strength degraded and recorded), **DECLARED-ALTERNATIVE** (policy-gated continuation under a declared different-binding). What is *forbidden* everywhere: silent degradation — every deviation is a recorded annotation or a block, never an unrecorded convenience.

---

## 5. The anti-drift guarantee, restated as a checkable property

An implementation **claims I-1d compliance** iff:

```text
(a) the IR exists for every instantiate attempt, with exactly the §1.1 fields;
(b) the verification results VV-1..VV-7 appear in the runtime trace;
(c) the mapping table (§1.2) is fully covered — no clause without an object+check;
(d) the failure taxonomy (§4) is honored — no failure class silently reclassified;
(e) the mapping table itself carries this design's freeze lineage.
```

Auditing an implementation = checking (a)–(e) against its trace. **This is the enforceable form of "the runtime realization has not silently changed the frozen instantiate semantics."** It converts a semantic worry into a field-presence check — the same move the whole program has made everywhere else (V-1 bounding, IR drop-test, grade accounting).

---

## 6. What this design does not do

No substrate/backend implementation or selection; no carrier choice (PALACE untouched — the interface in v0.3 §7 remains the only carrier surface, and restore stays optional); no storage-format binding for the IR (defined by fields, not by store); no experiment; no M-table or edge-vocabulary expansion; no new claim strength for UNBOUND/MISMATCH continuations (frozen v0.3 rules stand); no semantic judgment anywhere in the Verification Surface.

## 7. Open items for Human Review

1. **The creation-point ruling** — creation = materialize success (step 3); confirm or adjust.
2. **The IR field list** — accept as the freeze-candidate record shape.
3. **Fidelity covenants** for opaque substrates (VV-2/VV-4 covenant classes) — accept as marked trust boundaries, or require readback-capable substrates only.
4. **MISMATCH disposition default** (proceed as declared cross-model; block only if the envelope requires lineage-strict) — confirm.
5. **POST-CREATION-ANOMALY default** (conservative re-instantiation) — confirm.
6. **The three disposition classes** (BLOCK / PROCEED-WITH-ANNOTATION / DECLARED-ALTERNATIVE) — accept as the exhaustive policy vocabulary.

## 8. Non-claims

This design implements nothing, runs nothing, selects no carrier or backend, and does not claim any substrate is faithful beyond its recorded covenants; it does not claim structural continuity guarantees behavioral continuity (C-CAP's jurisdiction, unchanged); it does not expand the M-table, the edge vocabulary, or the frozen R2/CR contracts; it creates no new edge types (the IR is provenance-referenced, not a lineage node); it does not authorize implementation or experiments — the Implementation gate remains closed behind Human Review of this design and a subsequent ruling.
