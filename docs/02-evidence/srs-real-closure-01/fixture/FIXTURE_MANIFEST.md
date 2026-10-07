# SRS-REAL-CLOSURE-01 — FIXTURE_MANIFEST

> **Status:** FIXTURE PREPARATION COMPLETE — ARTIFACT BINDINGS
> **Date:** 2026-10-07
> **Authorization:** SRS_REAL_CLOSURE_01_SAR_FIXTURE_PREPARATION_001 @ `4c3def8`
> **Bound design:** SRS-REAL-CLOSURE-01 Design v0.2 (blob `a28e8d9b…`, sha256 `d43792b5…`)
> **Bound implementation artifact:** T-IMPL-01 SettledRelationValidationCore
> (canonical components per completion record §2; verified byte-identical
> during fixture build verification)

## 1. Fixture artifact bindings

```text
fixture/runner/es_runner.py
  git:blob:93e99a259054697891b153034dcfdc6f219f9651
  sha256:68899010c2edafd86f41df31ba77feed68475ff9ab73e1ed57ccdcbd8abb1427

fixture/adapter/srsval_adapter.swift
  git:blob:1573ae9eb7c7b334589a6ac901ea1889a20703a0
  sha256:61b8ad39c467ed7ff90e4d8670ea903bf7be12e20166c7cff21df4bdbf0231ac

fixture/adapter/BUILD.md
  git:blob:8573c1a60ce304323e582db6f5073e9435303740
  sha256:af2384b0bf20ae73d8fdcee1a929a273d6e052666cc36ac2b3314ae38779d2ba

fixture/schema/validate_srs.py
  git:blob:8c8fd9e8f87175debf77c485d7169e4e46c5e50b
  sha256:c1d75a7592652ba8eeb3831d734701b4494e6be0b14b0a6a295261fbe8822422

fixture/is_layout/IS_LAYOUT.md
  git:blob:4ea38dd5b81bb5a99f8e82ee5379939a30008d6b
  sha256:68f0590f273f644f75c8120f5721220b027d345b9bde1f9ef079bc71a9bdf113

fixture/inputs/D.md
  git:blob:f39361db5ac4c583287b1ae15d75e928f3bedfab
  sha256:806fffadef09d3ad491d75c6b42738e99626ee1961ed1aecf2d593aefd55980c

fixture/inputs/D_prime.md
  git:blob:daaeae4eb3dab4ad52bba2214ea29eddeee0a2b8
  sha256:8553f52449b67de21021bb50ad6380c455bf686ee2a06cc77ed51e9f30060955

fixture/tau/tau1.json
  git:blob:678bdec2fd2911e9df317a2a0cac16b8de1ce5d1
  sha256:bc31ce63e764aa79068fccf232767648d3b79eb1c15a57faf25dd0da465f63b0

fixture/tau/tau2.json
  git:blob:4b4aae5986abca0505306fd28cab51eec99b95c5
  sha256:bb8122d34d3bec16494cdeeee840f45140645eb54ae232dfb47721e02531e464

fixture/tau/tauN1.json
  git:blob:eda97c2ae1ff6e1c74e464ee6c30d36413180ea4
  sha256:fe211518e4082636b4ce3c34aabf96406308b68719ce4be47d6e3f66564fdd3f

fixture/observer/observer.py
  git:blob:248d3003c08609bbe3823ae7c05fb5c8747e2b52
  sha256:787b70d9cc291cfab081d9313877c58e375249875857f36dd93da45a44a80aaa
```

## 2. Computation parameters (frozen)

```text
expensive_unit_U     = iterated hash chain sha256^N(digest(D) || identity(P));
                       exactly one ledger entry per invocation, flushed
                       before return (write-before-return)
iterations_N         = 50000
derivation_procedure = SRS-REAL-CLOSURE-01-R1 @ 1.0.0
srs_identity_rule    = SRS-CANONICAL-ID-V1 @ 1.0.0
                       (canonical serialization: sort_keys JSON, separators
                       (",",":"), ensure_ascii=False; sha256 over ALL fields
                       including provenance — D-SRS-ID-1)
request_class        = R1-continuation
boundary_ids         = B-ES2 (positive) / B-ESN (negative control)
tau_files            = tau1.json (settlement), tau2.json (reuse),
                       tauN1.json (negative control)
srs_identity_at_run  = RESOLVED_FROM_IS_INDEX_BY_ES1_OUTPUT
                       (tau2/tauN1 carry a placeholder token; the ES₁ event
                       log publishes the actual srs_identity at execution
                       time and the driver substitutes it into the τ files
                       for the later processes — substitution is recorded
                       in the driver event log)
```

## 3. IS layout declaration reference

`fixture/is_layout/IS_LAYOUT.md` — objects/, index.jsonl,
current/dependencies.jsonl (sole mutable state). Declaration only; nothing
is materialized under fixture preparation.

## 4. Adapter build contract

`fixture/adapter/BUILD.md` — pins the temporary-directory build:
canonical sources exported from `07176ec`, SHA256-verified against the
completion-record bindings BEFORE compilation, then compiled together with
the adapter (same compilation unit; adapter holds no module import).
