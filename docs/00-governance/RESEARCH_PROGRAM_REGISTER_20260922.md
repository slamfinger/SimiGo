# Research Program Register

**Purpose:** 当前与未来研究路线的控制面。  
**Authority:** 本文件不替代 `docs/RESEARCH_STATE.md`；它登记研究路线、依赖和合法入口，具体当前状态仍以 RESEARCH_STATE 与 endpoint/closure 为准。

## 1. Program map

| Line | Purpose | Current state | Dependency / gate | Notes |
|---|---|---|---|---|
| Track B — Execution State | fork / continuation / representation lifecycle | CLOSED / FROZEN | Historical closure | 不自动重开 |
| Track E — Residency | residency policy / P3 / nodes-out | CLOSED / SEALED / archived | Historical closure | 不自动重开 |
| P4 / RQ-P4-01 | 核心驻留结构/状态机制 | NOT STARTED | 独立 Definition gate | 不因 Track E closure 自动开启 |
| Source/Runtime / RQ-F-01 candidate | 真实 Swift/MLX runtime 中的机制存在性与可验证性 | NOT DEFINED | 当前 Definition gate → STEP⑤ | 当前唯一活跃研究定义方向 |
| Track A — Kernel/Bandwidth | workload-specific kernel opportunity | NOT STARTED / conditional | exp06 roofline gate | 不得直接实现 |
| Track D — Adaptive Memory | dynamic memory budget / pressure response | NOT STARTED / independent | 独立定义 | 与 A/B/C 不形成自动依赖 |
| Track C — Multi-device | multi-device execution orchestration | FUTURE | hardware/scenario availability + independent definition | runtime2 仅占位 |

## 2. Control rules

1. Register entry ≠ RQ registration.
2. A route marked NOT STARTED / NOT DEFINED has no implementation authority.
3. CLOSED / SEALED / FROZEN lines remain historical unless a new question is independently defined.
4. A dependency expresses ordering or prerequisite knowledge; it does not transfer evidence across research questions.
5. Architecture documents may describe candidate directions; only findings/decisions with provenance may impose architecture constraints.

## 3. Program-level next gate

Current repository state points to the Source/Runtime definition sequence:

`STEP① → STEP② → STEP③ → STEP④ PASS → STEP⑤`

STEP⑤ is **existence criterion definition**, not runtime implementation or measurement.

## 4. Historical planning sources

The detailed 2.0 pre-research roadmap remains in `docs/architecture/ARCHITECTURE_2.0_PRERESEARCH_20260920.md`. This register is the navigation/control layer; it does not rewrite that historical planning document.


## 5. 2026-09-22 Architecture 2.0 direction reset

After re-examining the research from its origin, the program boundary is narrowed to **computational-architecture regularity**. Model-content regularity (knowledge, rules, semantics, probabilities, and their compression) is not the Architecture 2.0 core research object.

| Line | Revised state | Treatment |
|---|---|---|
| Track B — Execution State | CLOSED / FROZEN | **Terminal / archived.** Core lifecycle is complete within scope; do not reopen. |
| Track E — Residency / nodes-out | CLOSED / SEALED / archived | **Terminal / archived.** Historical questions complete; do not reopen. |
| P3 / H-P1 | CLOSED / SEALED | **Terminal / archived.** Historical supporting lines complete. |
| Source/Runtime / RQ-F-01 candidate | NOT DEFINED | **Retired as current direction.** Do not enter STEP⑤; its boundary/unit route is a pruned branch. |
| P4 / RQ-P4-01 | NOT STARTED | **Retained as the next candidate line.** Directly addresses Execution State → Residency / Loading; must begin with a fresh Definition gate. |
| Track A — Kernel/Bandwidth | NOT STARTED / conditional | **Dormant / non-core.** Retain only as a separate workload-specific performance line. |
| Track D — Adaptive Memory | NOT STARTED / independent | **Future independent line.** Do not auto-open from this reset. |
| Track C — Multi-device | FUTURE | **Long-horizon line.** Do not auto-open. |
| Boundary / Object / Identity / Invariant / Equivalence | Conceptual exploration | **Pruned from 2.0 mainline; preserved as intellectual history.** |

**Current core candidate chain:**

`Execution State → Residency / Loading → Layering / Working Set → Migration / Resource placement`

This is a direction map, not RQ registration.

**Important:** P4 remains NOT STARTED. No RQ is opened by this review.
