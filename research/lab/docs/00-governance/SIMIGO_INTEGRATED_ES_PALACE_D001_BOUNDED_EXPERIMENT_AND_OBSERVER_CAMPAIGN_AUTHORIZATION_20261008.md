# Integrated ES–PALACE D-001 Bounded Experiment and Observer Campaign Authorization

> **Status:** AUTHORIZED — BOUNDED EXPERIMENT + OBSERVER CAMPAIGN ONLY
> **Date:** 2026-10-08
> **Authorization ID:** `INTEGRATED-ES-PALACE-D001-BOUNDED-EXPERIMENT-AUTH-001`
> **Canonical base:** `fcb19f65396149dd373a7aeaa34d0f0a27a4a78c`

## 1. Human ruling

The Human ruled:

```text
现在开 D-001 bounded experiment + observer campaign；
不开放 mutation/E9/EXP-004。
```

Normalized ruling:

```text
OPEN D-001 BOUNDED EXPERIMENT + OBSERVER CAMPAIGN;
CANONICAL IS MUTATION REMAINS NOT AUTHORIZED;
E9 REMAINS NOT AUTHORIZED;
EXP-004 REMAINS NOT AUTHORIZED;
PIR REMAINS CLOSED.
```

## 2. Authorization scope

This ruling authorizes one fresh, read-only, bounded D-001 campaign against the
seven already-frozen fixture roots. It authorizes:

```text
one experiment run;
one independent observer campaign;
one reconciliation record;
one bounded claim record;
write-once evidence closure.
```

It does not authorize repair, rerun, fixture mutation, implementation mutation,
canonical IS mutation, observer-campaign renewal, scope broadening, or automatic
follow-on.

## 3. Continuing prohibitions

```text
canonical IS mutation       = NOT AUTHORIZED;
E9                          = NOT AUTHORIZED;
EXP-004                     = NOT AUTHORIZED;
PIR                         = CLOSED / VALIDATION DEFERRED;
CarrierSQLite semantic change = NOT AUTHORIZED;
E8 ruling change            = NOT AUTHORIZED;
R01 closure change          = NOT AUTHORIZED;
P1–P7 semantic change       = NOT AUTHORIZED;
PALACE equivalence claim    = FORBIDDEN;
general ES theorem          = FORBIDDEN;
production SimiGo validity  = FORBIDDEN;
LLM autonomy                = FORBIDDEN.
```

## 4. Permissible bounded claim

If experiment and observer reconcile, the only permissible claim is:

```text
For the pre-registered D-001 fixture configuration, Execution State produced the
seven pre-registered typed decisions and the independent observer reconciled
those decisions without forbidden-channel influence or canonical IS mutation.
```

This is not PALACE equivalence, integrated SimiGo proof, production validity,
LLM autonomy, or a general Execution State theorem.

## 5. Record integrity

This authorization is registered by the canonical commit introducing it. Later
modification creates a new content address and does not silently revise the
Human ruling.
