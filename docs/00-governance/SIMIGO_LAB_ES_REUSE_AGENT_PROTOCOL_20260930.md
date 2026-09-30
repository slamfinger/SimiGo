# SimiGo-Lab — Local Agent Protocol for Execution State Reuse

Date: 2026-09-30
Status: ACTIVE
Scope: ES-R1 and later Execution State Reuse experiments

## 1. Role separation

The research architect owns:
- hypothesis
- experiment question
- pre-registration
- phase authorization
- gate decision
- evidence interpretation
- scope control.

The local agent owns:
- code inspection
- test/harness implementation after authorization
- execution
- raw evidence capture
- exact reporting.

The agent must not independently:
- invent a new research hypothesis;
- redesign the semantic model;
- create a new durable State schema to rescue a failed experiment;
- convert an inconclusive result into a success;
- optimize before semantic proof;
- modify unrelated production behavior.

## 2. Current authorization

AUTHORIZED NOW:
Phase A — read-only fact trace.
Phase B — baseline and representation-loss boundary preparation using disposable copies/fixtures.

NOT AUTHORIZED:
Phase C destructive execution against real durable storage.
New persistence schema.
New ExecutionState object.
Production API redesign.
Performance optimization.
Cross-backend takeover.
PALACE schema design.

Phase C can be authorized only after the Phase A/B report is reviewed.

## 3. Phase A deliverable

Produce a fact trace covering:
- ExecutionID and identity sources
- lineage
- logical position
- continuation information
- RepresentationRef
- BindingRegistry
- physical representations
- restore/materialization/attach entry points
- generation/commit information
- backend-specific dependencies

Classify each as:
D Durable Semantic State
R Runtime Binding
P Physical Representation
O Observability/History
T Transient/Reconstructable
U Unknown

For each item state:
OBSERVED / INFERRED / UNKNOWN.

Do not rename architecture concepts merely to fit the table.

## 4. Phase B deliverable

Using a disposable copy/fixture:
- record pre-loss State and Representation identity;
- establish a deterministic continuation baseline;
- define exactly which Representation will be removed;
- enumerate what remains after removal;
- identify which existing APIs could consume the remaining State;
- document all safety controls.

No real durable store may be modified.

## 5. Required raw evidence

Every run must capture:
- timestamp
- git commit
- build configuration
- model/backend identity
- experiment fixture identity
- State identity
- logical position
- Representation identity
- exact probe
- execution trace
- full-history read: yes/no
- full-prefill: yes/no
- materialization/rebind operations
- output/result
- error and first failure seam
- artifact hash where applicable.

## 6. Failure reporting format

Never report only:
“reuse failed.”

Report:

State identified: YES/NO
Position identified: YES/NO
Lineage identified: YES/NO
Representation loss confirmed: YES/NO
New binding attempted: YES/NO
Materialization attempted: YES/NO
First missing seam: <exact concrete seam>
Full history used: YES/NO
Full prefill used: YES/NO
Result classification: R1-A/B/C/D candidate
Confidence: <bounded>

## 7. Experimental purity

A successful reuse experiment must demonstrate that continuation did not secretly fall back to:
- full history reconstruction;
- full cold prefill;
- an undeclared surviving Representation;
- a hidden durable copy of the removed Representation.

If any such fallback occurs, report it as a deviation and do not count the run as R1-A.

## 8. Evidence preservation

Keep raw output separate from interpretation.
Never overwrite raw evidence.
If a harness is corrected, retain the failed run and record the correction as an infrastructure deviation.

Negative results and first-failure seams are first-class evidence.

## 9. Reporting to research architect

At the end of each phase return:
1. what was inspected/run;
2. exact commit;
3. raw evidence locations;
4. observed facts;
5. deviations/anomalies;
6. first missing seam;
7. proposed gate classification;
8. what remains unknown;
9. exact next action required.

Do not continue into the next phase merely because the current phase completed.

## 10. Scope discipline

One experiment at a time.
One gate at a time.
Solve the first missing seam only.
Do not bundle unrelated fixes.

The guiding research method is:

工程事实 → 发现问题 → 抽象 → 语义 → Contract → 工程验证

For this track, the abstraction must be earned by the experiment.
