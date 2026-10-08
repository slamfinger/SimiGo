# SRS-REAL-CLOSURE-01 — Database-Carrier / PALACE PIR RM-001 Implementation & Fixture Preparation Completion Record 028

> **Status:** COMPLETE — IMPLEMENTATION PASS / FIXTURE PREPARATION PASS
> **Date:** 2026-10-08
> **Governing Request v2.5:** `f6a0e5e17e8d5ce0a130f8a58de0dd824384a2f2`
> **RM-001 accepted package:** `f777f2959591fc17606948b1dd8ecb7ac712d3f2`
> **MINIMAL-PIR-EXP-001:** NOT AUTHORIZED / NOT EXECUTED

## 1. Implementation result

The frozen Minimal PIR Probe v0.2 preparation contract is implemented in:

```text
docs/02-evidence/es-is-20261005/PIR_RM001_IMPLEMENTATION/implementation/pir_probe.py
```

It provides synthetic fixture construction, isolated archive handling, locator
and digest verification, deterministic opaque IDs, oracle separation, evidence
destination binding and fail-closed self-check. It does not perform
reconciliation observations, semantic inference, IS mutation or experiment
execution.

```text
implementation self-check = PASS;
fixture legality = PASS for E-L, E-S, C-NOCHANGE-L, C-NOCHANGE-S;
oracle isolation = PASS;
attribution separation = PASS;
physical observations generated = 0;
IS mutations = 0;
experiment output leak = NONE.
```

## 2. Fixture result

Four fixture sets are prepared:

```text
E-L           N=10,000, R=20, M=5;
E-S           N=20,     R=20, M=5;
C-NOCHANGE-L  N=10,000, R=20, M=0;
C-NOCHANGE-S  N=20,     R=20, M=0.
```

Each includes an isolated post-change physical-state archive, measured input,
sealed oracle ledger, public fixture manifest and EV-P01..EV-P18 destination
binding. The measured input excludes role, planted-change ledger, expected
verdicts, oracle output and control-side cost. Fixture preparation generated no
physical observations.

## 3. Fixture bindings

```text
E-L: archive=4ab5a70bf405cd1c5be0781e12d11a5585efedc11a9b2bd0e022eefc212d5058; measured_input=a0e136dc9c144fc6f80c25be6ca8335ba6431a8c25b364a72474cff8d4539124; oracle=b70a953db032e81d9d62d88c65dedc1aff6958e076e6c48b544df7e2f35aedb3; manifest=37296eec7084e2f98e7d90e3660ebd847ebb0bdbf5700057017c6c66a279c1cf
E-S: archive=869849eb1d745190c7900e209cf108a14fe71155f10753dc7af723209a59b17d; measured_input=cb7084a54f4665b17a71974042ccf0b850d15c7a2b9865f7fca0d08e75e81ae3; oracle=6106983fb7e06e639e752b911f07247e0b78aa1876410b9cbc48f4794dcf6751; manifest=0b522afe42aeef8c744cbc85f64a0afa55cd7f0c44fd31d74c01a04706b85bfb
C-NOCHANGE-L: archive=5855efbb379e39fae776f9d9bb3374a0ad9556516c40a8beda3c31bbe47b4e1e; measured_input=6a4dd858ba278b6fb899b45d37722643035f627a1ac3f0a3790300d50b10a6cd; oracle=083a90545d7b3ae119e0ade35d1bb7d91da1543e68bbe417c114c6f3e48ecf58; manifest=3a8af2df1d8ae71d9bc427b20f3b15e94b080eedcb262562158ccb3cf275971a
C-NOCHANGE-S: archive=f4f78c889071cbf8ddb55bbc58a45d19a985c138a12dda644c01acb1e6de1da3; measured_input=833cf5b469d1634fe682b713b7d2f8e871ad6a5f7e4f10ed2709cbc8c8598c39; oracle=dac0840446abf4c639fc3b0a951384a6677d00a3ab1a6dd8214f9faa4000fcd9; manifest=6b13d5b2e772b317c83db34d6e9763ed2f41fb7ceb9242d5800168f71c7955a0
```

## 4. Validation artifact

```text
implementation SHA256 = 1fa3a88b03e95cf59c3c258cc70e9cf1bec2e5a17f9fccdfeac8ac0abc714fe0;
self-check artifact SHA256 = f71003192b3f73c2c90691bacb5598252f2fc32713eb2005366de977792c002d;
self-check result = PASS;
```

## 5. Authorization boundary

```text
RM-001 package = ACCEPTED;
implementation/fixture preparation = COMPLETE;
MINIMAL-PIR-EXP-001 execution = NOT AUTHORIZED;
physical reconciliation observations = NOT AUTHORIZED;
IS mutation = NOT AUTHORIZED;
E9 / Database-Carrier work = NOT AUTHORIZED;
automatic experiment launch = FORBIDDEN.
```

## 6. Next lawful object

The next lawful object is separate **Experiment Launch Review**. The Human may
DENY `MINIMAL-PIR-EXP-001` or explicitly authorize its execution with the
already accepted RM-001 boundaries and fresh fixtures. No execution authorization
is granted by this record.

## 7. Record integrity

```text
record_integrity_binding = registered by the canonical commit introducing this
record; later modification creates a new content address and voids this
completion record.
```
