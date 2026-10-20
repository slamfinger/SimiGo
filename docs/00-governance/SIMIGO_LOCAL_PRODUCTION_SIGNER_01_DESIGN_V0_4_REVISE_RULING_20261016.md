# LOCAL-PRODUCTION-SIGNER-01 — Design v0.4 Third-Round Ruling: REVISE

> **Decision ID:** `LOCAL-PRODUCTION-SIGNER-01-DESIGN-V0.4-REVISE-20261016-01`
> **Type:** Governance registration (third formal design review ruling)
> **Date:** 2026-10-16
> **Review basis:** the v0.4 §3.2 / §6.3.1 / §6.4 / §7.2 excerpts provided
> in-session; the ruling does not claim verification of the repository file,
> sources, or any execution.
> **Ruling:** `REVISE` — not ACCEPT/FREEZE. Deliver v0.5 handling ONLY MR-10,
> MR-11, and the producer_authorization_reference semantics note. v0.1–v0.4
> preserved in place; MR-7/MR-8/MR-9 not reopened.

## 1. Re-check of MR-6..MR-9 (registered verbatim in substance)

| Item | Result |
|---|---|
| MR-6 canonical signing input | substantially closed; trust-semantics cross-check still blocks via MR-10 |
| MR-7 checkpoint trusted extension | PASSED design review |
| MR-8 reader seven-step order | PASSED design review (design-level; no implementation claim) |
| MR-9 headless dual modes | substantially closed |

## 2. New mandatory revisions

```text
MR-10 (main blocker) registry-semantics binding:
  issuer_generation must be cross-verified against the registry's generation
  record for that issuer_key_id; ACTIVE/RETIRED historical verification must
  use the same trusted generation record; missing/conflicting/unconfirmable
  key-generation-status relationship → typed rejection, never acceptance on
  signature validity alone; lineage reset rules must be consistent with
  host_instance_id changes so old-lineage generations are never interpreted
  as new-lineage state; host-identity scope of LOCALB records must be
  explicit (host-instance-scoped by default, or explicit authorized import);
MR-11 pairing-credential persistence:
  the credential secret exists only at issuance and in the client's
  possession; the Issued event stores the credential identifier plus
  verification material (appropriately hashed digest), never the bearer
  secret; REGISTERED atomically consumes the credential and creates the
  client record; expired/revoked/consumed/failed credentials never become
  reusable;
SUPPLEMENT producer_authorization_reference semantics:
  choose and state ONE meaning — verifiable authorization reference, or
  non-authoritative audit label (the latter acceptable without introducing a
  second authorization system).
```

## 3. Governance status

```text
v0.4 = REVISE; v0.5 = next design delivery;
Trust Universe A / Contract v1.8 / frozen anchor = unchanged;
R27 = STOP; REPAIR_ATTEMPT_6 = NOT AUTHORIZED / NOT CONSUMED;
LOCALB implementation, key generation, Build/Test = NOT AUTHORIZED.
```
