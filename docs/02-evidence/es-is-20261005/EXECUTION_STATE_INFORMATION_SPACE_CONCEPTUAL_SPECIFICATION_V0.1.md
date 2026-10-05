# Execution State ↔ Information Space — Conceptual Specification v0.1

Date: 2026-10-05
Branch: `codex/execution-state-research-20260929`
Status: `CONCEPTUAL SPECIFICATION · NEW LINE OPENED (ES↔IS) · NO EXPERIMENT · NO PALACE CONTENT · NO SEALED-LINE REOPENING · PENDING HUMAN REVIEW`
Directive: Human ruling 2026-10-05 — Admissibility line **PAUSED** (ES-3 sealed; D-SIG frozen; no D-SIG experiments); new line opened: **Execution State ↔ Information Space**, conceptual only. First deliverable: this specification, answering three core questions.
Location: `docs/02-evidence/es-is-20261005/` (new line directory; the Admissibility line remains sealed under `ci-c-own-structure-20261005/`)

---

## 0. Line positioning and genealogy

### 0.1 The lodestar question (Human, adopted as this line's fixed star)

> **一个 Execution State 要依赖什么样的信息关系，才能成为一个可以被识别、恢复并继续执行的计算对象？**
>
> *(What information relations must an Execution State depend on, in order to be a computable object that can be identified, restored, and continued?)*

This continues, at the conceptual level, the question registered in the ES line's Continuation Dependency work ("what minimal relation set enables continuation?") — but its center of gravity is new: the **ontology of Information relative to State**, which both sealed lines presupposed without making central.

### 0.2 Inheritance (all citations carry their registered boundings)

**From the sealed ES line** (closed at R3, `e27a7ba`):
- The Execution State concept: P6 frozen — *"minimal relation closure that preserves computational continuity"*, three layers Reference / Closure / Carrier; frozen name MLX-based, not universal.
- The Information Space concept: Boundary Synthesis H1–H3 (accepted) — IS = information domain / semantic environment, not carrier ontology; ES answers "what the execution has done", not "what the system knows".
- The dependency result: P5-4 — L1 minimal dependency set **{I, P, A, C}**, each independently irreplaceable (carrier-level); PA-2 — **Position ≠ Semantic Anchor** (output follows rendered prompt text; ES cannot just store KV).
- The continuation result: R-C1 — O1 SUPPORTED/task-domain-bounded (runtime state alone insufficient; persistent Information enables full continuation); O2 NOT OBSERVED (Relation showed no capability beyond independent Information there — ≠ unnecessary).
- The consistency results: R3 — differential sensitivity of the I/A/C conditions to Information-Space mutations, **fixture-slice bounded**; per its closing declaration, any citation of R3 must carry the bounded qualifier and restricted reading. R3 does not authorize generalization.

**From the sealed Admissibility line** (closed at ES-3, `65e4cdc`):
- The F phenomenon at transition level: F-absent → BLOCKED (semantically specific, C/N-replicated); F-STALE → DEGRADED (quality, not blocking); G / F-IRRELEVANT non-conditions.
- The discipline: explanatory models are held via their specific falsifiable commitments; never "supports Model B"; Case 2's non-identifiability lessons; ES-3's M2/M3 predication-level fork.

**What this line adds**: both lines *used* Information (as semantic environment; as transition condition) without asking what Information **is relative to State**. That ontological question, plus the dependency typology and the mutation→continuity semantics, is this line's territory.

### 0.3 What this specification does NOT do

- **No PALACE.** PALACE is not mentioned, mapped, or designed for. Whether PALACE is a concrete implementation of Information Space is a decision that can only be made **after** the concept stands (Human directive).
- No experiments, no instrument design, no code, no data collection.
- No reopening of any sealed line's locked items (R3-4 stays LOCKED; T3 stays CLOSED-LIMITED; the Admissibility line stays PAUSED; D-SIG-1..3 stay frozen).
- No re-derivation of sealed results beyond their boundings; no elevation of bounded findings to general claims.
- No formalization of "admissibility information" (the Admissibility line's standing boundary — respected in §2.4).
- No claim that Information "is" any one of the three readings — Q1's deliverable is the precise distinction, not a choice.

---

## 1. Q1 — What is Information?

**Answer delivered: the triad is formalized, then completed into a two-axis space; no choice is made among the readings; a load-bearing hypothesis is registered.**

### 1.1 The triad, formalized

```text
I1  Information = external context
    I is the semantic environment in which S is embedded; external to S,
    prior to it, not part of it. S refers into I; I exists independently.

I2  Information = the relational carrier of State
    I consists of the items that S's constitutive relations are relations
    TO. The relations that define S (P6: relation closure) have information
    items as their relata. I is external in location but constitutive in
    role: removing it does not merely impoverish interpretation — it
    un-constitutes (or breaks the closure of) the state.

I3  Information = part of State itself
    I is literally a component of S — the state includes the information
    content it needs. Information mutation is state mutation by definition.
```

### 1.2 The two-axis completion (this specification's first conceptual contribution)

The three readings are three points in a **two-dimensional space**, not three mutually exclusive answers:

```text
                 mere context            constitutive relatum
              ┌─────────────────────┬──────────────────────────┐
  external    │  I1                 │  I2                      │
              │  (surrounding       │  (relata of S's defining │
              │   environment)      │   relations)             │
              ├─────────────────────┼──────────────────────────┤
  internal    │  ** the fourth cell **│  I3                    │
              │  (carried but        │  (component of S)       │
              │   unreferenced)      │                         │
              └─────────────────────┴──────────────────────────┘

Axis 1 — locality:     does I live inside or outside the ES boundary?
Axis 2 — role:         is I a mere context, or a relatum of a relation
                       that constitutes/conditions S?
```

The Human's triad omits the **fourth cell** — information *carried by* the state but *unreferenced by* any constitutive relation. Its existence is not a pedantic completion: the sealed ES line's R3 observed exactly this split behaviorally (within its fixture): mutations of **referenced** information broke conditions (BROKEN side); mutations of **unreferenced** information held (HOLD side, 10/10). The fourth cell is where the HOLD-side information lives.

### 1.3 What the sealed material bears on each cell (considerations, not verdicts)

- **I1** is supported at the semantic level by Boundary Synthesis H1 (IS = semantic environment, non-carrier) — but H1 speaks to the *space*, not to the ES–item relation; it does not settle whether the items S depends on are mere context.
- **I2** is supported by the convergence of P6 (ES *defined* as relation closure), P5-4 (information an irreplaceable dependency), and R-C1 O1 (persistent Information enabling continuation): together they suggest S's defining relations have external information items as relata. Note I1 and I2 are **compatible** — locality (external) and role (constitutive) are different axes.
- **I3** has carrier-level precedents but no general support: the ES line repeatedly found "information inside the state" problematic at the carrier layer (ES-D1 formation-info uncaught by schema; T3's missing third carrier; P5 attempt-1's KV as representation fragment, not independent carrier) — all backend-bounded, and P6's frozen name is MLX-based. I3 remains a coherent reading with weak standing.
- The **role axis** has two-sided bounded evidence: R3's BROKEN/HOLD asymmetry, the Admissibility line's condition/non-condition asymmetry (F vs G/F-IRRELEVANT), and R32N's unreferenced-mutation holds. **Locality has no comparable evidence of being load-bearing.**

### 1.4 Working position (registered, not chosen)

No choice among I1/I2/I3. The line's **load-bearing working hypothesis**:

> **The role axis, not the locality axis, governs State–Information continuity outcomes.** What matters for what happens to S under I→I′ is whether the changed information stands in a constitutive relation to S — not whether it is stored inside or outside the state boundary.

Status: hypothesis, candidate-level, to be examined in this line's future work — never cited as established.

---

## 2. Q2 — The dependency typology: what does S do with I?

**Answer delivered: four relations provisionally defined; the interpretive/necessary partition is adopted as the line's central working distinction, with a criterion hypothesis; the sealed findings are mapped as relation-indexed necessity — at their own levels.**

### 2.1 Four relations (provisional definitions)

```text
R-id   S identifies against I
       Determining WHICH state this is requires resolving references into I.
       (Identity is reference-resolution, not content similarity — the threat
       model of the ES line's P4 identity checks: content-similar, separately
       formed.)

R-an   S anchors against I
       S's positional determinations (where in computation / information
       space it sits) are fixed by reference to I.
       ⚠ "anchor" is used here ONLY under this provisional definition. The
       ES line's correction H3 ("anchor undefined → must not be pre-inserted")
       is honored: R-an's definition is provisional and flagged for a
       dedicated definition gate before any matrix-level use.

R-res  S resumes using I
       Continuation of S consumes information (history, rendered prompt text,
       carrier-level state) to produce the next computation step.

R-adm  S is admissibility-evaluated against I
       Whether a transition FROM S is admissible depends on decision-relevant
       information. This is the F phenomenon elevated one level — the
       elevation itself is new work, not an established result (§2.4).
```

The relation inventory is **open** — these four are the Human's list, provisionally defined; other relations may exist.

### 2.2 The interpretive / necessary partition (the central working distinction)

The Human's question — *which information merely helps interpretation, and which is continuation-necessary?* — is answered with a **criterion hypothesis**, not a list:

> **Information stands on the necessary side of the partition iff it stands in at least one constitutive relation (R-id / R-an / R-res / R-adm) to S; otherwise it is interpretive (or irrelevant).**

This is the role axis of §1.4, seen from the State side. Note what the partition is NOT: it is not a partition of information *kinds* (documents vs metadata vs …), and not a partition by locality. It is a partition by **relation-holding** — which is why it can only be applied once the relations are defined and observable.

### 2.3 Relation-indexed necessity: the bounded evidence map

"Necessary" is not one thing — it is **relation-indexed**. The sealed findings populate different slots, each at its own level and bounding:

| Relation | Necessity-side evidence (bounded, at its level) | Interpretive-side evidence (bounded) |
|---|---|---|
| R-id | R3 A-conditions: anchor-substitution (A-SUB) mechanically detected; anchor mutations BROKEN — **fixture slice** | R3 HOLD side: unreferenced mutations hold — **fixture slice** |
| R-an | PA-2: Position ≠ Semantic Anchor; output follows rendered prompt text — **backend-bounded** | — |
| R-res | P5-4: {I, P, A, C} independently irreplaceable — **carrier-level**; R-C1 O1: persistent Information enables full continuation — **task-domain-bounded** | — |
| R-adm | F-absent → BLOCKED (semantically specific, C/N-replicated) — **transition-level** | G / F-IRRELEVANT → no blocking — **transition-level** |

**The elevation this line proposes (not established):** these are all instances of one structure — relation-indexed information dependency of a State. The table is a synthesis view, not a new result; each cell remains as bounded as its source.

### 2.4 Boundary note

The Admissibility line's standing boundary — *no formalizing "admissibility information" as a concept yet* — is respected: R-adm is a **relation label** for the elevated F phenomenon; no concept named "admissibility information" is defined, and no `Eligible(T | S, C)` extension is made (that boundary also stands).

---

## 3. Q3 — What happens to State when Information changes?

**Answer delivered: the five-outcome taxonomy is adopted as the line's working structure, with operationalization requirements; bounded shadows are mapped (not validations); the oracle-risk constraint and the mutation-locality variable are registered.**

### 3.1 Why this question is the line's core

A storage system with no mutation→continuity semantics is a database. The claim that Execution State is *more* than stored content stands or falls with this question: **S + I → fork → S₁ → I → I′ — what is S₁ afterwards?** (The product-facing weight of this is registered: the anti-forgetting foundation — a machine that does not recompute what it has already computed — requires states that survive their environment's changes *lawfully*, not accidentally.)

### 3.2 The outcome taxonomy (proposed, with operationalization requirements)

```text
O-1  State unchanged          all constitutive relations of S still hold under I′
O-2  State degraded           S continuable, but a quality dimension is lost
O-3  No longer continuable    at least one constitutive relation broken
O-4  State identity changed   the resulting object is a state, but not S
                              (same-shaped, different lineage)
O-5  State invalid            definition OPEN — candidate: S fails its own
                              formation/evaluability conditions; requires a
                              definition gate; not used casually
```

Two hard requirements, inherited from sealed lessons:

1. **Mechanizability.** O-1..O-4 must be operationalized by mechanical criteria (reference resolution, lineage/谱系 checks, referability) — **or they will inherit the no-oracle problem**: the ES line's R3 established (within its fixture) that *parsing success ≠ lineage correctness* and that no semantic-correctness oracle exists there. In particular, distinguishing O-2 (degraded) from O-4 (identity changed) from O-5 (invalid) without a semantic oracle is exactly where an unmechanized taxonomy goes to die.
2. **Level discipline.** The transition-level findings of the Admissibility line (F-absent → BLOCKED; F-STALE → DEGRADED) are shadows of O-3 / O-2 at the *transition* level — they motivate the taxonomy but do not establish it at the state level.

### 3.3 Bounded shadows (not validations)

| Taxonomy outcome | Nearest bounded shadow | Source bounding |
|---|---|---|
| O-1 unchanged | R3 HOLD side (unreferenced mutations, 10/10 hold) | fixture slice |
| O-3 not continuable | R3 BROKEN side (I/A/C signatures) | fixture slice |
| O-3, composition caveat | R3/IS-X: MASKING (X-08 confirmed) and order-dependence (X-09) — joint effects not predictable from single-variable composition | fixture slice, replication-level |
| O-4 identity changed | A-SUB silent substitution — mechanically detectable | fixture slice |
| O-2 degraded | F-STALE → DEGRADED | transition-level only |

The IS-X lesson is carried forward as a standing caution: **composition of information mutations is not naively additive** — a future Q3 treatment must not assume single-mutation outcomes compose trivially.

### 3.4 The mutation-locality variable (registered)

Under the P4 topology (S₀ as common base of multiple futures — sealed, topology-level), an information mutation can be **branch-local** (affecting one future's information) or **shared-base** (affecting information both futures depend on). These are structurally different Q3 cases; the taxonomy above does not yet distinguish them. Registered as a required variable for any future Q3 treatment — not resolved here.

---

## 4. Summary of delivered structure

```text
Q1  Information ontology   → triad formalized; completed into a 2×2
                             (locality × role) with the implicit fourth cell;
                             NO choice made; working hypothesis = the ROLE
                             axis is load-bearing (locality secondary)
Q2  Dependency typology    → four relations (R-id / R-an / R-res / R-adm),
                             provisionally defined ("anchor" flagged per H3);
                             interpretive/necessary partition adopted with
                             criterion hypothesis (relation-holding);
                             necessity is relation-indexed — sealed findings
                             mapped at their own levels
Q3  Mutation → continuity  → five-outcome taxonomy adopted with two hard
                             requirements (mechanizability; level discipline);
                             bounded shadows mapped (not validations);
                             composition-caution and mutation-locality
                             variable registered
```

Explicit non-choices: no I1/I2/I3 verdict; no claim that the four-relation inventory is complete; no state-level establishment of any partition or outcome class; no PALACE; no experiment.

## 5. Open questions and candidate next steps (none auto-open)

| # | Item | Type |
|---|---|---|
| 1 | Complete the 2×2: give the fourth cell (carried-but-unreferenced) a formal treatment and test the role-axis hypothesis against the bounded maps | conceptual, v0.2 candidate |
| 2 | "anchor" definition gate (per ES-line H3 lesson) before any matrix-level use of R-an | definition gate |
| 3 | Mechanize O-1..O-4 outcome criteria (reference resolution / lineage checks) — respecting the no-oracle constraint | conceptual → operationalization design (Human gate) |
| 4 | Decide whether Q3 treatment requires the mutation-locality variable from the outset | Human decision |
| 5 | Whether/when PALACE enters as an implementation question | explicitly deferred until the concept stands (Human directive) |

## 6. Boundary accounting and non-claims

- **Admissibility line**: PAUSED; ES-3 sealed; D-SIG-1..3 frozen (未出现 / 未解决 / 未规格化); no D-SIG experiments. This spec does not touch it beyond bounded citation.
- **ES line**: sealed at R3; all citations carry boundings; R3-4 LOCKED; nothing reopened; no OFF-MAINLINE item is cited as definition evidence.
- **This spec claims nothing as established** — every structure above (2×2, four relations, partition criterion, outcome taxonomy) is candidate-level conceptual work, pending Human review.
- No experiment, no code, no instrument, no data collection; no PALACE content; no `Eligible(T | S, C)` extension; no formalization of "admissibility information"; all hard boundaries of both sealed lines respected.
