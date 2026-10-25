# Architecture 2.0 / P4-A — STEP② Accepted, STEP③ Independence Open

**Date:** 2026-09-22  
**Status:** STEP③ OPEN / Independence analysis in progress

## 1. Governance transition

The human researcher explicitly authorizes transition from STEP② to STEP③.

STEP② is therefore treated as accepted for the current P4-A candidate. This is a governance transition, not empirical evidence and not an authorization to run experiments.

## 2. Candidate research object carried forward

The current object is the **Achievable Static Frontier** rather than an unrestricted mathematical optimum.

F_AS,X^(L,D,S)(R) is the infimum of D_X(P) over certificate-backed outputs of the declared static derivation strategy family S, subject to Rate_L(P) ≤ R.

The unrestricted frontier F*_X(R) remains a reference object. Their gap is interpreted only relative to the declared strategy family: Delta_AS(R) = F_AS(R) - F*(R).

No claim of universal optimality is made.

## 3. STEP② conclusions carried forward

- Description Language L is explicit and pre-registered.
- Decision Problem Family D is explicit and includes both isolation tasks and integrated tasks.
- Derivation Strategy Family S is explicit; static derivation outputs require auditable certificates.
- Construction provenance and evaluation measurement are separate channels; evaluation measurements must not flow backward into encoder construction.
- D-level non-degeneracy has been established by two property-isolating resource-decision tasks with mutually non-contained information requirements.
- Per-(L,X) expressibility/implementability is a downstream applicability-boundary check, not part of the D-level non-degeneracy proof.
- Cross-architecture comparison uses a normalized primary decision-loss track and an absolute secondary resource-cost track.
- Convexity remains a candidate structural property, not an assumed theorem; non-convexity is a valid finding.
- Knee stability across regimes is a testable proposition, not a premise.

## 4. STEP③ question

STEP③ asks whether the accepted RQ is genuinely independent of the conceptual machinery used to formulate it.

The independence attack must distinguish at least:

1. **Object independence:** Is Achievable Static Frontier a new measurement object, or merely a restatement of the already-declared decision problem plus compression rate?
2. **Parameter independence:** Are L, D, and S research-defining inputs or hidden knobs that can manufacture the claimed phenomenon?
3. **Architecture independence:** Does the estimand retain meaning when the architecture changes, without redefining the object per architecture?
4. **Historical independence:** Does the RQ add information beyond Track B's closed execution-state lifecycle findings, rather than rediscovering them under new terminology?
5. **Implementation independence:** Can the estimand be defined without depending on one Runtime implementation, MLX-LM representation, or physical state layout?

STEP③ must not assume that independence means invariance to every choice. The goal is to identify which quantities are constitutive of the RQ, which are nuisance parameters, and which choices would invalidate the research claim if changed.

## 5. Governance boundary

No STEP④ estimand finalization, harness construction, profiling, Runtime implementation, or experiment authorization is implied by opening STEP③.

**Current checkpoint:** determine whether the accepted RQ has sufficient independence to survive as a research question before formal estimand lock.
