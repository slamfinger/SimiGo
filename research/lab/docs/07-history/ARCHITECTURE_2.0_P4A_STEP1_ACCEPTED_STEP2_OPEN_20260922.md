# Architecture 2.0 / P4-A — STEP① Contract Acceptance and STEP② Entry

**Date:** 2026-09-22
**Status:** STEP① contract accepted by the human researcher; STEP② formally opened.

## 1. Decision

The human researcher explicitly accepts the P4-A STEP① candidate contract and authorizes formal entry into **STEP② Research Question**.

This is a governance transition, not an empirical result.

The accepted contract consists of:
- fixed Runtime-side Description Language `L`;
- frozen/public decoder as an auditable artifact;
- `L₀` byte-level direct-dump zero-distortion reference;
- explicit `O(A)` architecture-adaptation versus `O(D)` per-decision regime accounting;
- Static Derivability as the provenance criterion for `Encoder_X`;
- allowance for architecture-specific static knowledge, while forbidding target Runtime outcomes/profiling from defining the encoder;
- analytic structural skeleton + possible minimal measured coefficients as a non-binary candidate;
- Decision Loss `D` defined through a predeclared Bayesian decision problem and parameter family;
- Blackwell decision-theoretic treatment of information dominance/equivalence;
- oracle/full-information endpoint and excess decision cost as the conceptual distortion measure;
- strict separation between definition-stage validation artifacts and the later STEP⑨ research harness.

## 2. Decision-loss formalization accepted into the contract

A decision problem is represented as:

`𝓓 = (𝓐, 𝓒, Π_W)`

where:
- `𝓐` = admissible resource actions and granularity;
- `𝓒` = declared cost function, including symbolic recomputation, migration and capacity terms;
- `Π_W` = declared workload/continuation prior family.

For projection `P`, let `I_P` denote its decision-relevant information structure. For parameter setting `θ`, the Bayes risk is:

`R(P; θ) = inf_{δ ∈ Δ(I_P)} E_θ[C(δ(I_P), W)]`

and the decision loss relative to the declared full-information/oracle reference is:

`D(P; θ) = R(P; θ) − R_oracle(θ)`.

Robust comparison is parameter-family relative. If a dominance relation changes across `θ ∈ Θ`, the transition region is itself a candidate applicability boundary rather than an error to be averaged away.

Blackwell ordering provides the formal basis for saying that information superiority is decision-problem relative. If two projections induce the same decision-relevant information structure, they are candidates for decision-equivalence within the declared decision family; this does not imply a universal minimal Execution State.

## 3. Connection to the original research motivation

The accepted formal chain closes the conceptual loop without reopening Track B:

`Compute Once / Multiple Futures` → expensive recomputation → continuation-relevant state → resource decisions → caching/paging-style decision problem → oracle versus information-limited policy → Decision Loss `D`.

At the representation side:

`Architecture` → State description → fixed language `L` → Rate.

The two sides meet at a rate–decision-loss comparison. `L₀` and the oracle are reference endpoints, not claims that every practical system must implement them.

This establishes a formal candidate decision model; it does not yet establish that a cross-architecture projection exists, is low-rate, or is useful in practice.

## 4. Harness governance

STEP② may define the Research Question without implementing Runtime infrastructure.

A definition-stage toy/simulation artifact is not authorized merely because it might be convenient. Such an artifact would require its own explicit mini-gate and could only test definitional self-consistency; it could not generate research evidence.

The STEP⑨ research harness remains reserved for a registered RQ after the applicable design gates are passed.

Exit to a definition-stage executable artifact is permitted only if the predeclared decision-problem family is shown to be non-analytically evaluable. The current formal Bayesian/Blackwell/caching path does not itself trigger that exit.

## 5. STEP② boundary

STEP② now asks whether the accepted P4-A contract can be reduced to a **precise, independent, falsifiable Research Question**.

STEP② must not silently:
- assume the existence of a useful cross-architecture projection;
- assume low rate or low dimensionality;
- assume Runtime adoption value;
- convert the decision model into an implementation requirement;
- reopen Track B lifecycle questions;
- promote Architecture 2.0 hypotheses into findings.

The first legitimate task is therefore RQ formulation and adversarial narrowing, followed by the required independence and scope checks. No experiment, profiling, harness construction, or measurement is authorized by this document.

## 6. Governance stop point

The human researcher has made the transition decision. The Agent may now work within STEP②, but it may not autonomously declare a new RQ registered merely by drafting one.

The next formal checkpoint is the **STEP② Research Question definition/acceptance gate**.