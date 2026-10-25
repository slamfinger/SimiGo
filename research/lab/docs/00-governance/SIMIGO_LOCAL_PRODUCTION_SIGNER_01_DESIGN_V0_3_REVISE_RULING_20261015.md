# LOCAL-PRODUCTION-SIGNER-01 — Design v0.3 Second-Round Formal Ruling: REVISE

> **Decision ID:** `LOCAL-PRODUCTION-SIGNER-01-DESIGN-V0.3-REVISE-20261015-01`
> **Type:** Governance registration (second formal design review ruling)
> **Date:** 2026-10-15
> **Review basis:** the v0.3 §3 / §6 / §7 / §11 excerpts provided in-session by
> the delivering agent (the reviewer reviewed the provided text directly; this
> ruling does not claim verification of the repository file, sources, or any
> implementation).
> **Ruling:** `REVISE` — not ACCEPT/FREEZE. Deliver
> `LOCAL_PRODUCTION_SIGNER_01_CONCEPTUAL_DESIGN_V0.4.md`, preserving v0.1–v0.3
> in place. v0.4 addresses ONLY MR-6..MR-9; no scope expansion; no frozen
> Universe-A change.

## 1. New mandatory revisions

```text
MR-6 (blocker) signature input must bind ALL semantics-bearing fields:
  define a canonical byte-level LOCALB_SIGNING_INPUT_V1; include every field
  affecting record identity, attribution, authorization interpretation, and
  key generation (explicitly incl. logical_key_identity/version,
  producer_authorization_reference, issuer_generation); exclude only fields
  that cannot be signed or are derived, each with a stated protection
  (constant check / derivation / other verification rule); no ad-hoc string
  concatenation — a uniquely reproducible byte-level specification;
MR-7 (blocker) checkpoint "match" must not reject normal later writes:
  compare trusted-history relation, not head equality — B1 rollback/fork
  (local head earlier than checkpoint; same-seq-different-hash; checkpoint
  position absent from local log) → refuse + explicit recovery, and
  re-initialization requires a NEW lineage and a freshly recorded trusted
  head (appending a "re-initialized" event to a possibly rolled-back log
  never clears B1); B2 continuity unknown → fail-closed; B3 trusted
  extension (log matches checkpoint at its exact (seq, hash) and head is a
  verifiable extension, or equal) → normal operation;
MR-8 (blocker) reader order must match the early-isolation claim:
  distinguish frame parsing from payload parsing; obtain and check the
  envelope schema id WITHOUT payload parsing; typed rejection of non-LOCALB
  envelopes at that early step; then envelope constants, then payload
  digest/schema/canonical checks, then trust/registry/signature, then
  verdict; if the encoding could not deliver this order, the isolation
  CLAIM would have to be revised instead;
MR-9 headless confirmation semantics:
  strict headless (pre-bound client public key or equivalent trusted
  out-of-band identity confirmation) is the DEFAULT for headless
  deployments; a degraded "credential-holder-priority" mode, if retained,
  is a separate, explicitly risk-informed configuration that never presents
  the issuance-scope label as verified identity.
```

## 2. Re-check of the first-round items (registered verbatim in substance)

| Item | v0.3 outcome |
|---|---|
| TTL normative-vs-open conflict | FIXED (5 min frozen, non-configurable in v1) |
| signature input lacked schema binding | original gap FIXED; envelope-metadata binding now blocks via MR-6 |
| rollback detection branches | semantics improved; MR-7 still blocks (head continuity) |
| cryptographic vs trust-state verification conflation | FIXED (two classes distinct; records never restore trust authority) |

OQ-6 remains `PARK` (Ed25519/Keychain baseline). All other standing boundaries
remain in force.

## 3. Governance status

```text
v0.3 = REVISE; v0.4 = next design delivery;
Trust Universe A / Contract v1.8 / frozen anchor = unchanged;
R27 = STOP; REPAIR_ATTEMPT_6 = NOT AUTHORIZED / NOT CONSUMED;
implementation, key generation, Build/Test = NOT AUTHORIZED.
```
