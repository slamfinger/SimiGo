# SRS-REAL-CLOSURE-01 — Database-Carrier Adapter-Output Binding Correction & Sixth Equivalence Campaign Request v1.8

> **Status:** HUMAN-AUTHORIZED — PART R5 CORRECTION + PART E6
> **Date:** 2026-10-08
> **Predecessor E5 audit:** `cd0222873f1ac82ecbe89123eae7601d2945fa7e`
> **Predecessor canonical main:** `d8c1eddf621bb7d915f9e2106753cc7140fee51c`

## 1. Exact Human ruling

```text
授权 E6
```

This authorizes one independent Part R5 correction and one fresh E6 campaign.
The correction is limited to adapter-output persistence return-type binding on
the caller side. `persist_exact_json()` keeps its existing binding contract.

## 2. Inherited ruling

```text
E5 outcome = INVALID / NON-ADJUDICATIVE;
E5 audit   = cd0222873f1ac82ecbe89123eae7601d2945fa7e;
E5 stop = CAMPAIGN_ES2_OUTPUT_JSON_PARSE_BINDING_DEFECT;
root cause class =
  HARNESS_ADAPTER_OUTPUT_PERSISTENCE_RETURN_TYPE_BINDING_DEFECT;
explicit helper contract =
  persist_exact_json(path: Path, payload: bytes) -> dict;
defective call =
  json.loads(persist_exact_json(output_path, proc.stdout)).
```

R4 remains effective: v1.7 fresh preflight was 31/31 PASS, and exact ES2 output
persistence succeeded before the caller mis-consumed the persistence binding.
Raw O0–O2 remain facts only; raw ES2 REUSE remains non-authoritative; ESN was
not observed.

## 3. Part R5 — caller-side only

Part R5 may change only campaign instrumentation needed to consume the exact
adapter output after persistence:

```text
remove the persistence binding from json.loads;
parse the already-persisted adapter output bytes separately;
retain exact-byte persistence and persistence-binding checks unchanged;
retarget one fresh v1.8 evidence root/path map;
run fresh independent path preflight;
verify caller-side correction with static and executable self-checks.
```

Forbidden:

```text
persist_exact_json contract change;
ES2/ESN semantic change;
decision-boundary change;
carrier/schema/transaction semantic change;
tau/fixture/runner semantic-sequence change;
EQ/REJ criteria change;
old E5 budget/evidence reuse;
repair/rerun of E5;
automatic equivalence.
```

## 4. Part E6 — one fresh frozen campaign

After canonical R5, fresh 31-destination v1.8 preflight, static/executable
caller-binding self-checks, and this Human authorization, exactly one new E6
campaign may execute. E6 must execute O0–O5, close the complete evidence chain,
and stop for separate Human evidence audit. Even a mechanically valid result is
only `CANDIDATE_EQUIVALENCE_PENDING_HUMAN_AUDIT`.

## 5. Independent budgets

```text
adapter-output binding correction work cycle = 1;
sixth equivalence campaign                    = 1;
sixth IS-mutation campaign                    = 1;
sixth observer campaign                       = 1;
E5 budget/evidence reuse                      = FORBIDDEN;
rerun/repair/renewal beyond this authorization = FORBIDDEN.
```

## 6. Stop

If E6 encounters any missing, noncanonical, mismatched, partially written, or
unparsable artifact, it fails closed and stops. No post hoc reconstruction or
forced adjudication is authorized.
