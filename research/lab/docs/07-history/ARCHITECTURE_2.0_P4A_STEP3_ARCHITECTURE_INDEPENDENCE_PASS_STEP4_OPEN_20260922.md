# Architecture 2.0 P4-A — STEP③ Architecture Independence PASS / STEP④ Open

Date: 2026-09-22

## Governance transition

The human researcher formally closed STEP③ Independence after the Object Independence and Parameter Independence analyses and the Architecture Independence attack.

This is a research-governance transition, not empirical evidence. No RQ ID is assigned yet and no experiment, Runtime implementation, harness, profiling, data collection, or measurement is authorized.

## Architecture Independence adjudication

The accepted measurement object remains frame-indexed:

F_AS^(L,D,S,Pi)(X)

Architecture X is a legitimate input index only if the measurement pipeline is slot-separated.

### Rule slots — fixed across X

- Description Language L and rate accounting
- Decision-task semantics defined over L
- Static-derivation strategy family S
- normalization rule
- evaluation protocol Pi_W, budget, and estimator

### Input slots — allowed to vary with X

- architecture static description
- actual encoder output derived from that description
- architecture-specific oracle normalization factor R_oracle,X
- model instance / workload instance as declared by the evaluation protocol

### Forbidden slot

- per-X redefinition of decision-task semantics

The core rule is:

> Architecture differences may enter through input values, never through redefinition of the measurement rules.

## Hard applicability rule

If a frozen L and D cannot express/evaluate an architecture at the declared granularity, the legal outcome is:

task not evaluable at this granularity

It is forbidden to modify D for that architecture merely to make it evaluable.

This protects cross-architecture comparability. Per-X task redefinition would turn a shared measurement functional into different instruments and invalidate the cross-architecture comparison.

## Normalization

Primary semantic comparison may use the common normalization rule:

D_tilde_X(P) = D_X(P) / R_oracle,X

The rule is X-invariant while the normalization factor is X-dependent. Absolute costs and oracle scales remain on a secondary economic track; normalization must not be used to erase scale effects and then interpreted as deployment economics.

## X anti-vacuity

The original strong X-discrimination lemma was rejected as too strong. Different architectures need not produce different frontiers for X to remain a valid input index.

The accepted anti-vacuity requirement is weaker:

> There must exist a pre-registered admissible witness showing that the same frozen measurement functional can be sensitive to architecture description inputs; X need not distinguish every architecture.

A definition-layer toy witness was constructed:

- X1: component-structured state with enumerable components and heterogeneous declared attributes (w_i, r_i, t_i).
- X2: monolithic state description with only aggregate attributes, with no decomposition primitive available in L.
- Under the same frozen D and algorithmic S, X1 admits selective retention encodings with nontrivial interior rate/loss points, while X2 can collapse to a coarse two-endpoint encoding family.
- The witness difference follows from declared description-language syntax and symbolic task semantics, not from measured frontier results.

The witness passed the following anti-leakage checks:

1. no frontier result is used to construct the witness;
2. S remains one syntax-level algorithm with conditional branches over input description structure, not a per-X rule;
3. no runtime measurement is required.

The witness is an anti-vacuity construction, not a claim about the actual frontier of any real architecture. Real architecture readouts remain STEP④+ empirical objects.

## Formal STEP③ result

Architecture Independence: PASS, subject to the following four conditions:

1. slot separation holds and the forbidden per-X rule slot is empty;
2. per-X task redefinition is prohibited and non-evaluability takes precedence;
3. an X anti-vacuity witness exists under the frozen frame without using measured results;
4. evaluation protocol Pi_W and normalization rule remain fixed.

The rejected strong claim was:

all distinct X must yield distinct frontiers

The accepted claim is:

X is a genuine input index of a shared measurement functional when the functional is non-constant over the admissible description space and no rule slot is redefined per X.

## Boundary

This PASS does not establish cross-architecture transfer, common frontier shape, low-rate projections, or Runtime value. It only establishes that the object can be defined as one shared, frame-indexed measurement functional over varying architecture inputs.

## Next gate

STEP④ — Estimand.

The next task is to determine whether the accepted Research Question has a precise, identifiable, non-arbitrary estimand, including its scope, parameterization, uncertainty/robustness treatment, and negative criteria.

No STEP⑤–⑨ activity is authorized by this transition.
