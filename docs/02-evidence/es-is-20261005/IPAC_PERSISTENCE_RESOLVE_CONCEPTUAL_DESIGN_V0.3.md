# IPAC Persistence / Resolve — Conceptual Design v0.3 (Gap I-1)

Date: 2026-10-05
Branch: `codex/execution-state-research-20260929`
Status: `REVISED DRAFT v0.3 · INCORPORATES THE PRE-FREEZE REVIEW (ONE CONCEPTUAL GAP + TWO TIGHTENINGS) · READY FOR HUMAN REVIEW → FREEZE DECISION · IMPLEMENTATION / EXPERIMENT / PALACE REMAIN BLOCKED`
Revision lineage: v0.1 (`6fd02ba`) → review (direction ACCEPT, design REVISE) → v0.2 (`36b2f08`, four core revisions + three reinforcements) → review (revisions confirmed **closed**; reinforcements confirmed; **one conceptual gap + two tightenings before freeze**) → v0.3 (this document).

---

## 0. What changed from v0.2 — and what did not

**Human review of v0.2 (registered):** the four core revisions are **closed** (CR/R1 identity split; A-chain downgraded to lineage-bearing with the State-identity question left open; no-recompute independently mechanized with the semantic-equivalence coverage boundary registered; resolve outcomes re-tiered as a genuine capability hierarchy). The three reinforcements stand (A-CYCLE; V-5 hash-field mechanization; edge vocabulary frozen at three — *do not add edges to answer "enough"; let next-stage evidence force it*).

**Changed in v0.3 — the one conceptual gap:**

- **§3.3 rebuilt as a three-level object relation.** The resolve product is no longer called a reconstructed Execution State. It is the **Continuation Basis (R2 / Resolve Output)** — and **S2 = instantiate(R2, τ2)** is a separate step producing the actual execution object. The v0.2 formula "S2 = rendered surface + used items + lineage context" is withdrawn as an identity claim: that object is a *continuation reconstruction basis*, and whether a true Execution State contains components not recoverable from it has **not been proven omissible** in this design. Claiming otherwise would be a smuggled substitution (Information Space → continuation-ready representation → *declared* Execution State). The new chain:

```text
CR
 ↓ resolve
Continuation Basis (R2 / Resolve Output)
 ↓ instantiate (+ externally supplied task specification τ2)
Execution State (S2)
 ↓ execute T2
New Result / Trajectory
 ↓ persist (CR′)
Information Space
 ↺
```

  Ground: the Core line's own ES/carrier distinction (P5 attempt-1: KV = representation fragment; P6: Reference / Closure / Carrier). Refusing carrier cloning must not become declaring the rendered reference to be the full State. **What `instantiate` must supply beyond R2 — carrier-side state, τ2 binding, engine mechanics — is exactly I-1c's design space, and this design does not claim R2 alone suffices.**

**Two tightenings:**

- **§4, C-CAP: the T2 input boundary.** T2's task specification (τ2) is an **externally supplied execution input**. Resolve does not discover, infer, or endorse T2 — *resolve rebuilds the past; the task declares the future*. Without this boundary, "continue T2" would smuggle task semantics back into resolve (the oracle re-enters through the back door).
- **§2.1, canonical order**: stated as a **deterministic serialization order defined mechanically from the pinned content-identity byte strings** (e.g., lexicographic over identity bytes), pinned at freeze — a serialization convention, not a semantic judgment and not a hidden implementation freedom.

**Unchanged from v0.2 (review-confirmed closed/standing):** the CR/R1 identity split and the resolve handle `CR_ref`; the drop test; the A-chain as lineage-bearing with the State-identity question open; the trace-provenance no-recompute criterion with its registered coverage boundary; the three-tier resolve outcomes; V-1..V-5 with A-CYCLE and the mechanized V-5; the frozen three-edge vocabulary; PD-1..4 with binding notes; the storage-agnostic target and no-PALACE commitment; all boundings.

---

## 1. The design target

A finished execution **E1** (Task T1) has produced result **R1**. The design makes this chain well-defined:

```text
Information Space
      ↓ resolve(CR)
Continuation Basis (R2 / Resolve Output)
      ↓ instantiate (+ externally supplied τ2)
Execution State (S2)
      ↓ execute T2
New Result / Trajectory
      ↓ persist (CR′)
Information Space
      ↺
```

This is closer to the actual claim than the earlier "CR → S2" picture: **not "store an IPAC object", but "the Information Space can re-supply enough structure for a new Execution State to be restored continuously — and then produce genuinely incremental execution."**

---

## 2. The Persist model

### 2.1 The identity split (retained) — R1 and CR are different objects

```text
R1  = Content Identity                the result as an information item in the IS
CR  = Continuation Record Identity    the record of ONE continuation attempt
```

Content-identical R1 does not determine the continuation: two executions may emit content-identical R1 with different `used` sets, different surfaces, different parents. The CR:

```text
CR
 ├─ result    → R1 (content identity)
 ├─ used      → I1@v1, I2@v2, … (use-time pinned content identities)
 ├─ surface   → P (rendered continuation surface, bytes)
 └─ continues → CR-parent (recursion; acyclicity enforced — A-CYCLE)
```

**CR identity = the hash over its identity-bearing fields** — (result-ref, used-set with pinned versions in **canonical order**, surface bytes, parent CR-ref). **Canonical order = deterministic serialization order defined mechanically from the pinned content-identity byte strings** (e.g., lexicographic over identity bytes), pinned at freeze — a serialization convention, never a semantic judgment. **Provenance annotations sit outside the identity hash**: the drop test's second use — the identity-bearing fields are exactly what the hash covers.

**The resolve handle is `CR_ref`.** R1_ref alone yields a content hit plus a selection problem (upstream, I→I edge). (R1_ref, CR_ref) may serve as a redundant readable handle.

### 2.2 Record classes and the drop test (retained)

```text
result / used / surface / continues   — candidate IPAC vocabulary
(boundings carried: OPEN / NONBINDING / minimality UNPROVEN / semantics NOT FROZEN)
```

Tripartition by the drop test:

```text
continuation-identity-bearing   dropping it breaks same-continuation-record
                                verification (V-3 / V-4)
continuation-bearing            dropping it breaks the ability to continue at all
provenance                      otherwise (audit-bearing; outside the identity hash)
```

### 2.3 Role mapping (retained, v0.2 granularity)

```text
A-chain        → lineage-bearing
P + used-I     → continuation-bearing
CR reference   → continuation-record identity
R1             → content identity
```

State identity — whether it requires an additional irreducible structure — **remains open** (now additionally sharpened by the R2/S2 split: it may in part live in the instantiate step; see §3.3).

### 2.4 Writer, target, edges (retained with binding notes)

Executor-at-terminal (PD-2 — **a trust boundary, not independent proof**; compensated by use-time pinning + resolve-time re-verification). Storage-agnostic target (content-addressed nodes + typed edges + provenance). **Edges frozen at three** (`used / continues / surface`). PD-4 (unused reads → provenance) provisional by charter.

---

## 3. The Resolve model — now explicitly two-level

### 3.1 Input

`resolve(CR_ref)`. Reference acquisition upstream (I→I edge).

### 3.2 Traversal

Closure traversal over the CR's edges, with the visited-set cycle guard.

### 3.3 The Resolve Output — **R2, the Continuation Basis** (the conceptual-gap fix)

The product of resolve is:

```text
R2  = rendered continuation surface
    + re-materialized used items at pinned versions
    + lineage context
```

**R2 is NOT an Execution State.** It is the **continuation reconstruction basis** — the information-side object carrying everything the Information Space can supply. The v0.2 wording that called this assembled object "S2" is withdrawn: whether a true Execution State contains components **not recoverable from R2** (carrier-side state, engine mechanics, the task binding) has not been proven omissible here, and this design does not claim it. That honesty is the whole point of the split: refusing carrier cloning (PD-3) must not curdle into declaring the rendered reference to be the complete State.

### 3.4 Verification suite (retained; produces the R2 verdict)

```text
V-1 referability / V-2 content match / V-3 lineage integrity (incl. A-CYCLE) /
V-4 surface integrity / V-5 formation-baseline hash equality (enumerated fields)
```

Three-tier output: **RESOLVED** (clean — V-1..V-5 pass, R2 produced) / **RESOLVED-WITH-VIOLATIONS** (degradation / conditional; mechanically signed; policy external) / **UNRESOLVABLE** (capability failure). Fail-visible; no semantic judgment inside resolve.

### 3.5 The instantiate boundary — where Execution State begins

```text
S2 = instantiate(R2, τ2)
```

- **R2** = the Continuation Basis (resolve's product; information-side).
- **τ2** = the externally supplied T2 task specification (an execution input — §4).
- **instantiate** = the step that turns the basis into an actual, continuable execution object — the step at which a carrier/engine legitimately enters (position layer mechanics, consumed-prefix metrics), and the step whose completeness requirements are **I-1c's design space**: what must be added beyond R2 for S2 to be a true Execution State is a design question, not an assumption.

The ES/carrier distinction is thereby preserved end-to-end: persistence targets the Reference + Closure layers (PD-3); instantiation is where Carrier mechanics appear; and no step is allowed to declare the previous layer's output to be the next layer's object.

### 3.6 No-oracle discipline (unchanged)

Resolve judges: resolvability, content-identity, lineage integrity (incl. acyclicity), surface integrity, formation-field hash equality. It does not judge correctness, rightness of information, or what T2 should be.

---

## 4. Capability criterion (with the T2 input boundary)

```text
C-CAP (abstract):
  a later execution E2, given the CR reference and the externally
  supplied task specification τ2:
  (a) RESOLVES the record — clean RESOLVED, producing R2 (V-1..V-5);
  (b) INSTANTIATES S2 from R2 (+ τ2) and CONTINUES the externally
      specified T2's work from S2;
  (c) DOES NOT RE-EXECUTE T1's work — independently verified at the
      execution-trace level: E2's trace references E1.seg[0..k]
      (predecessor-execution provenance) and contains no new
      segment equivalent to the referenced ones (hash-level segment
      equivalence; the semantic-equivalence escape is a registered
      coverage boundary).

Instrumentations of (c): document-form trace provenance; carrier-form
consumed-prefix metrics (cacheHitTokens > 0) — implementations, not the definition.

**T2 input boundary (new, binding):** the T2 task specification τ2 is an
externally supplied execution input. **Resolve does not discover, infer,
or endorse T2.** Resolve rebuilds the past; the task declares the future.
Without τ2, R2 is a basis with no declared continuation — and inferring
"what to continue" from R2's content would reintroduce the semantic oracle.
```

NOT sufficient: the CR is written; IPAC relations serialized; R1 retrievable; even R2 produced. The criterion is the chain (a)+(b)+(c).

---

## 5. Scenario mapping (handles and layers corrected)

| Design element | Scenario problem it solves |
|---|---|
| CR + identity hash (canonical serialization) | the persist step, with a unique continuation handle |
| `used` edges, use-time pinning | F1..F4 load-bearing vs merely read |
| P-surface | the resume mechanic's information-side content |
| A-chain (lineage-bearing) | verifiable lineage continuity S1 → basis → S2 |
| R2 / instantiate split | the honest boundary between what IS supplies and what the execution object requires |
| τ2 externality | who declares the future (the task, not resolve) |
| verification suite + C-CAP(c) | mechanical checkability of "resolved" and "incremental" |

---

## 6. I-1c interface (updated to the three-level chain)

```text
I→S:   CR → resolve → R2 (Continuation Basis)
          ↓ instantiate(R2, τ2)          ← carrier/engine enters here
        Execution State S2
S→S:   T2 continuation (trace provenance per C-CAP(c))
```

The full `instantiate` design — what must be supplied beyond R2, with what carrier, verified how — **is I-1c's design space**, to be opened only after Human Review of this document.

## 7. Open items (updated)

1. **Instantiate-completeness** (new, the sharpened form of the State-identity question): what `instantiate` must supply beyond R2 for S2 to be a true Execution State — I-1c's design space; not assumed away here.
2. **E-SEG**: segment granularity/equivalence for the trace-level no-recompute check.
3. **State identity**: open by design (may partly live in the instantiate step).
4. **Edge-vocabulary sufficiency**: left to next-stage evidence.
5. PD-1..PD-4: retained with binding notes.
6. **Freeze decision**: this document is submitted for it; Implementation / Experiment / PALACE remain BLOCKED until the freeze ruling and subsequent gates.

## 8. Non-claims

No minimality claim; no implementation; no carrier commitment; no experiment; no claim that R2 is a complete Execution State (the instantiate gap is registered, not assumed away); no claim that the no-recompute criterion catches semantic re-derivation; no retroactive re-grading — v0.2's "S2" wording is recorded as the reviewed defect this revision fixes, at v0.2's own identity.
