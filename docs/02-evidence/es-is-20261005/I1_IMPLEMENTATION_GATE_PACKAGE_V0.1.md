# I-1 Implementation Gate Package v0.1

Date: 2026-10-05
Branch: `codex/execution-state-research-20260929`
Status: `GATE PACKAGE · COMMISSIONED (HUMAN: GATE CLOSED, COMMISSION AUTHORIZED) · NO IMPLEMENTATION · NO EXPERIMENT · NO CARRIER SELECTION · GATE OPENING = HUMAN RULING`
Directive: Human ruling 2026-10-05 — Implementation Gate **stays closed**; the commission is authorized. Per the declared next stage ("map the three Frozen Contracts onto a minimal real run carrier; begin obtaining the first auditable I-1 runtime evidence"), this package contains everything needed to open — or decline — the Implementation Gate by ruling. It changes no frozen object.

Session header (Constitution Article 6):

```text
Core target:               realization of the three frozen contracts on a minimal real run carrier
Affected closure edge:     all five — the first end-to-end evidence run closes the loop's missing integration joint
Real system object:        this package (carrier requirements, mapping plan, evidence-run definition, finding protocol)
Expected capability delta: upon gate opening — the first auditable I-1 runtime evidence (CR/IR chain + C-CAP measured on a real run)
Stop condition:            if the carrier requirements below prove unsatisfiable by any candidate, the package reports that fact (Gate-2 style) instead of weakening them
```

---

## 0. Purpose and boundaries

**What this package is**: the complete pre-gate artifact set. After Human Review, the Implementation Gate opens (or declines) by a single ruling — with scope, acceptance criteria, finding protocol, and evidence definition already pinned here.

**What it is not**: not an implementation (no code exists or is authorized); not a carrier selection (requirements only — candidate evaluation is the gate's first act); not an experiment (the evidence run is *defined*, not executed); not a modification of any frozen object (I-1 / I-1c / I-1d stand exactly as frozen; all inconsistencies found later enter as **Implementation Findings**, per the frozen I-1d post-freeze rules).

**The frozen stack being realized** (anchors):

```text
I-1   Persistence / Resolve               FROZEN (main 2b2e2ef)
I-1c  Instantiate Completeness            FROZEN (main 6c3cf6a)
I-1d  Runtime Realization / Verification  FROZEN (branch 1832676)
```

---

## 1. What must be realized — the three frozen contracts, restated as obligations

| Frozen layer | Normative object | Realization obligation |
|---|---|---|
| I-1 | CR (result/used/surface/continues, use-time pinning, CR identity hash) | write + read CRs as content-addressed nodes + typed edges; resolve = closure traversal + V-1..V-5; three-state output |
| I-1c | instantiate(R2, τ2★, substrate) → S2; IC-1..IC-7; binding three-state; substrate interface | realize bind / materialize [/ restore] / attach with envelope and position semantics |
| I-1d | IR (incl. TaskRecord, BindingRecord, Envelope, Manifest, PositionRecord); VV-1..VV-7 with tiers; pipeline order; disposition + lifecycle | produce the IR per attempt; run the Verification Surface; classify every outcome into the three disposition classes; honor the lifecycle |

---

## 2. Minimal real run carrier — candidate-agnostic requirements

Any carrier qualifying for the Implementation Gate must satisfy **all** of:

```text
MC-1  substrate execution   can execute the continuation task T2 on a bound weights
                            identity (IC-2/IC-3) — an inference substrate with an
                            addressable weights identity
MC-2  surface materialize   accepts the continuation surface as BYTES and is
                            contractually surface-faithful (VV-2: readback-verified
                            or declared covenant — tiers recorded, never merged)
MC-3  trace granularity     produces an execution trace with segment granularity
                            sufficient for predecessor references (C-CAP(c)
                            document-form) — or exposes consumed-prefix metrics
                            (carrier-form; optional path)
MC-4  IS-side records       the CR/IR field lists (frozen) can be stored and read
                            back as content-addressed records (store-agnostic:
                            git/files/DB all qualify — the store is not the IS,
                            it realizes IS persistence)
MC-5  envelope capture      configuration capture (and readback where available)
                            for ε2 (VV-4)
MC-6  tokenizer identity    the bound tokenizer is identifiable (VV-5/IC-5)
```

**Minimal scoping note**: the first evidence run is proposed at **document-form** (no carrier-state restore; C-CAP(c) via trace provenance) — it requires no new substrate engineering beyond MC-1..MC-6 and formalizes the loop the lab already runs informally. The **carrier-form** extension (restore + consumed-prefix metrics, per P7's validated assets) is the optional second step, same gate. No candidate is named or excluded; the requirements filter, the Human selects.

---

## 3. The mapping plan (how the frozen contracts land on the carrier)

Per the frozen I-1d §1.2 table: at gate opening, the selected carrier receives a **per-carrier mapping table** — each IC/SC clause mapped to the carrier's concrete object/field/operation and check — and compliance is audited as full coverage (I-1d §5 (a)–(e)). The mapping table for the selected carrier is a **gate deliverable**, reviewed before the first evidence run; a clause that cannot be mapped is escalated as an Implementation Finding (never silently weakened).

---

## 4. The first evidence run — definition (defined, not executed)

```text
E-run (the first auditable I-1 runtime evidence):
  E1 executes T1 → R1 produced → CR(E1) written (frozen I-1 format)
  resolve(CR_ref) → R2 (V-1..V-5, three-state output)
  instantiate(R2, τ2★, substrate) → IR(S2) + S2 (VV-1..VV-7 with tiers;
      BindingRecord three-state; disposition + lifecycle recorded)
  E2 executes T2 from S2 → CR(E2) written
  C-CAP measured: (a) clean RESOLVED, (b) T2 continued from S2,
      (c) no-recompute via trace provenance [document-form]
      and/or consumed-prefix metrics [carrier-form]
```

Judgment basis: exactly the frozen C-CAP — success is the chain (a)+(b)+(c), never "it stored something". Every check result, tier, disposition, and lifecycle state lands in the IR/CR chain, making the run auditable after the fact against I-1d §1.2.

---

## 5. Implementation Finding protocol (per the frozen I-1d post-freeze rules)

Any inconsistency discovered during realization is recorded **first** as an Implementation Finding — the Frozen Contract is never modified to accommodate the implementation. Finding classes: (i) realization deviates from the Frozen Contract; (ii) the Contract conflicts with reality within its declared boundaries (Evidence finding); (iii) a new candidate semantics (Future alternative — formed, not applied). Findings are resolved by Human ruling: fix the implementation, or open a contract revision with G-2 lineage. **No silent weakening; no unrecorded convenience** (the I-1d rule carries over verbatim).

---

## 6. Gate opening proposal (for Human ruling — nothing here opens the gate)

If the Implementation Gate is opened, the proposed scope is:

```text
G-1  implement the CR/IR record formats (frozen field lists) + resolve per I-1
G-2  implement the instantiate pipeline (0–5) + Verification Surface VV-1..VV-7
     per I-1d, over a carrier satisfying MC-1..MC-6
G-3  run the E-run once, end to end, with full IR/CR/trace capture
G-4  deliver the per-carrier mapping table + the E-run audit against I-1d §1.2
```

Acceptance criteria: I-1d §1.2 full coverage + C-CAP measured on the E-run + zero silent degradation events. **Still separate and BLOCKED regardless of gate opening**: PALACE selection (a post-evidence evaluation), experiments beyond the single E-run, and any Frozen Contract modification.

## 7. Non-claims and boundaries

This package implements nothing, runs nothing, selects nothing; its requirements are candidate-agnostic and may prove unsatisfiable (that report is a valid outcome per the stop condition); it does not modify any frozen object; it does not authorize the Implementation Gate (opening is a Human ruling); the no-oracle discipline, the three disposition classes, the M-table, and all hard boundaries stand unchanged.
