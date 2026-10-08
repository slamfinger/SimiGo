# SRS-REAL-CLOSURE-01 — Database-Carrier Serialization Closure & Fifth Equivalence Campaign Request v1.7

> **Status:** HUMAN-AUTHORIZED — PART R4 CORRECTION + PREPARE PART E5;
> E5 REMAINS CONDITIONALLY GATED BY POST-R4 HUMAN REVIEW
> **Date:** 2026-10-08
> **Predecessor audit closure:** `c126bd9503edb367e55b9edf1ec59eecf470281d`
> **Predecessor canonical main:** `36006066f2d10eb521244a82ebe77d49c70ec118`

## 1. Exact Human authorization

The Human authorized a new independent Request with scope limited to:

```text
harness evidence/provenance serialization correction;
post-sequence evidence serialization fail-closed verification;
serialization/schema self-check;
independent preflight;
preparation of a fifth frozen campaign.
```

The Human-directed objective is not merely “repair and rerun.” It is to build
one instrument-validated fifth campaign capable of producing a complete,
adjudicable evidence chain. Part E5 is not launched by this opening record;
it requires successful canonical Part R4 and explicit post-R4 Human review.

## 2. Authoritative inherited state

```text
E4 audit closure                         = c126bd9503edb367e55b9edf1ec59eecf470281d;
E4 invalid/evidence record               = 5ca190c…;
R3 verified observer correction          = 8c7aca5…;
Request v1.6                             = b5f15cb…;
accepted implementation                  = 7392fcb…;
accepted fresh empty database SHA256 =
  6baa7afa8b5c623c75b3111af267e270d76d663547e730af5e7ca62b7602d14d.

E4 raw sequence                          = O0–O5 COMPLETE;
E4 initial preflight                     = 30/30 PASS;
E4 outcome                               = INVALID / NON-ADJUDICATIVE;
E4 stop =
  CAMPAIGN_PREFLIGHT_VERIFICATION_JSON_SERIALIZATION_DEFECT;
root cause =
  HARNESS_POST_SEQUENCE_PREFLIGHT_JSON_PATH_SERIALIZATION_DEFECT.
```

R3 is accepted as proof that the former E3 observer canonical-key binding
defect was corrected. The E4 failure is an independent serialization defect.
Raw REUSE/BLOCK observations remain non-authoritative.

## 3. Part R4 — serialization closure only

One work cycle may modify only campaign evidence/provenance instrumentation:

```text
post-sequence evidence serialization;
provenance serialization;
serialization self-check;
JSON schema/type canonicalization;
fail-closed evidence binding;
independent preflight.
```

R4 must make evidence serialization a formal campaign invariant:

```text
canonical evidence object
  → pre-write recursive serialization check
  → exclusive write
  → reread
  → byte equality
  → parse
  → parsed-object equality
  → authorized persistence binding
  → evidence chain may continue.
```

The serializer must reject noncanonical, nonserializable, non-finite, symlink,
or partially written values before the campaign can claim closure. Path-like
values must never enter the JSON boundary; provenance paths must be normalized
to repository-relative POSIX strings at object construction. The check must
cover every canonical evidence/provenance JSON artifact, including but not
limited to repository/runtime/timing provenance, fresh-database binding,
adapter records, observer verdict, observer persistence binding, preflight
verification, campaign outcome, database validation, process result, and the
serialization self-check itself.

R4 must add one authoritative `EVIDENCE_SERIALIZATION_SELF_CHECK`
destination, produce an independent fresh v1.7 path map, and fail closed on
any missing, mismatched, partially written, or unparsable artifact.

## 4. Forbidden scope

```text
CarrierSQLite semantic change;
DB schema or transaction semantic change;
ES2/ESN change;
τ change;
fixture change;
runner semantic-sequence change;
decision-boundary change;
EQ-1..EQ-8 change;
REJ-1..REJ-14 change;
T-IMPL-01 change;
old campaign/evidence reuse;
logical import;
document rerun;
automatic renewal;
automatic equivalence.
```

## 5. Part E5 — conditional fifth frozen campaign

Only after canonical R4, independent preflight, and explicit Human
post-R4 review may exactly one new frozen fifth campaign execute. It must bind
this Request, the R4 corrected commit, the complete v1.7 path map, accepted
implementation/database baselines, unchanged EQ/REJ criteria, and fresh
campaign/IS-mutation/observer budgets.

Even if E5 closes mechanically, its result remains only
`CANDIDATE_EQUIVALENCE_PENDING_HUMAN_AUDIT`. Only after complete evidence
closure may EQ/REJ adjudication be presented for Human review.

## 6. Independent budgets

```text
serialization/provenance correction work cycle = 1;
fifth database equivalence campaign            = CONDITIONAL / 1;
fifth IS-mutation campaign                     = CONDITIONAL / 1;
fifth observer campaign                        = CONDITIONAL / 1;
E4 budget reuse                                = FORBIDDEN;
old campaign/evidence reuse                    = FORBIDDEN;
automatic renewal                              = FORBIDDEN;
automatic equivalence                          = FORBIDDEN.
```

## 7. Required stop

Part R4 must stop after canonical completion and independent self-check for
Human review. Part E5 must stop after either the first fail-closed evidence
defect or complete evidence closure, and never self-adjudicate equivalence
authority.
