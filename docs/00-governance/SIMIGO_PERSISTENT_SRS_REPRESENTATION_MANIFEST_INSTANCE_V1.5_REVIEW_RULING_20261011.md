# Persistent SRS Representation Manifest Instance v1.5 Review Ruling

> **Status:** `REVISE_PERSISTENT_SRS_MANIFEST_INSTANCE_V1.5`
> **Ruling date:** 2026-10-11
> **Review authority:** Human independent review
> **Reviewed basis:** `1f4f5b089e32f12540c0aa4bf177de03c5218ce5`
> **Reviewed object:** Persistent SRS Representation Manifest Instance v1.5

## 1. Contract state unchanged

```text
Persistence Manifest Contract v1.8 = ACCEPT / DESIGN FROZEN / NO STAGE AUTHORIZED;
bound I0 JSON Schema v1.6 = unchanged.
```

Only the Manifest Instance is revised.

## 2. Prior findings confirmed fixed

```text
B10 deterministic latest-candidate selection was defined and duplicate status was
    limited to duplicate registration in the Candidate Closure Set;
B11 closure invalidation triggers, lifecycle states, and rejected-replacement
    behavior were defined.
```

## 3. New blocking findings

```text
B12 evidence_digest input scope was undefined; digesting completion_order_key
    would be circular, while excluding it without a replay rule left the derived
    key unbound;
B13 closure commits did not have to reference the unique current chain head, so
    forks could yield multiple ACTIVE versions and projection could fall back
    after invalidation.
```

## 4. Authorized next object

The only authorized next object is Manifest Instance v1.6. It must define
core canonical evidence bytes, base evidence digest, derived completion-order
key, sealed evidence digest, verification order, and one linear closure chain
with a single mutable head. It must reject forks and never fall back after
invalidation.

## 5. Continuing prohibitions

```text
IMPLEMENTATION = NOT AUTHORIZED;
FIXTURE_PREPARATION = NOT AUTHORIZED;
EXECUTION_BATCH_nn = NOT AUTHORIZED;
independent JSON Schema validator run = NOT AUTHORIZED;
independent ES2 consumption = NOT AUTHORIZED;
non-recompute attribution = NOT AUTHORIZED;
marker creation = FORBIDDEN;
evidence-root creation = FORBIDDEN;
canonical PALACE mutation = FORBIDDEN;
canonical Information Space mutation = FORBIDDEN;
MLX execution = FORBIDDEN;
V6 rerun = FORBIDDEN;
production deployment / traffic = NOT AUTHORIZED.
```
