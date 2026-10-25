# SimiGo Research Constitution v1.0

Date: 2026-10-05
Authority: Human ruling (2026-10-05) — adopted as the project-level research governance mechanism
Scope: governs all research lines from adoption forward (line admission, promotion, session discipline, the Core/Satellite boundary). It does not rewrite sealed lines' histories, does not unfreeze anything, and does not authorize any experiment.
Amendment rule: the North Star (Article 1) is **unalterable**. Every other article amends only by explicit Human ruling registered in git.

---

## Article 0 — The constitution sentence (hard threshold)

> **SimiGo 的研究价值不以局部理论深度衡量，而以其对 Execution State ↔ Information Space 持续计算闭环的解释、实现或验证贡献衡量。**

Compressed form, usable as a veto:

> **Deep but disconnected ≠ Core.**

The question to ask of any attractive new theory is no longer "can this be pursued deeper?" but:

> **它能让 State 和 Information 更真实地耦合吗？**
> (Does it make State and Information more genuinely coupled?)

能 → Core。暂时不能，但很有价值 → Satellite。不能且与闭环越来越远 → 停止。

## Article 1 — The Core Research Spine (North Star, unalterable)

> **建立并验证一个现实可运行的、由 Execution State 与 Information Space 双向耦合形成的持续计算系统。**

"持续计算" is not a slogan. It must ultimately land as the closure loop:

```text
Information Space
        ↓  resolve / retrieve
Execution State
        ↓  execute
Trajectory / Result / New Information
        ↓  persist / index / relate
Information Space
        ↓
Next Execution   ↺
```

Every research question must be able to name the edge of this loop it lands on.

## Article 2 — Dual track: Core and Satellite

The historical failure mode is registered so it stays closed: it was never "too many good directions" — it was that **any branch that became deep enough was silently promoted to mainline**. Under this constitution that path no longer exists.

### Core — only work that directly answers one of:

```text
I → S     How does Information make State identifiable / readable / continuable?
S → I     How does Execution form new persistable information?
S ↔ I     How do the two maintain relational continuity?
S → S     How does State continue / restore / fork / incrementally execute?
I → I     How does the Information Space grow incrementally through Execution?
```

### Satellite

All research that is good and may be deep, but does not (yet) land directly on a loop edge. Satellites are **preserved — never deleted, never negated**. Only their status changes:

> **不得因为局部深度自动晋升为 Core。** (Local depth never auto-promotes a satellite to Core.)

## Article 3 — The four gates (admission requirements for Core work)

### Gate 1 — Core Relevance (must state all three)

```text
Core objective:               Execution State ↔ Information Space
Affected edge:                I→S / S→I / S↔I / S→S / I→I
Concrete system consequence:  if this problem is solved, what capability does the real system gain?
```

The third item is decisive.

- **FAIL**: "prove which of M2/M3 is philosophically more reasonable." — it cannot answer how State is saved, read, or continued.
- **PASS**: "clarify which relations must be persisted so that the next Execution can reconstruct the same continuation."

### Gate 2 — Reality Mapping (no unbounded conceptual depth on Core lines)

Every Core line must answer: **what object in the real system does this concept correspond to?** At minimum, a chain:

```text
Concept → runtime / storage artifact → read / write operation → observable capability
```

Worked form (IPAC):

```text
I/P/A/C → 持久化关系 (persisted relations) → Information Space index
        → resolve(state) → Execution State reconstructed
```

A concept that cannot find a realistic carrier may continue as a theoretical satellite, but cannot be upgraded to Core indefinitely. This gate exists to prevent exactly one failure: **the theory getting more beautiful while the reality model gets vaguer.**

### Gate 3 — Capability Delta (stated in advance)

If this research succeeds, what concretely does the system gain? Not "the theory is clearer", but:

```text
什么可以保存？ 什么可以读取？ 什么可以恢复？ 什么可以继续？
什么可以少算？ 什么可以复用？ 什么可以增量计算？ 会产生什么新的 Information？
```

Reference example of a good delta: artifacts → R1 → next task references R1 directly → **避免重复读取和重复计算，实现后续增量计算** (avoid duplicate reads and duplicate computation; enable subsequent incremental computation). This is a real capability.

### Gate 4 — Core Closure (post-completion review)

On completion, re-answer:

```text
它在闭环哪里？                              Where in the loop does it land?
它是否让下一个 Execution 更容易发生？          Does it make the next Execution easier to occur?
它是否让 Information Space 更丰富？           Does it make the Information Space richer?
它是否让 State ↔ Information 关系更明确？     Does it make the S↔I relation clearer?
它是否改变我们对 保存→读取→继续→再产生 的理解？ Does it change our understanding of save→read→continue→produce?
```

If all answers are "not obviously": **research complete, archived as Satellite. No automatic next round.**

## Article 4 — Satellite states (three, not a binary OPEN/CLOSED)

```text
SUPPORTING    directly supports Core (e.g., the F phenomenon)
EXPLORATORY   valuable research, but no proven direct Core relation yet
PAUSED        the research itself is sound, but continuing it does not improve Core closure completeness
```

**PAUSED is not failure.** It is a state a mature research program must allow to exist. Initial classifications: Article 7.

## Article 5 — Promotion requires a repatriation proof (回迁证明)

A Satellite re-promoting to Core must answer: **它改变了 Core Research Map 中哪一条边？** (Which edge of the Core Research Map does it change?)

Worked example (Admissibility): if it ever shows

```text
F relation → 决定 State 是否能继续 → 必须被持久化
```

then it directly changes the **I → S** edge and re-promotes — no longer an independent philosophical question, but **"Information → State continuation 的必要条件机制"** (the necessary-condition mechanism of Information → State continuation). That is the correct form of repatriation. Until such a proof exists, it stays a satellite.

## Article 6 — Mandatory session header (five lines, every research session)

```text
Core target:
Affected closure edge:
Real system object:
Expected capability delta:
Stop condition:
```

Worked example:

```text
Core target:               State ↔ Information continuity
Affected closure edge:     I → S
Real system object:        persisted state relations / information index
Expected capability delta: future execution can reconstruct continuation without recomputing history
Stop condition:            if no physical representation or capability change is found, downgrade to Satellite
```

## Article 7 — The research map (as of adoption)

```text
                    SimiGo Core Goal
                          │
        Execution State ↔ Information Space
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
       I→S               S→I              S↔I
        │                 │                 │
   resolve/read      trajectory→info    IPAC / relations
   continuation      result/provenance  admissibility
        │                 │                 │
        └─────────────────┼─────────────────┘
                          │
                  Continuous loop
                          │
                  Next Execution
```

Core (active):

```text
CORE
├─ ES↔IS line (conceptual)   ACTIVE — Core Reference Scenario required before any
│                            open question is deepened (Article 8.1)
└─ IPAC                      CORE BRIDGE — upgraded question adopted (Article 8.2)
```

Satellites (preserved, governed):

```text
SATELLITE RESEARCH
├─ Admissibility              PAUSED / SATELLITE  (closed loop complete; repatriation proof pending)
├─ M2 / M3                    EXPLORATORY  (predication fork; observationally unresolved)
├─ Evaluation Signature       EXPLORATORY  (D-SIG-1..3 frozen)
├─ Anchor theory              EXPLORATORY  (definition gate pending)
├─ Mutation locality          EXPLORATORY  (registered variable)
├─ Cross-backend              EXPLORATORY  (ES-line bounded results)
├─ 846 / CI-C                 EXPLORATORY  (own fixture, own boundaries)
└─ other exploratory branches EXPLORATORY
```

**旁支不是废弃，是被治理。** (Satellites are not discarded; they are governed.)

## Article 8 — Immediate applications at adoption (registered rulings)

1. **ES↔IS line**: the five open questions of spec v0.1 are **set aside until a Core Reference Scenario exists**; every v0.1 concept must answer *"我在这个 scenario 里到底解决哪一个问题？"*; concepts without a position are set aside. Delivered: `docs/02-evidence/es-is-20261005/CORE_REFERENCE_SCENARIO.md`.

2. **IPAC promoted to Core Bridge.** The research question upgrades from "is IPAC minimal?" to:

   > **哪些关系必须被保存，才能让一个已结束的 Execution State 在未来被重新解析成一个可继续的计算对象？**
   >
   > (Which relations must be saved, so that a finished Execution State can be re-parsed — in the future — into a continuable computational object?)

   "IPAC is minimal" becomes a sub-question beneath this, not the north star. The ES line's boundings on IPAC carry unchanged (OPEN / NONBINDING / minimality unproven / semantics NOT FROZEN) — this reframing changes the *aim*, not any freeze status.
