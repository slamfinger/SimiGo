# Authorization Object Decision

Date: 2026-10-05  
Decision type: `HUMAN_CONCEPTUAL_DECISION`  
Status: `OPTION_C_SELECTED · EXPERIMENT_DESIGN_NOT_AUTHORIZED`

## Decision

The Authorization research object is the **two-layer combination**:

```text
Information
    ↓
A_epistemic
    是否有资格被采纳为 premise / evidence
    ↓
A_execution
    是否有资格进入 execution path
    ↓
Relational Executable Function
    ↓
Continuation
```

Therefore, the object previously abbreviated as Authorization is not yet a single undivided
boundary. Under this decision, it must be treated as a layered combination of:

```text
A_epistemic = premise / evidence adoptability
A_execution = execution-path eligibility
```

## Consequences

1. ARES remains a hypothesis and is not updated.
2. The prior four-cell result remains `AMBIGUOUS`.
3. The prior run is understood as touching only the declared/provenance side of
   `A_epistemic`; it did not establish control over `A_execution`.
4. No equivalence between the two authorization layers is claimed.
5. No two-layer experiment is authorized by this decision.

## Current freeze

```text
Authorization object = OPTION_C_TWO_LAYER
ARES update = NONE
Experimental brake = ACTIVE
Next gate = separate human decision on whether to design a two-layer experiment
```

## Boundary

No leakage or fallback experiment is designed.  
No model run is authorized.  
No 846 atom is mapped, merged, deleted, or rewritten.  
No Observer is run.  
No InformationCore write occurs.  
No minimal Information Core is declared.
