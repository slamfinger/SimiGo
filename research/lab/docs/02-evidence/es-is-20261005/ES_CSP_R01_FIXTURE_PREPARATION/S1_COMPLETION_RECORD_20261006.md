# ES-CSP-RUN-01 — S1 Fixture Preparation Completion Record

> **Status:** S1 COMPLETE — AWAITING HUMAN S2 REVIEW
> **Date:** 2026-10-06
> **Authorization basis:** R01 Rev1 second-review ruling at `bce3dc4`
> **Frozen design baseline:** `39c1031`
> **Candidate run:** `ES-CSP-RUN-01`
> **Execution:** NOT RUN / NOT AUTHORIZED

## 1. Result

```text
S0 R01 Rev1 review        PASS
S1 fixture preparation    COMPLETE
S2 manifest review        REQUIRED
S3 execution              NOT AUTHORIZED
Experiment                NOT AUTHORIZED
```

Three independent fixtures were materialized with the accepted U-A SQLite
surface. No reconstruction, C1 evaluation, C2 evaluation, C3 action, or Probe
Run was performed.

## 2. Accepted fixtures

| Role | Fixture instance ID | Stable session locator | Registry SHA-256 | Manifest SHA-256 | G-R | G-C | Final carrier revision |
|---|---|---|---|---|---|---|---|
| `P-POS` | `E3645CE9-F8E3-4DF5-8644-33CD96143F9C` | `uasession:BB4710A0-F50B-46D3-A6B4-911BF0705B03` | `29ec7279dd567ef2f0f9e49133f16eadc3c6d91abdbaa0f6da456278a46b4537` | `5093a8c961698e48f3420512303cd31e5e4f2a40351778996fe76824d41efebe` | PASS | PASS | 12 |
| `N-A` | `DCC93C19-02B9-4E6C-BDD8-DF3371DF9871` | `uasession:91E26A9E-AA31-47AF-94F6-8951FFC3DCA4` | `adb6293c093d45ed86bf728ffa524edffc7261abfc3c68cbc4252a50119d9146` | `f8d85e5ae38cb75dcb2087871931d8384542ca6ca8b387a1de208e96b0d85374` | PASS | PASS | 12 |
| `N-B` | `2F204D32-02A4-416E-BEE2-965CD5A626CE` | `uasession:3CEB2438-ACA1-4B77-86D8-338F16F12730` | `a287f11b7ba87006bb8eb6c7c08eb703694d5c3d9ebed0da3cc03635d02e2a06` | `7c33d2ffed872382ff561d946ca8990fce4b66555703c008128236ec7a6a849d` | PASS | PASS | 16 |

All fixture roots are outside this repository under:

```text
/Users/mr.simi/Documents/SimiGo-Lab-R01-Fixtures/data/<fixture-instance-id>/carrier-root
```

No path or filename encodes fixture role.

## 3. Actual representation

Each fixture uses existing U-A session records and CC-5 mappings:

```text
objective             RAW
input reference       EVIDENCE_LINK
decision/work record  JUDGMENT
artifact reference    RESULT
boundary state        RESULT
continuation pointer  NEXT_ACTION
```

No `CarrierRelation`, new CarrierRecord kind, new semantic entity, relation
engine, Super Store, embedding, MCP, remote API, or backend was introduced.

Pointer observations:

```text
P-POS    P1          → B1
N-A      P1          → B1; I1 reference is independently unresolved
N-B      P1a         → B1
         P1b         → B2
```

All pointer `target_slot` values are scalar.

## 4. Gate results

Every accepted fixture has:

```text
G-R = PASS
G-C = PASS
integrity issues = 0
dangling provenance count = 0
```

`G-C-1` source audit passed:

```text
39c1031 is an ancestor of HEAD:                         PASS
39c1031..HEAD diff for trackD-memory:                   CLEAN
working-tree diff for trackD-memory:                    CLEAN
trackD-memory porcelain status:                         EMPTY
```

## 5. Blinding and control split

For each fixture, the reconstruction input contains only:

```text
source baseline identifier
run label
opaque fixture instance ID
isolated carrier data root path
Reconstruction Manifest schema version
```

The following are retained only in external control files and are not passed
to reconstruction:

```text
fixture role
expected C1 result
expected C2 result
deficiency description
```

Control and reconstruction input SHA-256 values:

| Role | Instance ID | Control SHA-256 | Reconstruction-input SHA-256 |
|---|---|---|---|
| `P-POS` | `E3645CE9-F8E3-4DF5-8644-33CD96143F9C` | `c09932a2aaa8880e7f63c84a79605b40c2a856579d8e859b114c7cb2eca0e128` | `4cb8815fedbe2a25361404e6eed9b8848b6aff295393b5c365fffd3250247496` |
| `N-A` | `DCC93C19-02B9-4E6C-BDD8-DF3371DF9871` | `d3c9a9fd3c6d6e8e31385624b03a3db32c5dfc7f4bfc2669ca763e4dc8a8cc3d` | `5d70aa148681a045e3ee735f1b079caca7f81cadf8747a52216763726f316ab3` |
| `N-B` | `2F204D32-02A4-416E-BEE2-965CD5A626CE` | `874e26a4f55b6d1b1b9b47312376be7e2d4206aff1364f362bd6bee959e6c7f4` | `46a842c221a1f44dbe91037d043fbae2f178f1898a819cee007a0ccbd5d090c4` |

## 6. Archived artifacts

In-repository evidence:

```text
E3645CE9-F8E3-4DF5-8644-33CD96143F9C.fixture-manifest.json
DCC93C19-02B9-4E6C-BDD8-DF3371DF9871.fixture-manifest.json
2F204D32-02A4-416E-BEE2-965CD5A626CE.fixture-manifest.json
fixture-preparation-result.json
fixture-prep-Package.swift
fixture-prep-main.swift
```

Aggregate preparation-result SHA-256:

```text
1c4acd41b0b8f10bc7b46af5488f3e2f3557abc803c3222945a7059d54eefbab
```

Preparation tool SHA-256 values:

```text
Package.swift   e0b48170e8c173b9eef172b88acf06eb15357ccc296d57b744fc3db63a584131
main.swift      9453524e104bca6fae195eb57a0f7de1f6fd2b1305dd500f6ada68c8878e3d07
```

## 7. Honest failed preparation attempts

Two earlier S1 attempts were aborted by the preparer's own validation and were
not used as accepted fixtures:

```text
20261006T131241Z-missing-pointer-records
  defect: pointer records were omitted

20261006T131409Z-pointer-target-harness-defect
  defect: preparer replaced scalar target_slot labels with runtime event IDs
```

Both attempts remain quarantined under `failed-attempts/` outside the
repository. Neither was reconstructed, evaluated, or used as a run input.

## 8. Next step

The only lawful next step is Human **S2 review** of the actual manifests and
fixture evidence.

```text
S2 fixture manifest review   REQUIRED
S3 execution                 NOT AUTHORIZED
Experiment                   NOT AUTHORIZED
```
