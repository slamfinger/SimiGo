# LOCAL-PRODUCTION-SIGNER-01 — Design v0.6 Fifth-Round Ruling: REVISE

> **Decision ID:** `LOCAL-PRODUCTION-SIGNER-01-DESIGN-V0.6-REVISE-20261016-01`
> **Type:** Governance registration (fifth formal design review ruling)
> **Date:** 2026-10-16
> **Review basis:** the v0.6 excerpts provided in-session; no claim of
> independent file, source, or implementation verification.
> **Ruling:** `REVISE` — not ACCEPT/FREEZE. Deliver v0.7 handling ONLY
> MR-14..MR-17. v0.1–v0.6 preserved in place; MR-12 closed and not reopened;
> MR-13's credential architecture not redesigned.

## 1. Closed items (registered verbatim in substance)

MR-12 AVC read-only archival isolation: CLOSED. MR-13 canonical digest:
core requirements met. Credential not consumable/lockable by unauthenticated
requests: core rule met. Atomic consumption/registration, V/P phase
separation: requirements clear.

## 2. New mandatory revisions

```text
MR-14 (blocker) credential plaintext lifecycle contradiction:
  the secret's allowed states must be stated as a persistence-vs-runtime
  boundary: memory only during issuance, client possession, and transient
  Phase-V processing; never persisted in registry / authoritative event log /
  persistent diagnostics; request bodies, QR originals, and secret-bearing
  error contexts never recorded; post-verification retention minimized
  (clearing mechanism = implementation requirement); digest and secret
  remain distinct concepts;
MR-15 (blocker) archival trust semantics vs revocation:
  three non-conflatable layers — cryptographic check, historical
  registration fact, acceptance verdict; without trusted signing-time (or
  equivalent ordering) evidence, archival verdicts state only "consistent
  with the verified lineage registration history" (signed timestamps are
  signer claims, not evidence); REVOKED keys may show layer-1 VALID but no
  result may be readable as current trust or acceptance; active reader,
  AVC, and revocation policy share consistent result semantics;
MR-16 failure telemetry bounded:
  failure events are never appended to the authoritative log; telemetry is
  bounded and non-authoritative; rate limiting may protect resources but
  never makes a credential terminal via unauthenticated failures; the
  design states honestly that bandwidth/resource exhaustion resistance is
  NOT promised — the guarantee is only credential-state immunity;
MR-17 fingerprint display vs machine binding:
  the pre-bound object is the FULL client public key (or full 64-hex
  fingerprint); machine checks compare full values; short fingerprints are
  display abbreviations only and never the sole basis of human first-trust;
  if a short form is used for human verification, a sufficient length and
  display rule must be defined.
```

## 3. Governance status

```text
v0.6 = REVISE; v0.7 = next design delivery;
Trust Universe A / Contract v1.8 / frozen anchor = unchanged;
R27 = STOP; REPAIR_ATTEMPT_6 = NOT AUTHORIZED / NOT CONSUMED;
LOCALB implementation, key generation, Build/Test = NOT AUTHORIZED.
```
