# Local Closure S-B Condition Prompts Instantiated

Date: 2026-10-04  
Status: `S-B0/S-B1/S-B2 PROMPT ARTIFACTS INSTANTIATED / EXECUTION NOT AUTHORIZED / OBSERVER AND STORE NOT AUTHORIZED`

## 1. Authorization

The human authorized only instantiation of the three direct-inline B prompt
conditions after the First B Panel review passed with narrowing amendments.

The authorization boundary is:

```text
instantiate S-B0;
instantiate S-B1;
instantiate S-B2;
STOP.
```

The authorization does not cover execution, runtime isolation, Observer,
Candidate Information store, Execution B, or any InformationCore/schema,
RelationCore, RuntimeMemory, bridge, or Cloud change.

## 2. Condition artifacts

The frozen prompt bytes are:

```text
docs/02-evidence/local-execution-information-closure/task-carrier-tc-a/condition-prompts/S-B0.prompt.txt
docs/02-evidence/local-execution-information-closure/task-carrier-tc-a/condition-prompts/S-B1.prompt.txt
docs/02-evidence/local-execution-information-closure/task-carrier-tc-a/condition-prompts/S-B2.prompt.txt
```

SHA-256:

```text
19c31ffa77349cf7285bab58951e3207413d3fea4a6f0f290826c3f686f945f4  S-B0.prompt.txt
531a71657557918f7a32b60b3e06a1921f9b5d985967924ae31f9551ca1a1d7d  S-B1.prompt.txt
756b1f0907e15b7c68c4c3c9450c2bf511f73de117cc48eb2f5cb5c3a6478f4f  S-B2.prompt.txt
```

The original sealed `execution-b-template.md` remains unchanged.

## 3. Frozen condition mapping

```text
S-B0 = no supplied compatibility residue;
S-B1 = M1.b(gamma is not baseline-compatible)
     + M2.b pair compatibility decisions;
S-B2 = M2.b pair compatibility decisions
     + explicit gamma blocked decision
     - M1.b gamma baseline decision.
```

The exact S-B0 → S-B1 difference is only the addition of the S-B1 residue
block. The exact S-B1 → S-B2 differences are only removal of:

```text
gamma is not baseline-compatible;
```

and addition of:

```text
gamma         = block.
```

Exact whitespace and field order are frozen in the prompt bytes.

## 4. Prompt leakage control

All three prompts identify the agent only as `Execution B`; they contain no
condition ID, A identity, A transcript, A result, source file access, tool
evidence, Runtime evidence, or InformationCore fetch surface.

The inherited B template's final-output example contained the answer-shaped
values `alpha`, `beta`, `gamma`, and `baseline incompatible`. To prevent that
example from becoming hidden task residue, the instantiated conditions use a
neutral placeholder schema and a neutral absence error:

```text
{"release_decision":"...","deployment_order":["..."],"blocked_services":[{"service_id":"...","reason":"..."}]}
```

```text
{"release_decision":"blocked","deployment_order":[],"blocked_services":[],"error":"compatibility residue unavailable"}
```

This preserves the required output shape and key order without smuggling the
expected deployment order, blocker, or baseline reason into S-B0 or S-B2.

## 5. Current state

```text
Prompt artifact review   = NOT YET PERFORMED;
Runtime isolation        = NOT AUTHORIZED;
Execution S-B0           = NOT AUTHORIZED;
Execution S-B1           = NOT AUTHORIZED;
Execution S-B2           = NOT AUTHORIZED;
Observer                 = NOT AUTHORIZED;
Store                    = NOT AUTHORIZED;
Execution B              = NOT AUTHORIZED.
```

The next step is human review of these exact prompt artifacts and, only after a
separate authorization, preparation of the isolated execution frame.
