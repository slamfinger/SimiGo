# Local Closure M1.b Minimal Pair Combinations

Date: 2026-10-04  
Status: `HALTED BY BREADTH-FIRST REDIRECT / F12 RAW OUTPUT ONLY / F13 + F23 NOT RUN / NO ADJUDICATION`

## 1. Halt precedence

This branch was halted after S-B1F12 by the later breadth-first redirect. The
control record is:

```text
docs/00-governance/SIMIGO_LAB_LOCAL_CLOSURE_M1B_PAIR_BRANCH_HALT_20261004.md
```

The following original design remains preserved but is not active.

## 2. Question

After all single-field replacements failed, does a minimal two-field
combination restore M1.b's continuation function?

The alternatives are:

```text
H1 distributed fields:
   a conjunction of semantic fields is sufficient;

H2 relation/context:
   fields remain insufficient without a larger relational context;

H3 wrong decomposition:
   the tested fields do not express M1.b's actual minimal semantics.
```

## 3. Conditions

Only the three two-field combinations are authorized. Field order is frozen and
follows the prior F1/F2/F3 order. The pair decisions remain unchanged.

```text
S-B1F12:
baseline_membership.gamma = false;
baseline_relation.gamma = incompatible;

S-B1F13:
baseline_membership.gamma = false;
release_scope.gamma = excluded;

S-B1F23:
baseline_relation.gamma = incompatible;
release_scope.gamma = excluded;
```

No three-field condition, explanation, provenance, M3 content, or new scope
text is authorized.

## 4. Frozen judgment

Use only:

```text
JSON validity;
semantic-referenced;
adopted;
release decision;
deployment order;
blocker;
continuation.
```

PASS requires exactly:

```text
valid JSON;
blocked;
deployment_order = [alpha,beta];
blocked_services = gamma.
```

## 5. Readings

```text
any pair PASS
      = single-field failure did not require all three fields;
        the passing conjunction becomes the minimal tested carrier;

all pairs FAIL
      = two-field conjunctions are insufficient;
        H2/H3 remain candidates;
        three-field or relation/context work requires separate authorization.
```

No result proves universal irreducibility or final Information minimality.

## 6. Boundary

```text
Observer tool             = NOT AUTHORIZED;
InformationCore store     = NOT AUTHORIZED;
three-field condition     = NOT AUTHORIZED;
M3 expansion              = NOT AUTHORIZED;
Runtime/schema/API change = NOT AUTHORIZED.
```

```text
F13/F23 execution         = HALTED;
branch interpretation      = NOT AUTHORIZED.
```
