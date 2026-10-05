# Claim Status / Evidence Boundary

Date: 2026-10-05
Status: `CLAIM_MAP_FROZEN · AWAITING_HUMAN_REVIEW`
Scope: 846 hypothesis → A_epistemic / A_execution behavioral evidence

---

## 1. What this document is

This document maps the original 846-derived hypotheses onto the evidence produced by the two completed experimental rounds. Its purpose is to make explicit which claims are supported, which are not established, and which are out of scope.

It does not introduce new claims. It does not authorize new experiments.

---

## 2. Claim map

| # | 846-derived claim | Current status | Evidence type | Key references |
|---|---|---|---|---|
| 1 | Authorization Object has a two-layer structure (`A_epistemic` / `A_execution`) | **SUPPORTED** (behavioral) | 8-cell factorial separation, C/N replication | `RESULT_REPORT.md` |
| 2 | `A_epistemic` and `A_execution` are behaviorally separable and ordered | **SUPPORTED / STRENGTHENED** | 8-cell + order-reversal probe, C/N replicated, pattern stable across metadata order | `ORDER_REVERSAL_RESULTS.md` |
| 3 | `E+X-` produces adoption without C4 (critical separation cell) | **REPLICATED** | C and N, both ordering conditions | `RESULT_REPORT.md`, `ORDER_REVERSAL_RESULTS.md` |
| 4 | `E-X+` does not produce bypass/leak in the tested frame | **OBSERVED ABSENT** (not exhaustively excluded) | No C4 in E- cells across all runs | `RIVAL_EXPLANATION_REVIEW.md` Q3 |
| 5 | Two layers have specific internal mechanistic relationship | **NOT ESTABLISHED** | No mechanistic probe; behavioral output only | `FALSIFICATION_ROUND2.md` |
| 6 | Information Core / minimal Information Core | **NOT CLAIMED** | Out of scope; hard boundary | `SESSION_STATUS.md` |
| 7 | Observer / InformationCore write | **NOT PERFORMED** | Hard boundary | `SESSION_STATUS.md` |
| 8 | 846 mapping / atom identity / merge / delete | **NOT PERFORMED** | Hard boundary | `SESSION_STATUS.md` |
| 9 | Generalization beyond C/N | **NOT ESTABLISHED** | Only C and N tested; A/B/D excluded for prior reasons | `RESULT_REPORT.md` §7 |
| 10 | Generalization beyond single F_content / single template | **NOT ESTABLISHED** | Only one F and one template tested | `RESULT_REPORT.md` §7 |

---

## 3. Explicit boundary statements

### What ORDERED_SEPARATION_SUPPORTED (STRENGTHENED) means

The behavioral pattern `E → adoption; X → C4` is:
- reproducible on two different models (C, N);
- stable across prompt metadata ordering (E→X and X→E);
- factorially separable across all 8 cells;
- free of bypass/leak in E- cells within the tested frame.

### What ORDERED_SEPARATION_SUPPORTED (STRENGTHENED) does NOT mean

It does NOT mean:
- the model internally implements two distinct sequential gates;
- the two-layer model is philosophically proven;
- the pattern generalizes beyond C/N, beyond this F, beyond this template;
- all bypass paths are exhaustively excluded;
- Information Core exists or has been demonstrated.

### The single most important boundary

> **This is behavioral evidence, not mechanistic proof.**

The claim is: *in the tested prompt-only frame, on models C and N, the output respects the declared two-layer order.* It is not: *the model has two internal authorization gates.*

---

## 4. Remaining probes and their status

| Probe | Priority | Status | What it attacks |
|---|---|---|---|
| partial-adoption | 1 | Proposed, not authorized | Does E-X+ suppress C4 because no adoption occurred, or because even partial adoption is blocked? |
| template paraphrase | 2 | Deferred | Is the pattern robust to different phrasings? |
| mechanistic probe | 3 | Deferred (different research layer) | Is there an internal mechanism corresponding to the behavioral separation? |

---

## 5. Proposed next gate

1. Human Review of this claim map.
2. If approved, minimal partial-adoption probe (same C/N, same 8-cell frame, one additional variable).
3. Update falsification status.
4. Consider closing this research phase.
