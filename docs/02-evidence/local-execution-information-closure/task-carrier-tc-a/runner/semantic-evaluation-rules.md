# TC-A Semantic Evaluation Rules

These rules run only after Execution A and Execution B. The expected register
is not available to the Agent workspace.

## 1. Execution A register check

Score A's final answer only if it is the exact bytes stored as Candidate
Information.

Required service readings:

```text
alpha: baseline_compatible = true
beta:  baseline_compatible = true
gamma: baseline_compatible = false
```

Required pair readings:

```text
alpha ↔ beta:  compatible
alpha ↔ gamma: incompatible
beta ↔ gamma:  incompatible
```

Issue wording may differ, but each incompatible pair must identify at least one
true cause. Acceptable causes include individual baseline incompatibility,
API version mismatch, and port conflict.

## 2. Execution B check

B must fetch Stored Information. Its final answer is continuation-supported
only if all of these hold:

```text
release_decision = blocked or partially released;
alpha and beta appear before or instead of gamma in deployment_order;
gamma is blocked, absent from deployment_order, or explicitly deferred;
each blocked/deferred gamma decision cites baseline incompatibility,
API mismatch, or a pair conflict involving gamma.
```

A correct B answer may be:

```json
{"release_decision":"blocked","deployment_order":["alpha","beta"],"blocked_services":[{"service_id":"gamma","reason":"baseline incompatible"}]}
```

Issue wording may differ if the cited cause is true.

## 3. Reading boundary

If A's register is materially wrong, record the A error separately. If B then
propagates that error, record propagation separately. Do not treat B's faithful
use of a wrong register as failure to use Stored Information.
