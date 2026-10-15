# Persistent SRS — R27-G0 Outcome, Repair-Boundary Acceptance, and D1 Registration

> **Decision ID:** `PERSISTENT-SRS-R27G0-REPAIR-BOUNDARY-D1-RULING-20261015-01`
> **Type:** Governance registration (read-only precheck outcome + boundary ruling + work-item registration)
> **Date:** 2026-10-15
> **Ruling provenance:** Human external-review recommendations, 2026-10-15 session
> directive ("三个有边界的外审建议"), registered per repository governance rules.
> **Baseline:** repository HEAD `1f80d50e31d678c13beed35f3c9026a2d2580958`;
> precheck record `docs/08-research-memory/SR_R27_G0_PRODUCTION_SIGNED_RECORD_PRECHECK_20261015.md`.
> **Status:** REGISTERED. No stage is authorized by this record. Commit/push of this
> record itself awaits explicit Human instruction.

---

## 1. Ruled decisions

```text
D-A R27-G0 outcome:
  ACCEPT_R27_G0_SCOPED_NEGATIVE_OUTCOME
  conclusion = NO_COMPLIANT_PRODUCTION_SIGNED_RECORD_FOUND_IN_SCOPE (Route B);
  the scoped negative is accepted as-is: it proves absence inside the authorized
  local search scope only, and must NOT be upgraded to "external signing
  capability does not exist", nor to "the public key should be replaced";
  REPAIR_ATTEMPT_6 remains STOPPED — no fixture, no Build, no Test, no anchor
  change.

D-B Repair Authorization Package v2.1:
  ACCEPT_REPAIR_PACKAGE_V2.1_BOUNDARY_WITHOUT_EXECUTION_AUTHORIZATION
  the package's fixed repair order (R3 five-step order, section 1), its R27
  signed-record hard gate and STOP branch (section 2), and its preserved
  boundaries (section 3) are accepted as the governance basis for any future
  constrained repair;
  acceptance of the boundary is NOT `AUTHORIZE_IMPLEMENTATION_REPAIR_V2`:
  REPAIR_ATTEMPT_6 execution authorization is NOT granted by this acceptance
  and still requires the R27 precondition plus a separate explicit ruling;
  REJECT was not returned either — the package remains the operative basis.

D-C R14 stage ordering:
  R14_REMAINS_OPEN_AS_CONTRACT_CONFORMANCE_ISSUE
  Contract v1.8 stays unchanged; the R14-before-R15 order in the frozen
  contract is NOT modified to match current implementation; the conflict is
  treated as an unresolved implementation-conformance question; v2.1 does not
  authorize R14 source reordering; any repair scope for R14 requires a
  separate definition; no source change now.

D-D attempt ledger:
  REPAIR_ATTEMPT_1–5 = CONSUMED / history immutable;
  REPAIR_ATTEMPT_6 = NOT AUTHORIZED / NOT CONSUMED;
  before any Attempt-6 start, source digests, baseline commit, and
  authorization records must be re-verified at execution time — a historical
  defect table (including the 2026-10-15 read-only comparison) does not
  substitute for execution-time binding checks.

D-E work item registered:
  D1 — Production Signing Capability Resolution (section 2);
  goal = determine whether the FROZEN production anchor has a lawful signing
  path; NOT to generate a new key.

D-F state reconciliation:
  RESEARCH_STATE.md reconciliation is registered as a separate, minimal,
  append-only action (preserve all historical strata; append current state:
  R27-G0 STOP, v2.1 actual ruling, R14 open, REPAIR_ATTEMPT_6 boundary);
  it requires separate registration/authorization, is sequenced after D1 in
  the advancement order, and must not be mixed into any code-repair commit.
```

## 2. D1 — Production Signing Capability Resolution

```text
D1.1 identify responsible party and lawful contact channel
      completion: a responsible subject is explicitly designated and the
      request is in a sendable state;
      REQUIRED HUMAN ACTION — until this is done, the request must be treated
      as NOT sent, and no external verification may be claimed;
      first candidate = the project owner (whether the anchor private key was
      ever generated/held offline at anchor rotation commit 6c345d73 is a
      fact only the owner can attest); external services are not presumed.

D1.2 send the External Custody Attestation Request
      (docs/00-governance/SIMIGO_PERSISTENT_SRS_EXTERNAL_CUSTODY_ATTESTATION_
      REQUEST_20261012.md; currently DRAFT, never sent, responsible-party
      fields blank; external contact is reserved to the project owner or a
      designated Human lead)
      completion: request plus evidence of sending are archived.

D1.3 verify the response and signing capability
      completion: one of — existing compliant records confirmed; an
      authorized signing service confirmed; or an authoritative statement
      that no lawful signing capability exists (per the request's F1–F4
      mandatory response format; unanswered items are NOT confirmed by
      default; responses containing secret material must be refused).

D1.4 re-evaluate the R27 precondition
      completion: either a verifiable production-anchor-signed record is
      available, or the outcome is escalated to the next independent
      governance decision (D2 territory: whether any lawful trust-architecture
      revision path exists — which "not found in current search" alone does
      NOT justify).
```

## 3. Registered repair targets (known, NOT authorized)

Carried from the 2026-10-15 read-only defect comparison and the Human review;
these are future targets only. Writable set remains the two authorized paths
(Manifest v2.2 §7). None may start before the Attempt-6 gate reopens.

```text
R2  make the production classification descriptor immutable/read-only;
    no publicly writable fields in the production module;
R3  enforce the v2.1 five-step order (key verify → root-only creation when
    absent → lock → classification → persistence subdirectories only for the
    NEW_RECORD path); cover both root states with recursive snapshots;
R4  do not swallow fsync errors; a failed refresh must block the final-file
    rename; remove mutable fault switches from the production path
    (test injection via internal seam parameter only);
R5  complete the 13-class negative matrix; R27 end-to-end must drive the
    complete Reader path with a real production-anchor-signed record;
R6  eligibility and invalidation must derive from verified records and event
    chains; caller-supplied boolean eligibility is not trusted;
R14 resolve separately (frozen check order vs implementation);
R27 satisfy the signed-record precondition first; a helper unit test is not
    end-to-end evidence.
```

## 4. Preserved boundaries (unchanged)

```text
Contract v1.8 / I0 Schema v1.6 / Manifest Instance v2.2 = FROZEN;
production trust anchor = unchanged (no key replacement, no test-key
  impersonation, no R27 bypass);
Implementation repair / Build / Test / Independent Validator / Fixture /
  Execution Batch / ES2 / MLX / V6 / Production = NOT AUTHORIZED;
PALACE / Information Space mutation = FORBIDDEN;
Execution State established baselines = unchanged;
2026-10-15 GUI click-through results = independent engineering evidence only,
  not an Information Space verification result and not a driver of its
  research pace.
```

## 5. Advancement order (as ruled)

```text
1. this registration (done by this record);
2. D1 (D1.1 is the immediate Human action);
3. RESEARCH_STATE.md minimal append-only reconciliation (separate
   authorization, after D1);
4. code repair under an eventually reopened Attempt-6 gate, limited to the
   two authorized files, verified per the registered test requirements;
5. separately authorized persistence validation and the ES₁ → Information
   Space → independent ES₂ experiments — unit tests passing never counts as
   end-to-end reuse being established.
```
