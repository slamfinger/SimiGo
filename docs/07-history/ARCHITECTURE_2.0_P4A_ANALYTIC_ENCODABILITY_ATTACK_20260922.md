# Architecture 2.0 P4-A — Analytic Encodability Attack

Date: 2026-09-22
Status: STEP① conceptual attack / not an RQ / no experiment authorization

## 1. Why this is the next gate

The previous Description Language / Rate-Distortion attack established a candidate accounting discipline:

- Codebook cost: architecture-side adaptation, approximately O(A);
- Rate: per-decision representation cost, approximately O(D);
- Decoder / primitive-set cost: language-side cost, accounted separately;
- L₀ = byte-level direct dump as a zero-distortion reference language;
- distortion is Runtime decision loss within a defined task scope.

The next vulnerability is upstream of rate measurement:

> **Where does the architecture-specific encoder come from?**

If Encoder_X is constructed using the target Runtime resource-behavior data, then the projection may merely move information acquisition from O(D) decision-time measurement into O(A) architecture-time profiling. A later positive rate-distortion result would then be unable to distinguish genuine shared-state information value from data-contaminated codec construction.

Therefore analytic encodability must be an independent pre-STEP② gate.

## 2. Candidate definition

A projection is **analytically encodable** within a defined scope if:

> The rule needed to construct Encoder_X can be determined from the architecture / computation-structure description and admissible prior knowledge, without observing the target Runtime resource-decision outcomes or profiling data.

This does not mean that the encoder is architecture-independent. On the contrary:

`Architecture X → Encoder_X → code`

is expected.

The independence requirement applies to the **source of the encoder rule**, not to the absence of architecture-specific information.

## 3. Permitted and forbidden information

### Permitted

Encoder construction may use information that is legitimately part of the architecture-side description, such as:

- computation structure;
- declared dependency relations;
- continuation-relevant structural properties;
- state growth / lifetime rules derivable from architecture;
- publicly or pre-registered architecture specifications.

### Forbidden for the analytic gate

Encoder construction must not require target Runtime decision data such as:

- measured migration cost;
- measured residency benefit;
- cache / reuse outcomes;
- memory-pressure traces;
- workload-specific resource behavior;
- target decision labels;
- profiling results used to discover which State fields predict the target outcome.

Otherwise the encoder has access to the answer it is later supposed to predict or compress.

## 4. The critical distinction

The research must distinguish:

`Architecture → analytic Encoder → Projection → Runtime decision`

from:

`Architecture → profiling → learned/manual Encoder → Projection → Runtime decision`

Both can produce useful representations. They answer different research questions.

The first tests whether the common description can be derived without target-resource measurement.

The second may still be a useful engineering codec, but it cannot by itself establish that the shared semantic projection reduces cross-architecture information-acquisition cost.

## 5. Falsification targets

Analytic Encodability should be attacked by attempting to construct counterexamples:

1. **Profiling dependence** — Encoder_X cannot be specified without observing target resource behavior.
2. **Workload dependence** — the encoder changes materially with workload or Runtime regime in a way not derivable from the architecture description.
3. **Decision leakage** — encoder fields are selected using the target decision outcome or its proxy.
4. **Hidden architecture-family prior** — the alleged analytic rule is actually a manually accumulated family-specific codec.
5. **Non-derivable key fields** — the projection requires empirical values that are not recoverable from architecture / computation structure.
6. **Codec instability** — the same architecture description admits materially different encoders depending on the resource data used to construct it.

Any decisive counterexample narrows the claim. If analytic encodability fails for the intended scope, the projection may remain a data-assisted engineering representation, but the stronger cross-architecture information-saving claim must not be advanced under this gate.

## 6. Relationship to the previous gates

The current conceptual chain is:

`Architecture → Computation Dependency → continuation-relevant information → candidate projection → fixed Description Language → Analytic Encoder → Rate / Distortion → Runtime decision information`

The order is intentional.

- Description Language Attack asks whether the language can hide complexity or architecture knowledge.
- Analytic Encodability Attack asks whether the encoder itself is contaminated by target observations.
- Only if both survive should Rate-Distortion become a candidate for a more concrete STEP② research question.

Analytic Encodability does **not** prove that the projection is useful. It only removes one major confounder.

## 7. Cost-accounting consequence

The O(A) / O(D) distinction must remain explicit.

A genuinely analytic encoder can make the architecture-side adaptation cost closer to a derivation cost:

`Architecture description → Encoder_X`

A data-trained or profiled encoder introduces an information-acquisition cost that may be substantial:

`Architecture → target profiling → Encoder_X`

Therefore later utility analysis must not count all O(A) encoder construction as equivalent. The provenance of the adaptation information matters.

This does not yet define a numerical estimand or threshold; those remain outside STEP①.

## 8. Governance boundary

This record remains conceptual.

Allowed at this stage:

- define analytic encodability;
- identify permitted / forbidden information sources;
- design the falsification logic conceptually;
- preserve the distinction between analytic and data-assisted encoders.

Not authorized:

- implement an encoder;
- construct a decoder;
- collect profiling data;
- build a harness;
- benchmark rate or distortion;
- register a new RQ;
- enter STEP②–⑨.

The Description Language remains a **candidate research vocabulary**, not a Runtime API or architecture commitment.

## 9. Next gate

If this attack survives, the next legitimate question is whether the surviving projection candidate has a well-defined information-value problem under fixed language, fixed decoder accounting, L₀ reference, and explicit A:D deployment regime.

If it fails, the failure itself should determine whether the candidate is closed, narrowed to data-assisted codecs, or moved to a separate engineering branch. No implementation follows automatically.
