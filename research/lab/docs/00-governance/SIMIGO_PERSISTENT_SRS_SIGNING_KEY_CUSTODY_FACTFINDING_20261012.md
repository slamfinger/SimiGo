# Persistent SRS Signing Key Custody Fact-Finding Record

> **Decision ID:** `R27-SIGNING-KEY-CUSTODY-FACTFINDING-20261012-01`
> **Type:** Governance-only / read-only audit
> **Date:** 2026-10-12
> **Conclusion:** `UNKNOWN`
> **Audit baseline:** `3c04863e65e7b18ddbe45697526c43cb66d6d3a1`

## 1. Scope, method, and boundaries

Read-only inspection limited to the local repository (tracked files, working
tree, and implementation sources) at the baseline above. No private key
material was read, exported, or derived for the production anchor; no signing
was triggered; no records, fixtures, or `.psrs` files were created; no build,
test, validator, or execution batch ran.

## 2. Evidence

```text
E1 anchor identity binding (CONFIRMED):
  The Persistent SRS production anchor public key
  +fG2YJ+YnW1RtsX8bCbukUERvSlIq4fvP7cZcs6+VMI= is byte-identical to
  SRSVALTrustAnchor.recordIntegrityIssuer in
  simigo2-experimental/Sources/SimiGo2Experimental/SRSVALDecisionCore.swift
  and appears identically in Manifest Contract v1.2–v1.8 (frozen docs).

E2 production issuer construction (NONE FOUND):
  SRSVALIssuer has zero construction sites in production code; the only
  construction is in Tests/SRSVALDecisionCoreTests.swift:29 with a raw key
  derived as SHA256("TEST-ONLY PRIVATE KEYrecordIntegrity") — a public
  deterministic string whose derived public key cannot equal the production
  anchor public key (only an astronomically improbable collision would make
  them equal). Decision Core explicitly states it "intentionally has no
  issuer initializer and consumes signed records."

E3 production private key traces (NONE FOUND):
  No repository file, configuration, or tracked history contains the
  production private key or any candidate material bound to the production
  anchor public key.

E4 custody / signing-service records (NONE FOUND):
  No governance document identifies a custodian, key-management service, or
  authorized signing interface for the production anchor.
```

## 3. Items that could not be verified

The absence of local evidence does not prove non-existence. Not verifiable
within this audit's permission boundary:

```text
whether a custodian holds the production private key outside this repository;
whether the private key was ever generated from the published public key;
whether an external authorized signing service exists;
whether future governance may designate or recover a signing capability.
```

## 4. Conclusion

```text
conclusion = UNKNOWN;
anchor identity = CONFIRMED bound to Decision Core recordIntegrityIssuer;
local private key / production issuer = NOT FOUND;
custodian or external signing interface = NOT IDENTIFIED;
```

## 5. Recommendation

Per the ruling's continuation rules, the UNKNOWN outcome maintains Option C:
R27 end-to-end remains NOT SATISFIED, `REPAIR_ATTEMPT_6` is not consumed, and
Options A/B do not advance. Any path forward (custodian identification,
external signing service, or an authorized minimal execution batch) requires
a separate Human decision; this record must not be used as an execution
authorization credential.

## 6. Preserved state

```text
R27 E2E = NOT SATISFIED;
REPAIR_ATTEMPT_1–5 = CONSUMED / history immutable;
REPAIR_ATTEMPT_6 = NOT CONSUMED / NOT AUTHORIZED;
R1–R6 = RESIDUAL BLOCKERS;
R14 stage ordering = OPEN / separate Human ruling;
Contract v1.8 / I0 Schema v1.6 / Manifest Instance v2.2 = FROZEN;
IMPLEMENTATION COMPLETE = NOT ESTABLISHED.
```
