# Architecture 2.0 / P4-A — STEP② RQ Candidate and First Attack

**Date:** 2026-09-22
**Status:** STEP② OPEN / RQ candidate under adversarial review / NOT REGISTERED

## 1. STEP② starting point

STEP① contract has been explicitly accepted by the human researcher. STEP② is therefore authorized to define, compress, and attack the Research Question. This document records the first RQ candidate only; it does not register an RQ and does not authorize experiments or implementation.

## 2. First RQ candidate

> **在固定且预注册的 Runtime-side Description Language 与 Decision Problem Family 下，由架构静态信息导出的 State Projection，是否能够在有限描述成本下保持该 Decision Family 所需的信息充分性？**

The candidate deliberately avoids assuming a universal Execution State, cross-architecture usefulness, low dimensionality, Runtime adoption value, or superiority over architecture-specific implementations.

## 3. Four hidden propositions

1. **Analytic:** Architecture → Encoder_X can be derived from static information.
2. **Representational:** the fixed language can express the relevant State description.
3. **Informational:** the Projection retains information needed by the declared decision family.
4. **Economic:** the representation has sufficient cost value under an O(A) / O(D) deployment regime.

STEP② should not collapse these into one vague claim. Runtime adoption value is downstream of information sufficiency and should not be smuggled into the core RQ.

## 4. First compression

Information sufficiency alone is vacuous because full State / L₀ can preserve all information at maximal rate. Therefore the relevant object must be the relationship between description rate and decision loss.

Instead of selecting an arbitrary fixed rate threshold K, a cleaner candidate is:

D*(R) = min_{P : Rate(P) ≤ R} D(P)

This treats rate as a budget and Decision Loss as the resulting minimum attainable loss, avoiding a post-hoc arbitrary K.

## 5. Current RQ-core candidate

> **在固定 Description Language 与预定义 Decision Problem Family 下，State representation 的描述成本与 Runtime Decision Loss 之间是否存在可重复、可区分的 Rate–Decision-Loss frontier？**

This formulation does not yet assume cross-architecture regularity.

## 6. Cross-architecture extension

> **该 frontier 的结构是否在不同计算架构之间表现出可比较的共性，以及其适用边界由哪些架构、workload 与 resource regimes 决定？**

A boundary/local-validity result remains a legitimate outcome. Universal validity is not the target condition.

## 7. First STEP② adversarial attack

> **Rate–Decision-Loss frontier 是否只是由研究者预先选择的 Description Language L 与 Decision Problem Family 所人为定义出来的数学对象，而不是 Architecture-induced phenomenon？**

Two sources of circularity must be separated:

- Rate(P) depends on the chosen description language and primitive vocabulary.
- D(P) depends on the chosen decision family, workload prior and cost model.

If the apparent frontier changes arbitrarily with these researcher-defined choices, the frontier may lack independent research status. If its qualitative structure remains stable across a predeclared family of admissible languages and decision problems, that stability would itself be informative.

No robustness result is assumed at this stage.

## 8. Governance status

**STEP② remains OPEN.**

- RQ ID: not assigned.
- RQ: candidate only.
- STEP③ Independence: not started.
- STEP④ Estimand: not started.
- STEP⑤–⑨: not started.
- no experiment authorization.
- no profiling.
- no Runtime implementation.
- no research harness.
- Track B remains CLOSED/FROZEN.

The next legitimate action is to attack the dependence of the proposed frontier on L and the Decision Problem Family before registering the RQ.
