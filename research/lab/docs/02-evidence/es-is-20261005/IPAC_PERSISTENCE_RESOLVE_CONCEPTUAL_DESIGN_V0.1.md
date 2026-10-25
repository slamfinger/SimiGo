# IPAC Persistence / Resolve — Conceptual Design v0.1 (Gap I-1)

Date: 2026-10-05
Branch: `codex/execution-state-research-20260929`
Status: `CONCEPTUAL DESIGN · GAP I-1 SELECTED (HUMAN RULING) · NO IMPLEMENTATION · NO EXPERIMENT · NO PALACE COMMITMENT · PENDING HUMAN REVIEW`
Directive: Human ruling 2026-10-05 — Gap I-1 selected as next Core work (Stage Synthesis `33844d5`, Addendum). Sequence fixed: **this design → Human Review → then decide Design / Implementation / Experiment.** First deliverable answers: *if IPAC is the candidate relational closure of State↔Information, what relations must a finished Execution State persist into the Information Space, and how are they re-parsed into a continuable State?*
Location: `docs/02-evidence/es-is-20261005/` (Core line directory)

Session header (Constitution Article 6):

```text
Core target:               I-1 — the closure loop run end-to-end (persist → resolve → continue)
Affected closure edge:     I→S primary (resolve/persist as information→state mechanics); S→I (the write);
                           S→S interface (coupling sketch only)
Real system object:        the Continuation Record — a CANDIDATE object; no runtime artifact exists
                           by design, and none may be built before Human Review
Expected capability delta: C-CAP (§5) — a later execution re-parses a continuable state from IS
                           and avoids recomputing prior work
Stop condition:            if the persist/resolve models cannot be stated without a semantic oracle,
                           or cannot be stated without naming a carrier, stop and downgrade (Gate 2)
```

---

## 0. Scope — what this design is and is not

**Is**: the conceptual design of the two missing mechanics of the closure loop — the **Persist model** (what a finished execution writes) and the **Resolve model** (how a later execution reconstructs a continuable state from what was written) — plus the stage **Capability Criterion**. It is the I-1a + I-1b design; I-1c (coupled continuation) is sketched at interface level only (§7).

**Is not**: an implementation; an experiment; a PALACE design (carrier choice is explicitly deferred — relation semantics → persistence model → resolve model → capability criterion **first**, carrier after; anti "carrier-first", per the E16 lesson that theory must not be dragged by its carrier); a minimality proof (IPAC's boundings carry: OPEN / NONBINDING / minimality UNPROVEN / semantics NOT FROZEN — the record classes below are **candidate vocabulary**); a semantic-correctness theory (§4.6).

**Inputs from the sealed lineage** (each at its registered bounding; the identity rule in force — these results were produced in other lines and are cited, not re-titled):

- **P6** (ES = minimal relation closure preserving computational continuity; layers Reference / Closure / Carrier): the persistence target is the **Reference + Closure layers made durable** — the Carrier layer is deliberately *not* the persistence target (PD-3).
- **P5-4 + PA-2** ({I,P,A,C} independently necessary; Position ≠ Semantic Anchor — output follows rendered prompt text): the position record must be persisted in **rendered form**, not as an abstract coordinate.
- **R-C1** (O1: runtime state alone insufficient; persistent Information + a persisted Relation actually used — task-domain-bounded): relation edges between information items are load-bearing, not just items.
- **R3** (differential sensitivity; referenced-mutation vs unreferenced-mutation asymmetry; mechanical detection signatures A-SUB / I-MISMATCH / I-NF / C-REF-NOT-FOUND; no semantic oracle — parsing success ≠ lineage correctness): use-time identity pinning and the verification suite below institutionalize the sealed detection machinery.
- **E16 / Palace F-8** (storage ≠ retrieval): resolve must be task-structural, and the carrier must not precede the semantics.

---

## 1. The design target

A finished execution **E1** (Task T1) has produced result **R1**. The design must make the following scenario step well-defined:

```text
persist(R1 + provenance + relations)   ← the Persist model   (§3)
        ↓
resolve(R1)                            ← the Resolve model   (§4)
        ↓
S2 reconstructed, continuable
        ↓
T2 continues without recomputing T1    ← the Capability Criterion (§5)
```

And it must do so **without a semantic oracle** (§4.6) and **without naming a carrier** (§0).

---

## 2. The Persist model

### 2.1 The persisted object: the Continuation Record (CR)

What E1 writes is not "the result" but a **Continuation Record** — the persist-time instantiation of the relation closure: a new IS node (the R1 item) plus relation edges, all content-identity-addressed. Four record classes, mapped to the candidate IPAC vocabulary:

```text
C-record (Content)      R1 itself as a first-class information item,
                        with content identity (hash / content-address)
I-records (Information) the items E1 actually USED — F1..F4 as referenced,
                        each pinned to the target's content identity AT USE TIME
P-record (Position)     the rendered continuation surface — the exact context
                        form from which the next execution continues (bytes)
A-records (Anchors)     the lineage chain: S1's identity, S1's own formation
                        record (recursion into earlier CRs), trajectory
                        reference structure
```

### 2.2 保存什么 — the tripartition, and the drop test

The Human checklist asks: which records are **State identity**, which **continuation anchors**, which **just provenance**? The design answers with a mechanical test rather than a list:

```text
the DROP TEST:
  a field is identity-bearing  if dropping it breaks "same continuation"
                               verification (V-3 / V-4 below)
  anchor-bearing               if dropping it breaks the ability to continue at all
  provenance                   otherwise (audit-bearing, not continuation-bearing)
```

Applied:

- **State identity = the A-chain.** What makes the reconstructed S2 *the* continuation of S1 (and not a similar state) is the resolvable, hash-consistent lineage of content-identities — identity by reference-resolution, never by content similarity (the P4 threat model).
- **Continuation anchor = the P-surface + the I-records.** Per PA-2, continuation is anchored in the rendered form; per R-C1, in the used information at pinned versions.
- **Provenance = formation annotations** attached to every record (task, trajectory, actor, backend, time, tool). Test: could continuation succeed without them? Yes → provenance. (They remain mandatory for audit and bounding — V-1 discipline — just not continuation-bearing.)

### 2.3 由谁写 — the writer

**Executor-at-terminal** (PD-2): the same process that ran E1 writes its own CR as part of task completion. Ground: only the executor knows **used-vs-merely-present** at use time — and R3 showed that use-claims made post hoc are exactly where silent substitution hides. Two compensating disciplines: (a) use-claims are recorded **with content identities at use time** (not as post-hoc narrative); (b) resolve re-verifies them mechanically (§4). Registered alternative: a second-party writer (harness-side recording — stronger independence, later design).

### 2.4 写入哪个信息实体 — storage-agnostic target

The CR is written as a **new node in the Information Space plus edges** — over an abstract model of (content-addressed nodes, typed edges, provenance annotations). Any store that can hold these qualifies. **No carrier is named** (§0); PALACE is a candidate to be evaluated only after Human Review of this design.

### 2.5 关系如何表达 — the edge vocabulary

```text
used       C-record → I-item at content-identity v(use time)     [I-records]
continues  C-record → prior CR / lineage pointer                  [A-records]
surface    C-record → rendered continuation surface (bytes)       [P-record]
produced   implicit in node creation (R1 enters the IS)           [C-record]
```

Every edge carries: source content-identity, target content-identity (pinned at use time), edge type, provenance annotations. **Use-time pinning is the institutionalized form of R3's finding**: it is what makes a later IS mutation detectable as I-MISMATCH instead of silently absorbed, and what makes unreferenced-mutation safety (the HOLD side) a checkable property rather than a hope.

Design decision **PD-4** (unused reads): items read but not used are recorded — if at all — as provenance annotations, **not** as `used` edges. Ground: the role-axis hypothesis (carried, hypothesis-level) predicts unreferenced items are continuation-irrelevant; recording them as load-bearing would blur the partition this line exists to draw.

### 2.6 Design decisions registered (with alternatives — the D-1 pattern)

```text
PD-1  position persistence:  persist the rendered surface AS BYTES (chosen;
                             conservative, PA-2-grounded)  vs  re-render from
                             structured records (requires a deterministic rendering
                             spec — a larger commitment; registered alternative)
PD-2  writer:                executor-at-terminal (chosen, §2.3)  vs  harness-writes
                             (stronger independence; registered alternative)
PD-3  persistence target:    Reference + Closure layers (chosen)  vs  carrier-state
                             cloning (registered alternative — the T3 line's examined-
                             and-closed territory: no durable third carrier form; KV =
                             representation fragment)
PD-4  unused reads:          provenance annotations only (chosen; role-axis caveat)  vs
                             full read-logging
```

---

## 3. The Resolve model

### 3.1 输入是什么 — an identity reference, not a description

Resolve takes a **resolvable reference to the R1 item** (content-identity / address). It does not take a narrative ("the analysis about X"). Two consequences: (a) resolve can never be asked to *find* the right information — that would be the semantic oracle; (b) **reference acquisition is upstream** — how Task T2 comes to hold R1's reference is a discovery/indexing question (the I→I edge, registered as unmechanized in the Synthesis), out of scope here.

### 3.2 查询哪些关系 — closure traversal

From the R1 node, resolve traverses the CR's edges: `used` (to re-materialize the pinned inputs), `continues` (to walk the lineage chain), `surface` (to retrieve the rendered continuation surface). Resolve = **closure traversal over the record's edges** — nothing more.

### 3.3 如何重建 State — rendered-reference level (PD-3)

S2 = the assembled **(rendered continuation surface + re-materialized used items at pinned versions + lineage context)**. Reconstruction is at the **rendered-reference level**, deliberately *not* carrier-state cloning: the ES line established that the carrier (KV) is a representation fragment, not an independent durable carrier (P5 attempt-1; T3 closed). The persisted relations define what must hold; the new execution continues from the reconstructed surface by its own computation.

### 3.4 如何确认"同一个 continuation" — the verification suite (mechanical only)

```text
V-1  referability       every edge target resolves at its pinned identity
                        else C-REF-NOT-FOUND / I-NF
V-2  content match      re-materialized items hash-match their pinned versions
                        else I-MISMATCH
V-3  lineage integrity  A-chain unbroken and link-wise hash-consistent
                        else A-SUB / A-NF
V-4  surface integrity  rendered surface byte-identical to the recorded one
                        else P-VIOLATION
V-5  formation baseline the record's own formation record is consistent
                        else K-0-style drift
```

The failure signatures are deliberately the R3 machinery's — the sealed detection work becomes the resolve-time instrument.

**Output — three states, fail-visible:**

```text
RESOLVED                    V-1..V-5 pass → the reconstruction is lineage-identical
                            to the record
RESOLVED-WITH-VIOLATIONS    specific violations, mechanically signed (which edges,
                            which identities)
UNRESOLVABLE                the record cannot be traversed
```

Resolve is **fail-visible**: it reports state mechanically. The *policy* under violations (proceed / repair / escalate) is a separate later decision — not resolve's, and not a semantic judgment made inside resolve.

### 3.5 如何避免 semantic oracle — the discipline

Resolve judges exactly four things: resolvability, content-identity, lineage integrity, surface integrity. Resolve does **not** judge: whether R1 is *correct*, whether the used information is *the right* information, whether T2 *should* proceed. Those belong to the continuing execution and, where applicable, to the Human. This is the R3 boundary carried into design: **evaluability is not semantic correctness; a passed verification means "lineage-identical to the record", never "semantically right."**

---

## 4. Capability criterion (the stage criterion — Human wording, formalized)

> **"不是'能保存 IPAC'，而是'未来能从 Information Space 中重新解析出可继续的 Execution State，并避免重复前序计算'。"**

```text
C-CAP:  the design is successful iff, for a finished E1 with its CR written:
  (a) a later execution E2, given only the reference to R1, RESOLVES the record
      (V-1..V-5 passing, or violations mechanically reported and explicitly accepted);
  (b) E2 CONTINUES T2's work from the reconstructed surface;
  (c) E2 DOES NOT RECOMPUTE T1's work — checked mechanically per form:
      document-form: E2's consumed input contains the resolve output (R1 + pinned
      items), not a re-derivation of them;
      carrier-form: restore metrics show consumed prefix (cacheHitTokens > 0 —
      the P7 metric, reused).
NOT sufficient: the CR is written and stored; IPAC relations are serialized;
R1 is retrievable. Saving is not the criterion.
```

This is the pre-registered judgment basis for whatever Design/Implementation/Experiment follows Human Review — stated now, before any carrier exists.

---

## 5. Scenario mapping (every element answers a scenario problem)

| Design element | Scenario problem it solves |
|---|---|
| CR (node + edges) | the "IS 新增 R1 + provenance + relations" step, made well-defined |
| `used` edges with use-time pinning | what makes F1..F4 load-bearing vs merely read (the read/used distinction) |
| P-surface | what T2 continues from (the resume mechanic, PA-2-honest) |
| A-chain | what makes S2 *the continuation of S1*, not a similar state |
| verification suite | what makes "resolve succeeded" checkable without an oracle |
| C-CAP | the "增量计算" arrow, made pre-registerable |

The locality axis stays set aside (Core Reference Scenario disposition); this design does not reintroduce it.

---

## 6. I-1c interface sketch (coupled continuation — deliberately shallow)

Interface-level only, to be designed after Human Review: the persisted relations provide the **verification layer** (what must hold for the continuation to be lineage-identical); a carrier restore provides the **position layer** (the rendered surface re-instantiated in a live engine, with consumed-prefix metrics). Coupling = the carrier restore is *selected and verified against* the CR (the CR says what the restored state must contain; the carrier metrics say what it consumed). Whether this coupling is worth its complexity is exactly what the C-CAP measurement exists to decide — asserted by no one in advance.

## 7. Open items for Human Review

1. PD-1..PD-4: confirm or flip any chosen alternative.
2. The edge vocabulary (used / continues / surface): is it sufficient for the scenario, or already too rich?
3. Whether V-1..V-5 is the right verification surface, and whether the three-state output discipline is acceptable as the pre-registered resolve outcome.
4. Whether C-CAP's mechanical no-recompute checks (both forms) are acceptable as the stage criterion's judgment basis.
5. Then: whether to proceed to carrier selection (PALACE evaluation — after, and only after, this design is accepted) and I-1c's full design.

## 8. Non-claims

This design claims no minimality for the record classes or edge vocabulary (IPAC bounding carried: OPEN / NONBINDING / minimality UNPROVEN / semantics NOT FROZEN); implements nothing; commits no carrier (PALACE unnamed as a target); runs nothing; resolves no open question of the parked five (anchor definition gate remains pending — R-an's A-records use provisional reference notions consistent with it); re-grades nothing; and does not extend `Eligible(T | S, C)` or formalize "admissibility information".
