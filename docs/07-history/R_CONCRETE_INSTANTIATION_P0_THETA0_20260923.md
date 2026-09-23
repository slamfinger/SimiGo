# Concrete Instantiation — P0 / θ0′

**Date**: 2026-09-23  
**Gate**: Concrete Instantiation  
**Status**: REGISTERED

## 1. Registration authority

This gate records the concrete instance after Final Registration Audit and explicit semantic ratification of the R1 horizon-settlement form. The parameter values are researcher/participant-proposed registration inputs; the assistant is not the source of those research choices.

## 2. Projection instance

S = S1 × S2 × S3 × S4 × S5.
P0 := π0 : S → B0.
b = (KV headroom, |resident sessions|, execution phase).
I_P0 = σ(π0).
The admissible decision family is constrained by I_P0 visibility; excluded unprojected variables include LRU order, fingerprint, and request identity. P distinguishes the research object through the information constraint induced by I_P0.

## 3. Regime instance

θ0′ ↦ μθ0′, where μθ0′ is the point measure on a deterministic exogenous workload W=(w1,…,wK), with strict A/B alternation, fixed prompt lengths and decode depths, FIFO handling, and horizon settlement. The workload is strategy-independent.
Strategy-induced state history is X^g(W)=(H1^g,…,HK^g), and visible decision history is Vt^g(W)=(π0(H1^g),a1,…,π0(Ht−1^g),at−1), with at=h_t(Vt^g(W)).

## 4. Action and runtime semantics

A = {serve, defer, reject}. `evict-LRU` is an execution mechanism under `serve`, not an action.
`defer` places the request into FIFO without loading KV. Each round has one arrival event; the action binds to the queue head when a queue exists, otherwise to the arriving request. Served and rejected requests leave the queue. Horizon-end unresolved requests are settled as rejected without a K+1 runtime event.

## 5. Concrete parameters

κ=128 KiB/token; L_A=512; D_A=256; L_B=1024; D_B=128; K=8; B=192 MiB; λ=1280 token-equivalent.
Decode depth is discrete: d_t∈N0, d_t≤D, with the instance fixing d_t to D_A or D_B by session type.
KV_j(t)=κ·(l_j+decoded_tokens_j), and usage(t)=Σresident j KV_j(t).
KVAmax=128 KiB×(512+256)=96 MiB; KVBmax=128 KiB×(1024+128)=144 MiB.
Contention condition: max(96,144)=144≤192<240=96+144. Each single session fits while the two-session maximum does not; both directions therefore contain a forced-eviction condition.

## 6. Admissibility and loss

𝒢_adm(P0) is the R-ASM-E composite predicate: I_P0 visibility plus trajectory feasibility KV_usage^{g,W}(t)≤B for all t.
C_LOSS(g,W)=Σ[t=1..K](v1^g(t;W)+λv2^g(t;W)).
v1 is zero when the request session KV is resident and otherwise equals l_t.
Final ratified settlement:
v2^g(t;W)=1 if a_t=reject and t<K;
v2^g(K;W)=𝟙[a_K=reject]+|Q_{K+1}^g(W)|, where Q_{K+1}^g(W) is the set of all unresolved FIFO requests after round K. Settlement is accounting only and introduces no K+1 runtime event. Each request is charged at most once.
L(g;P0,θ0′)=E_{μθ0′}[C_LOSS(g,·)]. Because μθ0′ is a point measure, this equals the loss on the fixed trajectory.

## 7. Domain-of-R instantiation

The always-reject rule witnesses non-emptiness of the admissible optimization domain because it never loads session KV.
Σv1≤8×1024=8192; Σv2≤8; λΣv2≤8×1280=10240.
Therefore 0≤C_LOSS(g,W)≤18432<∞, V(P0,θ0′)⊆[0,18432], and inf V(P0,θ0′)∈R.
Registered instance fact: (P0,θ0′)∈Dom(R). This is derived from the declared constraints, not an attainment or optimizer-existence assertion.

## 8. Non-degeneracy check

Always-serve-with-evict gives 4×512+4×1024=6144. Retain-A/reject-B gives 512+4×1280=5632. The distinct values establish a nontrivial strategy-comparison surface without asserting which rule attains the infimum or whether it is unique.

## 9. Explicit non-assertions / boundaries

This gate does not assert att(P0,θ0′), Argmin(P0,θ0′)≠∅, uniq(P0,θ0′), any selector/tie-breaking/canonical optimizer/g*, R_ORACLE, Δ/gap, FinLoss, NECT, historical δ(I_P), a new δ optimization domain, θ-level optimization, A(P,θ), or new topology/compactness/continuity/measurability/cardinality assumptions.
No implementation, harness, data collection, profiling, measurement, or experiment authorization follows from this gate. R-INTERNAL remains IDLE; R-ASSEMBLY remains CLOSED; STEP⑤ and STEP⑥ remain NOT ENTERED.

## 10. Registration decision

Concrete Instantiation for (P0,θ0′) is REGISTERED with (P0,θ0′)∈Dom(R). The gate is a concrete-instantiation record only; attainment, argmin, and uniqueness remain post-gate fact-check surfaces.