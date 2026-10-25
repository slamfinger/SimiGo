# Experiment Authorization Package R01 Rev1 Second Review Ruling

> **Status:** R01 Rev1 = **ACCEPTED**; **S1 = APPROVED**; **S3 = NOT AUTHORIZED**
> **Review date:** 2026-10-06
> **Review authority:** Human independent review
> **Reviewed package basis:** `bce3dc4`
> **Frozen design:** Probe v0.2 remains ACCEPTED / FROZEN
> **Candidate run:** `ES-CSP-RUN-01`

## 1. Ruling

```text
Probe v0.2                          ACCEPTED / FROZEN
Probe Representation Contract       ACCEPTED
R01 Rev1                            ACCEPTED
G-R / G-C ordering                  ACCEPTED
Experimental blinding               ACCEPTED
Deterministic entry point           ACCEPTED

S0 R01 Rev1 review                  PASS
S1 fixture preparation              APPROVED
S2 fixture manifest review          REQUIRED
S3 experiment execution             NOT AUTHORIZED
Experiment                          NOT AUTHORIZED
```

The Human separately approved preparation of the three independent fixture
manifests and checksums. Approval of S1 does not authorize execution of
`ES-CSP-RUN-01`.

## 2. Accepted revision checks

```text
N-B pointer schema
  PASS — two independent scalar NEXT_ACTION records:
         P1a → B1 and P1b → B2; no multi-target pointer structure.

Reconstruction blinding
  PASS — fresh reconstruction receives an opaque fixture instance ID,
         not its role; role and expected result remain control-side.

Deterministic entry point
  PASS — fresh reconstruction receives a pre-registered opaque stable
         session locator and must resolve exactly one registered session;
         discovery scanning and semantic fallbacks are forbidden.
```

The Human also confirmed positive/negative fixture independence, C1/C2
authority, G-R/G-C ordering, and the S1/S3 boundary.

## 3. S1 scope

S1 may prepare:

```text
P-POS fixture manifest
N-A fixture manifest
N-B fixture manifest
exact payload bytes and SHA-256 checksums
actual carrier/session/event/mapping/revision/locator records
G-R results
G-C results
fixture independence proof
```

S1 may not:

```text
run ES-CSP-RUN-01;
perform C1/C2 continuation research execution;
authorize S3;
modify Probe v0.2;
modify U-A code, Manifest v1.1, UA v1.0, PB v1.2, or any Frozen Contract;
introduce a semantic entity, new CarrierRecord kind, RelationCore rule,
relation engine, Super Store, embedding path, MCP path, remote API, or
backend selection.
```

## 4. S2 review requirements

The next Human review must inspect the materialized fixtures, not only the
manifest self-description:

```text
actual CarrierRecord kinds;
actual CC-5 mappings;
actual Information identities;
actual revision and provenance records;
actual locator / stable session addressing;
payload checksums;
G-R and G-C evidence;
N-A / N-B independence;
absence of hidden semantic growth.
```

S3 remains NOT AUTHORIZED until the Human explicitly rules after S2.
