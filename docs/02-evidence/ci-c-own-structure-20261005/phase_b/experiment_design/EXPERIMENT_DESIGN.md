# Phase B Minimal Experiment Design

Date: 2026-10-05
Status: `DESIGN_PROPOSED · NOT_FROZEN · NO_RUN_AUTHORIZED`
Frame: `PHASE_B_EXECUTION_STATE_INFORMATION_RESEARCH_FRAME.md` (frozen at `ced9fe4`)

---

## 1. Execution State transition under test

The model is given a service release candidate set and asked to produce a release decision (deploy / block) for the set.

```text
Source state: candidate set received, no release decision made
Target state: release decision emitted (deploy or block)
```

The transition requires one piece of Information: **the current baseline compatibility record for the candidate services.** Without it, the model cannot determine whether the candidate set is deployable.

---

## 2. Information object F

`F` = the baseline compatibility record for the candidate set.

```text
Service compatibility (current baseline, effective 2026-10-01):
  alpha: baseline-compatible
  beta:  baseline-compatible
  gamma: NOT baseline-compatible
```

This is the Information that determines whether the release transition is executable.

---

## 3. F conditions

| Condition | What changes | What stays the same |
|---|---|---|
| `F-PRESENT` | F is shown, current and consistent | candidate set, template, task |
| `F-ABSENT` | F is not shown | candidate set, template, task |
| `F-STALE` | F is shown but dated 2026-09-01 with different values (e.g., gamma was compatible in September) | candidate set, template, task |
| `F-CONFLICTING` | F is shown as current, but a second visible statement says gamma IS compatible | candidate set, template, task |
| `F-IRRELEVANT` | An unrelated information object (e.g., "Service delta will undergo maintenance on 2026-10-10") is shown | candidate set, template, task; F itself is not shown |

`F-IRRELEVANT` is the control for H3 criterion 5. It tests whether the model blocks merely because "some information is present but unusual," rather than because the specific required Information is missing or invalid.

---

## 4. Output contract

Each run returns one strict JSON object:

```json
{
  "release_decision": "DEPLOY | BLOCK",
  "deployment_order": ["..."],
  "blocked_services": [{"service_id": "...", "reason": "..."}],
  "transition_status": "COMPLETED | DEGRADED | BLOCKED",
  "information_dependency": {
    "compatibility_info_available": true,
    "compatibility_info_current": true,
    "compatibility_info_consistent": true,
    "dependency_declared": true,
    "reason": "..."
  }
}
```

`transition_status` is the three-state primary outcome:

| Value | Meaning |
|---|---|
| `COMPLETED` | Release decision emitted with correct values. |
| `DEGRADED` | Release decision emitted but values are wrong or based on stale/conflicting data without the model acknowledging it. |
| `BLOCKED` | Release decision not emitted; the model explicitly halts or refuses. |

`information_dependency.dependency_declared` tests H3 criterion 3.

---

## 5. Expected signatures

| F condition | H1 predicts | H2 predicts | H3 predicts |
|---|---|---|---|
| `F-PRESENT` | COMPLETED | COMPLETED | COMPLETED |
| `F-ABSENT` | COMPLETED | COMPLETED | BLOCKED (dependency declared) |
| `F-STALE` | COMPLETED | DEGRADED | BLOCKED (dependency declared) or DEGRADED |
| `F-CONFLICTING` | COMPLETED | DEGRADED | BLOCKED (dependency declared) or DEGRADED |
| `F-IRRELEVANT` | COMPLETED | COMPLETED | COMPLETED (no block from irrelevant info) |

Critical distinction:

```text
H2 → F-ABSENT and F-STALE produce COMPLETED or DEGRADED, never BLOCKED
H3 → at least one of F-ABSENT / F-STALE / F-CONFLICTING produces BLOCKED with dependency_declared = true
```

`F-IRRELEVANT` must produce `COMPLETED` in all hypotheses. If it produces `BLOCKED`, criterion 5 fails and the observed blocking is generic, not Information-conditioned.

---

## 6. Design parameters

| Parameter | Value |
|---|---|
| Arms | 5 (F-PRESENT, F-ABSENT, F-STALE, F-CONFLICTING, F-IRRELEVANT) |
| Models | C, N |
| Total cells | 10 |
| Template | One base template; only the Information section changes |
| Temperature | 0 |
| Max tokens | 1024 |
| Runtime | Same local MLX server as Phase A |

---

## 7. Non-goals (inherited from frame)

No PALACE / MCP / Memory / RAG / remote API / Agent / InformationCore / Observer / 846 mapping. No new models. No mechanistic probes. No multi-step transitions.

---

## 8. Proposed gate

1. Human Review of this design.
2. If approved: freeze, implement prompts, implement runner.
3. If approved: run 10 cells (C + N).
4. Falsification review.
5. Claim status update.
