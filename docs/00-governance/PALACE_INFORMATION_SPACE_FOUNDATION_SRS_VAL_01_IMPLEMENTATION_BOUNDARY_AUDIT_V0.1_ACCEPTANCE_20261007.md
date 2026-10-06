# SRS-VAL-01 Implementation Boundary Audit v0.1 Acceptance

> **Status:** Implementation Boundary Audit v0.1 = **ACCEPT / FROZEN**
> **Review date:** 2026-10-07
> **Review authority:** Human independent review
> **Reviewed basis:** `cb95c09`
> **Accepted target:** `T-IMPL-01 SRS-VAL Decision Core` as the minimal Implementation Boundary
> **Next object:** Run/Implementation Manifest v0.1 — DESIGN ONLY / NOT AUTHORIZED
> **SRS-VAL implementation / fixture / experiment:** NOT AUTHORIZED
> **IS mutation:** NOT AUTHORIZED
> **SimiGo code change:** NOT AUTHORIZED

## 1. Ruling

```text
T-IMPL-01 SRS-VAL Decision Core      ACCEPT / FROZEN
Minimal Implementation Boundary      ACCEPT / FROZEN

Carrier / SQLite / ExecutionCore /
MLX/LLM / observer / runner /
fixture builder / IS mutation executor  OUT OF MINIMAL TARGET

Four-stage separation                PRESERVED
Fixture / Manifest mapping           ACCEPTED
Adversarial pre-review checklist     ACCEPTED

Implementation                       NOT AUTHORIZED
Fixture preparation                  NOT AUTHORIZED
Execution                            NOT AUTHORIZED
IS mutation                          NOT AUTHORIZED
SimiGo code change                   NOT AUTHORIZED
```

The Human verified that Audit v0.1 defines a separately provable semantic core:

```text
Exact Validation Invocation
  → T-IMPL-01 SRS-VAL Decision Core
  → REUSE | BLOCK | RECOMPUTE
```

It does not smuggle carrier, SQLite, ExecutionCore, MLX/LLM, observer, runner, or
IS mutation into the first implementation boundary.

## 2. Mandatory implementation-contract additions

These constraints do not amend SRS-VAL v0.8 or Authorization Package v0.6. They
are binding requirements for Run/Implementation Manifest v0.1 and later stage
contracts.

### 2.1 Predicate Rule and Decision Core are separate bindable artifacts

```text
Registered Predicate Rule Artifact
  ↓ exact immutable binding
Decision Core
  ↓ interprets/applies
classified failure
```

The Decision Core must not name, version, hash, register, or authorize itself as
the predicate rule. Manifest v0.1 must bind:

```text
predicate_rule_identity;
predicate_rule_version;
predicate_rule_content_address;
covered_failure_classes;
rule_registration_authority;
Decision-Core → Rule exact binding.
```

### 2.2 Deterministic derivation trace is not observer evidence

Decision Core output must be labeled:

```text
DETERMINISTIC_SEMANTIC_DERIVATION_TRACE
```

It is not `OBSERVER_AUTHORITATIVE_EXECUTION_EVIDENCE`. Authoritative execution
evidence still comes only from:

```text
Subject
  → Independent Observer
  → Observation Integrity Boundary.
```

### 2.3 Invocation Record must be a closed immutable value graph

The entire invocation input must be resolved before entering T-IMPL-01. It must
not contain lazy resolvers, file/database/actor handles, callbacks, environment
lookups, clocks, global registries, or mutable references.

## 3. Next object

```text
Run/Implementation Manifest v0.1
STATUS = OPENED FOR DESIGN ONLY / SUBMITTED FOR HUMAN REVIEW
```

No code may be written. No fixture may be prepared. No execution may occur.

## 4. Continuing prohibitions

```text
SRS-VAL implementation       NOT AUTHORIZED
SRS-VAL fixture              NOT AUTHORIZED
SRS-VAL experiment           NOT AUTHORIZED
IS mutation                  NOT AUTHORIZED
SimiGo code change           NOT AUTHORIZED
```
