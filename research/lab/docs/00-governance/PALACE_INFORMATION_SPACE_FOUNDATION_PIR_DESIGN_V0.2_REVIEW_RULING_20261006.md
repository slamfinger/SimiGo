# PIR Design v0.2 Review Ruling

> **Status:** PIR Design v0.2 = **CONDITIONAL PASS**
> **Review date:** 2026-10-06
> **Review authority:** Human independent review
> **Reviewed basis:** `ce10827`
> **Required follow-up:** five definitional clarifications, not architectural redesign
> **Implementation:** NOT AUTHORIZED
> **Experiment:** NOT AUTHORIZED

## 1. Ruling

```text
PIR Query-Priority Direction              PASS / ACCEPTED
Architecture Principle                    PASS
Passive Information Space                 PASS
Query-Priority Reconciliation             PASS
HOT/COLD logical model                    PASS
ICAC direction                            PASS
No-new-backend boundary                   PASS
Governance separation                     PASS
R01 compatibility                         PASS

PIR Design v0.2                           CONDITIONAL PASS
Query Scope semantics                     NEED CLARIFICATION
Scope vs reconciliation measurement       NEED CLARIFICATION
ICAC scalar definition                    NEED CLARIFICATION
Freshness Window semantics                NEED CLARIFICATION
Historical/COLD classification            MINOR CLARIFICATION
```

The issues are measurement/semantic boundaries. They do not require an
architectural redesign, implementation, or experiment.

## 2. Accepted architecture

The following remain accepted:

```text
no whole-space continuous synchronization;
Index/Summary narrow scope but are not physical facts;
Physical Reconciliation is required for freshness;
non-current Query Scope information may defer reconciliation;
Information Space remains passive;
Reconciliation Sub-Agent has no business-judgment authority;
HOT/COLD is logical, not a new backend/store/schema;
ICAC is a later performance-research direction;
10k/20/5 is design direction only and is not commissioned.
```

## 3. Required clarifications

```text
F1  Query Scope must distinguish known Information Scope from the Physical
    Scope needed to discover create / move / rename / unregistered objects.

F2  Scope Resolution and Physical Reconciliation must be measured separately.

F3  ICAC is a cost vector / decomposition, not a single scalar formed by
    adding heterogeneous units.

F4  Freshness Window must distinguish physical-state age from
    query-to-fresh-closure latency budget.

F5  HOT/COLD is request-relative. Historical Information is not inherently
    COLD.
```

After these clarifications are reviewed, the next separate artifact would be a
Minimal PIR Probe Design. That design remains not commissioned by this ruling.

## 4. Continuing prohibitions

```text
PIR implementation        NOT AUTHORIZED
PIR experiment            NOT AUTHORIZED
fixture creation          NOT AUTHORIZED
filesystem access trial   NOT AUTHORIZED
SimiGo code change        NOT AUTHORIZED
Probe v0.3 rerun          NOT WARRANTED
```
