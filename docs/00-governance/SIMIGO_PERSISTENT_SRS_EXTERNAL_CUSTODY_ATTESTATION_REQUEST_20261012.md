# External Custody Fact Attestation Request — Persistent SRS Production Anchor

> **Status:** DRAFT — NOT YET COMMITTED; NOT YET SENT (external contact is
> reserved to the project owner or a designated Human lead)
> **Date:** 2026-10-12
> **Authorization:** `R27-CUSTODY-GOVERNANCE-MATERIALS-DRAFT-20261012-01`

## 1. Identity awaiting attestation

```text
production anchor public key (Base64) =
  +fG2YJ+YnW1RtsX8bCbukUERvSlIq4fvP7cZcs6+VMI=
raw public key (32 bytes, hex) =
  f9f1b6609f989d6d51b6c5fc6c26ee914111bd2948ab87ef3fb71972cebe54c2
public key SHA-256 =
  8c7c011f4f1458fad4b26b0d6a12b3f37bbab5b6a10eaef46530efb0c475c4c4
curve = Ed25519
role = Persistent SRS record signature trust anchor (frozen, unique)
```

## 2. Facts requested from the responsible party

```text
F1 key lifecycle — was this key ever generated? by whom, when, under what
  authority? Is the private key still retrievable and usable?
F2 custody — is there a lawful custodian or approved signing interface?
F3 signing capability — does an authorized signing service or normal
  production signing flow exist for this key, and under what authorization?
F4 evidence references — responsible party/organization/service identifier,
  written confirmation date, and traceable evidence citations.
```

Mandatory response format: for EACH of F1–F4 the responsible party must
explicitly mark "confirmed", "unable to confirm", or "not applicable", and
provide the corresponding evidence citation; when evidence cannot be
provided, the reason must be stated. Unanswered items must NOT be treated as
confirmed by default.

## 3. Confidentiality boundary

```text
This request does NOT require, accept, or record the private key itself, any
seed, or other secret credential. Only facts and authorization status are
requested. Any response containing secret material must be refused and
reported.
```

## 4. Conclusion classification (to be completed by the respondent)

```text
[ ] CONFIRMED_AVAILABLE   — custodian/signing interface identified, with
                            evidence of production-anchor signing ability;
[ ] CONFIRMED_UNAVAILABLE — authoritative confirmation that the private key
                            and any lawful signing interface are unavailable;
[ ] UNKNOWN               — insufficient evidence, with stated limitations.
```

## 5. Restrictions on this request

```text
Only facts and authorization status are requested;
no test-time signature generation may be requested or performed;
this request must not disguise a signing request as a fact confirmation;
the respondent is NOT presumed to hold the private key;
fields below are intentionally left blank pending identification of a
  responsible party by the project owner — no unverified organization,
  person, or service may be filled in.
```

## 6. Reserved fields (to be completed by the project owner / designated lead)

```text
responsible party / organization: ______________________________
contact channel and date of request: ____________________________
written confirmation received: __________________________________
confirmation date: ______________________________________________
evidence citations: _____________________________________________
```
