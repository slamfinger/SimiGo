# IPAC Persistence / Resolve — Conceptual Design v0.2 (Gap I-1)

Date: 2026-10-05
Branch: `codex/execution-state-research-20260929`
Status: `REVISED DRAFT v0.2 · INCORPORATES THE HUMAN REVIEW VERDICT ON V0.1 · FREEZE NOT YET · IMPLEMENTATION BLOCKED UNTIL REVISION REVIEW · EXPERIMENT BLOCKED · PALACE SELECTION BLOCKED · PENDING HUMAN REVIEW`
Revision lineage (G-2 applied to this design): v0.1 (`6fd02ba`) → Human Review verdict (2026-10-05: conceptual direction ACCEPT; design REVISE; four core revisions + three reinforcements; PD-1..4 all retained) → v0.2 (this document).

---

## 0. What changed from v0.1 — and what did not

**Human Review verdict on v0.1 (registered):**

```text
Conceptual direction:   ACCEPT
Conceptual design:      REVISE
Freeze:                 NOT YET
Implementation:         BLOCKED until revision + Human Review
Experiment:             BLOCKED
PALACE selection:       BLOCKED
```

**Four core revisions (applied here):**

1. **CR identity ≠ R1 content identity** (§2.1–2.2, §4.1). Two executions may produce content-identical R1 with different continuation records; the resolve handle is therefore **CR_ref**, not R1_ref.
2. **A-chain downgraded to lineage-bearing** (§2.3). "State identity = the A-chain" is withdrawn; the internal tension with V-3 ("lineage integrity") is removed. Whether genuine State identity needs an additional irreducible structure is **left open** — deliberately not pre-closed, consistent with the no-minimality-claim discipline.
3. **No-recompute independently mechanized** (§5). "Consumed the resolve output" and "did not re-execute the predecessor computation" are now two separate checks; the latter is carried by **execution-trace predecessor provenance** (E1.seg references + no-equivalent-new-segment), with the carrier metric (cacheHitTokens) demoted to one instrument's implementation evidence.
4. **Resolve outcomes re-tiered** (§4.4): RESOLVED (clean capability success) is separated from RESOLVED-WITH-VIOLATIONS (degradation / conditional capability — never equal-status success); C-CAP requires clean RESOLVED.

**Three reinforcements (applied here):**

- **V-5 mechanized**: formation-baseline consistency is hash/field comparison over enumerated formation fields — no "consistent" loophole.
- **A-chain acyclicity/termination**: traversal carries a visited-set; a repeated CR-id raises **A-CYCLE** — recursive closure is mechanically guaranteed finite per resolution.
- **Edge vocabulary frozen**: `used / continues / surface` only. Sufficiency of the edges is left to next-stage evidence; the ontology is not expanded at concept stage.

**PD dispositions (all retained, none flipped):** PD-1 rendered bytes — retained (the most honest, least-assuming P-definition). PD-2 executor-at-terminal — retained, **with an explicit note: it is a trust boundary, not independent proof** (compensation remains use-time pinning + resolve-time re-verification). PD-3 Reference + Closure, not carrier clone — **strongly retained** (this is what keeps the design off the "KV = State" regression). PD-4 unused reads → provenance — retained, **stays provisional**: it depends on the role-axis hypothesis and must not be promoted to fact.

**Unchanged**: the scenario mapping; the no-oracle discipline; the storage-agnostic target (no PALACE commitment); the fail-visible philosophy; all citations at original boundings.

---

## 1. The design target

A finished execution **E1** (Task T1) has produced result **R1**. The design makes this scenario step well-defined:

```text
persist(R1 + provenance + relations)   ← the Persist model    (§2)
        ↓
resolve(CR)                            ← the Resolve model    (§3)
        ↓
S2 reconstructed, continuable
        ↓
T2 continues without re-executing T1   ← the Capability Criterion (§4)
```

without a semantic oracle (§3.5) and without naming a carrier (§0/v0.1).

---

## 2. The Persist model

### 2.1 The identity split (Revision 1) — R1 and CR are different objects

```text
R1  = Content Identity       the result as an information item in the IS
CR  = Continuation Record Identity   the record of ONE continuation attempt
```

Two different executions may produce **content-identical R1** while their continuation records differ irreducibly:

```text
CR-a:  result → R1;  used = {F1@v1, F2@v2};  surface = P-a;  continues = CR-parent(S0)
CR-b:  result → R1;  used = {F3@v1, F4@v3};  surface = P-b;  continues = CR-parent(S7)
```

Content identity can coincide; **continuation identity cannot be derived from content identity**. Therefore:

```text
CR internal structure:
  CR
   ├─ result    → R1 (content identity)
   ├─ used      → I1@v1, I2@v2, … (use-time pinned content identities)
   ├─ surface   → P (rendered continuation surface, bytes)
   └─ continues → CR-parent (recursion; acyclicity enforced, §3.4)
```

**CR identity = the content-identity of the record itself**: the hash over its identity-bearing fields — (result-ref, used-set with pinned versions [canonical order], surface bytes, parent CR-ref). **Provenance annotations are excluded from the identity hash** — this is the drop test's second use: the identity-bearing fields are exactly what the hash covers. Two CRs differing in any identity-bearing field are different CRs even with identical R1.

**The resolve handle is `CR_ref`.** Holding only R1_ref yields a content hit plus a *selection problem* (possibly many CRs with result → R1_ref) — selection/discovery is upstream, on the I→I edge (unchanged scoping from v0.1). The pair (R1_ref, CR_ref) may be used as a redundant human-readable handle; CR_ref alone is sufficient and primary.

### 2.2 The record classes and the drop test

Record classes (candidate IPAC vocabulary — boundings carried: OPEN / NONBINDING / minimality UNPROVEN / semantics NOT FROZEN):

```text
result   → R1 as a first-class IS item (content-addressed)
used     → the items E1 actually USED, pinned at use time
surface  → the rendered continuation surface (bytes)
continues→ the lineage recursion
```

The tripartition is mechanical (the drop test), now stated at the corrected granularity:

```text
a field is continuation-identity-bearing
     if dropping it breaks same-continuation-record verification (V-3 / V-4)
  continuation-bearing
     if dropping it breaks the ability to continue at all
  provenance
     otherwise (audit-bearing, not continuation-bearing; outside the identity hash)
```

### 2.3 Role mapping (Revision 2 — A-chain downgraded)

```text
A-chain        → lineage-bearing   (lineage identity / lineage continuity)
P + used-I     → continuation-bearing
CR reference   → continuation-record identity
R1             → content identity
```

The v0.1 claim "State identity = the A-chain" is **withdrawn**: what the A-chain verifiably carries is *lineage* identity and lineage continuity — which is exactly what V-3 tests. Whether genuine **State identity** requires an additional, irreducible structure beyond these four roles is **an open question, deliberately not pre-closed**. The design proceeds with continuation-record identity as its operative notion and registers the State-identity question for future evidence.

Provenance = formation annotations attached to every record (task, trajectory, actor, backend, time, tool), outside the identity hash, mandatory for audit (V-1 discipline), never continuation-bearing.

### 2.4 Writer, target, edges (retained from v0.1, with verdict notes)

- **Writer**: executor-at-terminal (PD-2, retained) — with the review's note made binding: *this is a trust boundary, not independent proof*; the compensations are use-time identity pinning and resolve-time re-verification. Harness-side writing remains the registered alternative.
- **Target**: storage-agnostic — content-addressed nodes + typed edges + provenance annotations. No carrier named.
- **Edges — frozen at three** (reinforcement): `used`, `continues`, `surface`. No additional IPAC edge kinds are introduced at concept stage; whether these suffice is answered by next-stage evidence, not by ontology growth. `produced` remains implicit in node creation.
- **PD-4** (unused reads → provenance annotations): retained, **provisional by charter** — it depends on the role-axis hypothesis and is not to be promoted to fact by usage.

---

## 3. The Resolve model

### 3.1 Input — a CR reference

`resolve(CR_ref)`. Not `resolve(R1_ref)` (§2.1: R1_ref under-determines the continuation). Resolve does not take narratives; reference *acquisition* remains upstream (I→I edge).

### 3.2 Traversal

Closure traversal over the CR's edges: `used` → re-materialize pinned inputs; `continues` → walk the lineage chain (with cycle guard, §3.4); `surface` → retrieve the rendered continuation surface.

### 3.3 Reconstruction level

Rendered-reference level (PD-3, strongly retained): S2 = assembled (rendered surface + re-materialized used items at pinned versions + lineage context). Not carrier-state cloning — the T3 line's examined-and-closed territory.

### 3.4 Verification suite (mechanical only; reinforced)

```text
V-1  referability        every edge target resolves at its pinned identity
                         else C-REF-NOT-FOUND / I-NF
V-2  content match       re-materialized items hash-match pinned versions
                         else I-MISMATCH
V-3  lineage integrity   A-chain unbroken, link-wise hash-consistent,
                         AND acyclic/finite: traversal carries a visited-set;
                         a repeated CR-id raises A-CYCLE
                         else A-SUB / A-NF / A-CYCLE
V-4  surface integrity   rendered surface byte-identical to the recorded one
                         else P-VIOLATION
V-5  formation baseline  hash/field comparison over the ENUMERATED formation
                         fields (formation-procedure identity, formation-input
                         identities, recorded setup baseline) — byte/hash equality
                         only; anything not hash-comparable is not part of V-5
                         else FORM-DRIFT
```

V-5's mechanization closes the v0.1 loophole: "consistent" is now field-wise hash equality over a fixed field list (the list is pinned at freeze), never a semantic review.

**Output — three tiers, re-defined (Revision 4):**

```text
RESOLVED                    V-1..V-5 all pass.
                            = clean capability success.

RESOLVED-WITH-VIOLATIONS    specific violations, mechanically signed.
                            = degradation / conditional capability: mechanically
                            surfaced, continuation policy external. NEVER equal-
                            status success; any continuation under it is
                            conditional/degraded and is a separate capability
                            branch to be defined later.

UNRESOLVABLE                the record cannot be traversed.
                            = capability failure.
```

Resolve remains fail-visible: it reports mechanically; policy under violations is external and later.

### 3.5 No-oracle discipline (unchanged)

Resolve judges exactly: resolvability, content-identity, lineage integrity (including acyclicity), surface integrity, formation-field hash equality. Resolve does not judge: whether R1 is correct, whether the used information is "the right" information, whether T2 should proceed.

---

## 4. Capability criterion (restructured — Revision 3)

The v0.1 criterion conflated two checks. Separated:

```text
C-CAP (abstract):
  a later execution E2, given the CR reference:
  (a) RESOLVES the record — clean RESOLVED (V-1..V-5);
  (b) CONTINUES T2's work from the reconstructed surface;
  (c) DOES NOT RE-EXECUTE T1's work — verified independently of (a),
      at the execution-trace level:
        T1's execution is recorded as segments E1.seg[0..k];
        E2's execution trace REFERENCES E1.seg[0..k]
        (predecessor-execution provenance)
        and contains NO NEW execution segment equivalent
        to the referenced ones.

Instrumentations (implementations of (c), not the definition):
  document-form:  trace-level segment provenance per the above.
  carrier-form:   restore metrics show consumed prefix (cacheHitTokens > 0)
                  — ONE instrument's evidence; it no longer carries the
                  no-recompute definition alone.

Consumption ≠ non-re-execution:
  "E2's consumed input contains the resolve output" (necessary)
  is a DIFFERENT check from
  "E2's trace contains no re-execution of referenced segments" (required).
  E2 may read R1 and still re-run T1; only the trace check sees that.
```

**Mechanical definition of segment equivalence, and its honest boundary**: two segments are equivalent-for-recompute-detection iff their (operation class, input content-identity, parameter hash, output content-identity) match — hash-level, no semantics. Boundary, registered: a *semantically* equivalent re-derivation that differs mechanically (different wording, different tool, reordered steps) is **not caught** by this criterion. That is a detection boundary of the no-oracle stance, not an oversight; it is recorded so the criterion's coverage is never overstated. (Open item E-SEG: refine segment granularity/equivalence as trace protocols mature.)

This is the pre-registered judgment basis for any following Design/Implementation/Experiment — stated before any carrier exists.

---

## 5. Scenario mapping (unchanged in structure, handles corrected)

| Design element | Scenario problem it solves |
|---|---|
| CR (node + identity-bearing fields + edges) | the "IS 新增 R1 + provenance + relations" step, with a **unique continuation handle** |
| `used` edges with use-time pinning | F1..F4 load-bearing vs merely read |
| P-surface | what T2 continues from |
| A-chain (lineage-bearing) | verifiable lineage continuity from S1 to S2 |
| verification suite (incl. A-CYCLE, mechanized V-5) | resolve checkable without an oracle |
| C-CAP with trace-provenance | the "增量计算" arrow, now mechanically checkable |

Locality axis stays set aside. The scenario's informal "resolve R1" is now precisely `resolve(CR(R1))`.

## 6. I-1c interface sketch (unchanged, shallow by design)

Persisted relations = verification layer; carrier restore = position layer; coupling = the restore is selected and verified against the CR, with consumed-prefix metrics as one instrumentation of C-CAP(c). Designed fully only after Human Review.

## 7. Open items (updated)

1. **E-SEG**: segment-granularity and equivalence definition for the trace-level no-recompute check (mechanical; boundary registered §4).
2. **State identity**: whether an irreducible structure beyond lineage/continuation/content roles is required — open by design (Revision 2), not to be closed without evidence.
3. **Edge-vocabulary sufficiency**: answered by next-stage evidence, not by concept-stage expansion.
4. PD-1..PD-4: retained; PD-2's trust-boundary note and PD-4's provisional charter are binding annotations.
5. Freeze decision: after Human Review of this revision. Implementation, experiment, and PALACE selection remain BLOCKED until then.

## 8. Non-claims

No minimality claim (IPAC boundings carried); no implementation; no carrier commitment; no experiment; no claim that RESOLVED-WITH-VIOLATIONS continuations carry full capability; no claim that the no-recompute criterion catches semantic re-derivation (boundary registered, §4); no retroactive re-grading of v0.1 — its conflation of CR and R1 identity is recorded as the reviewed defect this revision fixes, at v0.1's own identity.
