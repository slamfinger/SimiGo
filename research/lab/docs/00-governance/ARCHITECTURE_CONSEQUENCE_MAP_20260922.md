# Architecture Consequence Map

**Purpose:** 把“研究结果形成的架构约束”与“尚未验证的架构假设”分开，供多个 Agent 恢复设计背景。

## 1. Evidence-backed constraints

### Track B lifecycle

```
TB-FND-001/003/007/008
        ↓
TB-DEC-002/003/005/008
        ↓
TRACK_B_ARCHITECTURE_CONSTRAINTS
```

Registered consequences include:

- parent continuation preservation;
- child isolation;
- disjoint append ownership;
- GDN functional-state reference-fork isolation;
- representation transition semantic equivalence;
- discard = non-adoption;
- migration cost separately observable;
- adaptive policy remains non-authoritative.

These are bounded by the tested lifecycle and must not be generalized into a universal runtime architecture claim.

## 2. Architecture 2.0 pre-research hypotheses

`docs/architecture/ARCHITECTURE_2.0_PRERESEARCH_20260920.md` contains broader candidate architecture directions, including Runtime2 concepts, Track A/B/C/D planning, and boundary assumptions.

Those statements are **planning hypotheses / research direction**, not automatically validated architecture.

## 3. Source/Runtime boundary

Current estimand is Runtime Boundary Structure:

`B(M,W,O)`

It describes runtime-observed boundary structure. It does not yet establish:

- a Model Unit exists;
- a specific layer/block/tensor/KV object is the unit;
- Swift/MLX exposes the required controllable state;
- an implementation path is viable.

STEP⑤ is the next gate for existence.

## 4. Promotion rule

```
Observation
   ↓
Finding
   ↓
Decision
   ↓
Architecture constraint
```

A memory item or architecture proposal cannot skip these layers.

## 5. Agent check

Before an Agent says “architecture already proves X”, locate the supporting Finding/Decision and verify its scope. If the only source is RESEARCH_MEMORY or a pre-research architecture document, describe X as a hypothesis/candidate rather than a proven constraint.
